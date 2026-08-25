# Example: ship unhandled errors to any webhook (Slack, ntfy, your own).
if (url = ENV["ERROR_WEBHOOK_URL"]).present?
  Rails.error.subscribe(->(error, handled:, severity:, context:, source: nil) {
    Thread.new do
      require "net/http"
      Net::HTTP.post(URI(url),
        { error: error.class.name, message: error.message.to_s.truncate(500),
          severity: severity, handled: handled, source: source }.to_json,
        "Content-Type" => "application/json")
    rescue StandardError
      nil # never let error reporting raise
    end
  })
end
