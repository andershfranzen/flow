# SSE: conversation-list refresh + collision presence (F6/B13/H20).
class Api::StreamController < Api::BaseController
  include ActionController::Live

  # GET /api/stream?conversation_id= — emits `conversations` bumps and `presence`.
  # Connection lives ~90s; the client reconnects with backoff.
  def show
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    sse = ActionController::Live::SSE.new(response.stream, retry: 3000)
    last_stamp = latest_stamp
    last_viewers = nil
    sse.write({ ok: true }, event: "hello")
    30.times do
      current = latest_stamp
      if current != last_stamp
        last_stamp = current
        sse.write({ changed_at: current }, event: "conversations")
      end
      if params[:conversation_id].present?
        viewers = Presence.viewers(params[:conversation_id]).reject { |v| v["id"] == current_agent.id }
        if viewers != last_viewers
          last_viewers = viewers
          sse.write({ viewers: viewers }, event: "presence")
        end
      end
      sleep 3
    end
  rescue IOError, ActionController::Live::ClientDisconnected
    # client went away
  ensure
    sse&.close
  end

  # POST /api/conversations/:conversation_id/presence — viewing heartbeat
  def presence
    conversation = find_accessible_conversation!(params[:conversation_id])
    viewers = Presence.heartbeat(conversation.id, current_agent).reject { |v| v["id"] == current_agent.id }
    render json: { viewers: viewers }
  end

  private

  def latest_stamp
    Conversation.where(mailbox: current_agent.accessible_mailboxes).maximum(:updated_at)&.to_f
  end
end
