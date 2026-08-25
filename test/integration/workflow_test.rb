require "test_helper"

class WorkflowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = Agent.create!(email: "a@example.com", name: "Ada", password: "secret123", role: "admin")
    @mailbox = Mailbox.create!(address: "support@example.com", name: "Support", smtp_host: "s.example.com")
    @fetcher = ImapFetcher.new(@mailbox)
    WorkflowEngine.install! # DomainEvents.reset! in other tests may have cleared it
    post "/api/session", params: { email: "a@example.com", password: "secret123" }
  end

  teardown { DomainEvents.reset! }

  def ingest(subject:, from: "kunde@example.dk", body: "hello", message_id: SecureRandom.hex(6))
    raw = Mail.new do
      from from; to "support@example.com"; subject subject; body body
      message_id "<#{message_id}@x>"
    end.to_s
    @fetcher.ingest(raw)
    Conversation.order(:id).last
  end

  test "matching workflow tags, assigns and stars a new conversation" do
    Workflow.create!(name: "Billing triage", trigger: "message.inbound",
      conditions: [ { "field" => "subject", "operator" => "contains", "value" => "invoice" } ],
      actions: [ { "type" => "add_tag", "value" => "billing" },
                 { "type" => "assign", "value" => @admin.id.to_s },
                 { "type" => "star" } ])
    conversation = ingest(subject: "Invoice 900 is wrong")
    assert_equal [ "billing" ], conversation.tags.pluck(:name)
    assert_equal @admin.id, conversation.assignee_id
    assert conversation.starred
    assert_equal "workflow", conversation.events.last.kind
    assert_equal 1, Workflow.first.reload.runs_count

    other = ingest(subject: "Totally unrelated")
    assert_equal [], other.tags.pluck(:name)
  end

  test "any-match, from_domain and regex operators" do
    Workflow.create!(name: "VIP", trigger: "message.inbound", match_type: "any",
      conditions: [ { "field" => "from_domain", "operator" => "equals", "value" => "vip.dk" },
                    { "field" => "subject", "operator" => "matches_regex", "value" => "urgent|asap" } ],
      actions: [ { "type" => "add_tag", "value" => "vip" } ])
    assert_equal [ "vip" ], ingest(subject: "hello", from: "boss@vip.dk").tags.pluck(:name)
    assert_equal [ "vip" ], ingest(subject: "ASAP please").tags.pluck(:name)
    assert_equal [], ingest(subject: "calm request").tags.pluck(:name)
  end

  test "send_reply is auto-submitted and does not cascade other workflows" do
    Workflow.create!(name: "Ack", trigger: "message.inbound",
      actions: [ { "type" => "send_reply", "value" => "We got it, {{customer.name}}" } ])
    Workflow.create!(name: "Outbound spy", trigger: "message.outbound",
      actions: [ { "type" => "add_tag", "value" => "should-never-appear" } ])
    conversation = ingest(subject: "Ping")
    reply = conversation.messages.find_by(kind: "outbound")
    assert reply.auto_submitted
    assert_includes reply.body_text, "We got it"
    assert_equal [], conversation.tags.pluck(:name), "workflow actions must not trigger workflows"
  end

  test "mailbox scoping and disabled workflows are skipped" do
    other_mailbox = Mailbox.create!(address: "sales@example.com", name: "Sales")
    Workflow.create!(name: "Sales only", trigger: "message.inbound", mailbox: other_mailbox,
      actions: [ { "type" => "add_tag", "value" => "sales" } ])
    Workflow.create!(name: "Off", trigger: "message.inbound", enabled: false,
      actions: [ { "type" => "add_tag", "value" => "off" } ])
    assert_equal [], ingest(subject: "Hi").tags.pluck(:name)
  end

  test "workflows run in priority order and reorder endpoint flips it" do
    a = Workflow.create!(name: "A", trigger: "message.inbound",
      actions: [ { "type" => "set_status", "value" => "pending" } ])
    b = Workflow.create!(name: "B", trigger: "message.inbound",
      actions: [ { "type" => "set_status", "value" => "closed" } ])
    assert_equal "closed", ingest(subject: "one").status # B runs last

    patch "/api/workflows/reorder", params: { ids: [ b.id, a.id ] }
    assert_equal "pending", ingest(subject: "two").status # now A runs last
  end

  test "api validates fields and requires at least one action" do
    post "/api/workflows", params: { name: "Bad", trigger: "message.inbound",
      conditions: [ { field: "hax", operator: "contains", value: "x" } ],
      actions: [ { type: "add_tag", value: "t" } ] }
    assert_response :unprocessable_entity

    post "/api/workflows", params: { name: "Empty", trigger: "message.inbound", actions: [] }
    assert_response :unprocessable_entity

    post "/api/workflows", params: { name: "Good", trigger: "message.inbound",
      conditions: [], actions: [ { type: "star" } ] }
    assert_response :created
  end
end
