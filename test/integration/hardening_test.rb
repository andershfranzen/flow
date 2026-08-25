require "test_helper"

class HardeningTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @ada = Agent.create!(email: "a@example.com", name: "Ada", password: "secret123", role: "admin")
    @mailbox = Mailbox.create!(address: "support@example.com", name: "Support", smtp_host: "s.example.com")
    raw = Mail.new do
      from "kunde@example.dk"; to "support@example.com"; subject "Hi"; body "hello"
      message_id "<h1@x>"
    end.to_s
    ImapFetcher.new(@mailbox).ingest(raw)
    @conversation = Conversation.last
    post "/api/session", params: { email: "a@example.com", password: "secret123" }
  end

  test "undo send within the window deletes the message and restores a draft" do
    post "/api/conversations/#{@conversation.id}/messages",
         params: { kind: "outbound", body_text: "oops", body_html: "<p>oops</p>" }
    message = Message.order(:id).last
    assert_equal "queued", message.status
    job = enqueued_jobs.find { |j| j["job_class"] == "SendMessageJob" }
    assert job["scheduled_at"].present?, "send must be delayed for the undo window"

    delete "/api/conversations/#{@conversation.id}/messages/#{message.id}"
    assert_response :success
    refute Message.exists?(message.id)
    assert_includes @ada.drafts.find_by(conversation_id: @conversation.id).body, "oops"

    # already sent → cannot undo
    post "/api/conversations/#{@conversation.id}/messages",
         params: { kind: "outbound", body_text: "final" }
    sent = Message.order(:id).last
    sent.update!(status: "sent")
    delete "/api/conversations/#{@conversation.id}/messages/#{sent.id}"
    assert_response :unprocessable_entity
  end

  test "2fa setup, enable, login challenge, disable" do
    post "/api/me/2fa/setup"
    body = response.parsed_body
    assert body["secret"].present?
    assert_includes body["uri"], "otpauth://totp/"
    assert_includes body["qr_svg"], "<svg"

    post "/api/me/2fa/enable", params: { code: "000000" }
    assert_response :unprocessable_entity
    post "/api/me/2fa/enable", params: { code: Totp.code(body["secret"]) }
    assert_response :success

    # fresh login now requires the code
    post "/api/session", params: { email: "a@example.com", password: "secret123" }
    assert_response :unauthorized
    assert_equal "otp_required", response.parsed_body["error"]
    post "/api/session", params: { email: "a@example.com", password: "secret123",
                                   otp_code: Totp.code(@ada.reload.otp_secret) }
    assert_response :success

    post "/api/me/2fa/disable", params: { code: Totp.code(@ada.reload.otp_secret) }
    assert_response :success
    refute @ada.reload.otp_required
  end

  test "oversized attachments are skipped" do
    HandlesUploads.send(:remove_const, :MAX_ATTACHMENT_BYTES)
    HandlesUploads.const_set(:MAX_ATTACHMENT_BYTES, 10)
    big = Rack::Test::UploadedFile.new(StringIO.new("x" * 50), "application/octet-stream",
                                       original_filename: "big.bin")
    post "/api/conversations/#{@conversation.id}/messages",
         params: { kind: "outbound", body_text: "see attached", files: [ big ] }
    assert_response :created
    assert_equal 0, Message.order(:id).last.files.count
  ensure
    HandlesUploads.send(:remove_const, :MAX_ATTACHMENT_BYTES)
    HandlesUploads.const_set(:MAX_ATTACHMENT_BYTES, 25.megabytes)
  end

  test "reports aggregate new, closed, per-agent and first-reply time" do
    @conversation.messages.create!(kind: "outbound", status: "sent", agent: @ada,
                                   body_text: "reply", created_at: @conversation.created_at + 120)
    @conversation.set_status!("closed", agent: @ada)

    get "/api/reports", params: { days: 7 }
    body = response.parsed_body
    assert_equal 1, body["totals"]["new"]
    assert_equal 1, body["totals"]["closed"]
    assert_in_delta 120, body["totals"]["avg_first_reply_seconds"], 5
    ada = body["by_agent"].find { |a| a["name"] == "Ada" }
    assert_equal 1, ada["replies"]
    assert_equal 1, ada["closed"]
  end
end
