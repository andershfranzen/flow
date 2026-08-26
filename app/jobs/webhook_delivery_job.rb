require "ipaddr"
require "net/http"
require "socket"

# POST JSON with HMAC signature, retry with backoff (G3).
class WebhookDeliveryJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  # IANA special-purpose ranges plus non-routable IPv4 space. A hostname is
  # rejected when any address in its single DNS answer falls in one of these
  # ranges; this prevents split DNS from selecting an unsafe sibling address.
  SPECIAL_USE_NETWORKS = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
    172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.31.196.0/24
    192.52.193.0/24 192.88.99.0/24 192.168.0.0/16 192.175.48.0/24
    198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4
    240.0.0.0/4
    ::/128 ::1/128 64:ff9b::/96 64:ff9b:1::/48 100::/64 100:0:0:1::/64
    2001::/23 2001:4:112::/48 2001:db8::/32 2002::/16 2620:4f:8000::/48
    3fff::/20 5f00::/16 fc00::/7 fe80::/10 ff00::/8
  ].map { |network| IPAddr.new(network) }.freeze
  PUBLIC_IPV6 = IPAddr.new("2000::/3").freeze

  def perform(webhook, event, payload)
    body = { event: event, data: payload, sent_at: Time.current.iso8601 }.to_json
    uri = URI(webhook.url)
    ipaddr = guard_ssrf!(uri)
    signature = OpenSSL::HMAC.hexdigest("SHA256", webhook.secret, body)
    http = Net::HTTP.new(uri.hostname, uri.port, nil)
    http.proxy_from_env = false
    http.ipaddr = ipaddr
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10
    response = http.start do |session|
      session.post(uri.request_uri, body,
        "Content-Type" => "application/json",
        "X-Inbox-Event" => event,
        "X-Inbox-Signature" => "sha256=#{signature}")
    end
    raise "webhook #{webhook.id} got #{response.code}" unless response.code.to_i.between?(200, 299)
  end

  private

  # Admin-entered URLs must not reach internal or special-purpose networks.
  # Set FLOW_ALLOW_PRIVATE_WEBHOOKS=1 for intentionally internal targets.
  def guard_ssrf!(uri)
    addresses = Socket.getaddrinfo(uri.hostname, nil, Socket::AF_UNSPEC, Socket::SOCK_STREAM)
                   .map { |entry| IPAddr.new(entry[3]) }.uniq
    raise SocketError, "no addresses returned" if addresses.empty?

    unless ENV["FLOW_ALLOW_PRIVATE_WEBHOOKS"] == "1"
      address = addresses.find { |candidate| non_public_address?(candidate) }
      if address
        raise "webhook target #{uri.hostname} resolves to a non-public address (set FLOW_ALLOW_PRIVATE_WEBHOOKS=1 to allow)"
      end
    end
    addresses.first.to_s
  rescue SocketError, IPAddr::InvalidAddressError => e
    raise "could not resolve webhook target #{uri.hostname}: #{e.message}"
  end

  def non_public_address?(address)
    return true if address.ipv4_mapped? || address.native.family != address.family
    return true if address.private? || address.loopback? || address.link_local?
    return true if address.ipv6? && !PUBLIC_IPV6.include?(address)

    SPECIAL_USE_NETWORKS.any? { |network| network.include?(address) }
  end
end
