# Who is viewing which conversation (B12). Heartbeat + TTL.
# ponytail: in-memory map, correct for the single web process v1 ships with;
# move to the DB or a bus when web scales past one process.
class Presence
  TTL_SECONDS = 15
  @map = Hash.new { |h, k| h[k] = {} }
  @mutex = Mutex.new

  class << self
    def heartbeat(conversation_id, agent)
      @mutex.synchronize do
        @map[conversation_id.to_i][agent.id] = { "id" => agent.id, "name" => agent.name, "at" => Time.now.to_f }
      end
      viewers(conversation_id)
    end

    def viewers(conversation_id)
      cutoff = Time.now.to_f - TTL_SECONDS
      @mutex.synchronize do
        @map[conversation_id.to_i].delete_if { |_, v| v["at"] <= cutoff }
        @map[conversation_id.to_i].values.map { |v| v.slice("id", "name") }
      end
    end
  end
end
