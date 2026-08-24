# In-app notifications (D1/D2), email-to-agent (D3), webhook emit (G3).
class Notifier
  def self.new_conversation(message)
    conversation = message.conversation
    recipients = agents_for(conversation.mailbox).select { |a| a.notify_prefs["new_unassigned"] }
    notify(recipients, conversation, "new_unassigned")
    Webhook.emit("thread.created", conversation_payload(conversation))
    Webhook.emit("message.inbound", message_payload(message))
  end

  def self.customer_reply(message)
    conversation = message.conversation
    if (assignee = conversation.assignee) && assignee.notify_prefs["customer_reply"]
      notify([ assignee ], conversation, "customer_reply")
    end
    Webhook.emit("message.inbound", message_payload(message))
  end

  def self.assigned(conversation, by:)
    assignee = conversation.assignee
    if assignee && assignee != by && assignee.notify_prefs["assigned_to_me"]
      notify([ assignee ], conversation, "assigned_to_me")
    end
    Webhook.emit("thread.assigned", conversation_payload(conversation))
  end

  def self.status_changed(conversation)
    Webhook.emit("thread.status", conversation_payload(conversation))
  end

  def self.note_added(message, author:)
    conversation = message.conversation
    assignee = conversation.assignee
    if assignee && assignee != author && assignee.notify_prefs["note_on_mine"]
      notify([ assignee ], conversation, "note_on_mine")
    end
  end

  def self.outbound_sent(message)
    Webhook.emit("message.outbound", message_payload(message))
  end

  def self.agents_for(mailbox)
    Agent.where(role: "admin").or(Agent.where(id: mailbox.agent_ids)).distinct
  end

  def self.notify(agents, conversation, kind)
    agents.each do |agent|
      notification = Notification.create!(agent: agent, conversation: conversation, kind: kind)
      NotifyAgentEmailJob.perform_later(notification)
    end
  end

  def self.conversation_payload(c)
    { id: c.id, number: c.number, subject: c.subject, status: c.status,
      mailbox_id: c.mailbox_id, customer_email: c.customer.email,
      assignee_id: c.assignee_id, preview: c.preview }
  end

  def self.message_payload(m)
    { id: m.id, conversation_id: m.conversation_id, conversation_number: m.conversation.number,
      kind: m.kind, from_email: m.from_email, subject: m.conversation.subject,
      body_text: m.body_text.to_s.truncate(2000) }
  end
end
