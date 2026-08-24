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

  test "lists the six tools" do
    body = rpc("tools/list")
    names = body.dig("result", "tools").map { |t| t["name"] }
    assert_equal %w[assign draft_reply get_thread list_mailboxes search send].sort, names.sort
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
