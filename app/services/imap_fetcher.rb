require "net/imap"

# IMAP overlay fetch (A2): read-only EXAMINE, cursor = UIDVALIDITY + last UID.
# Dedup (A9) happens here so refetches and UIDVALIDITY resets never duplicate.
class ImapFetcher
  BATCH = 50
  MAX_PER_RUN = 500          # a huge backlog drains over several polls, not one
  MAX_MESSAGE_BYTES = 30.megabytes
  OPEN_TIMEOUT = 15

  def self.call(mailbox) = new(mailbox).call

  def initialize(mailbox)
    @mailbox = mailbox
  end

  def call
    imap = Net::IMAP.new(@mailbox.imap_host, port: @mailbox.imap_port, ssl: @mailbox.imap_ssl,
                         open_timeout: OPEN_TIMEOUT)
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
    uids = uids.first(MAX_PER_RUN)
    uids.each_slice(BATCH) do |batch|
      # Two-phase: check sizes first so one giant message can't eat memory.
      sizes = imap.uid_fetch(batch, "RFC822.SIZE").to_h { |d| [ d.attr["UID"], d.attr["RFC822.SIZE"].to_i ] }
      batch.each do |uid|
        if sizes.fetch(uid, 0) > MAX_MESSAGE_BYTES
          Rails.logger.warn("fetch: skipping oversized message uid=#{uid} (#{sizes[uid]} bytes) in #{@mailbox.address}")
        else
          data = imap.uid_fetch([ uid ], [ "BODY.PEEK[]", "INTERNALDATE" ])&.first
          ingest(data.attr["BODY[]"], received_at: data.internaldate) if data
        end
        @mailbox.update_column(:last_uid, uid) if uid > @mailbox.last_uid
      end
    end

    @mailbox.update!(last_fetched_at: Time.current, fetch_error: nil)
    uids.size
  ensure
    imap&.logout rescue nil
    imap&.disconnect rescue nil
  end

  def ingest(raw, received_at: nil)
    raw = raw.to_s
    key = raw[/^Message-I[dD]:\s*(<[^>]+>|\S+)/i, 1]&.delete("<>")
    key ||= Digest::SHA256.hexdigest(raw) # fallback hash when no Message-ID (A9)
    begin
      # Savepoint so the unique-violation doesn't poison an enclosing
      # transaction (PostgreSQL aborts the whole tx otherwise).
      InboundDedup.transaction(requires_new: true) do
        InboundDedup.create!(mailbox: @mailbox, dedup_key: key)
      end
    rescue ActiveRecord::RecordNotUnique
      return :duplicate
    end

    inbound_email = ActionMailbox::InboundEmail.create_and_extract_message_id!(raw, status: :processing)
    begin
      InboundProcessor.call(@mailbox, inbound_email, received_at: received_at)
      inbound_email.delivered!
    rescue StandardError => e
      inbound_email.update!(status: :failed)
      Rails.logger.error("inbound: processing failed for #{key}: #{e.class} #{e.message}")
    end
  end
end
