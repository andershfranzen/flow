require "test_helper"

class AuthTest < ActionDispatch::IntegrationTest
  setup do
    @admin = Agent.create!(email: "admin@example.com", name: "Admin", password: "secret123", role: "admin")
    @user = Agent.create!(email: "user@example.com", name: "User", password: "secret123", role: "user")
  end

  def login(email, password = "secret123")
    post "/api/session", params: { email: email, password: password }
  end

  test "wrong password is rejected" do
    login("admin@example.com", "nope")
    assert_response :unauthorized
  end

  test "login and me" do
    login("admin@example.com")
    assert_response :success
    get "/api/me"
    assert_equal "admin@example.com", response.parsed_body.dig("email")
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

  test "unauthenticated is rejected" do
    get "/api/agents"
    assert_response :unauthorized
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
