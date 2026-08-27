require "net/imap"
require "net/smtp"

class Mailbox < ApplicationRecord
  AUTH_KINDS = %w[password microsoft microsoft_app google].freeze

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
  before_validation :apply_microsoft_app_defaults

  # A To/Cc/Bcc address matches this mailbox, including plus-addressing (A12).
  def matches_address?(email)
    email = email.to_s.downcase
    return true if email == address
    local, domain = address.split("@", 2)
    email.match?(/\A#{Regexp.escape(local)}\+[^@]*@#{Regexp.escape(domain)}\z/)
  end

  def oauth? = auth_kind != "password"
  def oauth_connected? = auth_kind == "microsoft_app" ? MailOauth.configured?(auth_kind) : oauth? && oauth_refresh_token.present?

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

  # Try a real IMAP login and SMTP connect; used by the API test button and
  # the MCP test_mailbox tool.
  def connection_test = { imap: test_imap, smtp: test_smtp }

  def test_imap
    return { ok: false, error: "not configured" } unless imap_configured?
    imap = Net::IMAP.new(imap_host, port: imap_port, ssl: imap_ssl)
    if oauth?
      imap.authenticate("XOAUTH2", imap_user, MailOauth.access_token!(self))
    else
      imap.login(imap_user, imap_password)
    end
    imap.examine(imap_folder)
    { ok: true }
  rescue StandardError => e
    { ok: false, error: e.message.truncate(200) }
  ensure
    imap&.disconnect rescue nil
  end

  def test_smtp
    return { ok: false, error: "not configured" } unless smtp_configured?
    opts = smtp_options
    smtp = Net::SMTP.new(opts[:address], opts[:port])
    smtp.enable_starttls_auto if opts[:enable_starttls_auto]
    smtp.enable_tls if opts[:tls]
    smtp.open_timeout = 5
    if opts[:user_name]
      smtp.start(opts[:domain], opts[:user_name], opts[:password], opts[:authentication]) {}
    else
      smtp.start(opts[:domain]) {}
    end
    { ok: true }
  rescue StandardError => e
    { ok: false, error: e.message.truncate(200) }
  end

  private

  def apply_microsoft_app_defaults
    return unless auth_kind == "microsoft_app"

    self.imap_host = "outlook.office365.com" if imap_host.blank?
    self.imap_user = address if imap_user.blank?
    self.smtp_host = "smtp.office365.com" if smtp_host.blank?
    self.smtp_user = address if smtp_user.blank?
  end

end
