class Notification < ApplicationRecord
  belongs_to :agent
  belongs_to :conversation
  scope :unread, -> { where(read_at: nil) }
end
