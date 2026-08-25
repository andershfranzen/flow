# Safe SQLite backups via VACUUM INTO (consistent even under writes).
# PostgreSQL installs use pg_dump — see docs/OPERATIONS.md.
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
    prune(dir)
    stamp_dir
  end

  def self.database_paths
    ActiveRecord::Base.configurations.configs_for(env_name: Rails.env)
                      .filter_map { |c| c.database if c.adapter == "sqlite3" }
                      .map { |d| Rails.root.join(d) }.uniq.select { |p| File.exist?(p) }
  end

  def self.prune(dir)
    Dir[File.join(dir, "*")].sort.reverse.drop(KEEP).each { |old| FileUtils.rm_rf(old) }
  end
end
