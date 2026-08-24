class Mailbox < ApplicationRecord
  encrypts :imap_password, :smtp_password

  has_many :mailbox_accesses, dependent: :destroy
  has_many :agents, through: :mailbox_accesses
  has_many :conversations, dependent: :destroy
  has_many :saved_replies, dependent: :destroy
  has_many :inbound_dedups, dependent: :delete_all

  validates :address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :smtp_security, inclusion: { in: %w[starttls ssl none] }

  before_validation { self.address = address.to_s.downcase.strip }

  # A To/Cc/Bcc address matches this mailbox, including plus-addressing (A12).
  def matches_address?(email)
    email = email.to_s.downcase
    return true if email == address
    local, domain = address.split("@", 2)
    email.match?(/\A#{Regexp.escape(local)}\+[^@]*@#{Regexp.escape(domain)}\z/)
  end

  def imap_configured? = imap_host.present? && imap_user.present? && imap_password.present?
  def smtp_configured? = smtp_host.present?
end
