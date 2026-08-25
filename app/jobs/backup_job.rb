class BackupJob < ApplicationJob
  queue_as :default

  def perform
    return if SearchIndex.postgres? # PG: schedule pg_dump outside the app
    Backup.run
  end
end
