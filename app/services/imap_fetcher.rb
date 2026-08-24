require "net/imap"

# IMAP overlay fetch (A2): read-only EXAMINE, cursor = UIDVALIDITY + last UID.
# Dedup (A9) happens here so refetches and UIDVALIDITY resets never duplicate.
class ImapFetcher
  BATCH = 50

  def self.call(mailbox) = new(mailbox).call

  def initialize(mailbox)
    @mailbox = mailbox
  end

  def call
    imap = Net::IMAP.new(@mailbox.imap_host, port: @mailbox.imap_port, ssl: @mailbox.imap_ssl)
    if @mailbox.oauth?
      imap.authenticate("XOAUTH2", @mailbox.imap_user, MailOauth.access_token!(@mailbox))
    else
      imap.login(@mailbox.imap_user, @mailbox.imap_password)
    end
    imap.examine(@mailbox.imap_folder) # read-only: we never touch flags (A24 off)

    uid_validity = imap.responses("UIDVALIDITY", &:last)
    uid_next = imap.responses("UIDNEXT", &:last)

    if @mailbox.uid_validity != uid_validity
      # New mailbox or UIDVALIDITY reset: start from now, don't import history.
      # Dedup catches any overlap if the server merely renumbered.
      @mailbox.update!(uid_validity: uid_validity, last_uid: uid_validity.nil? ? 0 : (uid_next.to_i - 1))
      @mailbox.update!(last_uid: 0) if @mailbox.last_uid.negative?
    end

    uids = imap.uid_search([ "UID", "#{@mailbox.last_uid + 1}:*" ]).select { |u| u > @mailbox.last_uid }
    uids.each_slice(BATCH) do |batch|
      imap.uid_fetch(batch, "BODY.PEEK[]").each do |data|
        uid = data.attr["UID"]
        ingest(data.attr["BODY[]"])
        @mailbox.update_column(:last_uid, uid) if uid > @mailbox.last_uid
      end
    end

    @mailbox.update!(last_fetched_at: Time.current, fetch_error: nil)
    uids.size
  ensure
    imap&.logout rescue nil
    imap&.disconnect rescue nil
  end

  def ingest(raw)
    raw = raw.to_s
    key = raw[/^Message-I[dD]:\s*(<[^>]+>|\S+)/i, 1]&.delete("<>")
    key ||= Digest::SHA256.hexdigest(raw) # fallback hash when no Message-ID (A9)
    begin
      InboundDedup.create!(mailbox: @mailbox, dedup_key: key)
    rescue ActiveRecord::RecordNotUnique
      return :duplicate
    end

    inbound_email = ActionMailbox::InboundEmail.create_and_extract_message_id!(raw)
    begin
      InboundProcessor.call(@mailbox, inbound_email)
      inbound_email.delivered!
    rescue StandardError => e
      inbound_email.update!(status: :failed)
      Rails.logger.error("inbound: processing failed for #{key}: #{e.class} #{e.message}")
    end
  end
end
