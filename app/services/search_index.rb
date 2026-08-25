# Full-text search behind one seam (E1), per adapter:
# SQLite → an FTS5 table kept in sync by Message callbacks.
# PostgreSQL → expression tsvector queries over messages (+ subject ILIKE),
#   nothing to maintain — conversation_id moves with the row on merge.
# The index is ensured lazily so schema.rb stays adapter-neutral.
class SearchIndex
  class << self
    def postgres?
      ActiveRecord::Base.connection.adapter_name.match?(/postg/i)
    end

    def ensure!
      return if @ready
      unless postgres?
        ActiveRecord::Base.connection.execute(<<~SQL)
          CREATE VIRTUAL TABLE IF NOT EXISTS message_search USING fts5(
            subject, body, conversation_id UNINDEXED, message_id UNINDEXED
          );
        SQL
      end
      @ready = true
    end

    def reset! = @ready = false # tests / reconnects

    def index_message(message)
      ensure!
      return if postgres?
      execute("INSERT INTO message_search(subject, body, conversation_id, message_id) VALUES (?, ?, ?, ?)",
              message.conversation.subject, message.body_text.to_s, message.conversation_id, message.id)
    end

    def deindex_message(message_id)
      ensure!
      return if postgres?
      execute("DELETE FROM message_search WHERE message_id = ?", message_id)
    end

    def reassign(from_conversation_id, to_conversation_id)
      ensure!
      return if postgres? # derived from messages.conversation_id, already correct
      execute("UPDATE message_search SET conversation_id = ? WHERE conversation_id = ?",
              to_conversation_id, from_conversation_id)
    end

    # → conversation ids matching the query
    def search(query)
      ensure!
      if postgres?
        Message.where(
          "to_tsvector('simple', coalesce(subject, '') || ' ' || coalesce(body_text, '')) @@ websearch_to_tsquery('simple', ?)",
          query
        ).distinct.pluck(:conversation_id) |
          Conversation.where("subject ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%").ids
      else
        quoted = query.split.map { |t| "\"#{t.delete('"')}\"" }.join(" ")
        sql = ActiveRecord::Base.sanitize_sql(
          [ "SELECT DISTINCT conversation_id FROM message_search WHERE message_search MATCH ?", quoted ]
        )
        ActiveRecord::Base.connection.select_values(sql)
      end
    rescue ActiveRecord::StatementInvalid
      [] # user-typed query syntax is never an error
    end

    private

    def execute(sql, *binds)
      ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql([ sql, *binds ]))
    end
  end
end
