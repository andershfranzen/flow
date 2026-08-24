class Draft < ApplicationRecord
  belongs_to :agent
  belongs_to :conversation, optional: true
  belongs_to :mailbox, optional: true
end
