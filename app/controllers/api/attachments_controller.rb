class Api::AttachmentsController < Api::BaseController
  # Authz: agent must see the mailbox (E3). Never serve HTML inline (I3).
  def show
    attachment = ActiveStorage::Attachment.find(params[:id])
    message = attachment.record
    raise ActiveRecord::RecordNotFound unless message.is_a?(Message) &&
      current_agent.can_access?(message.conversation.mailbox)

    blob = attachment.blob
    inline = blob.content_type.to_s.match?(%r{\A(image/(png|jpeg|gif|webp)|application/pdf)\z})
    send_data blob.download,
      filename: attachment.filename.to_s,
      type: inline ? blob.content_type : "application/octet-stream",
      disposition: inline ? "inline" : "attachment"
  end
end
