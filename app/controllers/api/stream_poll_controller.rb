# Development stand-in for the SSE stream: a one-shot text/event-stream body
# with no ActionController::Live involved. EventSource's retry field turns it
# into 3s polling, and the dev code reloader never has a stream to wait on.
class Api::StreamPollController < Api::BaseController
  def show
    conversation = find_accessible_conversation!(params[:conversation_id]) if params[:conversation_id].present?
    lines = [ "retry: 3000", "", "event: hello", "data: {\"ok\":true}", "" ]
    stamp = Conversation.where(mailbox: current_agent.accessible_mailboxes).maximum(:updated_at)&.to_f
    if params[:since].present? && stamp && stamp > params[:since].to_f
      lines += [ "event: conversations", "data: #{{ changed_at: stamp }.to_json}", "" ]
    end
    lines += [ "event: stamp", "data: #{{ stamp: stamp }.to_json}", "" ]
    if conversation
      viewers = Presence.viewers(conversation.id).reject { |v| v["id"] == current_agent.id }
      lines += [ "event: presence", "data: #{{ viewers: viewers }.to_json}", "" ]
    end
    render plain: lines.join("\n") + "\n", content_type: "text/event-stream"
  end
end
