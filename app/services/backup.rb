# Safe SQLite backups via VACUUM INTO (consistent even under writes), plus a
# tarball of Active Storage files. PostgreSQL installs use pg_dump for the
# database — see docs/OPERATIONS.md — but the files tarball still applies.
#
#   bin/rails flow:backup            # writes storage/backups/<stamp>/
#   bin/rails flow:restore[stamp]    # STOP THE APP FIRST, then restore
require "rubygems/package"
require "tmpdir"
require "zlib"

class Backup
  KEEP = 7
  STAMP_PATTERN = /\A\d{8}-\d{6}\z/
  ARCHIVE_TYPES = [ "0", "\0", "1", "2", "5", "x", "g", "L", "K" ].freeze

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
    unless File.directory?(stamp_dir) && !File.symlink?(stamp_dir)
      raise ArgumentError, "no such backup: #{stamp_dir}"
    end
    stamp_dir = File.realpath(stamp_dir.to_s)

    databases = Dir[File.join(stamp_dir, "*.sqlite3*")]
    databases.each do |file|
      raise ArgumentError, "invalid backup database: #{file}" unless File.file?(file) && !File.symlink?(file)
    end
    tarball = File.join(stamp_dir, "files.tgz")
    if File.exist?(tarball) || File.symlink?(tarball)
      raise ArgumentError, "invalid backup archive: #{tarball}" unless File.file?(tarball) && !File.symlink?(tarball)
      validate_archive!(tarball)
    end

    destination = File.expand_path(into.to_s)
    raise ArgumentError, "restore destination must not be a symlink" if File.symlink?(destination)
    staging = Dir.mktmpdir("flow-restore-", File.dirname(destination))
    database_staging = File.join(staging, "databases")
    files_staging = File.join(staging, "files")
    FileUtils.mkdir_p([ database_staging, files_staging ])

    databases.each { |file| FileUtils.cp(file, database_staging) }
    if File.file?(tarball)
      system("tar", "-xzf", tarball, "-C", files_staging, exception: true)
    end

    FileUtils.mkdir_p(destination)
    merge_tree(database_staging, destination)
    merge_tree(files_staging, destination) if File.file?(tarball)
    into
  ensure
    FileUtils.rm_rf(staging) if staging && File.exist?(staging)
  end

  def self.backup_dir(stamp, root: Rails.root.join("storage", "backups"))
    stamp = stamp.to_s
    raise ArgumentError, "invalid backup stamp" unless stamp.match?(STAMP_PATTERN)

    root = File.realpath(root.to_s)
    chosen = File.realpath(File.join(root, stamp))
    unless chosen.start_with?("#{root}#{File::SEPARATOR}")
      raise ArgumentError, "backup is outside storage/backups"
    end
    raise ArgumentError, "no such backup: #{stamp}" unless File.directory?(chosen)
    chosen
  rescue Errno::ENOENT, Errno::ENOTDIR, Errno::EACCES
    raise ArgumentError, "no such backup: #{stamp}"
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

  def self.validate_archive!(tarball)
    entries = {}
    hardlinks = []
    global_attributes = {}
    pending_attributes = {}
    pending_name = pending_link = nil

    File.open(tarball, "rb") do |file|
      Zlib::GzipReader.wrap(file) do |gzip|
        Gem::Package::TarReader.new(gzip).each do |entry|
          type = entry.header.typeflag
          raise ArgumentError, "unsupported backup archive entry type: #{type.inspect}" unless ARCHIVE_TYPES.include?(type)

          if type == "g" || type == "x"
            attributes = parse_pax_attributes(entry.read)
            global_attributes.merge!(attributes) if type == "g"
            pending_attributes.merge!(attributes) if type == "x"
            next
          end

          if type == "L" || type == "K"
            value = entry.read.to_s.split("\0", 2).first
            raise ArgumentError, "invalid backup archive link metadata" if value.empty?

            type == "L" ? pending_name = value : pending_link = value
            next
          end

          attributes = global_attributes.merge(pending_attributes)
          name = safe_archive_path(attributes["path"] || pending_name || entry.full_name)
          link = attributes["linkpath"] || pending_link || entry.header.linkname
          entries[name] = type
          if type == "2"
            validate_link_target!(name, link, symlink: true)
          elsif type == "1"
            target = safe_archive_path(link)
            validate_link_target!(name, target, symlink: false)
            hardlinks << [ name, target ]
          end
          pending_attributes = {}
          pending_name = pending_link = nil
        end
      end
    end

    raise ArgumentError, "empty backup archive" if entries.empty?
    hardlinks.each do |_name, target|
      unless entries[target] == "0" || entries[target] == "\0"
        raise ArgumentError, "unsafe backup hardlink target: #{target}"
      end
    end
  rescue ArgumentError
    raise
  rescue StandardError => e
    raise ArgumentError, "invalid backup archive: #{e.message}"
  end

  def self.parse_pax_attributes(data)
    attributes = {}
    offset = 0
    while offset < data.bytesize
      match = data.byteslice(offset..).match(/\A(\d+) /)
      raise ArgumentError, "invalid backup archive metadata" unless match

      length = match[1].to_i
      record = data.byteslice(offset, length)
      raise ArgumentError, "invalid backup archive metadata" unless record && record.bytesize == length && record.end_with?("\n")

      key, value = record.byteslice(match[0].bytesize, length).chomp.split("=", 2)
      raise ArgumentError, "invalid backup archive metadata" unless key && value

      attributes[key] = value
      offset += length
    end
    attributes
  end

  def self.safe_archive_path(path)
    path = path.to_s
    raise ArgumentError, "unsafe backup archive path: #{path.inspect}" if path.empty? || path.include?("\0")
    raise ArgumentError, "unsafe backup archive path: #{path.inspect}" unless path.valid_encoding?
    if path.start_with?("/", "\\") || path.match?(/\A[A-Za-z]:[\\\/]/)
      raise ArgumentError, "unsafe backup archive path: #{path.inspect}"
    end

    parts = path.split(/[\\\/]/, -1)
    raise ArgumentError, "unsafe backup archive path: #{path.inspect}" if parts.include?("..")

    normalized = parts.reject { |part| part.empty? || part == "." }.join("/")
    raise ArgumentError, "unsafe backup archive path: #{path.inspect}" if normalized.empty?

    normalized
  end

  def self.validate_link_target!(name, target, symlink:)
    target = target.to_s
    raise ArgumentError, "unsafe backup link target: #{target.inspect}" if target.empty? || target.include?("\0")
    raise ArgumentError, "unsafe backup link target: #{target.inspect}" unless target.valid_encoding?

    target = target.tr("\\", "/")
    if target.start_with?("/") || target.match?(/\A[A-Za-z]:\//)
      raise ArgumentError, "unsafe backup link target: #{target.inspect}"
    end

    root = "/restore-root"
    base = symlink ? File.dirname(File.join(root, name)) : root
    resolved = File.expand_path(target, base)
    raise ArgumentError, "unsafe backup link target: #{target}" unless resolved == root || resolved.start_with?("#{root}/")
  end

  def self.merge_tree(source, destination)
    Dir.each_child(source) do |name|
      source_path = File.join(source, name)
      destination_path = File.join(destination, name)
      if File.directory?(source_path) && !File.symlink?(source_path)
        if File.symlink?(destination_path) || (File.exist?(destination_path) && !File.directory?(destination_path))
          FileUtils.rm_rf(destination_path)
        end
        FileUtils.mkdir_p(destination_path)
        merge_tree(source_path, destination_path)
      else
        FileUtils.rm_rf(destination_path) if File.exist?(destination_path) || File.symlink?(destination_path)
        FileUtils.mv(source_path, destination_path)
      end
    end
  end
end
