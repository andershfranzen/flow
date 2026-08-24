class MailboxAccess < ApplicationRecord
  belongs_to :agent
  belongs_to :mailbox
end
