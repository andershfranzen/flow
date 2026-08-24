class Follower < ApplicationRecord
  belongs_to :agent
  belongs_to :conversation
end
