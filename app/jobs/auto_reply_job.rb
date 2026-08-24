# "We got your mail" once per thread, loop-safe (D6). Off by default.
class AutoReplyJob < ApplicationJob
  queue_as :default

  def perform(conversation)
    mailbox = conversation.mailbox
    return unless mailbox.auto_reply_enabled && mailbox.auto_reply_body.present?
    return if conversation.messages.exists?(kind: "outbound") # only before any real reply
    message = conversation.messages.create!(
      kind: "outbound", status: "queued", auto_submitted: true,
      to: [ conversation.customer.email ], body_text: mailbox.auto_reply_body
    )
    OutboundSender.call(message)
  end
end
