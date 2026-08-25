require "test_helper"

class PluginManagerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = Agent.create!(email: "a@example.com", name: "Ada", password: "secret123", role: "admin")
    @tmp = Pathname.new(Dir.mktmpdir("flow-plugins"))
    PluginRegistry.singleton_class.alias_method :orig_root, :root
    tmp = @tmp
    PluginRegistry.define_singleton_method(:root) { tmp }
    PluginRegistry.reset!
    write_plugin("hello_notes", <<~RUBY)
      DomainEvents.subscribe("thread.created") { |p| HELLO_SEEN << p[:id] }
    RUBY
    Object.const_set(:HELLO_SEEN, []) unless defined?(HELLO_SEEN)
    HELLO_SEEN.clear
    post "/api/session", params: { email: "a@example.com", password: "secret123" }
  end

  teardown do
    PluginRegistry.singleton_class.alias_method :root, :orig_root
    PluginRegistry.singleton_class.remove_method :orig_root
    PluginRegistry.reset!
    DomainEvents.reset!
    FileUtils.rm_rf(@tmp)
  end

  def write_plugin(name, code, manifest: { "version" => "1.0", "description" => "Test plugin" })
    dir = @tmp.join(name)
    FileUtils.mkdir_p(dir)
    File.write(dir.join("plugin.rb"), code)
    File.write(dir.join("plugin.json"), manifest.to_json)
  end

  test "discovery lists plugins with manifest data" do
    get "/api/plugins"
    plugin = response.parsed_body["plugins"].first
    assert_equal "hello_notes", plugin["name"]
    assert_equal "1.0", plugin["version"]
    assert plugin["enabled"]
    refute plugin["loaded"]
  end

  test "enable loads the plugin and disable silences its hooks instantly" do
    PluginRegistry.load_plugin("hello_notes")
    DomainEvents.emit("thread.created", { id: 42 })
    assert_equal [ 42 ], HELLO_SEEN

    patch "/api/plugins/hello_notes", params: { enabled: false }
    assert_response :success
    DomainEvents.emit("thread.created", { id: 43 })
    assert_equal [ 42 ], HELLO_SEEN, "disabled plugin must not receive events"

    patch "/api/plugins/hello_notes", params: { enabled: true }
    DomainEvents.emit("thread.created", { id: 44 })
    assert_equal [ 42, 44 ], HELLO_SEEN
  end

  test "a broken plugin reports its error instead of crashing" do
    write_plugin("broken", "raise 'kaputt'")
    refute PluginRegistry.load_plugin("broken")
    get "/api/plugins"
    broken = response.parsed_body["plugins"].find { |p| p["name"] == "broken" }
    assert_includes broken["error"], "kaputt"
  end

  test "install rejects non-https urls and duplicate names without touching the network" do
    post "/api/plugins/install", params: { git_url: "file:///etc" }
    assert_response :unprocessable_entity
    post "/api/plugins/install", params: { git_url: "https://example.com/x/hello_notes.git" }
    assert_response :unprocessable_entity
    assert_equal "already_installed", response.parsed_body["error"]
  end

  test "uninstall removes the plugin directory" do
    delete "/api/plugins/hello_notes"
    assert_response :success
    refute File.exist?(@tmp.join("hello_notes"))

    delete "/api/plugins/does-not-exist"
    assert_response :not_found
  end

  test "non-admin cannot manage plugins" do
    Agent.create!(email: "u@example.com", name: "U", password: "secret123", role: "user")
    post "/api/session", params: { email: "u@example.com", password: "secret123" }
    get "/api/plugins"
    assert_response :forbidden
  end
end
