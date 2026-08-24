class Tag < ApplicationRecord
  has_many :conversation_tags, dependent: :destroy
  has_many :conversations, through: :conversation_tags
  validates :name, presence: true, uniqueness: true
end
