# Reports-lite numbers, shared by the API controller and the MCP `report` tool.
class Reports
  def self.summary(agent:, days: 30)
    days = days.to_i.clamp(1, 365)
    from = days.days.ago.beginning_of_day
    mailbox_ids = agent.accessible_mailboxes.ids
    conversations = Conversation.where(mailbox_id: mailbox_ids)

    pg = SearchIndex.postgres?
    day = ->(col) { pg ? "CAST(#{col} AS DATE)" : "date(#{col})" }
    status_is_closed = pg ? "data->>'status' = 'closed'" : "json_extract(data, '$.status') = 'closed'"

    new_per_day = conversations.where(created_at: from..).group(Arel.sql(day.call("created_at"))).count
    closed_events = Event.joins(:conversation)
                         .where(conversations: { mailbox_id: mailbox_ids })
                         .where(kind: "status_changed", created_at: from..)
                         .where(Arel.sql(status_is_closed))
    closed_per_day = closed_events.group(Arel.sql(day.call("events.created_at"))).count

    by_agent = Agent.order(:name).map do |a|
      replies = Message.joins(:conversation)
                       .where(conversations: { mailbox_id: mailbox_ids }, agent: a,
                              kind: "outbound", created_at: from..).count
      closed = closed_events.where(agent: a).count
      { name: a.name, replies: replies, closed: closed }
    end.reject { |row| row[:replies].zero? && row[:closed].zero? }

    by_mailbox = Mailbox.where(id: mailbox_ids).order(:name).map do |mailbox|
      { name: mailbox.name,
        new: mailbox.conversations.where(created_at: from..).count,
        open: mailbox.conversations.where(status: %w[active pending]).count }
    end

    { days: days,
      totals: { new: new_per_day.values.sum, closed: closed_per_day.values.sum,
                open_now: conversations.where(status: %w[active pending]).count,
                avg_first_reply_seconds: avg_first_reply(conversations.where(created_at: from..)) },
      new_per_day: new_per_day, closed_per_day: closed_per_day,
      by_agent: by_agent, by_mailbox: by_mailbox }
  end

  # ponytail: Ruby loop over the window's conversations; SQL window functions when it hurts
  def self.avg_first_reply(scope)
    samples = scope.limit(2000).filter_map do |conversation|
      first_in = conversation.messages.where(kind: "inbound").minimum(:created_at)
      next unless first_in
      first_out = conversation.messages.where(kind: "outbound", auto_submitted: false)
                              .where("created_at > ?", first_in).minimum(:created_at)
      first_out && (first_out - first_in)
    end
    samples.empty? ? nil : (samples.sum / samples.size).round
  end
end
