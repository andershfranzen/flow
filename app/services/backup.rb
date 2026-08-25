# Safe SQLite backups via VACUUM INTO (consistent even under writes), plus a
# tarball of Active Storage files. PostgreSQL installs use pg_dump for the
# database — see docs/OPERATIONS.md — but the files tarball still applies.
#
#   bin/rails flow:backup            # writes storage/backups/<stamp>/
#   bin/rails flow:restore[stamp]    # STOP THE APP FIRST, then restore
class Backup
  KEEP = 7

  def self.run(dir = Rails.root.join("storage", "backups"))
    raise "SQLite only — use pg_dump for PostgreSQL" if SearchIndex.postgres?
    stamp_dir = File.join(dir, Time.now.strftime("%Y%m%d-%H%M%S"))
    FileUtils.mkdir_p(stamp_dir)
    database_paths.each do |path|
      target = File.join(stamp_dir, File.basename(path))
      SQLite3::Database.new(path.to_s, readonly: true) do |db|
        db.execute("VACUUM INTO ?", target)
      end
    end
    archive_files(stamp_dir)
    prune(dir)
    stamp_dir
  end

  # Restore a backup into the live storage directory. The app (web + jobs)
  # must be stopped; SQLite files are replaced wholesale.
  def self.restore(stamp_dir, into: Rails.root.join("storage"))
    raise ArgumentError, "no such backup: #{stamp_dir}" unless File.directory?(stamp_dir)
    Dir[File.join(stamp_dir, "*.sqlite3*")].each do |file|
      FileUtils.cp(file, File.join(into, File.basename(file)))
    end
    tarball = File.join(stamp_dir, "files.tgz")
    if File.exist?(tarball)
      system("tar", "-xzf", tarball, "-C", into.to_s, exception: true)
    end
    into
  end

  def self.database_paths
    configured = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)
                                   .filter_map { |c| c.database if c.adapter == "sqlite3" }
    # Live pools too: parallel tests (and any runtime override) suffix the file.
    connected = ActiveRecord::Base.connection_handler.connection_pool_list(:all)
                                  .filter_map { |p| p.db_config.database if p.db_config.adapter == "sqlite3" }
    (configured + connected).map { |d| Rails.root.join(d) }.uniq.select { |p| File.exist?(p) }
  end

  def self.prune(dir)
    Dir[File.join(dir, "*")].sort.reverse.drop(KEEP).each { |old| FileUtils.rm_rf(old) }
  end

  # Active Storage shards blobs into two-character directories under the Disk
  # service root (storage/ in production).
  def self.files_root
    service = ActiveStorage::Blob.service
    service.respond_to?(:root) ? service.root.to_s : nil
  end

  def self.archive_files(stamp_dir, root = files_root)
    return unless root
    shards = Dir[File.join(root, "??")].select { |d| File.directory?(d) }.map { |d| File.basename(d) }
    return if shards.empty?
    system("tar", "-czf", File.join(stamp_dir, "files.tgz"), "-C", root, *shards, exception: true)
  end
end
