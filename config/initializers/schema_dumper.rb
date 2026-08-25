# The FTS5 virtual table is runtime-managed by SearchIndex, never dumped.
ActiveSupport.on_load(:active_record) do
  ActiveRecord::SchemaDumper.ignore_tables |= [ "message_search" ]
end
