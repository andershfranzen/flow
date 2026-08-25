require "test_helper"

class PipelineTest < ActiveSupport::TestCase
  setup do
    @mailbox = Mailbox.create!(address: "support@example.com", name: "Support",
                               smtp_host: "smtp.example.com")
    @fetcher = ImapFetcher.new(@mailbox)
  end

  def raw_mail(from: "kunde@example.dk", to: "support@example.com", subject: "Help",
               message_id: "m-#{SecureRandom.hex(6)}@example.dk", headers: {}, html: nil, text: "hello", &block)
    m = Mail.new
    m.from = from
    m.to = to
    m.subject = subject
    m.message_id = "<#{message_id}>"
    headers.each { |k, v| m.header[k] = v }
    if html
      m.text_part = Mail::Part.new { body "fallback" } if text
      m.html_part = Mail::Part.new { content_type "text/html; charset=UTF-8"; body html }
    else
      m.body = text
    end
    block&.call(m)
    m.to_s
  end

  test "new mail becomes an unassigned conversation" do
    @fetcher.ingest(raw_mail(subject: "Fridge broken", text: "It beeps"))
    conv = Conversation.last
    assert_equal "Fridge broken", conv.subject
    assert_nil conv.assignee_id
    assert_equal "active", conv.status
    assert_equal "kunde@example.dk", conv.customer.email
    assert_equal "It beeps", conv.messages.first.body_text.strip
  end

  test "fetching the same mail twice does not duplicate" do
    raw = raw_mail
    @fetcher.ingest(raw)
    assert_equal :duplicate, @fetcher.ingest(raw)
    assert_equal 1, Message.count
  end

  test "reply threads by In-Reply-To and reopens a closed conversation" do
    @fetcher.ingest(raw_mail(message_id: "orig@example.dk"))
    conv = Conversation.last
    conv.update!(status: "closed")
    @fetcher.ingest(raw_mail(subject: "Re: Help", message_id: "r1@example.dk",
                             headers: { "In-Reply-To" => "<orig@example.dk>" }))
    assert_equal 1, Conversation.count
    assert_equal 2, conv.reload.messages_count
    assert_equal "active", conv.status
  end

  test "cc'd stranger reply keeps the original customer" do
    @fetcher.ingest(raw_mail(from: "kunde@example.dk", message_id: "orig@example.dk"))
    conv = Conversation.last
    @fetcher.ingest(raw_mail(from: "stranger@else.com", message_id: "s1@else.com",
                             headers: { "References" => "<orig@example.dk>" }))
    assert_equal 1, Conversation.count
    assert_equal "kunde@example.dk", conv.reload.customer.email
  end

  test "subject fallback threads same customer within window" do
    @fetcher.ingest(raw_mail(subject: "Order 55"))
    @fetcher.ingest(raw_mail(subject: "SV: Order 55", message_id: "x2@example.dk"))
    assert_equal 1, Conversation.count
    assert_equal 2, Conversation.last.messages_count
  end

  test "auto-submitted mail is skipped" do
    @fetcher.ingest(raw_mail(headers: { "Auto-Submitted" => "auto-replied" }))
    assert_equal 0, Conversation.count
  end

  test "mail from the mailbox itself is skipped" do
    @fetcher.ingest(raw_mail(from: "support@example.com"))
    assert_equal 0, Conversation.count
  end

  test "bounce marks the outbound and opens no new thread" do
    @fetcher.ingest(raw_mail(message_id: "orig@example.dk"))
    conv = Conversation.last
    outbound = conv.messages.create!(kind: "outbound", status: "sent",
                                     message_id_header: "si-abc@example.com", to: [ "kunde@example.dk" ])
    dsn = raw_mail(from: "MAILER-DAEMON@mx.example.dk", subject: "Undelivered",
                   message_id: "b1@mx.example.dk",
                   headers: { "In-Reply-To" => "<si-abc@example.com>" })
    @fetcher.ingest(dsn)
    assert_equal 1, Conversation.count
    assert_equal "bounced", outbound.reload.status
    assert conv.reload.messages.last.bounce
  end

  test "stray bounce is dropped entirely" do
    @fetcher.ingest(raw_mail(from: "mailer-daemon@mx.example.dk", subject: "Undelivered"))
    assert_equal 0, Conversation.count
  end

  test "html is sanitized and text extracted" do
    @fetcher.ingest(raw_mail(text: nil, html: "<p>Hi</p><script>alert(1)</script><img src=\"http://evil/track.gif\" onerror=\"x()\">"))
    msg = Message.last
    assert_no_match(/script/, msg.body_html)
    assert_no_match(/onerror/, msg.body_html)
    assert_match(/Hi/, msg.body_html)
    assert_equal "Hi", msg.body_text.strip
  end

  test "inline styles survive sanitization but css attacks do not" do
    html = '<p style="color: #cc0000; font-family: Georgia">Warm</p>' \
           '<div style="background: url(javascript:alert(1)); color: blue">tricky</div>' \
           '<table bgcolor="#eeeeee" align="center"><tr><td style="width: 300px">cell</td></tr></table>'
    @fetcher.ingest(raw_mail(text: nil, html: html))
    out = Message.last.body_html
    assert_includes out.delete(" "), "color:#cc0000", "benign styling must survive"
    assert_includes out, 'bgcolor="#eeeeee"'
    refute_includes out, "javascript:", "css url attacks must be stripped"
  end

  test "nested multipart with windows-1252 charset decodes" do
    raw = <<~MAIL
      From: kunde@example.dk
      To: support@example.com
      Subject: =?windows-1252?Q?K=F8leskab_st=F8jer?=
      Message-ID: <cp1252@example.dk>
      MIME-Version: 1.0
      Content-Type: multipart/mixed; boundary="outer"

      --outer
      Content-Type: multipart/alternative; boundary="inner"

      --inner
      Content-Type: text/plain; charset=windows-1252
      Content-Transfer-Encoding: quoted-printable

      K=F8leskabet st=F8jer igen =96 kan I hj=E6lpe?
      --inner
      Content-Type: text/html; charset=windows-1252
      Content-Transfer-Encoding: quoted-printable

      <p>K=F8leskabet st=F8jer igen =96 kan I hj=E6lpe?</p>
      --inner--
      --outer
      Content-Type: application/pdf; name="bilag.pdf"
      Content-Disposition: attachment; filename="bilag.pdf"
      Content-Transfer-Encoding: base64

      JVBERi0xLjQ=
      --outer--
    MAIL
    @fetcher.ingest(raw)
    conversation = Conversation.last
    assert_equal "Køleskab støjer", conversation.subject
    message = conversation.messages.last
    assert_includes message.body_text, "Køleskabet støjer igen – kan I hjælpe?"
    assert_includes message.body_html, "hjælpe"
    assert_equal [ "bilag.pdf" ], message.files.map { |f| f.filename.to_s }
  end

  test "attachments are stored with content id" do
    raw = raw_mail do |m|
      m.attachments["photo.png"] = { mime_type: "image/png", content: "PNGDATA" }
      m.attachments["photo.png"].content_id = "<cid123@x>"
    end
    @fetcher.ingest(raw)
    file = Message.last.files.first
    assert_equal "photo.png", file.filename.to_s
    assert_equal "cid123@x", file.blob.metadata["content_id"]
  end

  test "outbound sender builds a threaded reply" do
    @fetcher.ingest(raw_mail(message_id: "orig@example.dk", subject: "Help me"))
    conv = Conversation.last
    reply = conv.messages.create!(kind: "outbound", status: "queued",
                                  to: [ "kunde@example.dk" ], body_text: "On it",
                                  body_html: "<p>On it</p>")
    sender = OutboundSender.new(reply)
    sender.send(:ensure_message_id)
    mail = sender.send(:build)
    assert_equal [ "support@example.com" ], mail.from
    assert_equal "Re: Help me", mail.subject
    assert_includes mail.in_reply_to.to_s, "orig@example.dk"
    assert_includes Array(mail.references).join, "orig@example.dk"
    assert mail.multipart?
    assert_match "On it", mail.text_part.decoded
  end
end
