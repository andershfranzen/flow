class FetchAllMailboxesJob < ApplicationJob
  queue_as :default

  def perform
    Mailbox.find_each { |mb| FetchMailboxJob.perform_later(mb) }
  end
end
