require "test_helper"

class ApiFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = Agent.create!(email: "a@example.com", name: "Ada", password: "secret123", role: "admin")
    @bob = Agent.create!(email: "b@example.com", name: "Bob", password: "secret123", role: "user")
    @outsider = Agent.create!(email: "c@example.com", name: "Cat", password: "secret123", role: "user")
    @mailbox = Mailbox.create!(address: "support@example.com", name: "Support", smtp_host: "smtp.example.com")
    MailboxAccess.create!(agent: @bob, mailbox: @mailbox)

    raw = Mail.new do
      from "kunde@example.dk"
      to "support@example.com"
      subject "Fridge broken"
      body "It beeps all night"
      message_id "<m1@example.dk>"
    end.to_s
    ImapFetcher.new(@mailbox).ingest(raw)
    @conversation = Conversation.last
  end

  def login(email) = post("/api/session", params: { email: email, password: "secret123" })

  test "inbound mail is an unassigned conversation with folder counts" do
    login("a@example.com")
    get "/api/conversations", params: { folder: "unassigned" }
    body = response.parsed_body
    assert_equal 1, body["conversations"].size
    assert_equal "Fridge broken", body["conversations"].first["subject"]
    assert_equal 1, body["folder_counts"]["unassigned"]
  end

  test "api exposes sender and inbox arrival times separately" do
    sent_at = 2.days.ago.change(usec: 0)
    received_at = 1.hour.ago.change(usec: 0)
    raw = Mail.new do
      from "arrival@example.dk"
      to "support@example.com"
      subject "Arrival timestamp"
      body "Check the inbox time"
      message_id "<arrival@example.dk>"
      date sent_at
    end
    ImapFetcher.new(@mailbox).ingest(raw.to_s, received_at: received_at)
    conversation = Conversation.order(:id).last

    login("a@example.com")
    get "/api/conversations"
    listed = response.parsed_body["conversations"].find { |item| item["id"] == conversation.id }
    assert_equal received_at.to_i, Time.zone.parse(listed["last_message_at"]).to_i

    get "/api/conversations/#{conversation.id}"
    message = response.parsed_body["messages"].first
    assert_equal sent_at.to_i, Time.zone.parse(message["sent_at"]).to_i
    assert_equal received_at.to_i, Time.zone.parse(message["received_at"]).to_i
  end

  test "acl: outsider sees nothing and cannot open the conversation" do
    login("c@example.com")
    get "/api/conversations"
    assert_equal 0, response.parsed_body["conversations"].size
    get "/api/conversations/#{@conversation.id}"
    assert_response :not_found
  end

  test "acl: merge cannot target an inaccessible mailbox" do
    private_mailbox = Mailbox.create!(address: "private@example.com", name: "Private", smtp_host: "smtp.example.com")
    private_conversation = Conversation.create!(
      mailbox: private_mailbox,
      customer: Customer.create!(email: "private-customer@example.com"),
      subject: "Private thread"
    )

    login("b@example.com")
    post "/api/conversations/#{@conversation.id}/merge", params: { into_number: private_conversation.number }

    assert_response :not_found
    assert_nil @conversation.reload.merged_into_id
    assert_equal [ @conversation.id ], @conversation.messages.reload.map(&:conversation_id).uniq
    assert_empty private_conversation.reload.events
  end

  test "acl: drafts require an accessible conversation and use its mailbox" do
    private_mailbox = Mailbox.create!(address: "private@example.com", name: "Private", smtp_host: "smtp.example.com")
    private_conversation = Conversation.create!(
      mailbox: private_mailbox,
      customer: Customer.create!(email: "private-customer@example.com"),
      subject: "Private thread"
    )

    login("b@example.com")
    put "/api/drafts", params: { conversation_id: @conversation.id, mailbox_id: private_mailbox.id, body: "Visible draft" }
    assert_response :success
    draft = @bob.drafts.find_by!(conversation_id: @conversation.id)
    assert_equal @mailbox.id, draft.mailbox_id

    put "/api/drafts", params: { conversation_id: private_conversation.id, body: "Hidden draft" }
    assert_response :not_found
    refute @bob.drafts.exists?(conversation_id: private_conversation.id)
  end

  test "acl: stream presence requires an accessible conversation" do
    private_mailbox = Mailbox.create!(address: "private@example.com", name: "Private", smtp_host: "smtp.example.com")
    private_conversation = Conversation.create!(
      mailbox: private_mailbox,
      customer: Customer.create!(email: "private-customer@example.com"),
      subject: "Private thread"
    )
    Presence.heartbeat(private_conversation.id, @admin)

    login("b@example.com")
    with_stream_ticks(0) do
      get "/api/stream", params: { conversation_id: private_conversation.id }
    end

    assert_response :not_found
  end

  test "assign notifies the assignee" do
    login("a@example.com")
    patch "/api/conversations/#{@conversation.id}", params: { assignee_id: @bob.id }
    assert_equal "Bob", response.parsed_body.dig("assignee", "name")
    assert Notification.exists?(agent: @bob, conversation: @conversation, kind: "assigned_to_me")
    assert_equal "assigned", @conversation.events.last.kind
  end

  test "bulk assignment rejects an assignee without mailbox access" do
    login("b@example.com")
    patch "/api/conversations/bulk", params: { ids: [ @conversation.id ], assignee_id: @outsider.id }

    assert_response :not_found
    assert_nil @conversation.reload.assignee_id
    refute Notification.exists?(agent: @outsider, conversation: @conversation)
  end

  test "reply queues an outbound message and can close in one action" do
    login("b@example.com")
    assert_enqueued_with(job: SendMessageJob) do
      post "/api/conversations/#{@conversation.id}/messages",
           params: { kind: "outbound", body_text: "We will fix it", close: true }
    end
    assert_response :created
    message = Message.order(:id).last
    assert_equal "queued", message.status
    assert_equal [ "kunde@example.dk" ], message.to
    assert_equal "closed", @conversation.reload.status
  end

  test "note stays internal and is visually distinct data" do
    login("b@example.com")
    post "/api/conversations/#{@conversation.id}/messages",
         params: { kind: "note", body_text: "internal only" }
    assert_response :created
    assert_equal "note", Message.order(:id).last.kind
    assert_no_enqueued_jobs only: SendMessageJob
  end

  test "search finds the subject, including by prefix while typing" do
    login("a@example.com")
    get "/api/conversations", params: { q: "fridge" }
    assert_equal 1, response.parsed_body["conversations"].size
    get "/api/conversations", params: { q: "frid" }
    assert_equal 1, response.parsed_body["conversations"].size, "prefix must match for live search"
    get "/api/conversations", params: { q: "frid beep" }
    assert_equal 1, response.parsed_body["conversations"].size, "multi-term prefixes must AND"
    get "/api/conversations", params: { q: "nonexistentterm" }
    assert_equal 0, response.parsed_body["conversations"].size
  end

  test "presence heartbeat reports other viewers" do
    login("a@example.com")
    post "/api/conversations/#{@conversation.id}/presence"
    assert_equal [], response.parsed_body["viewers"]
    Presence.heartbeat(@conversation.id, @bob)
    post "/api/conversations/#{@conversation.id}/presence"
    assert_equal [ "Bob" ], response.parsed_body["viewers"].map { |v| v["name"] }
  end

  test "saved reply renders variables" do
    login("a@example.com")
    reply = SavedReply.create!(name: "hi", body: "Hello {{customer.name}}, — {{agent.name}}")
    get "/api/saved_replies/#{reply.id}/render", params: { conversation_id: @conversation.id }
    assert_equal "Hello kunde@example.dk, — Ada", response.parsed_body["body"]
  end

  test "saved reply visibility and mutation follow mailbox scope" do
    private_mailbox = Mailbox.create!(address: "private@example.com", name: "Private", smtp_host: "smtp.example.com")
    global = SavedReply.create!(name: "global", body: "Global")
    private_reply = SavedReply.create!(name: "private", body: "Private", mailbox: private_mailbox)
    scoped = SavedReply.create!(name: "scoped", body: "Scoped", mailbox: @mailbox)

    login("b@example.com")
    get "/api/saved_replies"
    assert_includes response.parsed_body.map { |r| r["name"] }, "global"
    refute_includes response.parsed_body.map { |r| r["name"] }, "private"

    get "/api/saved_replies/#{global.id}/render", params: { conversation_id: @conversation.id }
    assert_response :success
    get "/api/saved_replies/#{private_reply.id}/render"
    assert_response :not_found
    patch "/api/saved_replies/#{private_reply.id}", params: { body: "changed" }
    assert_response :not_found
    delete "/api/saved_replies/#{private_reply.id}"
    assert_response :not_found
    post "/api/saved_replies", params: { name: "hidden", body: "hidden", mailbox_id: private_mailbox.id }
    assert_response :not_found

    patch "/api/saved_replies/#{global.id}", params: { body: "changed" }
    assert_response :forbidden
    delete "/api/saved_replies/#{global.id}"
    assert_response :forbidden
    patch "/api/saved_replies/#{scoped.id}", params: { body: "updated", mailbox_id: private_mailbox.id }
    assert_response :not_found
    assert_equal "Scoped", scoped.reload.body
  end

  test "tag definitions are admin-managed while users can attach existing tags" do
    tag = Tag.create!(name: "billing", color: "#2563eb")
    login("b@example.com")

    post "/api/tags", params: { name: "new-tag" }
    assert_response :forbidden
    patch "/api/tags/#{tag.id}", params: { color: "#dc2626" }
    assert_response :forbidden

    patch "/api/conversations/#{@conversation.id}", params: { tag_ids: [ tag.id ] }
    assert_response :success
    assert_includes @conversation.reload.tags, tag
  end

  test "new outbound conversation from an agent defaults assignment to the author" do
    login("b@example.com")
    assert_enqueued_with(job: SendMessageJob) do
      post "/api/conversations", params: { mailbox_id: @mailbox.id, to: [ "new@example.dk" ],
                                           subject: "Welcome", body_text: "Hello there" }
    end
    assert_response :created
    conv = Conversation.order(:id).last
    assert_equal "Welcome", conv.subject
    assert_equal @bob.id, conv.assignee_id
    assert_equal "active", conv.status
  end

  test "new conversation honors assignee, status, cc and inline images" do
    login("a@example.com")
    img = Rack::Test::UploadedFile.new(StringIO.new("PNG"), "image/png", original_filename: "local-x1")
    post "/api/conversations", params: {
      mailbox_id: @mailbox.id, to: [ "new@example.dk" ], cc: [ "cc@example.dk" ],
      subject: "Logged call", body_text: "Summary", body_html: '<p>Summary <img src="cid:local-x1"></p>',
      assignee_id: @bob.id, status: "closed", inline_images: [ img ]
    }
    assert_response :created
    conv = Conversation.order(:id).last
    assert_equal @bob.id, conv.assignee_id
    assert_equal "closed", conv.status
    message = conv.messages.first
    assert_equal [ "cc@example.dk" ], message.cc
    content_id = message.files.first.blob.metadata["content_id"]
    assert_includes message.body_html, "cid:#{content_id}"
  end

  test "mailbox settings hide passwords but report presence" do
    login("a@example.com")
    @mailbox.update!(imap_password: "sekrit")
    get "/api/mailboxes/#{@mailbox.id}"
    body = response.parsed_body
    assert body["imap_password_set"]
    refute body.key?("imap_password")
  end

  test "health endpoint requires a token and preserves detailed diagnostics" do
    with_health_token(nil) do
      get "/health"
      assert_response :unauthorized
    end

    with_health_token("health-secret") do
      get "/health"
      assert_response :unauthorized

      get "/health", headers: { "Authorization" => "Bearer wrong" }
      assert_response :unauthorized

      get "/health", headers: { "Authorization" => "Bearer health-secret" }
      assert_response :success
      body = response.parsed_body
      assert_equal "support@example.com", body["mailboxes"].first["address"]
      assert body.key?("queue")
    end
  end

  private

  def with_health_token(value)
    previous = ENV["FLOW_HEALTH_TOKEN"]
    value.nil? ? ENV.delete("FLOW_HEALTH_TOKEN") : ENV["FLOW_HEALTH_TOKEN"] = value
    yield
  ensure
    previous.nil? ? ENV.delete("FLOW_HEALTH_TOKEN") : ENV["FLOW_HEALTH_TOKEN"] = previous
  end

  def with_stream_ticks(value)
    previous = Api::StreamController::TICKS
    Api::StreamController.send(:remove_const, :TICKS)
    Api::StreamController.const_set(:TICKS, value)
    yield
  ensure
    Api::StreamController.send(:remove_const, :TICKS)
    Api::StreamController.const_set(:TICKS, previous)
  end
end
