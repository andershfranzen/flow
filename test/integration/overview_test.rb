require "test_helper"

class OverviewTest < ActionDispatch::IntegrationTest
  setup do
    @ada = Agent.create!(email: "a@example.com", name: "Ada", password: "secret123", role: "admin")
    @bob = Agent.create!(email: "b@example.com", name: "Bob", password: "secret123", role: "admin")
    @mailbox = Mailbox.create!(address: "support@example.com", name: "Support", smtp_host: "s.example.com")
    @fetcher = ImapFetcher.new(@mailbox)
    ingest(subject: "One", message_id: "o1@x")
    ingest(subject: "Two", message_id: "o2@x")
    @one, @two = Conversation.order(:id).to_a
    post "/api/session", params: { email: "a@example.com", password: "secret123" }
  end

  def ingest(subject:, message_id:, headers: {})
    raw = Mail.new do
      from "kunde@example.dk"; to "support@example.com"
      subject subject; body "body of #{subject}"; message_id "<#{message_id}>"
      headers.each { |k, v| header[k] = v }
    end.to_s
    @fetcher.ingest(raw)
  end

  def list(params = {})
    get "/api/conversations", params: params
    response.parsed_body
  end

  test "unread until opened, per agent, and again on new reply" do
    assert_equal [ true, true ], list["conversations"].map { |c| c["unread"] }

    get "/api/conversations/#{@one.id}"
    unread = list["conversations"].to_h { |c| [ c["id"], c["unread"] ] }
    assert_equal false, unread[@one.id]
    assert_equal true, unread[@two.id]

    # Bob's read state is his own
    post "/api/session", params: { email: "b@example.com", password: "secret123" }
    assert_equal [ true, true ], list["conversations"].map { |c| c["unread"] }

    # a new reply makes it unread again for Ada
    post "/api/session", params: { email: "a@example.com", password: "secret123" }
    ingest(subject: "Re: One", message_id: "o3@x", headers: { "In-Reply-To" => "<o1@x>" })
    unread = list["conversations"].to_h { |c| [ c["id"], c["unread"] ] }
    assert_equal true, unread[@one.id]
  end

  test "snooze hides from open folders, shows in snoozed, expires by time, wakes on reply" do
    patch "/api/conversations/#{@one.id}", params: { snooze_until: 2.days.from_now.iso8601 }
    assert_response :success

    assert_equal [ @two.id ], list(folder: "unassigned")["conversations"].map { |c| c["id"] }
    assert_equal [ @one.id ], list(folder: "snoozed")["conversations"].map { |c| c["id"] }
    assert_equal 1, list(folder: "unassigned")["folder_counts"]["snoozed"]

    # expiry is scope-based: a past snooze just reappears
    @one.update_columns(snoozed_until: 1.minute.ago)
    assert_includes list(folder: "unassigned")["conversations"].map { |c| c["id"] }, @one.id

    # a customer reply wakes a snoozed conversation
    @one.update_columns(snoozed_until: 2.days.from_now)
    ingest(subject: "Re: One", message_id: "o4@x", headers: { "In-Reply-To" => "<o1@x>" })
    assert_nil @one.reload.snoozed_until
  end

  test "bulk close and assign respect access" do
    patch "/api/conversations/bulk", params: { ids: [ @one.id, @two.id ], status: "closed" }
    assert_equal 2, response.parsed_body["updated"]
    assert_equal %w[closed closed], [ @one.reload.status, @two.reload.status ]

    patch "/api/conversations/bulk", params: { ids: [ @one.id ], assignee_id: @bob.id, status: "active" }
    assert_equal @bob.id, @one.reload.assignee_id
  end

  test "oldest-first sort and assignee filter" do
    @one.update_columns(last_message_at: 2.days.ago)
    assert_equal [ @one.id, @two.id ], list(sort: "oldest")["conversations"].map { |c| c["id"] }
    assert_equal [ @two.id, @one.id ], list["conversations"].map { |c| c["id"] }

    @one.update!(assignee: @bob)
    assert_equal [ @one.id ], list(folder: "all", assignee_id: @bob.id)["conversations"].map { |c| c["id"] }
  end
end
