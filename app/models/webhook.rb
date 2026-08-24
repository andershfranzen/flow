class Webhook < ApplicationRecord
  EVENTS = %w[thread.created message.inbound message.outbound thread.assigned thread.status].freeze
  validates :url, presence: true, format: { with: %r{\Ahttps?://} }
  before_validation { self.secret = SecureRandom.hex(24) if secret.blank? }

  def subscribed?(event) = events.blank? || events.include?(event)
end
