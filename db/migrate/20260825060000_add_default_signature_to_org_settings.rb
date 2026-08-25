class AddDefaultSignatureToOrgSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :org_settings, :default_signature, :text
  end
end
