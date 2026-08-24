require "net/imap"

# IMAP IDLE (A3): hold a connection per mailbox; when the server reports new
# mail, enqueue a fetch. Run by bin/idle. The 30s poll remains the safety net,
# so a dropped IDLE connection only costs latency, never mail.
class IdleWatcher
  IDLE_TIMEOUT = 240 # re-issue IDLE before common 5-minute server limits
  BACKOFF = 30

  def self.run(mailbox_id)
    loop do
      mailbox = Mailbox.find_by(id: mailbox_id)
      return if mailbox.nil? || !mailbox.imap_configured?
      watch(mailbox)
    rescue StandardError => e
      Rails.logger.warn("idle: mailbox #{mailbox_id}: #{e.class} #{e.message}; reconnecting in #{BACKOFF}s")
      sleep BACKOFF
    end
  end

  def self.watch(mailbox)
    imap = Net::IMAP.new(mailbox.imap_host, port: mailbox.imap_port, ssl: mailbox.imap_ssl)
    if mailbox.oauth?
      imap.authenticate("XOAUTH2", mailbox.imap_user, MailOauth.access_token!(mailbox))
    else
      imap.login(mailbox.imap_user, mailbox.imap_password)
    end
    unless imap.capabilities.include?("IDLE")
      Rails.logger.info("idle: #{mailbox.address} has no IDLE capability; polling covers it")
      imap.disconnect rescue nil
      sleep 3600
      return
    end
    imap.examine(mailbox.imap_folder)
    loop do
      poked = false
      imap.idle(IDLE_TIMEOUT) do |response|
        if response.respond_to?(:name) && %w[EXISTS RECENT].include?(response.name)
          poked = true
          imap.idle_done
        end
      end
      FetchMailboxJob.perform_later(mailbox) if poked
    end
  ensure
    imap&.disconnect rescue nil
  end
end
