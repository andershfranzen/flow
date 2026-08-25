class Agent < ApplicationRecord
  ROLES = %w[admin user].freeze
  DEFAULT_NOTIFY_PREFS = {
    "new_unassigned" => true,
    "assigned_to_me" => true,
    "customer_reply" => true,
    "note_on_mine" => true
  }.freeze

  encrypts :otp_secret
  has_secure_password
  has_secure_token :session_token

  has_many :mailbox_accesses, dependent: :destroy
  has_many :mailboxes, through: :mailbox_accesses
  has_many :api_tokens, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :drafts, dependent: :destroy

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }

  before_validation { self.email = email.to_s.downcase.strip }
  # Password change invalidates existing sessions (C5).
  before_save :rotate_session_on_password_change

  def admin? = role == "admin"

  def accessible_mailboxes
    admin? ? Mailbox.all : mailboxes
  end

  def can_access?(mailbox)
    admin? || mailbox_accesses.exists?(mailbox_id: mailbox.id)
  end

  def notify_prefs
    DEFAULT_NOTIFY_PREFS.merge(super || {})
  end

  # Form params deliver ids as strings; comparisons need integers (D5).
  def muted_mailbox_ids = Array(super).map(&:to_i).reject(&:zero?)

  private

  def rotate_session_on_password_change
    self.session_token = self.class.generate_unique_secure_token if password_digest_changed? && !new_record?
  end
end
