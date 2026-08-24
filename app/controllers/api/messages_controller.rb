class Api::MessagesController < Api::BaseController
  # POST /api/conversations/:conversation_id/messages — reply or note (B6/B7)
  def create
    conversation = find_accessible_conversation!(params[:conversation_id])
    kind = params.require(:kind)
    case kind
    when "note"
      message = conversation.messages.create!(
        kind: "note", status: "received", agent: current_agent,
        body_text: params[:body_text].to_s,
        body_html: HtmlSanitizer.call(params[:body_html].to_s)
      )
      Notifier.note_added(message, author: current_agent)
    when "outbound"
      mailbox = conversation.mailbox
      to = params[:to].present? ? Array(params[:to]).map(&:to_s) : [ conversation.customer.email ]
      message = conversation.messages.create!(
        kind: "outbound", status: "queued", agent: current_agent,
        to: to, cc: Array(params[:cc]).map(&:to_s), bcc: Array(params[:bcc]).map(&:to_s),
        body_text: params[:body_text].to_s,
        body_html: HtmlSanitizer.call(append_signature(params[:body_html].to_s, mailbox))
      )
      attach_uploads(message)
      SendMessageJob.perform_later(message)
      # Close-from-reply is one action (B5).
      conversation.set_status!("closed", agent: current_agent) if params[:close] == "true" || params[:close] == true
      current_agent.drafts.where(conversation: conversation).destroy_all
    else
      return render json: { error: "invalid_kind" }, status: :unprocessable_entity
    end
    render json: { id: message.id, kind: message.kind, status: message.status }, status: :created
  end

  private

  def attach_uploads(message)
    Array(params[:files]).each do |upload|
      next unless upload.respond_to?(:original_filename)
      message.files.attach(io: upload.to_io, filename: upload.original_filename,
                           content_type: upload.content_type)
    end
    Array(params[:inline_images]).each do |img|
      next unless img.respond_to?(:original_filename)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: img.to_io, filename: img.original_filename, content_type: img.content_type,
        metadata: { content_id: "inline-#{SecureRandom.hex(8)}@shared-inbox" }
      )
      message.files.attach(blob)
    end
  end

  def append_signature(html, mailbox)
    return html if mailbox.signature.blank? || params[:skip_signature]
    "#{html}<br><br>--<br>#{mailbox.signature}"
  end
end
