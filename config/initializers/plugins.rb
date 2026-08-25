# In-process plugins: enabled plugins/*/plugin.rb load at boot.
# Managed from Settings -> Plugins; see docs/EXTENDING.md.
# Tests exercise plugins explicitly against a stubbed root, never implicitly.
unless Rails.env.test?
  Rails.application.config.after_initialize do
    PluginRegistry.load_enabled! if ActiveRecord::Base.connection.table_exists?("plugin_states") rescue nil
  end
end
