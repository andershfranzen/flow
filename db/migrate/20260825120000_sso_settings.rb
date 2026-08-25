class SsoSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :org_settings, :ms_sso_enabled, :boolean, default: false, null: false
    add_column :org_settings, :sso_auto_provision, :boolean, default: false, null: false
    add_column :org_settings, :sso_allowed_domains, :string, default: "", null: false
  end
end
