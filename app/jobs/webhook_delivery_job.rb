require "net/http"

# POST JSON with HMAC signature, retry with backoff (G3).
class WebhookDeliveryJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(webhook, event, payload)
    body = { event: event, data: payload, sent_at: Time.current.iso8601 }.to_json
    uri = URI(webhook.url)
    signature = OpenSSL::HMAC.hexdigest("SHA256", webhook.secret, body)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: 5, read_timeout: 10) do |http|
      http.post(uri.request_uri, body,
        "Content-Type" => "application/json",
        "X-Inbox-Event" => event,
        "X-Inbox-Signature" => "sha256=#{signature}")
    end
    raise "webhook #{webhook.id} got #{response.code}" unless response.code.to_i.between?(200, 299)
  end
end
