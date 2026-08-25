class AddThemeToOrgSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :org_settings, :theme, :json, default: {}, null: false
  end
end
