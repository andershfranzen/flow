# In-process plugins: any plugins/*/plugin.rb is loaded at boot.
# A plugin is ordinary Ruby — it can subscribe to DomainEvents, register MCP
# tools via McpTools.register, and use every model and service in the app.
Rails.application.config.after_initialize do
  Dir[Rails.root.join("plugins/*/plugin.rb")].sort.each do |file|
    require file
  rescue StandardError => e
    Rails.logger.error("plugin #{file} failed to load: #{e.class} #{e.message}")
  end
end
