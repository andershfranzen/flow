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

  test "acl: outsider sees nothing and cannot open the conversation" do
    login("c@example.com")
    get "/api/conversations"
    assert_equal 0, response.parsed_body["conversations"].size
    get "/api/conversations/#{@conversation.id}"
    assert_response :not_found
  end

  test "assign notifies the assignee" do
    login("a@example.com")
    patch "/api/conversations/#{@conversation.id}", params: { assignee_id: @bob.id }
    assert_equal "Bob", response.parsed_body.dig("assignee", "name")
    assert Notification.exists?(agent: @bob, conversation: @conversation, kind: "assigned_to_me")
    assert_equal "assigned", @conversation.events.last.kind
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

  test "search finds the subject" do
    login("a@example.com")
    get "/api/conversations", params: { q: "fridge" }
    assert_equal 1, response.parsed_body["conversations"].size
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

  test "health endpoint reports mailboxes without auth" do
    get "/health"
    assert_response :success
    assert_equal "support@example.com", response.parsed_body["mailboxes"].first["address"]
  end
end
