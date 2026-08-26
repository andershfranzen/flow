require "test_helper"

class CrmTest < ActionDispatch::IntegrationTest
  setup do
    OrgSetting.current.update!(mcp_enabled: true)
    @agent = Agent.create!(email: "a@example.com", name: "Ada", password: "secret123", role: "admin")
    post "/api/session", params: { email: "a@example.com", password: "secret123" }
    OrgSetting.current.update!(crm_enabled: true, crm_url: "https://acmecool.crm4.dynamics.com",
                               ms_client_id: "cid", ms_client_secret: "sec",
                               ms_tenant: "11111111-2222-3333-4444-555555555555")
    @mailbox = Mailbox.create!(address: "support@example.com", name: "Support", smtp_host: "s.example.com")
    %w[lars@nordiccooling.dk unknown@nordiccooling.dk someone@gmail.com x@y.dk].each do |email|
      Conversation.create!(mailbox: @mailbox, customer: Customer.create!(email: email), subject: email)
    end
    Conversation.create!(mailbox: @mailbox, customer: Customer.create!(email: "o'brien@example.org"), subject: "O'Brien")
    Rails.cache.clear
  end

  CONTACT = {
    "contactid" => "abc-123", "fullname" => "Lars Beck", "jobtitle" => "Purchaser",
    "emailaddress1" => "lars@nordiccooling.dk", "telephone1" => "+45 11 22 33 44",
    "mobilephone" => nil, "address1_city" => "Odense", "address1_country" => "Denmark",
    "parentcustomerid_account" => { "accountid" => "acc-9", "name" => "Nordic Køling A/S",
                                    "websiteurl" => "https://nordiccooling.dk",
                                    "telephone1" => "+45 55 66 77 88",
                                    "address1_city" => "Odense", "address1_country" => "Denmark" }
  }.freeze

  def stub_crm(responses)
    Crm.define_singleton_method(:access_token) { "tok" }
    Crm.define_singleton_method(:get) do |entity, params|
      responses.fetch(entity).call(params)
    end
    yield
  ensure
    Crm.singleton_class.remove_method(:access_token)
    Crm.singleton_class.remove_method(:get)
  end

  test "lookup returns contact with expanded account" do
    captured = nil
    stub_crm("contacts" => ->(p) { captured = p; { "value" => [ CONTACT.deep_dup ] } }) do
      get "/api/crm/lookup", params: { email: "lars@nordiccooling.dk" }
    end
    assert_response :success
    body = response.parsed_body
    assert body["configured"]
    assert_equal "Lars Beck", body.dig("contact", "name")
    assert_equal "Nordic Køling A/S", body.dig("account", "name")
    assert_equal "https://nordiccooling.dk", body.dig("account", "website")
    assert_includes body.dig("contact", "url"), "etn=contact&id=abc-123"
    assert_includes captured["$filter"], "emailaddress1 eq 'lars@nordiccooling.dk'"
  end

  test "no contact falls back to account by company domain, skipping generic domains" do
    calls = []
    stub_crm("contacts" => ->(_) { { "value" => [] } },
             "accounts" => ->(p) { calls << p; { "value" => [ CONTACT["parentcustomerid_account"].dup ] } }) do
      get "/api/crm/lookup", params: { email: "unknown@nordiccooling.dk" }
      assert_equal "Nordic Køling A/S", response.parsed_body.dig("account", "name")
      assert_nil response.parsed_body["contact"]
      assert_includes calls.last["$filter"], "contains(websiteurl,'nordiccooling.dk')"

      get "/api/crm/lookup", params: { email: "someone@gmail.com" }
      assert_nil response.parsed_body["account"], "generic domains must not match accounts"
    end
  end

  test "odata single quotes are escaped" do
    captured = nil
    stub_crm("contacts" => ->(p) { captured = p; { "value" => [] } },
             "accounts" => ->(_) { { "value" => [] } }) do
      get "/api/crm/lookup", params: { email: "o'brien@example.org" }
    end
    assert_includes captured["$filter"], "eq 'o''brien@example.org'"
  end

  test "account websites allow only http and https" do
    contact = CONTACT.deep_dup
    contact["parentcustomerid_account"]["websiteurl"] = "javascript:alert(1)"
    stub_crm("contacts" => ->(_) { { "value" => [ contact ] } }) do
      get "/api/crm/lookup", params: { email: "lars@nordiccooling.dk" }
    end
    assert_response :success
    assert_nil response.parsed_body.dig("account", "website")
  end

  test "lookup is limited to visible customers and their aliases for HTTP and MCP" do
    visible = Customer.find_by!(email: "lars@nordiccooling.dk")
    visible.update!(emails: [ "alias@nordiccooling.dk" ])
    limited = Agent.create!(email: "limited@example.com", name: "Limited", password: "secret123", role: "user")
    MailboxAccess.create!(agent: limited, mailbox: @mailbox)
    private_mailbox = Mailbox.create!(address: "private@example.com", name: "Private", smtp_host: "s.example.com")
    private_customer = Customer.create!(email: "private@example.com")
    Conversation.create!(mailbox: private_mailbox, customer: private_customer, subject: "Private")
    post "/api/session", params: { email: limited.email, password: "secret123" }

    calls = 0
    stub_crm("contacts" => ->(_) { calls += 1; { "value" => [ CONTACT.deep_dup ] } }) do
      get "/api/crm/lookup", params: { email: "ALIAS@nordiccooling.DK" }
      assert_equal "Lars Beck", response.parsed_body.dig("contact", "name")
      assert_equal 1, calls

      calls = 0
      get "/api/crm/lookup", params: { email: private_customer.email }
      assert_response :success
      assert_nil response.parsed_body["contact"]
      assert_nil response.parsed_body["account"]
      assert_equal 0, calls

      _, token = ApiToken.issue(agent: limited, name: "crm", scope: "read")
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                             params: { name: "crm_lookup", arguments: { email: private_customer.email } } }.to_json,
                   headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
      assert_equal({}, JSON.parse(response.parsed_body.dig("result", "content").first["text"]))
      assert_equal 0, calls
    end
  end

  test "unconfigured and errors are graceful" do
    OrgSetting.current.update!(crm_enabled: false)
    get "/api/crm/lookup", params: { email: "x@y.dk" }
    assert_equal false, response.parsed_body["configured"]

    OrgSetting.current.update!(crm_enabled: true)
    stub_crm("contacts" => ->(_) { raise Crm::Error, "Dynamics returned 403" }) do
      get "/api/crm/lookup", params: { email: "x@y.dk" }
    end
    assert_response :bad_gateway
  end

  test "session payload exposes crm_enabled and mcp tool answers" do
    get "/api/session"
    assert response.parsed_body.dig("org", "crm_enabled")

    _, raw = ApiToken.issue(agent: @agent, name: "t", scope: "read")
    stub_crm("contacts" => ->(_) { { "value" => [ CONTACT.deep_dup ] } }) do
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                             params: { name: "crm_lookup", arguments: { email: "lars@nordiccooling.dk" } } }.to_json,
                   headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{raw}" }
    end
    text = JSON.parse(response.parsed_body.dig("result", "content").first["text"])
    assert_equal "Lars Beck", text.dig("contact", "fullname")
  end
end
