class Message < ApplicationRecord
  KINDS = %w[inbound outbound note].freeze
  STATUSES = %w[received queued sent failed bounced].freeze

  belongs_to :conversation, counter_cache: true
  belongs_to :agent, optional: true
  has_many_attached :files

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  after_create_commit :bump_conversation, :index_for_search
  after_destroy_commit :deindex_for_search

  def note? = kind == "note"

  private

  def bump_conversation
    conversation.update_columns(
      last_message_at: created_at,
      preview: body_text.to_s.gsub(/\s+/, " ").strip.truncate(140),
      updated_at: Time.current
    )
  end

  def index_for_search
    sql = ActiveRecord::Base.sanitize_sql(
      [ "INSERT INTO message_search(subject, body, conversation_id, message_id) VALUES (?, ?, ?, ?)",
        conversation.subject, body_text.to_s, conversation_id, id ]
    )
    self.class.connection.execute(sql)
  end

  def deindex_for_search
    sql = ActiveRecord::Base.sanitize_sql([ "DELETE FROM message_search WHERE message_id = ?", id ])
    self.class.connection.execute(sql)
  end
end
