# Runtime-managed tables never belong in db/schema.rb:
# - Solid Queue tables live in the primary database on PostgreSQL (single-DB)
#   but in a separate queue database on SQLite; flow:ensure_queue_tables
#   creates them where needed.
# - message_search is an FTS5 virtual table SearchIndex creates lazily on
#   SQLite (its shadow tables break the dump entirely).
ActiveRecord::SchemaDumper.ignore_tables |= [ /\Asolid_queue_/, /\Amessage_search/ ]
