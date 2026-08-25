class Team < ApplicationRecord
  has_many :team_members, dependent: :destroy
  has_many :agents, through: :team_members
  validates :name, presence: true, uniqueness: true

  # Round-robin over members with access to the mailbox (C8).
  def next_agent(mailbox)
    members = agents.order(:id).to_a.select { |a| a.can_access?(mailbox) }
    return nil if members.empty?
    agent = members[rr_index % members.size]
    update_columns(rr_index: rr_index + 1)
    agent
  end
end
