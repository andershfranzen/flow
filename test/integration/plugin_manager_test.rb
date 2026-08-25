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

  def make_zip(entries)
    buffer = Zip::OutputStream.write_buffer do |out|
      entries.each { |name, content| out.put_next_entry(name); out.write(content) }
    end
    file = Tempfile.new([ "plugin", ".zip" ])
    file.binmode
    file.write(buffer.string)
    file.rewind
    file
  end

  def upload(zipfile, filename: "my_zip_plugin.zip")
    post "/api/plugins/install_zip",
         params: { file: Rack::Test::UploadedFile.new(zipfile.path, "application/zip",
                                                      original_filename: filename) }
  end

  test "zip install: wrapped folder, flat zip, replace, and rejects" do
    # WordPress-style: one top-level folder becomes the plugin name
    upload(make_zip("zippy/plugin.rb" => "ZIPPY_LOADED = 1",
                    "zippy/plugin.json" => { version: "2.0" }.to_json))
    assert_response :created
    names = response.parsed_body["plugins"].map { |p| p["name"] }
    assert_includes names, "zippy"
    assert File.exist?(@tmp.join("zippy", "plugin.rb"))

    # flat zip installs under the zip's own name
    upload(make_zip("plugin.rb" => "FLAT_OK = 1"))
    assert_response :created
    assert File.exist?(@tmp.join("my_zip_plugin", "plugin.rb"))

    # re-upload replaces the previous zip install (old files gone)
    File.write(@tmp.join("zippy", "stale.txt"), "old")
    upload(make_zip("zippy/plugin.rb" => "ZIPPY_V2 = 1"))
    assert_response :created
    refute File.exist?(@tmp.join("zippy", "stale.txt")), "replace wipes old files"

    # no plugin.rb → rejected
    upload(make_zip("zippy2/readme.md" => "hi"))
    assert_response :unprocessable_entity
    assert_equal "not_a_plugin", response.parsed_body["error"]
  end

  test "zip install blocks zip-slip and git collisions" do
    upload(make_zip("evil/plugin.rb" => "ok", "evil/../../escape.rb" => "pwn"))
    assert_response :unprocessable_entity
    refute File.exist?(@tmp.parent.join("escape.rb")), "zip-slip must not write outside plugins/"
    refute File.exist?(@tmp.join("escape.rb"))

    write_plugin("gitty", "GITTY = 1")
    FileUtils.mkdir_p(@tmp.join("gitty", ".git"))
    upload(make_zip("gitty/plugin.rb" => "GITTY2 = 1"))
    assert_response :unprocessable_entity
    assert_equal "installed_from_git", response.parsed_body["error"]
  end

  test "declared plugin settings save, filter, and mask secrets" do
    write_plugin("cfg", "CFG = 1", manifest: {
      "version" => "1.0", "description" => "cfg",
      "settings" => [ { "key" => "url", "label" => "URL" },
                      { "key" => "api_key", "label" => "Key", "type" => "password" } ] })

    patch "/api/plugins/cfg", params: { settings: { url: "https://dgw.example", api_key: "s3cret", junk: "no" } }
    assert_response :success
    plugin = response.parsed_body["plugins"].find { |p| p["name"] == "cfg" }
    assert_equal "https://dgw.example", plugin.dig("settings", "url")
    assert plugin.dig("settings", "api_key_set")
    assert_nil plugin.dig("settings", "api_key"), "secret never echoed"
    assert_nil plugin.dig("settings", "junk"), "undeclared keys dropped"
    assert_equal({ "url" => "https://dgw.example", "api_key" => "s3cret" }, PluginState.settings_for("cfg"))

    # blank password keeps the stored secret; text fields update
    patch "/api/plugins/cfg", params: { settings: { url: "https://new.example", api_key: "" } }
    assert_equal "s3cret", PluginState.settings_for("cfg")["api_key"]
    assert_equal "https://new.example", PluginState.settings_for("cfg")["url"]

    # stored encrypted at rest
    raw = PluginState.connection.select_value("SELECT settings FROM plugin_states WHERE name = 'cfg'")
    refute_includes raw.to_s, "s3cret"
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
