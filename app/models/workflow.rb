# An automation rule: trigger event → conditions → ordered actions.
# Built in the visual editor (Settings → Workflows); executed by WorkflowEngine.
class Workflow < ApplicationRecord
  TRIGGERS = %w[message.inbound thread.created message.outbound thread.assigned thread.status].freeze
  MATCH_TYPES = %w[all any].freeze
  CONDITION_FIELDS = %w[subject body from_email from_domain to_cc customer_email
                        status assignee_email has_attachment tag].freeze
  OPERATORS = %w[contains not_contains equals not_equals starts_with ends_with matches_regex].freeze
  ACTION_TYPES = %w[assign assign_team unassign add_tag remove_tag set_status star move_mailbox
                    add_note send_reply forward_to].freeze

  belongs_to :mailbox, optional: true

  validates :name, presence: true
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :match_type, inclusion: { in: MATCH_TYPES }
  validate :validate_steps

  before_create { self.position = (self.class.maximum(:position) || 0) + 1 }

  scope :runnable_for, ->(event, mailbox_id) {
    where(enabled: true, trigger: event, mailbox_id: [ nil, mailbox_id ]).order(:position, :id)
  }

  def matches?(conversation, message)
    return true if conditions.blank?
    results = conditions.map { |c| condition_met?(c, conversation, message) }
    match_type == "any" ? results.any? : results.all?
  end

  private

  def condition_met?(condition, conversation, message)
    value = field_value(condition["field"], conversation, message).to_s
    expected = condition["value"].to_s
    case condition["operator"]
    when "contains"      then value.downcase.include?(expected.downcase)
    when "not_contains"  then !value.downcase.include?(expected.downcase)
    when "equals"        then value.casecmp?(expected)
    when "not_equals"    then !value.casecmp?(expected)
    when "starts_with"   then value.downcase.start_with?(expected.downcase)
    when "ends_with"     then value.downcase.end_with?(expected.downcase)
    when "matches_regex" then safe_regex_match?(value, expected)
    else false
    end
  end

  def field_value(field, conversation, message)
    case field
    when "subject"        then conversation.subject
    when "body"           then message&.body_text
    when "from_email"     then message&.from_email.presence || conversation.customer.email
    when "from_domain"    then (message&.from_email.presence || conversation.customer.email).to_s.split("@").last
    when "to_cc"          then (Array(message&.to) + Array(message&.cc)).join(" ")
    when "customer_email" then conversation.customer.email
    when "status"         then conversation.status
    when "assignee_email" then conversation.assignee&.email
    when "has_attachment" then (message&.files&.attached? ? "yes" : "no")
    when "tag"            then conversation.tags.pluck(:name).join(" ")
    end
  end

  def safe_regex_match?(value, pattern)
    Regexp.new(pattern, Regexp::IGNORECASE, timeout: 1.0).match?(value)
  rescue RegexpError, Regexp::TimeoutError
    false
  end

  def validate_steps
    unless conditions.is_a?(Array) && conditions.all? { |c|
      c.is_a?(Hash) && CONDITION_FIELDS.include?(c["field"]) && OPERATORS.include?(c["operator"])
    }
      errors.add(:conditions, "contain an unknown field or operator")
    end
    unless actions.is_a?(Array) && actions.present? && actions.all? { |a|
      a.is_a?(Hash) && ACTION_TYPES.include?(a["type"])
    }
      errors.add(:actions, "must contain at least one valid action")
    end
  end
end
