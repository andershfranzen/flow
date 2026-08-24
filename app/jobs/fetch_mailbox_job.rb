class FetchMailboxJob < ApplicationJob
  queue_as :default
  # No overlapping fetch for the same mailbox (A2).
  limits_concurrency to: 1, key: ->(mailbox) { mailbox }

  def perform(mailbox)
    return unless mailbox.imap_configured?
    ImapFetcher.call(mailbox)
  rescue StandardError => e
    # Surface on the mailbox, next poll retries (backoff = poll interval).
    mailbox.update_columns(fetch_error: "#{e.class}: #{e.message}".truncate(255))
    Rails.logger.error("fetch: mailbox #{mailbox.id} failed: #{e.class} #{e.message}")
  end
end
