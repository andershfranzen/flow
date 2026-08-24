class Conversation < ApplicationRecord
  STATUSES = %w[active pending closed spam trash].freeze

  belongs_to :mailbox
  belongs_to :customer
  belongs_to :assignee, class_name: "Agent", optional: true
  has_many :messages, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :conversation_tags, dependent: :destroy
  has_many :tags, through: :conversation_tags
  has_many :notifications, dependent: :destroy
  has_many :drafts, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  before_create :assign_number

  scope :in_folder, ->(folder, agent) {
    case folder
    when "unassigned" then where(status: %w[active pending], assignee_id: nil)
    when "mine"       then where(status: %w[active pending], assignee_id: agent.id)
    when "assigned"   then where(status: %w[active pending]).where.not(assignee_id: nil)
    when "starred"    then where(starred: true).where.not(status: %w[spam trash])
    when "closed"     then where(status: "closed")
    when "spam"       then where(status: "spam")
    when "trash"      then where(status: "trash")
    else                   where(status: %w[active pending])
    end
  }

  def set_status!(status, agent: nil)
    return if self.status == status
    update!(status: status)
    events.create!(agent: agent, kind: "status_changed", data: { status: status })
  end

  def assign!(to, agent: nil)
    update!(assignee: to)
    events.create!(agent: agent, kind: to ? "assigned" : "unassigned",
                   data: { assignee_id: to&.id, assignee_name: to&.name })
  end

  private

  def assign_number
    # ponytail: max+1 relies on SQLite's single writer + unique index; a sequence table if this ever races
    self.number ||= (self.class.maximum(:number) || 0) + 1
  end
end
