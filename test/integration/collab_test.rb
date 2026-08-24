require "test_helper"

class CollabTest < ActionDispatch::IntegrationTest
  setup do
    @ada = Agent.create!(email: "a@example.com", name: "Ada Byron", password: "secret123", role: "admin")
    @bob = Agent.create!(email: "b@example.com", name: "Bob Noel", password: "secret123", role: "admin")
    @mailbox = Mailbox.create!(address: "support@example.com", name: "Support", smtp_host: "s.example.com")
    raw = Mail.new do
      from "Kunde <kunde@example.dk>"
      to "support@example.com, other@partner.dk"
      cc "cc-person@firma.dk"
      subject "Multi-party"
      body "hello all"
      message_id "<mp1@example.dk>"
    end.to_s
    ImapFetcher.new(@mailbox).ingest(raw)
    @conversation = Conversation.last
    post "/api/session", params: { email: "a@example.com", password: "secret123" }
  end

  test "reply_all prefill includes cc'd participants but never our own mailbox" do
    get "/api/conversations/#{@conversation.id}"
    body = response.parsed_body
    assert_equal [ "kunde@example.dk" ], body["reply_all"]["to"]
    assert_equal [ "other@partner.dk", "cc-person@firma.dk" ].sort, body["reply_all"]["cc"].sort
    emails = body["participants"].map { |p| p["email"] }
    assert_includes emails, "cc-person@firma.dk"
    refute_includes emails, "support@example.com"
  end

  test "follower gets notified on customer reply even when not assignee" do
    post "/api/conversations/#{@conversation.id}/follow"
    assert_response :success
    raw = Mail.new do
      from "kunde@example.dk"; to "support@example.com"
      subject "Re: Multi-party"; body "more info"; message_id "<mp2@example.dk>"
    end.to_s
    ImapFetcher.new(@mailbox).ingest(raw)
    assert Notification.exists?(agent: @ada, conversation: @conversation, kind: "customer_reply")

    delete "/api/conversations/#{@conversation.id}/follow"
    assert_equal false, response.parsed_body["followed"]
  end

  test "mentioning an agent in a note notifies them once" do
    post "/api/conversations/#{@conversation.id}/messages",
         params: { kind: "note", body_text: "hey @Bob can you take this?" }
    assert_response :created
    assert_equal 1, Notification.where(agent: @bob, kind: "mention").count
    assert_equal 0, Notification.where(agent: @ada, kind: "mention").count
  end

  test "inline pasted image gets a real content id wired into the html" do
    img = Rack::Test::UploadedFile.new(StringIO.new("PNGDATA"), "image/png", original_filename: "localcid-abc")
    post "/api/conversations/#{@conversation.id}/messages",
         params: { kind: "outbound", body_text: "see image",
                   body_html: '<p>see <img src="cid:localcid-abc"></p>',
                   inline_images: [ img ] }
    assert_response :created
    message = Message.order(:id).last
    content_id = message.files.first.blob.metadata["content_id"]
    assert content_id.start_with?("inline-")
    assert_includes message.body_html, "cid:#{content_id}"
    refute_includes message.body_html, "localcid-abc"
  end
end
