# The mail pipeline's core: raw inbound mail → Customer / Conversation / Message.
# Covers MIME decode (A6), sanitize (A7), text extract (A8), threading (A10),
# new-vs-reply (A11), recipients (A12), loop/flood guard (A13), bounce (A14).
class InboundProcessor
  FLOOD_CAP_PER_MINUTE = 30
  SUBJECT_FALLBACK_WINDOW = 30.days

  def self.call(mailbox, inbound_email, received_at: nil)
    new(mailbox, inbound_email, received_at: received_at).call
  end

  def initialize(mailbox, inbound_email, received_at: nil)
    @mailbox = mailbox
    @inbound_email = inbound_email
    @mail = inbound_email.mail
    @received_at = received_at
  end

  def call
    return :skipped_loop if loop?
    return :skipped_auto if auto_submitted_drop?

    conversation = find_by_references

    if bounce?
      original = find_bounced_outbound
      if original
        original.update!(status: "bounced")
        create_message(original.conversation, bounce: true)
        return :bounce_recorded
      elsif conversation.nil?
        # Never open a customer thread for a stray bounce (A14).
        Rails.logger.info("inbound: dropped unmatched bounce #{@mail.message_id}")
        return :bounce_dropped
      end
    end

    customer = Customer.for_email(from_email, name: from_name)
    conversation ||= find_by_subject_fallback(customer)

    if conversation
      # A merged-away thread must not resurrect: route to the surviving target.
      conversation = resolve_merge_target(conversation)
      # Reply from a CC'd stranger keeps the original customer (A11).
      message = create_message(conversation, bounce: bounce?)
      # Spam stays spam: appending keeps the record, but replying to a spam
      # thread must not reopen it or ping anyone.
      return :reply_to_spam if conversation.status == "spam"
      # An assignee who left or lost this mailbox can't handle the reopened
      # thread — unassign so it lands in Unassigned instead of a dead "Mine".
      if conversation.assignee && !conversation.assignee.can_access?(@mailbox)
        conversation.assign!(nil)
      end
      conversation.set_status!("active") if %w[pending closed trash].include?(conversation.status)
      conversation.update!(snoozed_until: nil) if conversation.snoozed_until # reply wakes it (B18)
      Notifier.customer_reply(message)
      :reply
    else
      return :skipped_flood if flooded?
      conversation = Conversation.create!(
        mailbox: @mailbox, customer: customer,
        subject: subject, last_message_at: arrival_time
      )
      message = create_message(conversation, bounce: bounce?)
      Notifier.new_conversation(message)
      if @mailbox.auto_reply_enabled && @mailbox.auto_reply_body.present? &&
         !bounce? && !list_mail?
        AutoReplyJob.perform_later(conversation)
      end
      :new_conversation
    end
  end

  private

  def from_email = @mail.from&.first.to_s.downcase.presence || "unknown@invalid"
  def from_name = @mail[:from]&.display_names&.first
  def subject = @mail.subject.to_s.scrub.strip
  # Clamped: a future Date header would pin the thread atop the inbox for good.
  def sent_time
    time = (@mail.date&.to_time rescue nil)
    time && [ time, Time.current ].min
  end
  # IMAP INTERNALDATE when the fetcher had it; the (clamped) Date header otherwise.
  def arrival_time = @received_at || sent_time

  def loop?
    return true if from_email == @mailbox.address
    # Our own outbound coming back around (A13).
    @mail.message_id.present? &&
      Message.where(kind: "outbound", message_id_header: @mail.message_id).exists?
  end

  def auto_submitted_drop?
    auto = @mail.header["Auto-Submitted"]&.value
    return true if auto.present? && auto.downcase != "no"
    @mail.header["X-Auto-Response-Suppress"].present? && !bounce?
  end

  def list_mail?
    @mail.header["List-Unsubscribe"].present? || @mail.header["List-Id"].present?
  end

  def bounce?
    return true if from_email.match?(/\A(mailer-daemon|postmaster)@/i)
    @mail.content_type.to_s.include?("report-type=delivery-status")
  end

  def find_bounced_outbound
    ids = referenced_message_ids
    # DSNs often embed the original as a message/rfc822 part.
    @mail.all_parts.each do |part|
      next unless part.content_type.to_s.start_with?("message/rfc822")
      embedded_id = part.body.decoded[/^Message-I[dD]:\s*(<[^>]+>|\S+)/i, 1]
      ids << embedded_id.to_s.delete("<>") if embedded_id
    rescue StandardError
      next
    end
    return nil if ids.empty?
    Message.joins(:conversation)
           .where(conversations: { mailbox_id: @mailbox.id }, kind: "outbound", message_id_header: ids)
           .order(created_at: :desc).first
  end

  def referenced_message_ids
    [ @mail.in_reply_to, *Array(@mail.references) ].flatten.compact.map(&:to_s)
  end

  def resolve_merge_target(conversation)
    seen = Set.new
    while conversation.merged_into_id && seen.add?(conversation.id)
      conversation = Conversation.find(conversation.merged_into_id)
    end
    conversation
  end

  def find_by_references
    ids = referenced_message_ids
    return nil if ids.empty?
    Message.joins(:conversation)
           .where(conversations: { mailbox_id: @mailbox.id }, message_id_header: ids)
           .order(created_at: :desc).first&.conversation
  end

  def find_by_subject_fallback(customer)
    normalized = normalize_subject(subject)
    return nil if normalized.blank?
    Conversation.where(mailbox: @mailbox, customer: customer)
                .where(last_message_at: SUBJECT_FALLBACK_WINDOW.ago..)
                .order(last_message_at: :desc)
                .detect { |c| normalize_subject(c.subject) == normalized }
  end

  def normalize_subject(s)
    s.to_s.gsub(/\A(\s*(re|fwd?|sv|aw|vs)\s*(\[\d+\])?:\s*)+/i, "").gsub(/\s+/, " ").strip.downcase
  end

  def flooded?
    @mailbox.conversations.where(created_at: 1.minute.ago..).count >= FLOOD_CAP_PER_MINUTE
  end

  def create_message(conversation, bounce: false)
    message = conversation.messages.create!(
      kind: "inbound",
      status: "received",
      message_id_header: @mail.message_id,
      in_reply_to: @mail.in_reply_to.is_a?(Array) ? @mail.in_reply_to.first : @mail.in_reply_to,
      references_header: Array(@mail.references).flatten.compact.join(" "),
      from_email: from_email,
      from_name: from_name,
      to: address_list(:to), cc: address_list(:cc), bcc: address_list(:bcc),
      body_text: extract_text,
      body_html: extract_html,
      bounce: bounce,
      auto_submitted: list_mail?,
      sent_at: sent_time,
      received_at: @received_at
    )
    attach_files(message)
    message
  end

  def address_list(field)
    Array(@mail.send(field)).map(&:to_s)
  rescue StandardError
    []
  end

  def extract_text
    part = @mail.multipart? ? @mail.text_part : (@mail unless html_only?)
    text = decode(part)
    text.presence || strip_html(extract_html)
  end

  def extract_html
    HtmlSanitizer.call(decode(html_part))
  end

  def html_part = @mail.multipart? ? @mail.html_part : (@mail if html_only?)
  def html_only? = @mail.mime_type == "text/html"

  def decode(part)
    return "" if part.nil?
    part.decoded.encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
  rescue StandardError
    part.body.to_s.force_encoding("UTF-8").scrub
  end

  def strip_html(html)
    return "" if html.blank?
    Nokogiri::HTML5.fragment(html).text.gsub(/[ \t]+/, " ").strip
  end

  MAX_INBOUND_ATTACHMENT = 30.megabytes

  def attach_files(message)
    @mail.attachments.each do |att|
      if att.body.raw_source.bytesize > MAX_INBOUND_ATTACHMENT
        Rails.logger.warn("inbound: skipping oversized attachment #{att.filename} on message #{message.id}")
        next
      end
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(att.decoded),
        filename: att.filename.presence || "attachment",
        content_type: att.mime_type,
        metadata: { content_id: att.content_id.to_s.delete("<>").presence }.compact
      )
      message.files.attach(blob)
    rescue StandardError => e
      Rails.logger.warn("inbound: attachment failed on message #{message.id}: #{e.message}")
    end
  end
end
