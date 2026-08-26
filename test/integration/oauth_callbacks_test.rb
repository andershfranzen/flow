require "test_helper"

class OauthCallbacksTest < ActionDispatch::IntegrationTest
  test "callback posts only to the configured app origin and closes the popup" do
    origin = "https://flow.example.com"
    OrgSetting.current.update!(base_url: origin)

    get "/oauth/callback", params: { error: "access_denied", error_description: "cancelled" }

    assert_response :unprocessable_entity
    assert_includes response.body, %(postMessage({ flowOauth: false }, #{origin.to_json}))
    refute_includes response.body, 'postMessage({ flowOauth: false }, "*")'
    assert_includes response.body, "setTimeout(() => window.close(), 1500)"
  end

  test "callback fails closed without a configured HTTPS origin" do
    OrgSetting.current.update!(base_url: nil)

    get "/oauth/callback", params: { error: "access_denied", error_description: "ignored" },
                           headers: { "HOST" => "attacker.example" }

    assert_response :unprocessable_entity
    assert_includes response.body, "OAuth is not configured"
    refute_includes response.body, "postMessage"
    refute_includes response.body, "attacker.example"
  end

  test "API OAuth start returns configuration error instead of using request Host" do
    agent = Agent.create!(email: "admin@example.com", name: "Admin", password: "secret123", role: "admin")
    _, token = ApiToken.issue(agent: agent, name: "oauth", scope: "write")
    mailbox = Mailbox.create!(address: "support@example.com", name: "Support")
    OrgSetting.current.update!(base_url: nil, ms_client_id: "client", ms_client_secret: "secret", ms_tenant: "common")

    post "/api/oauth/microsoft/start", params: { mailbox_id: mailbox.id },
         headers: { "Authorization" => "Bearer #{token}", "HOST" => "attacker.example" }

    assert_response :unprocessable_entity
    assert_equal "oauth_not_configured", response.parsed_body["error"]
  end
end
