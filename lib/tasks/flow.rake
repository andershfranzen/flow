namespace :flow do
  desc "Back up SQLite databases and Active Storage files to storage/backups/<stamp>"
  task backup: :environment do
    puts Backup.run
  end

  desc "Restore a backup (flow:restore[20260825-120000]). STOP web + jobs first."
  task :restore, [ :stamp ] => :environment do |_t, args|
    dir = Rails.root.join("storage", "backups", args.fetch(:stamp))
    Backup.restore(dir)
    puts "Restored #{dir}. Restart the app."
  end
end
