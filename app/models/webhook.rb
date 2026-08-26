class Webhook < ApplicationRecord
  EVENTS = %w[thread.created message.inbound message.outbound thread.assigned thread.status].freeze

  # Encrypt newly persisted secrets while allowing rows written before this
  # declaration to remain readable until they are explicitly rotated.
  encrypts :secret, support_unencrypted_data: true

  validates :url, presence: true, format: { with: %r{\Ahttps?://} }
  before_validation { self.secret = SecureRandom.hex(24) if secret.blank? }

  def subscribed?(event) = events.blank? || events.include?(event)

  def self.emit(event, payload)
    where(enabled: true).find_each do |hook|
      WebhookDeliveryJob.perform_later(hook, event, payload.as_json) if hook.subscribed?(event)
    end
  end
end
