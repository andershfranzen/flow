require "test_helper"

class AuthTest < ActionDispatch::IntegrationTest
  setup do
    @admin = Agent.create!(email: "admin@example.com", name: "Admin", password: "secret123", role: "admin")
    @user = Agent.create!(email: "user@example.com", name: "User", password: "secret123", role: "user")
  end

  def login(email, password = "secret123", otp_code: nil)
    params = { email: email, password: password }
    params[:otp_code] = otp_code if otp_code
    post "/api/session", params: params
  end

  test "wrong password is rejected" do
    login("admin@example.com", "nope")
    assert_response :unauthorized
  end

  test "unknown email still performs a bcrypt comparison" do
    original_new = BCrypt::Password.method(:new)
    checked_dummy = false
    BCrypt::Password.define_singleton_method(:new) do |digest|
      checked_dummy = true if digest == Api::SessionsController::DUMMY_PASSWORD_DIGEST
      original_new.call(digest)
    end
    login("missing@example.com", "nope")

    assert_response :unauthorized
    assert_equal({ "error" => "invalid_credentials" }, response.parsed_body)
    assert checked_dummy
  ensure
    BCrypt::Password.define_singleton_method(:new, original_new) if original_new
  end

  test "login account limit follows normalized email across source IPs" do
    store = Api::SessionsController.cache_store
    original_increment = store.method(:increment)
    memory = ActiveSupport::Cache::MemoryStore.new
    store.define_singleton_method(:increment) do |key, amount = 1, **options|
      memory.increment(key, amount, **options)
    end

    10.times do |index|
      post "/api/session", params: { email: " USER@EXAMPLE.COM ", password: "wrong" },
                           headers: { "REMOTE_ADDR" => "198.51.100.#{index + 1}" }
      assert_response :unauthorized
    end
    post "/api/session", params: { email: "user@example.com", password: "wrong" },
                         headers: { "REMOTE_ADDR" => "198.51.100.20" }
    assert_response :too_many_requests
  ensure
    store&.define_singleton_method(:increment, original_increment) if original_increment
  end

  test "login and me" do
    login("admin@example.com")
    assert_response :success
    get "/api/me"
    assert_equal "admin@example.com", response.parsed_body.dig("email")
  end

  test "agent listing exposes only assignment identity to users" do
    login("user@example.com")
    get "/api/agents"
    assert_response :success
    user_view = response.parsed_body.find { |agent| agent["email"] == "admin@example.com" }
    assert_equal %w[email id name], user_view.keys.sort

    login("admin@example.com")
    get "/api/agents"
    admin_view = response.parsed_body.find { |agent| agent["email"] == "user@example.com" }
    assert admin_view.key?("signature")
    assert admin_view.key?("otp_required")
    assert admin_view.key?("mailbox_ids")
    assert admin_view.key?("notify_prefs")
  end

  test "admin creates an agent, user cannot" do
    login("admin@example.com")
    post "/api/agents", params: { email: "new@example.com", name: "New", password: "secret123", role: "user" }
    assert_response :created

    login("user@example.com")
    post "/api/agents", params: { email: "x@example.com", name: "X", password: "secret123" }
    assert_response :forbidden
  end

  test "password change invalidates existing sessions" do
    login("user@example.com")
    get "/api/me"
    assert_response :success

    @user.update!(password: "newsecret123")
    get "/api/me"
    assert_response :unauthorized
  end

  test "password change requires the current password" do
    login("user@example.com")

    patch "/api/me", params: { name: "Renamed" }
    assert_response :success
    assert_equal "Renamed", @user.reload.name

    patch "/api/me", params: { password: "newsecret123" }
    assert_response :unprocessable_entity
    assert_equal "invalid_current_password", response.parsed_body["error"]

    patch "/api/me", params: { password: "newsecret123", current_password: "nope" }
    assert_response :unprocessable_entity

    patch "/api/me", params: { password: "newsecret123", current_password: "secret123" }
    assert_response :success
    get "/api/me"
    assert_response :success

    delete "/api/session"
    login("user@example.com", "newsecret123")
    assert_response :success
  end

  test "logout invalidates a copied session cookie" do
    browser = open_session
    browser.post "/api/session", params: { email: "user@example.com", password: "secret123" }
    browser.assert_response :success
    copied_cookie = browser.cookies.to_hash.map { |key, value| "#{key}=#{value}" }.join("; ")

    browser.delete "/api/session"
    browser.assert_response :no_content

    attacker = open_session
    attacker.get "/api/me", headers: { "Cookie" => copied_cookie }
    attacker.assert_response :unauthorized
  end

  test "bearer logout does not rotate browser sessions" do
    browser = open_session
    browser.post "/api/session", params: { email: "user@example.com", password: "secret123" }
    browser.assert_response :success
    _, bearer = ApiToken.issue(agent: @user, name: "read", scope: "read")
    session_token = @user.reload.session_token

    api = open_session
    api.delete "/api/session", headers: { "Authorization" => "Bearer #{bearer}" }
    api.assert_response :no_content
    assert_equal session_token, @user.reload.session_token

    browser.get "/api/me"
    browser.assert_response :success
  end

  test "malformed authorization headers cannot skip cookie logout revocation" do
    browser = open_session
    browser.post "/api/session", params: { email: "user@example.com", password: "secret123" }
    browser.assert_response :success
    copied_cookie = browser.cookies.to_hash.map { |key, value| "#{key}=#{value}" }.join("; ")

    browser.delete "/api/session", headers: { "Authorization" => "Basic ignored" }
    browser.assert_response :no_content

    attacker = open_session
    attacker.get "/api/me", headers: { "Cookie" => copied_cookie }
    attacker.assert_response :unauthorized
  end

  test "two-factor setup keeps the secret pending until enabled" do
    login("user@example.com")

    post "/api/me/2fa/setup"
    assert_response :success
    secret = response.parsed_body.fetch("secret")
    assert_nil @user.reload.otp_secret
    refute @user.otp_required?

    post "/api/me/2fa/enable", params: { code: Totp.code(secret) }
    assert_response :success
    assert_equal secret, @user.reload.otp_secret
    assert @user.otp_required?

    post "/api/me/2fa/disable", params: { code: Totp.code(secret) }
    assert_response :success
    assert_nil @user.reload.otp_secret
    refute @user.otp_required?
  end

  test "two-factor setup cannot disarm an armed secret" do
    secret = Totp.generate_secret
    @user.update!(otp_secret: secret, otp_required: true)
    login("user@example.com", otp_code: Totp.code(secret))

    post "/api/me/2fa/setup"
    assert_response :unprocessable_entity
    assert_equal "otp_already_enabled", response.parsed_body["error"]
    assert_equal secret, @user.reload.otp_secret
    assert @user.otp_required?
  end

  test "armed password changes require a current TOTP code" do
    secret = Totp.generate_secret
    @user.update!(otp_secret: secret, otp_required: true)
    login("user@example.com", otp_code: Totp.code(secret))

    patch "/api/me", params: { password: "newsecret123", current_password: "secret123" }
    assert_response :unprocessable_entity
    assert_equal "otp_required", response.parsed_body["error"]

    patch "/api/me", params: { password: "newsecret123", current_password: "secret123", otp_code: "000000" }
    assert_response :unprocessable_entity

    patch "/api/me", params: { password: "newsecret123", current_password: "secret123", otp_code: Totp.code(secret) }
    assert_response :success
    delete "/api/session"
    login("user@example.com", "newsecret123", otp_code: Totp.code(secret))
    assert_response :success
  end

  test "api token creation needs a cookie reauthentication and expires" do
    login("admin@example.com")

    post "/api/api_tokens", params: { name: "missing-password" }
    assert_response :unprocessable_entity
    assert_equal "invalid_current_password", response.parsed_body["error"]

    post "/api/api_tokens", params: { name: "ci", current_password: "secret123", scope: "read" }
    assert_response :created
    raw = response.parsed_body.fetch("token")
    token = @admin.api_tokens.order(:id).last
    assert token.expires_at.future?

    get "/api/agents", headers: { "Authorization" => "Bearer #{raw}" }
    assert_response :success

    token.update!(expires_at: 1.minute.ago)
    get "/api/agents", headers: { "Authorization" => "Bearer #{raw}" }
    assert_response :unauthorized
  end

  test "api token creation rejects bearer sessions and is revoked on password change" do
    login("admin@example.com")
    _, bearer = ApiToken.issue(agent: @admin, name: "existing", scope: "read")

    post "/api/api_tokens", params: { name: "minted", current_password: "secret123" },
                         headers: { "Authorization" => "Bearer #{bearer}" }
    assert_response :forbidden

    post "/api/api_tokens", params: { name: "existing-2", current_password: "secret123" }
    assert_response :created
    raw = response.parsed_body.fetch("token")

    patch "/api/me", params: { password: "newsecret123", current_password: "secret123" }
    assert_response :success
    assert_nil ApiToken.authenticate(raw)
  end

  test "unauthenticated is rejected" do
    get "/api/agents"
    assert_response :unauthorized
  end

  test "admin can upload, expose and remove a company logo" do
    login("admin@example.com")
    png = Rack::Test::UploadedFile.new(StringIO.new("\x89PNGfake"), "image/png", original_filename: "logo.png")
    patch "/api/org_settings", params: { site_name: "Acme", logo: png }
    assert_response :success
    logo_url = response.parsed_body["logo_url"]
    assert logo_url.present?

    get "/api/session"
    assert_equal logo_url, response.parsed_body.dig("org", "logo_url")

    bad = Rack::Test::UploadedFile.new(StringIO.new("<svg/>"), "image/svg+xml", original_filename: "evil.svg")
    patch "/api/org_settings", params: { logo: bad }
    assert_response :unprocessable_entity

    patch "/api/org_settings", params: { remove_logo: "1" }
    assert_nil response.parsed_body["logo_url"]
  end

  test "admin sets a brand theme; junk keys and values are filtered" do
    login("admin@example.com")
    patch "/api/org_settings", params: { theme: { accent: "#1e3a8a", bogus_key: "#111111",
                                                  danger: "red; background:url(x)", warn: "#12345" } },
                               as: :json
    assert_response :success
    assert_equal({ "accent" => "#1e3a8a" }, response.parsed_body["theme"])

    get "/api/session"
    assert_equal "#1e3a8a", response.parsed_body.dig("org", "theme", "accent")
  end

  test "api token authenticates and respects scope" do
    _, raw = ApiToken.issue(agent: @admin, name: "ci", scope: "read")
    get "/api/agents", headers: { "Authorization" => "Bearer #{raw}" }
    assert_response :success

    post "/api/agents", params: { email: "t@example.com", name: "T", password: "secret123" },
                        headers: { "Authorization" => "Bearer #{raw}" }
    assert_response :forbidden
  end
end
