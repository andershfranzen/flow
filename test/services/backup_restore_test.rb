require "test_helper"
require "rubygems/package"
require "zlib"

class BackupRestoreTest < ActiveSupport::TestCase
  # VACUUM INTO reads committed state on disk, so no test transaction here.
  self.use_transactional_tests = false

  teardown do
    Conversation.destroy_all
    Customer.delete_all
    Mailbox.delete_all
    OrgSetting.current.logo.purge if OrgSetting.current.logo.attached?
    OrgSetting.current.update!(site_name: "Flow")
  end

  test "backup captures databases plus files, and restore round-trips them" do
    skip "SQLite-only backup path" if SearchIndex.postgres?
    OrgSetting.current.update!(site_name: "Backup Probe")
    OrgSetting.current.logo.attach(io: StringIO.new("\x89PNGprobe"), filename: "logo.png",
                                   content_type: "image/png")

    Dir.mktmpdir do |tmp|
      stamp = Backup.run(File.join(tmp, "backups"))
      dbs = Dir[File.join(stamp, "*.sqlite3*")]
      assert dbs.any?, "backup contains the sqlite database(s)"
      assert File.exist?(File.join(stamp, "files.tgz")), "backup contains Active Storage files"

      copy = SQLite3::Database.new(dbs.find { |f| f.include?("test") } || dbs.first)
      assert_equal "Backup Probe", copy.get_first_value("SELECT site_name FROM org_settings LIMIT 1")
      copy.close

      restored = File.join(tmp, "restored")
      FileUtils.mkdir_p(restored)
      Backup.restore(stamp, into: Pathname.new(restored))
      assert Dir[File.join(restored, "*.sqlite3*")].any?
      blob_key = OrgSetting.current.logo.blob.key
      assert File.exist?(File.join(restored, blob_key[0, 2], blob_key[2, 2], blob_key)),
             "restored tree contains the attached blob"
    end
  end

  test "restore stamps must be exact and stay under the backup root" do
    Dir.mktmpdir do |tmp|
      root = Pathname.new(tmp).join("backups")
      selected = root.join("20260825-120000")
      outside = Pathname.new(tmp).join("outside")
      FileUtils.mkdir_p([ selected, outside ])

      assert_equal File.realpath(selected), Backup.backup_dir("20260825-120000", root: root)
      assert_raises(ArgumentError) { Backup.backup_dir("../outside", root: root) }
      assert_raises(ArgumentError) { Backup.backup_dir("latest", root: root) }

      File.symlink(outside, root.join("20260826-120000"))
      assert_raises(ArgumentError) { Backup.backup_dir("20260826-120000", root: root) }
    end
  end

  test "restore rejects unsafe archive paths and links before touching storage" do
    Dir.mktmpdir do |tmp|
      stamp = Pathname.new(tmp).join("stamp")
      restored = Pathname.new(tmp).join("restored")
      FileUtils.mkdir_p([ stamp, restored ])
      File.write(restored.join("sentinel"), "keep")
      File.write(stamp.join("test.sqlite3"), "new-db")
      File.write(restored.join("test.sqlite3"), "keep-db")

      [ "../escape", "/absolute", "safe/../../escape" ].each do |name|
        write_archive(stamp.join("files.tgz")) do |tar, _raw|
          tar.add_file(name, 0o644) { |file| file.write("bad") }
        end
        assert_raises(ArgumentError) { Backup.restore(stamp, into: restored) }
        assert_equal "keep", File.read(restored.join("sentinel"))
        assert_equal "keep-db", File.read(restored.join("test.sqlite3"))
        refute File.exist?(Pathname.new(tmp).join("escape"))
      end

      [ "/outside", "../../outside" ].each do |target|
        write_archive(stamp.join("files.tgz")) do |tar, _raw|
          tar.add_symlink("link", target, 0o777)
        end
        assert_raises(ArgumentError) { Backup.restore(stamp, into: restored) }
        assert_equal "keep", File.read(restored.join("sentinel"))
        assert_equal "keep-db", File.read(restored.join("test.sqlite3"))
      end

      write_archive(stamp.join("files.tgz")) do |tar, raw|
        tar.add_file("safe", 0o644) { |file| file.write("safe") }
        raw.write Gem::Package::TarHeader.new(name: "link", mode: 0o644, size: 0,
                                               prefix: "", typeflag: "1",
                                               linkname: "../outside").to_s
      end
      assert_raises(ArgumentError) { Backup.restore(stamp, into: restored) }
      assert_equal "keep", File.read(restored.join("sentinel"))
      assert_equal "keep-db", File.read(restored.join("test.sqlite3"))
    end
  end

  test "housekeeping purges old trash and spam" do
    mailbox = Mailbox.create!(address: "hk@example.com", name: "HK")
    customer = Customer.create!(email: "c@example.com")
    old = Conversation.create!(mailbox: mailbox, customer: customer, subject: "old", status: "trash")
    old.update_column(:updated_at, 45.days.ago)
    fresh = Conversation.create!(mailbox: mailbox, customer: customer, subject: "new", status: "trash")

    HousekeepingJob.perform_now
    assert_nil Conversation.find_by(id: old.id)
    assert Conversation.find_by(id: fresh.id)
  end

  private

  def write_archive(path)
    raw = Tempfile.new("backup-tar")
    Gem::Package::TarWriter.new(raw) { |tar| yield tar, raw }
    raw.close
    File.open(path, "wb") do |file|
      Zlib::GzipWriter.wrap(file) { |gzip| gzip.write(File.binread(raw.path)) }
    end
  ensure
    raw&.unlink
  end
end
