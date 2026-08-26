# SSE: conversation-list refresh + collision presence (F6/B13/H20).
#
# Dead-socket writes don't reliably raise, so a stream that outlives its
# client would hold a Puma thread for the whole loop. Each agent therefore
# gets ONE live stream: opening a new one bumps the agent's generation and
# every older loop exits at its next tick. Worst case: streams-per-agent = 1
# plus a few seconds of overlap.
class Api::StreamController < Api::BaseController
  include ActionController::Live

  TICK_SECONDS = 3
  # Development keeps streams one tick long (the client reconnects every ~3s,
  # so it degrades to polling): long-lived Live streams deadlock the dev code
  # reloader when a dead socket blocks mid-write. Production has no reloader
  # and keeps real ~90s streams.
  TICKS = Rails.env.development? ? 1 : 30

  @generation = Hash.new(0)
  @mutex = Mutex.new

  class << self
    def open_stream!(agent_id)
      @mutex.synchronize { @generation[agent_id] += 1 }
    end

    def current_stream?(agent_id, generation)
      @mutex.synchronize { @generation[agent_id] == generation }
    end
  end

  # GET /api/stream?conversation_id= — emits `conversations` bumps and `presence`.
  def show
    conversation = find_accessible_conversation!(params[:conversation_id]) if params[:conversation_id].present?
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    generation = self.class.open_stream!(current_agent.id)
    sse = ActionController::Live::SSE.new(response.stream, retry: 3000)
    last_stamp = latest_stamp
    last_viewers = nil
    sse.write({ ok: true }, event: "hello")
    TICKS.times do
      break unless self.class.current_stream?(current_agent.id, generation)
      current = latest_stamp
      if current != last_stamp
        last_stamp = current
        sse.write({ changed_at: current }, event: "conversations")
      end
      if conversation
        viewers = Presence.viewers(conversation.id).reject { |v| v["id"] == current_agent.id }
        if viewers != last_viewers
          last_viewers = viewers
          sse.write({ viewers: viewers }, event: "presence")
        end
      end
      # Ping every tick — frees the thread promptly when the socket does report closed.
      sse.write({ t: Time.now.to_i }, event: "ping")
      # Release the autoload interlock while sleeping: otherwise dev-mode code
      # reloads queue behind live streams and every request freezes for the
      # stream's lifetime. No-op in production.
      ActiveSupport::Dependencies.interlock.permit_concurrent_loads { sleep TICK_SECONDS }
    end
  rescue IOError, ActionController::Live::ClientDisconnected
    # client went away
  ensure
    sse&.close
  end

  private

  def latest_stamp
    Conversation.where(mailbox: current_agent.accessible_mailboxes).maximum(:updated_at)&.to_f
  end
end
