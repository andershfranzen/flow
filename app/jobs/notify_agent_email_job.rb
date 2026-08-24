class NotifyAgentEmailJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  KIND_LABEL = {
    "new_unassigned" => "New conversation",
    "assigned_to_me" => "Assigned to you",
    "customer_reply" => "Customer replied",
    "note_on_mine" => "New note"
  }.freeze

  def perform(notification)
    conversation = notification.conversation
    mailbox = conversation.mailbox
    return unless mailbox.smtp_configured?

    base_url = OrgSetting.current.base_url.presence
    mail = Mail.new
    mail.from = OrgSetting.current.notify_from.presence || mailbox.address
    mail.to = notification.agent.email
    mail.subject = "[##{conversation.number}] #{KIND_LABEL.fetch(notification.kind, notification.kind)}: #{conversation.subject}"
    body = +"#{KIND_LABEL.fetch(notification.kind, notification.kind)} in #{mailbox.name}\n\n"
    body << "#{conversation.preview}\n"
    body << "\n#{base_url}/conversations/#{conversation.id}\n" if base_url
    mail.body = body
    mail.header["Auto-Submitted"] = "auto-generated" # never loops back in (A13)
    mail.delivery_method(:smtp, mailbox.smtp_options)
    mail.deliver!
  end
end
