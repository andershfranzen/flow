# Shared attachment/inline-image handling for outbound composition (A20).
module HandlesUploads
  extend ActiveSupport::Concern

  MAX_ATTACHMENT_BYTES = 25.megabytes

  private

  # Attaches files + inline images; returns { client_local_cid => content_id }.
  def attach_uploads(message)
    Array(params[:files]).each do |upload|
      next unless upload.respond_to?(:original_filename)
      next if upload.size > MAX_ATTACHMENT_BYTES # E2 size cap
      message.files.attach(io: upload.to_io, filename: upload.original_filename,
                           content_type: upload.content_type)
    end
    Array(params[:inline_images]).each_with_object({}) do |img, map|
      next unless img.respond_to?(:original_filename)
      content_id = "inline-#{SecureRandom.hex(8)}@flow"
      blob = ActiveStorage::Blob.create_and_upload!(
        io: img.to_io, filename: img.original_filename, content_type: img.content_type,
        metadata: { content_id: content_id }
      )
      message.files.attach(blob)
      map[img.original_filename] = content_id
    end
  end

  def rewrite_inline_cids!(message, cid_map)
    return if cid_map.empty?
    html = message.body_html.to_s
    cid_map.each { |local, content_id| html = html.gsub("cid:#{local}", "cid:#{content_id}") }
    message.update!(body_html: html)
  end
end
