# Build MIME (A15) and deliver over the mailbox's SMTP (A16/A17/A18).
# Runs inside SendMessageJob, never on the HTTP request.
class OutboundSender
  def self.call(message) = new(message).call

  def initialize(message)
    @message = message
    @conversation = message.conversation
    @mailbox = @conversation.mailbox
  end

  def call
    raise "mailbox #{@mailbox.id} has no SMTP host" unless @mailbox.smtp_configured?
    ensure_message_id
    mail = build
    mail.delivery_method(:smtp, @mailbox.smtp_options)
    mail.deliver!
    @message.update!(status: "sent", sent_at: Time.current)
    Notifier.outbound_sent(@message)
  end

  private

  def ensure_message_id
    return if @message.message_id_header.present?
    domain = @mailbox.address.split("@").last
    @message.update!(message_id_header: "si-#{SecureRandom.hex(16)}@#{domain}")
  end

  def build
    m = Mail.new
    m.from = @mailbox.from_name.present? ? "#{@mailbox.from_name} <#{@mailbox.address}>" : @mailbox.address
    m.reply_to = @mailbox.address
    m.to = @message.to
    m.cc = @message.cc if @message.cc.present?
    m.bcc = @message.bcc if @message.bcc.present?
    m.subject = reply_subject
    m.message_id = "<#{@message.message_id_header}>"

    m.header["Auto-Submitted"] = "auto-replied" if @message.auto_submitted

    # A subject override (forward, B16) starts a fresh thread for the recipient.
    if @message.subject.blank? && (parent = last_inbound)
      m.in_reply_to = "<#{parent.message_id_header}>" if parent.message_id_header.present?
      refs = "#{parent.references_header} #{parent.message_id_header}".split.map { |r| "<#{r.delete('<>')}>" }
      m.references = refs.join(" ") if refs.any?
    end

    text = @message.body_text.presence || strip_html(@message.body_html)
    html = @message.body_html

    m.text_part = Mail::Part.new { body text }
    if html.present?
      m.html_part = Mail::Part.new do
        content_type "text/html; charset=UTF-8"
        body html
      end
    end

    @message.files.each do |file|
      content_id = file.blob.metadata["content_id"]
      m.add_file(filename: file.filename.to_s, content: file.download)
      part = m.attachments.last
      part.content_type = file.content_type if file.content_type.present?
      if content_id.present? # inline image (A20)
        part.content_id = "<#{content_id}>"
        part.content_disposition = "inline; filename=\"#{file.filename}\""
      end
    end

    m
  end

  def last_inbound
    @conversation.messages.where(kind: "inbound").where.not(id: @message.id).order(created_at: :desc).first
  end

  def reply_subject
    return @message.subject if @message.subject.present?
    base = @conversation.subject.presence || ""
    return base if @conversation.messages.where(kind: "inbound").none?
    base.match?(/\A\s*re:/i) ? base : "Re: #{base}"
  end

  def strip_html(html)
    Nokogiri::HTML5.fragment(html.to_s).text
  end
end
