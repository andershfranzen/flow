namespace :flow do
  # Solid Queue's tables are not in schema.rb (SQLite keeps them in a separate
  # queue database), so a fresh PostgreSQL database prepared from the schema
  # lacks them: db:prepare marks the migration as run without executing it.
  desc "Create Solid Queue tables when they share the primary database (PostgreSQL)"
  task ensure_queue_tables: :environment do
    connection = ActiveRecord::Base.connection
    unless connection.adapter_name.match?(/sqlite/i) || connection.table_exists?(:solid_queue_jobs)
      require Rails.root.join("db/migrate/20260825040000_create_solid_queue_tables_for_single_db.rb").to_s
      CreateSolidQueueTablesForSingleDb.migrate(:up)
      puts "Created Solid Queue tables in the primary database"
    end
  end

  desc "Back up SQLite databases and Active Storage files to storage/backups/<stamp>"
  task backup: :environment do
    puts Backup.run
  end

  desc "Restore a backup (flow:restore[20260825-120000]). STOP web + jobs first."
  task :restore, [ :stamp ] => :environment do |_t, args|
    dir = Backup.backup_dir(args.fetch(:stamp))
    Backup.restore(dir)
    puts "Restored #{dir}. Restart the app."
  end
end
