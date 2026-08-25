# Example Flow plugin: tag new conversations by subject keywords.
# Everything in Flow is available here — models, services, jobs.
RULES = {
  /invoice|billing|payment/i => [ "billing", "#b45309" ],
  /urgent|asap|immediately/i => [ "urgent", "#e5484d" ]
}.freeze

DomainEvents.subscribe("thread.created") do |payload|
  conversation = Conversation.find_by(id: payload[:id])
  next unless conversation
  RULES.each do |pattern, (tag_name, color)|
    next unless conversation.subject.match?(pattern)
    tag = Tag.find_or_create_by!(name: tag_name) { |t| t.color = color }
    conversation.tags << tag unless conversation.tags.include?(tag)
  end
end
