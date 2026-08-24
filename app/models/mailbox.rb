class Mailbox < ApplicationRecord
  AUTH_KINDS = %w[password microsoft google].freeze

  encrypts :imap_password, :smtp_password, :oauth_refresh_token, :oauth_access_token

  has_many :mailbox_accesses, dependent: :destroy
  has_many :agents, through: :mailbox_accesses
  has_many :conversations, dependent: :destroy
  has_many :saved_replies, dependent: :destroy
  has_many :inbound_dedups, dependent: :delete_all

  validates :address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :smtp_security, inclusion: { in: %w[starttls ssl none] }
  validates :auth_kind, inclusion: { in: AUTH_KINDS }

  before_validation { self.address = address.to_s.downcase.strip }

  # A To/Cc/Bcc address matches this mailbox, including plus-addressing (A12).
  def matches_address?(email)
    email = email.to_s.downcase
    return true if email == address
    local, domain = address.split("@", 2)
    email.match?(/\A#{Regexp.escape(local)}\+[^@]*@#{Regexp.escape(domain)}\z/)
  end

  def oauth? = auth_kind != "password"
  def oauth_connected? = oauth? && oauth_refresh_token.present?

  def imap_configured?
    return imap_host.present? && imap_user.present? && oauth_connected? if oauth?
    imap_host.present? && imap_user.present? && imap_password.present?
  end

  def smtp_configured?
    return smtp_host.present? && oauth_connected? if oauth?
    smtp_host.present?
  end

  def smtp_options
    opts = { address: smtp_host, port: smtp_port, domain: address.split("@").last }
    if oauth?
      opts.merge!(user_name: smtp_user.presence || self.address, password: MailOauth.access_token!(self),
                  authentication: :xoauth2)
    elsif smtp_user.present?
      opts.merge!(user_name: smtp_user, password: smtp_password, authentication: :plain)
    end
    case smtp_security
    when "ssl"      then opts.merge!(tls: true)
    when "starttls" then opts.merge!(enable_starttls_auto: true)
    when "none"     then opts.merge!(enable_starttls_auto: false)
    end
    opts
  end
end
