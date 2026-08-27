require "test_helper"

class SsoTest < ActionDispatch::IntegrationTest
  RSA = OpenSSL::PKey::RSA.new(2048)
  JWK = JWT::JWK.new(RSA, { use: "sig", alg: "RS256" })
  ROTATED_RSA = OpenSSL::PKey::RSA.new(2048)
  ROTATED_JWK = JWT::JWK.new(ROTATED_RSA, { use: "sig", alg: "RS256" })
  TID = "11111111-2222-3333-4444-555555555555"

  setup do
    OrgSetting.current.update!(ms_client_id: "client-1", ms_client_secret: "s3cret", ms_tenant: TID,
                               ms_sso_enabled: true, sso_auto_provision: true,
                               sso_allowed_domains: "contoso.com", base_url: "https://flow.example.com")
    @agent = Agent.create!(email: "known@contoso.com", name: "Known", password: "secret123")
    Sso.define_singleton_method(:fetch_jwks) { { "keys" => [ JWK.export ] } }
    Rails.cache.delete("sso-jwks-#{TID}")
  end

  teardown { Sso.singleton_class.remove_method(:fetch_jwks) }

  def id_token(email:, nonce:, name: "Some One", tid: TID, aud: "client-1", exp: 5.minutes.from_now,
               oid: "oid-#{email}", sub: nil)
    payload = { iss: "https://login.microsoftonline.com/#{tid}/v2.0", aud: aud, exp: exp.to_i,
                tid: tid, nonce: nonce, email: email, name: name }
    payload[:oid] = oid if oid
    payload[:sub] = sub if sub
    JWT.encode(payload, RSA, "RS256", { kid: JWK[:kid] })
  end

  def stub_tokens(id_token)
    MailOauth.singleton_class.alias_method :orig_post_token, :post_token
    MailOauth.define_singleton_method(:post_token) { |*| { "id_token" => id_token } }
    yield
  ensure
    MailOauth.singleton_class.alias_method :post_token, :orig_post_token
    MailOauth.singleton_class.remove_method :orig_post_token
  end

  def start_and_callback(email:, **token_overrides)
    get "/auth/microsoft/start"
    assert_response :redirect
    query = Rack::Utils.parse_query(URI(response.location).query)
    stub_tokens(id_token(email: email, nonce: query["nonce"], **token_overrides)) do
      get "/auth/microsoft/callback", params: { code: "the-code", state: query["state"] }
    end
  end

  test "start redirects to entra with signed state and nonce" do
    get "/auth/microsoft/start"
    assert_response :redirect
    assert_includes response.location, "login.microsoftonline.com/#{TID}/oauth2/v2.0/authorize"
    query = Rack::Utils.parse_query(URI(response.location).query)
    assert_equal query["nonce"], Sso.verifier.verified(query["state"])["nonce"]
  end

  test "callback signs in an existing agent" do
    start_and_callback(email: "known@contoso.com")
    assert_redirected_to "/inbox"
    get "/api/me"
    assert_equal "known@contoso.com", response.parsed_body["email"]
    assert_equal [ TID, "oid-known@contoso.com" ], @agent.reload.values_at(:sso_tenant_id, :sso_subject)
  end

  test "callback auto-provisions an agent for an allowed domain" do
    start_and_callback(email: "new@contoso.com")
    assert_redirected_to "/inbox"
    agent = Agent.find_by(email: "new@contoso.com")
    assert_equal "user", agent.role
    assert_equal "Some One", agent.name
    assert_empty agent.mailbox_ids, "admins grant mailbox access after provisioning"
  end

  test "callback state is bound to the browser session" do
    attacker = open_session
    attacker.get "/auth/microsoft/start"
    query = Rack::Utils.parse_query(URI(attacker.response.location).query)

    stub_tokens(id_token(email: "known@contoso.com", nonce: query["nonce"])) do
      get "/auth/microsoft/callback", params: { code: "the-code", state: query["state"] }
    end

    assert_match %r{/login\?sso_error=}, response.location
    get "/api/me"
    assert_response :unauthorized
  end

  test "SSO rejects common tenant configuration and forged Host headers" do
    OrgSetting.current.update!(ms_tenant: "common")
    get "/auth/microsoft/start", headers: { "HOST" => "attacker.example" }
    assert_equal "/login?sso_error=sign_in_failed", URI(response.location).request_uri
    refute_includes response.location, "attacker.example"

    OrgSetting.current.update!(ms_tenant: TID)
    get "/auth/microsoft/start", headers: { "HOST" => "attacker.example" }
    query = Rack::Utils.parse_query(URI(response.location).query)
    assert_equal "https://flow.example.com/auth/microsoft/callback", query["redirect_uri"]
    refute_includes response.location, "attacker.example"
  end

  test "SSO requires a canonical HTTPS base URL" do
    OrgSetting.current.update!(base_url: "http://flow.example.com")
    get "/auth/microsoft/start"
    assert_response :unprocessable_entity
    assert_equal "sign_in_failed", response.body
    assert_nil response.location
  end

  test "development permits HTTP only on loopback hosts" do
    environment = Rails.env
    development = environment.method(:development?)
    environment.define_singleton_method(:development?) { true }

    OrgSetting.current.update!(base_url: "http://localhost:5173")
    assert_equal "http://localhost:5173", OrgSetting.current.canonical_base_url

    OrgSetting.current.update!(base_url: "http://attacker.example")
    assert_nil OrgSetting.current.canonical_base_url
  ensure
    environment&.define_singleton_method(:development?, development)
  end

  test "force password login only accepts explicit true values" do
    %w[0 false].each do |value|
      ENV["FLOW_FORCE_PASSWORD_LOGIN"] = value
      refute Sso.password_login_allowed?, value
    end

    ENV["FLOW_FORCE_PASSWORD_LOGIN"] = "1"
    assert Sso.password_login_allowed?
    ENV["FLOW_FORCE_PASSWORD_LOGIN"] = "true"
    assert Sso.password_login_allowed?

    ENV.delete("FLOW_FORCE_PASSWORD_LOGIN")
    OrgSetting.current.update!(base_url: "http://flow.example.com")
    refute Sso.password_login_allowed?, "an invalid SSO configuration must not reopen password login"
  ensure
    ENV.delete("FLOW_FORCE_PASSWORD_LOGIN")
  end

  test "SSO errors do not put provider details in redirect history" do
    get "/auth/microsoft/callback", params: {
      error: "access_denied", error_description: "attacker@example.com provider detail"
    }
    assert_equal "/login?sso_error=sign_in_failed", URI(response.location).request_uri
    refute_includes response.location, "attacker@example.com"
    refute_includes response.location, "provider detail"
  end

  test "SSO callbacks are rate limited before provider exchange" do
    store = SsoController.cache_store
    original_increment = store.method(:increment)
    memory = ActiveSupport::Cache::MemoryStore.new
    store.define_singleton_method(:increment) do |key, amount = 1, **options|
      memory.increment(key, amount, **options)
    end

    10.times do
      get "/auth/microsoft/callback", params: { error: "access_denied" }
      assert_response :redirect
    end
    get "/auth/microsoft/callback", params: { error: "access_denied" }
    assert_response :too_many_requests
  ensure
    store&.define_singleton_method(:increment, original_increment) if original_increment
  end

  test "an existing agent cannot be rebound to another subject" do
    start_and_callback(email: "known@contoso.com")
    start_and_callback(email: "known@contoso.com", oid: "different-oid")
    assert_equal "/login?sso_error=sign_in_failed", URI(response.location).request_uri
  end

  test "unknown signing key refreshes the cached jwks" do
    calls = 0
    Sso.singleton_class.remove_method(:fetch_jwks)
    Sso.define_singleton_method(:fetch_jwks) do
      calls += 1
      { "keys" => [ (calls == 1 ? JWK : ROTATED_JWK).export ] }
    end
    Rails.cache.delete("sso-jwks-#{TID}")
    Sso.jwks

    payload = { iss: "https://login.microsoftonline.com/#{TID}/v2.0", aud: "client-1",
                exp: 5.minutes.from_now.to_i, tid: TID, nonce: "fresh", email: "known@contoso.com" }
    token = JWT.encode(payload, ROTATED_RSA, "RS256", { kid: ROTATED_JWK[:kid] })

    assert_equal "known@contoso.com", Sso.verify_id_token!(token, nonce: "fresh")["email"]
    assert_equal 2, calls
  end

  test "unknown domain is rejected, no agent created" do
    start_and_callback(email: "mallory@evil.com")
    assert_match %r{/login\?sso_error=}, response.location
    assert_nil Agent.find_by(email: "mallory@evil.com")
  end

  test "auto-provision off rejects unknown accounts" do
    OrgSetting.current.update!(sso_auto_provision: false)
    start_and_callback(email: "new@contoso.com")
    assert_match %r{/login\?sso_error=}, response.location
    assert_nil Agent.find_by(email: "new@contoso.com")
  end

  test "wrong audience and wrong tenant are rejected" do
    start_and_callback(email: "known@contoso.com", aud: "other-client")
    assert_match %r{/login\?sso_error=}, response.location
    start_and_callback(email: "known@contoso.com", tid: "99999999-2222-3333-4444-555555555555")
    assert_match %r{/login\?sso_error=}, response.location
  end

  test "tampered state is rejected" do
    stub_tokens(id_token(email: "known@contoso.com", nonce: "x")) do
      get "/auth/microsoft/callback", params: { code: "c", state: "forged" }
    end
    assert_match %r{/login\?sso_error=}, response.location
  end

  test "password login is disabled while sso is enabled" do
    post "/api/session", params: { email: "known@contoso.com", password: "secret123" }
    assert_response :forbidden
    assert_equal "password_login_disabled", response.parsed_body["error"]

    get "/api/session"
    assert_equal({ "enabled" => true, "password_login" => false }, response.parsed_body["sso"])

    OrgSetting.current.update!(ms_sso_enabled: false)
    post "/api/session", params: { email: "known@contoso.com", password: "secret123" }
    assert_response :success
  end

  test "sso endpoints are inert when disabled" do
    OrgSetting.current.update!(ms_sso_enabled: false)
    get "/auth/microsoft/start"
    assert_redirected_to "/login"
  end
end
