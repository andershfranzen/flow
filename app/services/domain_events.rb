# The extension seam. Every domain event flows through here:
# webhooks get it (G3), and in-process plugins can subscribe (docs/EXTENDING.md).
class DomainEvents
  EVENTS = %w[thread.created message.inbound message.outbound thread.assigned thread.status].freeze

  @subscribers = Hash.new { |h, k| h[k] = [] }

  class << self
    # Plugins: DomainEvents.subscribe("message.inbound") { |payload| ... }
    # "*" subscribes to everything (payload gets :event merged in).
    def subscribe(event = "*", &block)
      @subscribers[event] << block
    end

    def emit(event, payload)
      Webhook.emit(event, payload)
      (@subscribers[event] + @subscribers["*"]).each do |sub|
        sub.call(payload.merge(event: event))
      rescue StandardError => e
        Rails.logger.error("plugin subscriber for #{event} raised: #{e.class} #{e.message}")
      end
    end

    def reset! = @subscribers.clear # tests
  end
end
