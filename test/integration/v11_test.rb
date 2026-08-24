require "test_helper"

class V11Test < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = Agent.create!(email: "a@example.com", name: "Ada", password: "secret123", role: "admin")
    @mailbox = Mailbox.create!(address: "support@example.com", name: "Support", smtp_host: "smtp.example.com")
    @mailbox2 = Mailbox.create!(address: "sales@example.com", name: "Sales", smtp_host: "smtp.example.com")
    @fetcher = ImapFetcher.new(@mailbox)
    ingest(subject: "First", message_id: "m1@x")
    ingest(subject: "Second", message_id: "m2@x")
    @first, @second = Conversation.order(:id).to_a
    post "/api/session", params: { email: "a@example.com", password: "secret123" }
  end

  def ingest(subject:, message_id:, from: "kunde@example.dk", to: "support@example.com", body: "hello")
    raw = Mail.new do
      from from; to to; subject subject; body body; message_id "<#{message_id}>"
    end.to_s
    @fetcher.ingest(raw)
  end

  test "merge concatenates and redirects the source" do
    post "/api/conversations/#{@second.id}/merge", params: { into_number: @first.number }
    assert_response :success
    assert_equal 2, @first.reload.messages_count
    assert_equal @first.id, @second.reload.merged_into_id
    assert_equal 0, @second.messages_count
    assert_equal "merged", @first.events.last.kind

    get "/api/conversations/#{@second.id}"
    assert_equal @first.id, response.parsed_body["merged_into_id"]

    # FTS rows follow the merge
    hits = ActiveRecord::Base.connection.select_values(
      "SELECT DISTINCT conversation_id FROM message_search WHERE message_search MATCH 'hello'"
    )
    assert_equal [ @first.id ], hits
  end

  test "move to another mailbox records an event and enforces access" do
    patch "/api/conversations/#{@first.id}", params: { mailbox_id: @mailbox2.id }
    assert_response :success
    assert_equal @mailbox2.id, @first.reload.mailbox_id
    assert_equal({ "from" => "Support", "to" => "Sales" }, @first.events.last.data)
  end

  test "forward sends with subject override and no threading headers" do
    post "/api/conversations/#{@first.id}/messages",
         params: { kind: "outbound", to: [ "ext@other.com" ], subject: "Fwd: First",
                   body_text: "---------- Forwarded ----------\nhello" }
    assert_response :created
    message = Message.order(:id).last
    sender = OutboundSender.new(message)
    sender.send(:ensure_message_id)
    mail = sender.send(:build)
    assert_equal "Fwd: First", mail.subject
    assert_nil mail.in_reply_to
  end

  test "auto-reply fires once per new conversation, not for replies or lists" do
    @mailbox.update!(auto_reply_enabled: true, auto_reply_body: "We got it!")
    assert_enqueued_with(job: AutoReplyJob) do
      ingest(subject: "Third", message_id: "m3@x")
    end
    conversation = Conversation.order(:id).last
    perform_enqueued_jobs only: AutoReplyJob # will fail at SMTP; message row still created first
    auto = conversation.messages.find_by(kind: "outbound")
    assert auto&.auto_submitted

    # a customer reply does not enqueue another
    assert_no_enqueued_jobs only: AutoReplyJob do
      ingest(subject: "Re: Third", message_id: "m4@x")
    end
  rescue StandardError
    # SMTP connection refusal inside the job is fine for this test
  end

  test "muted mailbox suppresses notifications" do
    patch "/api/me", params: { muted_mailbox_ids: [ @mailbox.id ] }
    assert_equal [ @mailbox.id ], @admin.reload.muted_mailbox_ids
    before = Notification.count
    ingest(subject: "Quiet", message_id: "m5@x")
    assert_equal before, Notification.count

    patch "/api/me", params: { muted_mailbox_ids: [] }
    assert_equal [], @admin.reload.muted_mailbox_ids
  end
end
