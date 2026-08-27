# Executes workflows off the domain-event bus. A thread-local guard stops
# workflow actions from triggering further workflows (no cascades, no loops).
class WorkflowEngine
  def self.install!
    DomainEvents.subscribe("*", key: :workflow_engine) { |payload| handle(payload) }
  end

  def self.handle(payload)
    event = payload[:event]
    return unless Workflow::TRIGGERS.include?(event)
    return if Thread.current[:flow_workflow_running]

    conversation_id = event.start_with?("message.") ? payload[:conversation_id] : payload[:id]
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation
    message = event.start_with?("message.") ? Message.find_by(id: payload[:id]) : nil
    # Never react to our own auto-submitted outbound (no reply loops after
    # delivery); inbound list mail still gets triage workflows, but the
    # reply-sending actions below refuse to answer it.
    return if message&.auto_submitted? && message.kind == "outbound"

    Workflow.runnable_for(event, conversation.mailbox_id).each do |workflow|
      next unless workflow.matches?(conversation, message)
      Thread.current[:flow_workflow_running] = true
      begin
        execute(workflow, conversation.reload, message)
      rescue StandardError => e
        Rails.logger.error("workflow #{workflow.id} (#{workflow.name}) failed: #{e.class} #{e.message}")
      ensure
        Thread.current[:flow_workflow_running] = false
      end
    end
  end

  def self.execute(workflow, conversation, message)
    applied = []
    workflow.actions.each do |action|
      apply(action, conversation, message)
      applied << action["type"]
    end
    workflow.update_columns(runs_count: workflow.runs_count + 1, last_run_at: Time.current)
    conversation.events.create!(kind: "workflow", data: { name: workflow.name, actions: applied })
  end

  def self.apply(action, conversation, message)
    value = action["value"].to_s
    case action["type"]
    when "assign"
      agent = Agent.find_by(id: action["value"])
      return unless agent&.can_access?(conversation.mailbox)
      conversation.assign!(agent)
      Notifier.assigned(conversation, by: nil)
    when "assign_team"
      team = Team.find_by(id: action["value"])
      agent = team&.next_agent(conversation.mailbox)
      if agent
        conversation.assign!(agent)
        Notifier.assigned(conversation, by: nil)
      end
    when "unassign"
      conversation.assign!(nil)
    when "add_tag"
      tag = Tag.find_or_create_by!(name: value.presence || "untitled")
      conversation.tags << tag unless conversation.tags.include?(tag)
    when "remove_tag"
      conversation.tags.delete(Tag.find_by(name: value))
    when "set_status"
      return unless Conversation::STATUSES.include?(value)
      conversation.set_status!(value)
      Notifier.status_changed(conversation)
    when "move_mailbox"
      mailbox = Mailbox.find_by(id: action["value"])
      conversation.update!(mailbox: mailbox) if mailbox && mailbox.id != conversation.mailbox_id
    when "add_note"
      conversation.messages.create!(kind: "note", status: "received", body_text: value)
    when "send_reply"
      # Loop-safe canned reply: marked auto-submitted, never re-triggers (A13/D6),
      # and never answers auto-submitted mail (mailing lists, bounces).
      return if message&.auto_submitted?
      body = rendered_reply(value, conversation)
      return if body.blank?
      outbound = conversation.messages.create!(
        kind: "outbound", status: "queued", auto_submitted: true,
        to: [ conversation.customer.email ], body_text: body
      )
      SendMessageJob.perform_later(outbound)
    when "forward_to"
      return if message&.auto_submitted?
      return unless value.match?(URI::MailTo::EMAIL_REGEXP)
      source = message || conversation.messages.where(kind: "inbound").last
      outbound = conversation.messages.create!(
        kind: "outbound", status: "queued", auto_submitted: true, to: [ value ],
        subject: "Fwd: #{conversation.subject}",
        body_text: "---------- Forwarded by workflow ----------\nFrom: #{source&.from_email}\n\n#{source&.body_text}"
      )
      SendMessageJob.perform_later(outbound)
    end
  end

  def self.rendered_reply(value, conversation)
    if value.match?(/\A\d+\z/) && (saved = SavedReply.find_by(id: value))
      saved.render(customer: conversation.customer, mailbox: conversation.mailbox)
    else
      value
    end
  end
end
