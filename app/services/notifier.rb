# In-app notifications (D1/D2), email-to-agent (D3), webhook emit (G3).
class Notifier
  def self.new_conversation(message)
    conversation = message.conversation
    recipients = agents_for(conversation.mailbox).select { |a| a.notify_prefs["new_unassigned"] }
    notify(recipients, conversation, "new_unassigned")
    DomainEvents.emit("thread.created", conversation_payload(conversation))
    DomainEvents.emit("message.inbound", message_payload(message))
  end

  def self.customer_reply(message)
    conversation = message.conversation
    recipients = []
    if (assignee = conversation.assignee)
      recipients << assignee if assignee.notify_prefs["customer_reply"]
    else
      # No owner (never assigned, or the assignee left): the reply must not
      # vanish — alert the same crowd a new unassigned conversation would.
      recipients |= agents_for(conversation.mailbox).select { |a| a.notify_prefs["new_unassigned"] }
    end
    recipients |= conversation.following_agents.to_a
    notify(recipients, conversation, "customer_reply")
    DomainEvents.emit("message.inbound", message_payload(message))
  end

  def self.assigned(conversation, by:)
    assignee = conversation.assignee
    if assignee && assignee != by && assignee.notify_prefs["assigned_to_me"]
      notify([ assignee ], conversation, "assigned_to_me")
    end
    DomainEvents.emit("thread.assigned", conversation_payload(conversation))
  end

  def self.status_changed(conversation)
    DomainEvents.emit("thread.status", conversation_payload(conversation))
  end

  def self.note_added(message, author:)
    conversation = message.conversation
    mentioned = mentioned_agents(message.body_text)
    notify(mentioned - [ author ], conversation, "mention")

    recipients = []
    assignee = conversation.assignee
    recipients << assignee if assignee && assignee.notify_prefs["note_on_mine"]
    recipients |= conversation.following_agents.to_a
    notify(recipients - [ author ] - mentioned, conversation, "note_on_mine")
  end

  # @firstname or @full.email in a note (B19). First-name collisions notify all matches.
  def self.mentioned_agents(text)
    return [] if text.blank?
    Agent.all.select do |agent|
      text.include?("@#{agent.email}") ||
        text.match?(/@#{Regexp.escape(agent.name.split.first)}\b/i)
    end
  end

  def self.outbound_sent(message)
    DomainEvents.emit("message.outbound", message_payload(message))
  end

  def self.agents_for(mailbox)
    # No joins → no duplicate rows; DISTINCT would break on PG json columns.
    Agent.where(role: "admin").or(Agent.where(id: mailbox.agent_ids))
  end

  def self.notify(agents, conversation, kind)
    agents = agents.reject { |a| a.muted_mailbox_ids.include?(conversation.mailbox_id) }
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
