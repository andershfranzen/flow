class Api::MessagesController < Api::BaseController
  include HandlesUploads
  UNDO_SECONDS = 15

  rate_limit to: 60, within: 1.minute, only: :create # I4: sending is rate-limited

  # DELETE /api/conversations/:conversation_id/messages/:id — undo send (still queued)
  def destroy
    conversation = find_accessible_conversation!(params[:conversation_id])
    message = conversation.messages.find(params[:id])
    unless message.kind == "outbound" && message.status == "queued"
      return render json: { error: "already_sent" }, status: :unprocessable_entity
    end
    body_html = message.body_html
    message.destroy!
    draft = current_agent.drafts.find_or_initialize_by(conversation_id: conversation.id)
    draft.update!(body: body_html, mailbox_id: conversation.mailbox_id)
    render json: { undone: true, body: body_html }
  end

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
        subject: params[:subject].presence,
        body_text: params[:body_text].to_s,
        body_html: HtmlSanitizer.call(append_signature(params[:body_html].to_s, mailbox))
      )
      cid_map = attach_uploads(message)
      if cid_map.any?
        html = message.body_html.to_s
        cid_map.each { |local, content_id| html = html.gsub("cid:#{local}", "cid:#{content_id}") }
        message.update!(body_html: html)
      end
      # Undo window (15s) before the queue picks it up.
      SendMessageJob.set(wait: UNDO_SECONDS.seconds).perform_later(message)
      # Close-from-reply is one action (B5).
      conversation.set_status!("closed", agent: current_agent) if params[:close] == "true" || params[:close] == true
      current_agent.drafts.where(conversation: conversation).destroy_all
    else
      return render json: { error: "invalid_kind" }, status: :unprocessable_entity
    end
    render json: { id: message.id, kind: message.kind, status: message.status }, status: :created
  end

  private


  def append_signature(html, mailbox)
    signature = current_agent.signature.presence || mailbox.signature.presence ||
                OrgSetting.current.default_signature
    return html if signature.blank? || params[:skip_signature]
    "#{html}<br><br>--<br>#{signature}"
  end
end
