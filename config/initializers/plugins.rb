# In-process plugins: enabled plugins/*/plugin.rb load at boot.
# Managed from Settings -> Plugins; see docs/EXTENDING.md.
Rails.application.config.after_initialize do
  PluginRegistry.load_enabled! if ActiveRecord::Base.connection.table_exists?("plugin_states") rescue nil
end
