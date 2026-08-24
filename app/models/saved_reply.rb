class SavedReply < ApplicationRecord
  belongs_to :mailbox, optional: true # nil = global
  validates :name, presence: true
  validates :body, presence: true

  # {{customer.name}}, {{agent.name}}, {{mailbox.name}} (B9)
  def render(customer: nil, agent: nil, mailbox: nil)
    vars = {
      "customer.name" => customer&.display_name, "customer.email" => customer&.email,
      "agent.name" => agent&.name, "mailbox.name" => mailbox&.name
    }
    body.gsub(/\{\{\s*([\w.]+)\s*\}\}/) { vars[Regexp.last_match(1)].to_s }
  end
end
