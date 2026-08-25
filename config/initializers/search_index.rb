# Ensure the adapter-appropriate search index exists (no-op when already there).
Rails.application.config.after_initialize do
  SearchIndex.ensure! if ActiveRecord::Base.connection.table_exists?("messages")
rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
  # first boot before db:prepare — the lazy path covers it
end
