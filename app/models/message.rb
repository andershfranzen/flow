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
    message_time = sent_at || created_at
    return if conversation.last_message_at && conversation.last_message_at > message_time

    conversation.update_columns(
      last_message_at: message_time,
      preview: body_text.to_s.gsub(/\s+/, " ").strip.truncate(140),
      updated_at: Time.current
    )
  end

  def index_for_search = SearchIndex.index_message(self)
  def deindex_for_search = SearchIndex.deindex_message(id)
end
