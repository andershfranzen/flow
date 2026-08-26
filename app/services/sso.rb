require "net/http"

# "Sign in with Microsoft" (OIDC authorization code flow) reusing the same
# Entra app as mailbox OAuth. When enabled it replaces password login entirely
# (one or the other); FLOW_FORCE_PASSWORD_LOGIN=1 is the break-glass override.
class Sso
  class Error < StandardError; end
  TENANT_GUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  FORCE_PASSWORD_VALUES = %w[1 true].freeze

  def self.settings = OrgSetting.current

  def self.enabled?
    settings.ms_sso_enabled && configured?
  end

  def self.configured?
    MailOauth.configured?("microsoft") && tenant_guid? && settings.canonical_base_url.present?
  end

  # Password login is refused while SSO is on, unless the operator forces it
  # (e.g. locked out by a broken Entra app).
  def self.password_login_allowed?
    !settings.ms_sso_enabled || FORCE_PASSWORD_VALUES.include?(ENV["FLOW_FORCE_PASSWORD_LOGIN"].to_s.strip.downcase)
  end

  def self.tenant = settings.ms_tenant.to_s.strip

  def self.authorize_url(redirect_uri, browser_nonce:)
    ensure_configured!
    validate_redirect_uri!(redirect_uri)
    nonce = SecureRandom.hex(16)
    state = verifier.generate({ nonce: nonce, browser_nonce: browser_nonce }, expires_in: 15.minutes)
    params = {
      client_id: settings.ms_client_id, response_type: "code", redirect_uri: redirect_uri,
      response_mode: "query", scope: "openid email profile", state: state, nonce: nonce
    }
    "https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/authorize?#{URI.encode_www_form(params)}"
  end

  # Full callback handling: state → code exchange → id_token verification →
  # agent lookup / provisioning. Returns the Agent or raises Sso::Error.
  def self.authenticate!(code:, state:, redirect_uri:, browser_nonce:)
    ensure_configured!
    validate_redirect_uri!(redirect_uri)
    data = verifier.verified(state) or raise Error, "invalid or expired state"
    unless browser_nonce.present? && ActiveSupport::SecurityUtils.secure_compare(data["browser_nonce"].to_s, browser_nonce)
      raise Error, "invalid or expired state"
    end
    config = MailOauth.provider_config("microsoft")
    tokens = MailOauth.post_token(config, grant_type: "authorization_code", code: code,
                                          redirect_uri: redirect_uri, scope: "openid email profile")
    claims = verify_id_token!(tokens["id_token"].to_s, nonce: data["nonce"])
    agent_for(claims)
  rescue MailOauth::Error => e
    raise Error, e.message
  end

  def self.verify_id_token!(id_token, nonce:)
    ensure_configured!
    raise Error, "no id_token returned" if id_token.blank?
    claims, _header = JWT.decode(id_token, nil, true,
      algorithms: [ "RS256" ], jwks: method(:jwks),
      verify_aud: true, aud: settings.ms_client_id, verify_expiration: true)
    tid = claims["tid"].to_s
    unless tid.match?(TENANT_GUID) && claims["iss"] == "https://login.microsoftonline.com/#{tid}/v2.0"
      raise Error, "unexpected token issuer"
    end
    unless tid.casecmp?(tenant)
      raise Error, "token is from a different tenant"
    end
    raise Error, "nonce mismatch" unless nonce.present? && claims["nonce"] == nonce
    claims
  rescue JWT::DecodeError => e
    raise Error, "id_token verification failed: #{e.message}"
  end

  def self.agent_for(claims)
    ensure_configured!
    email = (claims["email"].presence || claims["preferred_username"]).to_s.downcase.strip
    raise Error, "no email address in the Microsoft account" unless email.match?(/\A[^\s@]+@[^\s@]+\z/)
    tenant_id = claims["tid"].to_s
    subject = (claims["oid"].presence || claims["sub"]).to_s.presence
    raise Error, "no stable Microsoft subject" if subject.blank?
    domain = email.split("@", 2).last
    raise Error, "#{domain} is not in the allowed sign-in domains" unless allowed_domain?(domain)

    agent = Agent.find_by(sso_tenant_id: tenant_id, sso_subject: subject)
    return agent if agent

    agent = Agent.find_by(email: email)
    return bind_agent!(agent, tenant_id, subject) if agent

    raise Error, "no Flow account for #{email} (auto-provisioning is off)" unless settings.sso_auto_provision
    Agent.create!(email: email, name: claims["name"].presence || email.split("@").first,
                  role: "user", password: SecureRandom.hex(24),
                  sso_tenant_id: tenant_id, sso_subject: subject)
  rescue ActiveRecord::RecordNotUnique
    raise Error, "Microsoft account is already linked to another Flow account"
  end

  # Microsoft signing keys, cached; keyed by tenant so a tenant change refetches.
  def self.jwks(options = {})
    ensure_configured!
    Rails.cache.delete("sso-jwks-#{tenant}") if options[:invalidate]
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

  def self.tenant_guid? = tenant.match?(TENANT_GUID)

  def self.ensure_configured!
    raise Error, "SSO is not configured" unless configured?
  end

  def self.validate_redirect_uri!(redirect_uri)
    expected = "#{settings.canonical_base_url}/auth/microsoft/callback"
    raise Error, "SSO redirect URI is not configured" unless redirect_uri.to_s == expected
  end

  def self.allowed_domain?(domain)
    settings.sso_allowed_domains.to_s.downcase.split(/[,\s]+/).reject(&:blank?).include?(domain.downcase)
  end

  def self.bind_agent!(agent, tenant_id, subject)
    if agent.sso_tenant_id.present? || agent.sso_subject.present?
      return agent if agent.sso_tenant_id.to_s.casecmp?(tenant_id) && agent.sso_subject.to_s == subject
      raise Error, "Flow account is linked to a different Microsoft account"
    end

    agent.update!(sso_tenant_id: tenant_id, sso_subject: subject)
    agent
  rescue ActiveRecord::RecordNotUnique
    raise Error, "Microsoft account is already linked to another Flow account"
  end

  def self.verifier = Rails.application.message_verifier("sso")
end
