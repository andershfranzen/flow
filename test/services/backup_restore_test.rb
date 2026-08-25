require "test_helper"

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
end
