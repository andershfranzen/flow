require "test_helper"

class CustomersTeamsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = Agent.create!(email: "a@example.com", name: "Ada", password: "secret123", role: "admin")
    @bob = Agent.create!(email: "b@example.com", name: "Bob", password: "secret123", role: "admin")
    @mailbox = Mailbox.create!(address: "support@example.com", name: "Support", smtp_host: "s.example.com")
    @fetcher = ImapFetcher.new(@mailbox)
    WorkflowEngine.install!
    post "/api/session", params: { email: "a@example.com", password: "secret123" }
  end

  teardown { DomainEvents.reset! }

  def ingest(subject:, from:, message_id: SecureRandom.hex(6))
    raw = Mail.new do
      from from; to "support@example.com"; subject subject; body "hi"; message_id "<#{message_id}@x>"
    end.to_s
    @fetcher.ingest(raw)
    Conversation.order(:id).last
  end

  test "customer fields are editable" do
    conv = ingest(subject: "Hi", from: "kunde@example.dk")
    patch "/api/customers/#{conv.customer_id}",
          params: { name: "Kunde Hansen", company: "Hansen A/S", notes: "VIP", phones: [ "+45 11 22 33 44" ] }
    body = response.parsed_body
    assert_equal "Hansen A/S", body["company"]
    assert_equal [ "+45 11 22 33 44" ], body["phones"]
  end

  test "customer details require a conversation in an accessible mailbox" do
    private_mailbox = Mailbox.create!(address: "private@example.com", name: "Private", smtp_host: "s.example.com")
    private_customer = Customer.create!(email: "private@example.com", notes: "secret")
    Conversation.create!(mailbox: private_mailbox, customer: private_customer, subject: "Private")
    user = Agent.create!(email: "limited@example.com", name: "Limited", password: "secret123", role: "user")
    MailboxAccess.create!(agent: user, mailbox: @mailbox)

    post "/api/session", params: { email: user.email, password: "secret123" }
    get "/api/customers/#{private_customer.id}"
    assert_response :not_found
    patch "/api/customers/#{private_customer.id}", params: { notes: "changed" }
    assert_response :not_found
    assert_equal "secret", private_customer.reload.notes

    visible = ingest(subject: "Visible", from: "visible@example.dk")
    get "/api/customers/#{visible.customer_id}"
    assert_response :success
    patch "/api/customers/#{visible.customer_id}", params: { notes: "updated" }
    assert_response :success
  end

  test "customer merge rejects hidden conversations before global reparenting" do
    private_mailbox = Mailbox.create!(address: "private@example.com", name: "Private", smtp_host: "s.example.com")
    user = Agent.create!(email: "limited@example.com", name: "Limited", password: "secret123", role: "user")
    MailboxAccess.create!(agent: user, mailbox: @mailbox)

    target = ingest(subject: "Target", from: "target@example.dk")
    source_visible = ingest(subject: "Source visible", from: "source@example.dk")
    hidden = Conversation.create!(mailbox: private_mailbox, customer: source_visible.customer, subject: "Source hidden")

    post "/api/session", params: { email: user.email, password: "secret123" }
    post "/api/customers/#{target.customer_id}/merge", params: { source_email: source_visible.customer.email }

    assert_response :not_found
    assert_equal source_visible.customer_id, source_visible.reload.customer_id
    assert_equal source_visible.customer_id, hidden.reload.customer_id
    assert Customer.exists?(source_visible.customer_id)
  end

  test "merge folds identities and future mail from either address maps to one customer" do
    c1 = ingest(subject: "One", from: "kunde@example.dk")
    c2 = ingest(subject: "Two", from: "k.hansen@gmail.com")
    assert_equal 2, Customer.count

    post "/api/customers/#{c1.customer_id}/merge", params: { source_email: "k.hansen@gmail.com" }
    assert_response :success
    assert_equal 1, Customer.count
    target = Customer.first
    assert_equal [ c1.id, c2.id ].sort, target.conversations.pluck(:id).sort
    assert_includes target.emails, "k.hansen@gmail.com"

    c3 = ingest(subject: "Three", from: "k.hansen@gmail.com")
    assert_equal target.id, c3.customer_id, "mail from the merged address must map to the surviving customer"
  end

  test "team round-robin workflow action rotates members" do
    team = Team.create!(name: "Frontline")
    team.team_members.create!(agent: @admin)
    team.team_members.create!(agent: @bob)
    Workflow.create!(name: "RR", trigger: "message.inbound",
      actions: [ { "type" => "assign_team", "value" => team.id.to_s } ])

    assignees = 4.times.map { |i| ingest(subject: "T#{i}", from: "x#{i}@y.dk").assignee_id }
    assert_equal [ @admin.id, @bob.id, @admin.id, @bob.id ], assignees
  end

  test "agent signature is preferred over mailbox signature" do
    @mailbox.update!(signature: "Mailbox sig")
    @admin.update!(signature: "Ada's own sig")
    conv = ingest(subject: "Sig", from: "kunde@example.dk")
    post "/api/conversations/#{conv.id}/messages",
         params: { kind: "outbound", body_text: "hello", body_html: "<p>hello</p>" }
    assert_includes Message.order(:id).last.body_html, "own sig"

    @admin.update!(signature: nil)
    post "/api/conversations/#{conv.id}/messages",
         params: { kind: "outbound", body_text: "again", body_html: "<p>again</p>" }
    assert_includes Message.order(:id).last.body_html, "Mailbox sig"
  end
end
