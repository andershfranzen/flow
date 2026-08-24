class RenameDefaultSiteName < ActiveRecord::Migration[8.1]
  def change
    change_column_default :org_settings, :site_name, from: "Shared Inbox", to: "Flow"
    reversible do |dir|
      dir.up { execute "UPDATE org_settings SET site_name = 'Flow' WHERE site_name = 'Shared Inbox'" }
    end
  end
end
