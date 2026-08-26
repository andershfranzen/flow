class SecureMcpDefault < ActiveRecord::Migration[8.1]
  def up
    change_column_default :org_settings, :mcp_enabled, from: true, to: false
    execute "UPDATE org_settings SET mcp_enabled = FALSE"
  end

  def down
    execute "UPDATE org_settings SET mcp_enabled = TRUE"
    change_column_default :org_settings, :mcp_enabled, from: false, to: true
  end
end
