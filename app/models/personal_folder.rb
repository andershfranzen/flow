# A private organizational layer (like labels): visible and editable only by
# its owner; membership never affects shared state.
class PersonalFolder < ApplicationRecord
  belongs_to :agent
  has_many :personal_folder_items, dependent: :delete_all
  has_many :conversations, through: :personal_folder_items

  validates :name, presence: true, length: { maximum: 40 },
                   uniqueness: { scope: :agent_id, case_sensitive: false }
end
