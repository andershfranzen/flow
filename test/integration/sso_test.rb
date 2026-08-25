require "test_helper"

class SsoTest < ActionDispatch::IntegrationTest
  RSA = OpenSSL::PKey::RSA.new(2048)
  JWK = JWT::JWK.new(RSA, { use: "sig", alg: "RS256" })
  TID = "11111111-2222-3333-4444-555555555555"

  setup do
    OrgSetting.current.update!(ms_client_id: "client-1", ms_client_secret: "s3cret", ms_tenant: TID,
                               ms_sso_enabled: true, sso_auto_provision: true,
                               sso_allowed_domains: "contoso.com")
    @agent = Agent.create!(email: "known@contoso.com", name: "Known", password: "secret123")
    Sso.define_singleton_method(:fetch_jwks) { { "keys" => [ JWK.export ] } }
    Rails.cache.delete("sso-jwks-#{TID}")
  end

  teardown { Sso.singleton_class.remove_method(:fetch_jwks) }

  def id_token(email:, nonce:, name: "Some One", tid: TID, aud: "client-1", exp: 5.minutes.from_now)
    payload = { iss: "https://login.microsoftonline.com/#{tid}/v2.0", aud: aud, exp: exp.to_i,
                tid: tid, nonce: nonce, email: email, name: name }
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
  end

  test "callback auto-provisions an agent for an allowed domain" do
    start_and_callback(email: "new@contoso.com")
    assert_redirected_to "/inbox"
    agent = Agent.find_by(email: "new@contoso.com")
    assert_equal "user", agent.role
    assert_equal "Some One", agent.name
    assert_equal Mailbox.ids.sort, agent.mailbox_ids.sort, "new agents get every mailbox by default"
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
