class SendMessageJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError # message was undone before the delay elapsed
  # Retry with backoff, dead-letter after 5 (A16). Failure leaves status visible.
  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, _error|
    job.arguments.first&.update_columns(status: "failed")
  end

  def perform(message)
    return unless message.status == "queued"
    OutboundSender.call(message)
  end
end
