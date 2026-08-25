class AddMcpEnabledToOrgSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :org_settings, :mcp_enabled, :boolean, default: true, null: false
  end
end
