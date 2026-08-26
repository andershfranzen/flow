require "test_helper"

class WebhookDeliveryJobTest < ActiveSupport::TestCase
  class FakeHttp
    attr_accessor :proxy_from_env, :ipaddr, :use_ssl, :open_timeout, :read_timeout
    attr_reader :address, :port, :proxy_address, :request

    def initialize(address, port, proxy_address)
      @address = address
      @port = port
      @proxy_address = proxy_address
    end

    def start
      yield self
    end

    def post(*args)
      @request = args
      Struct.new(:code).new("204")
    end
  end

  test "resolves once, pins the approved address, and bypasses environment proxies" do
    calls = 0
    socket = class << Socket; self; end
    socket.alias_method :webhook_test_original_getaddrinfo, :getaddrinfo
    socket.define_method(:getaddrinfo) do |*|
      calls += 1
      raise "unexpected second DNS lookup" if calls > 1

      [ [ "AF_INET", 0, "rebind.test", "93.184.216.34", Socket::AF_INET,
          Socket::SOCK_STREAM, Socket::IPPROTO_TCP ] ]
    end

    http = nil
    net_http = Net::HTTP.singleton_class
    net_http.alias_method :webhook_test_original_new, :new
    net_http.define_method(:new) do |address, port, proxy_address|
      http = FakeHttp.new(address, port, proxy_address)
    end
    WebhookDeliveryJob.perform_now(Webhook.new(url: "https://rebind.test/hooks", secret: "secret"),
                                    "thread.created", { id: 1 })

    assert_equal 1, calls
    assert_equal "rebind.test", http.address, "the hostname must remain available for Host and TLS SNI"
    assert_equal 443, http.port
    assert_nil http.proxy_address, "Net::HTTP must not inherit an environment proxy"
    assert_equal false, http.proxy_from_env
    assert_equal "93.184.216.34", http.ipaddr
    assert_equal true, http.use_ssl
  ensure
    socket.alias_method :getaddrinfo, :webhook_test_original_getaddrinfo
    socket.remove_method :webhook_test_original_getaddrinfo
    net_http.alias_method :new, :webhook_test_original_new
    net_http.remove_method :webhook_test_original_new
  end

  test "rejects special-use and non-public IPv4 and IPv6 addresses" do
    addresses = %w[
      0.0.0.0 10.0.0.1 100.64.0.1 127.0.0.1 169.254.1.1 172.16.0.1
      192.0.2.1 192.168.0.1 198.18.0.1 224.0.0.1 255.255.255.255
      ::1 ::ffff:8.8.8.8 2001:db8::1 fc00::1 fe80::1 ff02::1
    ]

    addresses.each do |address|
      with_dns_result(address) do
        error = assert_raises(RuntimeError) do
          WebhookDeliveryJob.new.send(:guard_ssrf!, URI("https://special.test/hooks"))
        end
        assert_includes error.message, "non-public address", address
      end
    end
  end

  test "FLOW_ALLOW_PRIVATE_WEBHOOKS preserves the opt-in for private targets" do
    previous = ENV["FLOW_ALLOW_PRIVATE_WEBHOOKS"]
    ENV["FLOW_ALLOW_PRIVATE_WEBHOOKS"] = "1"
    with_dns_result("10.0.0.1") do
      assert_equal "10.0.0.1",
                   WebhookDeliveryJob.new.send(:guard_ssrf!, URI("https://internal.test/hooks"))
    end
  ensure
    ENV["FLOW_ALLOW_PRIVATE_WEBHOOKS"] = previous
  end

  test "FLOW_ALLOW_PRIVATE_WEBHOOKS only accepts the documented explicit value" do
    previous = ENV["FLOW_ALLOW_PRIVATE_WEBHOOKS"]
    ENV["FLOW_ALLOW_PRIVATE_WEBHOOKS"] = "0"
    with_dns_result("10.0.0.1") do
      assert_raises(RuntimeError) do
        WebhookDeliveryJob.new.send(:guard_ssrf!, URI("https://internal.test/hooks"))
      end
    end
  ensure
    ENV["FLOW_ALLOW_PRIVATE_WEBHOOKS"] = previous
  end

  private

  def with_dns_result(address)
    family = IPAddr.new(address).ipv6? ? Socket::AF_INET6 : Socket::AF_INET
    socket = class << Socket; self; end
    socket.alias_method :webhook_test_original_getaddrinfo, :getaddrinfo
    socket.define_method(:getaddrinfo) do |*|
      [ [ "AF_#{family == Socket::AF_INET6 ? "INET6" : "INET"}", 0, "special.test", address,
          family, Socket::SOCK_STREAM, Socket::IPPROTO_TCP ] ]
    end
    yield
  ensure
    socket.alias_method :getaddrinfo, :webhook_test_original_getaddrinfo
    socket.remove_method :webhook_test_original_getaddrinfo
  end
end
