require "net/http"

# OAuth2 (XOAUTH2) for Microsoft 365 and Google mailboxes (A5).
# The operator registers an app with the provider and pastes client id/secret
# into Settings → Organisation; each mailbox then connects via the browser.
class MailOauth
  class Error < StandardError; end

  PROVIDERS = %w[microsoft google].freeze

  def self.settings = OrgSetting.current

  def self.configured?(provider)
    case provider
    when "microsoft" then settings.ms_client_id.present? && settings.ms_client_secret.present?
    when "microsoft_app"
      settings.ms_client_id.present? && settings.ms_client_secret.present? &&
        settings.ms_tenant.present? && !%w[common organizations consumers].include?(settings.ms_tenant.downcase)
    when "google"    then settings.google_client_id.present? && settings.google_client_secret.present?
    else false
    end
  end

  def self.provider_config(provider)
    s = settings
    case provider
    when "microsoft"
      tenant = s.ms_tenant.presence || "common"
      { auth_url: "https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/authorize",
        token_url: "https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/token",
        scope: "offline_access https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send",
        client_id: s.ms_client_id, client_secret: s.ms_client_secret,
        imap_host: "outlook.office365.com", smtp_host: "smtp.office365.com", smtp_port: 587 }
    when "google"
      { auth_url: "https://accounts.google.com/o/oauth2/v2/auth",
        token_url: "https://oauth2.googleapis.com/token",
        scope: "https://mail.google.com/",
        client_id: s.google_client_id, client_secret: s.google_client_secret,
        imap_host: "imap.gmail.com", smtp_host: "smtp.gmail.com", smtp_port: 587 }
    else
      raise Error, "unknown provider #{provider}"
    end
  end

  def self.authorize_url(provider, mailbox, redirect_uri)
    config = provider_config(provider)
    state = verifier.generate({ mailbox_id: mailbox.id, provider: provider }, expires_in: 15.minutes)
    params = {
      client_id: config[:client_id], response_type: "code", redirect_uri: redirect_uri,
      scope: config[:scope], state: state, access_type: "offline", prompt: "consent",
      login_hint: mailbox.address
    }
    "#{config[:auth_url]}?#{URI.encode_www_form(params)}"
  end

  def self.verify_state!(state)
    verifier.verified(state) or raise Error, "invalid or expired state"
  end

  # Exchange the authorization code and store tokens on the mailbox.
  def self.connect!(mailbox, provider, code, redirect_uri)
    config = provider_config(provider)
    tokens = post_token(config, grant_type: "authorization_code", code: code, redirect_uri: redirect_uri)
    raise Error, "no refresh token returned — remove the app's prior consent and retry" if tokens["refresh_token"].blank?
    mailbox.update!(
      auth_kind: provider,
      oauth_refresh_token: tokens["refresh_token"],
      oauth_access_token: tokens["access_token"],
      oauth_expires_at: Time.current + tokens.fetch("expires_in", 3600).to_i,
      imap_host: mailbox.imap_host.presence || config[:imap_host],
      imap_port: 993, imap_ssl: true,
      imap_user: mailbox.imap_user.presence || mailbox.address,
      smtp_host: mailbox.smtp_host.presence || config[:smtp_host],
      smtp_port: config[:smtp_port], smtp_security: "starttls",
      smtp_user: mailbox.smtp_user.presence || mailbox.address
    )
  end

  # A valid access token, refreshed when within a minute of expiry.
  def self.access_token!(mailbox)
    return application_access_token! if mailbox.auth_kind == "microsoft_app"

    raise Error, "mailbox #{mailbox.address} is not OAuth-connected" if mailbox.oauth_refresh_token.blank?
    return mailbox.oauth_access_token if mailbox.oauth_access_token.present? &&
                                         mailbox.oauth_expires_at&.after?(1.minute.from_now)
    config = provider_config(mailbox.auth_kind)
    tokens = post_token(config, grant_type: "refresh_token", refresh_token: mailbox.oauth_refresh_token)
    mailbox.update!(
      oauth_access_token: tokens.fetch("access_token"),
      oauth_expires_at: Time.current + tokens.fetch("expires_in", 3600).to_i,
      oauth_refresh_token: tokens["refresh_token"].presence || mailbox.oauth_refresh_token
    )
    mailbox.oauth_access_token
  end

  # Exchange app-only access uses one short-lived token for every mailbox
  # explicitly granted to the service principal by the tenant administrator.
  def self.application_access_token!
    raise Error, "Microsoft application access needs a client ID, secret, and tenant ID" unless configured?("microsoft_app")

    s = settings
    Rails.cache.fetch([ "mail-oauth", "microsoft-app", s.ms_tenant, s.ms_client_id ], expires_in: 50.minutes) do
      post_token(provider_config("microsoft"),
        grant_type: "client_credentials", scope: "https://outlook.office365.com/.default")
        .fetch("access_token") { raise Error, "token endpoint returned no access token" }
    end
  end

  def self.post_token(config, params)
    uri = URI(config[:token_url])
    response = Net::HTTP.post_form(uri, params.merge(
      client_id: config[:client_id], client_secret: config[:client_secret]
    ))
    body = JSON.parse(response.body) rescue {}
    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "token endpoint #{response.code}: #{body['error_description'] || body['error'] || 'unknown'}"
    end
    body
  end

  def self.verifier = Rails.application.message_verifier("mail-oauth")
end
