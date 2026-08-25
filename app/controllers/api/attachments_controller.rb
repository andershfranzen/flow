class Api::AttachmentsController < Api::BaseController
  # Native browser-renderable types served with their real content type (E3).
  INLINE_TYPES = %r{\A(image/(png|jpeg|gif|webp)|application/pdf|audio/(mpeg|mp4|ogg|wav|webm)|video/(mp4|webm|ogg|quicktime))\z}
  # Text-ish types are forced to text/plain so nothing executes (I3).
  TEXT_TYPES = %r{\A(text/|application/(json|xml|x-yaml))}

  # Authz: agent must see the mailbox (E3). Never serve HTML as HTML (I3).
  # ponytail: send_data has no Range support, so long video seeking is limited.
  def show
    attachment = ActiveStorage::Attachment.find(params[:id])
    message = attachment.record
    raise ActiveRecord::RecordNotFound unless message.is_a?(Message) &&
      current_agent.can_access?(message.conversation.mailbox)

    blob = attachment.blob
    content_type = blob.content_type.to_s
    if content_type.match?(INLINE_TYPES)
      send_data blob.download, filename: attachment.filename.to_s,
                type: content_type, disposition: "inline"
    elsif content_type.match?(TEXT_TYPES) && !content_type.include?("html")
      send_data blob.download, filename: attachment.filename.to_s,
                type: "text/plain; charset=utf-8", disposition: "inline"
    else
      send_data blob.download, filename: attachment.filename.to_s,
                type: "application/octet-stream", disposition: "attachment"
    end
  end
end
