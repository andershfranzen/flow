require "test_helper"

class McpTest < ActionDispatch::IntegrationTest
  setup do
    @agent = Agent.create!(email: "a@example.com", name: "Ada", password: "secret123", role: "admin")
    _, @raw_token = ApiToken.issue(agent: @agent, name: "mcp", scope: "write")
    _, @read_token = ApiToken.issue(agent: @agent, name: "ro", scope: "read")
    @mailbox = Mailbox.create!(address: "support@example.com", name: "Support", smtp_host: "s.example.com")
    raw = Mail.new do
      from "kunde@example.dk"; to "support@example.com"
      subject "Fridge broken"; body "It beeps"; message_id "<m1@example.dk>"
    end.to_s
    ImapFetcher.new(@mailbox).ingest(raw)
    @conversation = Conversation.last
  end

  def rpc(method, params = {}, token: @raw_token, id: 1)
    post "/mcp", params: { jsonrpc: "2.0", id: id, method: method, params: params }.to_json,
                 headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
    response.parsed_body
  end

  def call_tool(name, args, token: @raw_token)
    rpc("tools/call", { name: name, arguments: args }, token: token)
  end

  test "rejects without token" do
    post "/mcp", params: {}.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  test "lists the full tool surface" do
    body = rpc("tools/list")
    names = body.dig("result", "tools").map { |t| t["name"] }
    %w[assign draft_reply get_thread list_mailboxes search send
       set_status add_note tag_conversation list_agents save_agent save_mailbox test_mailbox
       save_team save_tag save_saved_reply list_webhooks save_webhook list_workflows
       save_workflow get_org_settings update_org_settings list_plugins set_plugin_enabled
       report].each { |t| assert_includes names, t }
  end

  def tool_text(body) = JSON.parse(body.dig("result", "content").first["text"])

  test "an agent can set up a whole flow through mcp" do
    out = tool_text(call_tool("save_mailbox", { address: "sales@example.com",
      attributes: { name: "Sales", imap_host: "imap.example.com", imap_port: 993, imap_ssl: true,
                    imap_user: "sales@example.com", imap_password: "pw",
                    smtp_host: "smtp.example.com", smtp_port: 587, smtp_user: "sales@example.com",
                    smtp_password: "pw", smtp_security: "starttls" } }))
    assert out["imap_configured"]
    assert out["smtp_configured"]

    out = tool_text(call_tool("save_agent", { email: "new@example.com", name: "Newbie",
                                              mailbox_addresses: [ "sales@example.com" ] }))
    assert_equal [ "sales@example.com" ], out["mailboxes"]

    out = tool_text(call_tool("save_team", { name: "Support", agent_emails: [ "new@example.com" ] }))
    assert_equal [ "new@example.com" ], out["members"]

    tool_text(call_tool("save_tag", { name: "billing", color: "#aa3311" }))
    assert_equal "#aa3311", Tag.find_by(name: "billing").color

    out = tool_text(call_tool("save_workflow", { name: "Auto-tag billing", trigger: "message.inbound",
      conditions: [ { "field" => "subject", "operator" => "contains", "value" => "invoice" } ],
      actions: [ { "type" => "add_tag", "value" => "billing" } ] }))
    assert_equal "message.inbound", out["trigger"]

    out = tool_text(call_tool("save_webhook", { url: "https://hooks.example.com/flow", events: [ "thread.created" ] }))
    assert out["secret"].present?

    out = tool_text(call_tool("update_org_settings", { attributes: {
      "site_name" => "acmecool Support", "theme" => { "accent" => "#1e3a8a", "bogus" => "nope" } } }))
    assert_equal "acmecool Support", out["site_name"]
    assert_equal({ "accent" => "#1e3a8a" }, out["theme"])

    out = tool_text(call_tool("report", {}))
    assert out["totals"].key?("open_now")
  end

  test "admin tools reject non-admin agents and read tokens" do
    user = Agent.create!(email: "u@example.com", name: "U", password: "secret123", role: "user")
    _, user_token = ApiToken.issue(agent: user, name: "u", scope: "write")
    body = call_tool("save_mailbox", { address: "x@example.com", attributes: {} }, token: user_token)
    assert body.dig("result", "isError") || body["error"].present?, "non-admin must not reach admin tools"
    assert_nil Mailbox.find_by(address: "x@example.com")

    body = call_tool("set_status", { number: @conversation.number, status: "closed" }, token: @read_token)
    assert body.dig("result", "isError") || body["error"].present?, "read tokens must not write"
    assert_not_equal "closed", @conversation.reload.status
  end

  test "mcp endpoint can be disabled in org settings" do
    OrgSetting.current.update!(mcp_enabled: false)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
                 headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@raw_token}" }
    assert_response :not_found
  end

  test "search then get_thread then send" do
    body = call_tool("search", { query: "fridge" })
    results = JSON.parse(body.dig("result", "content").first["text"])
    assert_equal @conversation.number, results.first["number"]

    body = call_tool("get_thread", { number: @conversation.number })
    thread = JSON.parse(body.dig("result", "content").first["text"])
    assert_equal "It beeps", thread["messages"].first["text"]

    body = call_tool("send", { number: @conversation.number, body: "On the way" })
    result = JSON.parse(body.dig("result", "content").first["text"])
    assert result["queued"]
    assert_equal "queued", Message.order(:id).last.status
    assert_equal [ "kunde@example.dk" ], Message.order(:id).last.to
  end

  test "read scope cannot send but can draft context" do
    body = call_tool("send", { number: @conversation.number, body: "x" }, token: @read_token)
    assert body["error"].present? || body.dig("result", "isError"), "expected error, got #{body}"
    assert_equal 0, Message.where(kind: "outbound").count

    body = call_tool("draft_reply", { number: @conversation.number }, token: @read_token)
    ctx = JSON.parse(body.dig("result", "content").first["text"])
    assert_equal "It beeps", ctx["last_customer_message"]
  end

  test "draft_reply with body saves a draft" do
    call_tool("draft_reply", { number: @conversation.number, body: "Suggested reply" })
    draft = @agent.drafts.find_by(conversation_id: @conversation.id)
    assert_equal "Suggested reply", draft.body
  end
end
