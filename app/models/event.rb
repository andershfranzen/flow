class Event < ApplicationRecord
  belongs_to :conversation
  belongs_to :agent, optional: true
end
