require "net/http"

# "Sign in with Microsoft" (OIDC authorization code flow) reusing the same
# Entra app as mailbox OAuth. When enabled it replaces password login entirely
# (one or the other); FLOW_FORCE_PASSWORD_LOGIN=1 is the break-glass override.
class Sso
  class Error < StandardError; end

  def self.settings = OrgSetting.current

  def self.enabled?
    settings.ms_sso_enabled && MailOauth.configured?("microsoft")
  end

  # Password login is refused while SSO is on, unless the operator forces it
  # (e.g. locked out by a broken Entra app).
  def self.password_login_allowed?
    !enabled? || ENV["FLOW_FORCE_PASSWORD_LOGIN"].present?
  end

  def self.tenant = settings.ms_tenant.presence || "common"

  def self.authorize_url(redirect_uri)
    nonce = SecureRandom.hex(16)
    state = verifier.generate({ nonce: nonce }, expires_in: 15.minutes)
    params = {
      client_id: settings.ms_client_id, response_type: "code", redirect_uri: redirect_uri,
      response_mode: "query", scope: "openid email profile", state: state, nonce: nonce
    }
    "https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/authorize?#{URI.encode_www_form(params)}"
  end

  # Full callback handling: state → code exchange → id_token verification →
  # agent lookup / provisioning. Returns the Agent or raises Sso::Error.
  def self.authenticate!(code:, state:, redirect_uri:)
    data = verifier.verified(state) or raise Error, "invalid or expired state"
    config = MailOauth.provider_config("microsoft")
    tokens = MailOauth.post_token(config, grant_type: "authorization_code", code: code,
                                          redirect_uri: redirect_uri, scope: "openid email profile")
    claims = verify_id_token!(tokens["id_token"].to_s, nonce: data["nonce"])
    agent_for(claims)
  rescue MailOauth::Error => e
    raise Error, e.message
  end

  def self.verify_id_token!(id_token, nonce:)
    raise Error, "no id_token returned" if id_token.blank?
    claims, _header = JWT.decode(id_token, nil, true,
      algorithms: [ "RS256" ], jwks: jwks,
      verify_aud: true, aud: settings.ms_client_id, verify_expiration: true)
    tid = claims["tid"].to_s
    unless claims["iss"] == "https://login.microsoftonline.com/#{tid}/v2.0" && tid.present?
      raise Error, "unexpected token issuer"
    end
    # Tenant-specific config (a GUID) must match the token's tenant.
    if tenant.match?(/\A[0-9a-f-]{36}\z/i) && !tid.casecmp?(tenant)
      raise Error, "token is from a different tenant"
    end
    raise Error, "nonce mismatch" unless nonce.present? && claims["nonce"] == nonce
    claims
  rescue JWT::DecodeError => e
    raise Error, "id_token verification failed: #{e.message}"
  end

  def self.agent_for(claims)
    email = (claims["email"].presence || claims["preferred_username"]).to_s.downcase.strip
    raise Error, "no email address in the Microsoft account" unless email.match?(/\A[^\s@]+@[^\s@]+\z/)
    agent = Agent.find_by(email: email)
    return agent if agent

    raise Error, "no Flow account for #{email} (auto-provisioning is off)" unless settings.sso_auto_provision
    domains = settings.sso_allowed_domains.to_s.downcase.split(/[,\s]+/).reject(&:blank?)
    unless domains.include?(email.split("@").last)
      raise Error, "#{email.split('@').last} is not in the allowed sign-in domains"
    end
    agent = Agent.create!(email: email, name: claims["name"].presence || email.split("@").first,
                          role: "user", password: SecureRandom.hex(24))
    # Fresh sign-ins start with access to every mailbox; admins can trim per agent.
    Mailbox.ids.each { |id| agent.mailbox_accesses.create!(mailbox_id: id) }
    agent
  end

  # Microsoft signing keys, cached; keyed by tenant so a tenant change refetches.
  def self.jwks
    keys = Rails.cache.fetch("sso-jwks-#{tenant}", expires_in: 12.hours) { fetch_jwks }
    JWT::JWK::Set.new(keys)
  end

  def self.fetch_jwks
    uri = URI("https://login.microsoftonline.com/#{tenant}/discovery/v2.0/keys")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri)
    end
    raise Error, "could not fetch Microsoft signing keys (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  def self.verifier = Rails.application.message_verifier("sso")
end
