class AddCrmToOrgSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :org_settings, :crm_enabled, :boolean, default: false, null: false
    add_column :org_settings, :crm_url, :string, default: "", null: false
  end
end
