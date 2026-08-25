# Reports-lite: enough numbers to run a support team, no BI suite.
class Api::ReportsController < Api::BaseController
  before_action :require_admin!

  def show
    days = params.fetch(:days, 30).to_i.clamp(1, 365)
    from = days.days.ago.beginning_of_day
    mailbox_ids = current_agent.accessible_mailboxes.ids
    conversations = Conversation.where(mailbox_id: mailbox_ids)

    new_per_day = conversations.where(created_at: from..).group("date(created_at)").count
    closed_events = Event.joins(:conversation)
                         .where(conversations: { mailbox_id: mailbox_ids })
                         .where(kind: "status_changed", created_at: from..)
                         .where("json_extract(data, '$.status') = 'closed'")
    closed_per_day = closed_events.group("date(events.created_at)").count

    by_agent = Agent.order(:name).map do |agent|
      replies = Message.joins(:conversation)
                       .where(conversations: { mailbox_id: mailbox_ids }, agent: agent,
                              kind: "outbound", created_at: from..).count
      closed = closed_events.where(agent: agent).count
      { name: agent.name, replies: replies, closed: closed }
    end.reject { |row| row[:replies].zero? && row[:closed].zero? }

    by_mailbox = Mailbox.where(id: mailbox_ids).order(:name).map do |mailbox|
      { name: mailbox.name,
        new: mailbox.conversations.where(created_at: from..).count,
        open: mailbox.conversations.where(status: %w[active pending]).count }
    end

    render json: {
      days: days,
      totals: { new: new_per_day.values.sum, closed: closed_per_day.values.sum,
                open_now: conversations.where(status: %w[active pending]).count,
                avg_first_reply_seconds: avg_first_reply(conversations.where(created_at: from..)) },
      new_per_day: new_per_day, closed_per_day: closed_per_day,
      by_agent: by_agent, by_mailbox: by_mailbox
    }
  end

  private

  # ponytail: Ruby loop over the window's conversations; SQL window functions when it hurts
  def avg_first_reply(scope)
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
