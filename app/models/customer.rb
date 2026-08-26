class Customer < ApplicationRecord
  has_many :conversations, dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  before_validation { self.email = email.to_s.downcase.strip }

  def accessible_to?(agent)
    conversations.where(mailbox_id: agent.accessible_mailboxes.select(:id)).exists?
  end

  def fully_accessible_to?(agent)
    mailbox_ids = agent.accessible_mailboxes.select(:id)
    accessible_to?(agent) && !conversations.where.not(mailbox_id: mailbox_ids).exists?
  end

  def self.accessible_for_email(email, agent)
    normalized = email.to_s.downcase.strip
    return nil if normalized.blank?

    alias_pattern = "%\"#{sanitize_sql_like(normalized)}\"%"
    joins(:conversations)
      .where(conversations: { mailbox_id: agent.accessible_mailboxes.select(:id) })
      .where("customers.email = :email OR CAST(customers.emails AS TEXT) LIKE :alias", email: normalized, alias: alias_pattern)
      .distinct
      .first
  end

  def self.for_email(email, name: nil)
    email = email.to_s.downcase.strip
    # Merged customers keep their old addresses in emails[] — match those too.
    customer = find_by(email: email) ||
               where("CAST(emails AS TEXT) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like("\"#{email}\"")}%").first ||
               create!(email: email)
    customer.update!(name: name) if name.present? && customer.name.blank?
    customer
  end

  def display_name = name.presence || email
end
