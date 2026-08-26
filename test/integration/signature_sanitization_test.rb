require "test_helper"

class SignatureSanitizationTest < ActionDispatch::IntegrationTest
  setup do
    @agent = Agent.create!(email: "admin@example.com", name: "Admin", password: "secret123",
                           role: "admin", signature: unsafe_signature)
    @mailbox = Mailbox.create!(address: "support@example.com", name: "Support",
                               signature: unsafe_signature)
    OrgSetting.current.update!(default_signature: unsafe_signature)
    post "/api/session", params: { email: @agent.email, password: "secret123" }
  end

  test "signature APIs sanitize legacy stored HTML before browser rendering" do
    get "/api/me"
    assert_safe_signature response.parsed_body.fetch("signature")

    get "/api/mailboxes"
    assert_safe_signature response.parsed_body.first.fetch("signature")

    get "/api/org_settings"
    assert_safe_signature response.parsed_body.fetch("default_signature")

    get "/api/session"
    assert_safe_signature response.parsed_body.dig("org", "default_signature")
  end

  private

  def unsafe_signature
    '<p>Regards <strong>Flow</strong></p><img src="https://example.com/logo.png" onerror="alert(1)"><script>alert(2)</script>'
  end

  def assert_safe_signature(value)
    assert_includes value, "<strong>Flow</strong>"
    assert_includes value, "https://example.com/logo.png"
    refute_includes value, "onerror"
    refute_includes value, "<script"
  end
end
