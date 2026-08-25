class Star < ApplicationRecord
  belongs_to :agent
  belongs_to :conversation
end
