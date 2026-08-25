# WordPress-style plugin lifecycle over the plugins/ directory.
#
# A plugin is a directory with a `plugin.rb` entry point and an optional
# `plugin.json` manifest ({name, version, description, author, url,
# settings_path}). Enabled state lives in plugin_states; hooks registered
# through DomainEvents/McpTools are tagged with the owning plugin and skipped
# at runtime when it is disabled, so enable/disable is instant. Ruby cannot
# unload code, so removing a plugin's classes entirely takes a restart.
class PluginRegistry
  Info = Struct.new(:name, :dir, :manifest, :error, :loaded, :enabled, keyword_init: true)

  @loaded = Set.new
  @errors = {}
  @loading = nil
  @mutex = Mutex.new

  class << self
    attr_reader :loading

    def root = Rails.root.join("plugins")

    def discover
      Dir[root.join("*/")].filter_map do |dir|
        name = File.basename(dir)
        next unless File.exist?(File.join(dir, "plugin.rb"))
        manifest = read_manifest(dir)
        Info.new(name: name, dir: dir, manifest: manifest,
                 error: @errors[name], loaded: @loaded.include?(name),
                 enabled: PluginState.enabled?(name))
      end.sort_by(&:name)
    end

    def load_enabled!
      discover.each { |plugin| load_plugin(plugin.name) if plugin.enabled }
    end

    def load_plugin(name)
      @mutex.synchronize do
        return true if @loaded.include?(name)
        entry = root.join(name, "plugin.rb").to_s
        return false unless File.exist?(entry)
        begin
          @loading = name
          load entry
          @loaded << name
          @errors.delete(name)
          true
        rescue StandardError, SyntaxError => e
          @errors[name] = "#{e.class}: #{e.message}".truncate(300)
          Rails.logger.error("plugin #{name} failed to load: #{e.class} #{e.message}")
          false
        ensure
          @loading = nil
        end
      end
    end

    def set_enabled(name, enabled)
      state = PluginState.find_or_initialize_by(name: name)
      state.update!(enabled: enabled)
      load_plugin(name) if enabled
      state
    end

    def enabled?(name)
      name.nil? || !PluginState.disabled_names.include?(name)
    end

    def valid_name?(name)
      name.to_s.match?(/\A[\w][\w.-]{0,80}\z/) && !name.include?("..")
    end

    def reset! # tests
      @loaded.clear
      @errors.clear
    end

    private

    def read_manifest(dir)
      path = File.join(dir, "plugin.json")
      return {} unless File.exist?(path)
      JSON.parse(File.read(path)).slice("name", "version", "description", "author", "url", "settings_path")
    rescue JSON::ParserError => e
      { "error" => "invalid plugin.json: #{e.message}" }
    end
  end
end
