# Nightly hygiene. Delivered raw emails self-incinerate via Action Mailbox
# (30 days); this catches what that misses and keeps small tables small.
class HousekeepingJob < ApplicationJob
  queue_as :default

  def perform
    ActionMailbox::InboundEmail.where(status: :failed)
                               .where(created_at: ..90.days.ago).find_each(&:destroy)
    Notification.where.not(read_at: nil).where(created_at: ..90.days.ago).delete_all

    # Trash/spam retention: destroyed for good after N days (0 disables).
    days = ENV.fetch("FLOW_TRASH_RETENTION_DAYS", "30").to_i
    if days.positive?
      Conversation.where(status: %w[trash spam])
                  .where(updated_at: ..days.days.ago).find_each(&:destroy)
    end
  end
end
