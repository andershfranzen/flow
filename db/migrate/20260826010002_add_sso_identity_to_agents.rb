class AddSsoIdentityToAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :sso_tenant_id, :string
    add_column :agents, :sso_subject, :string
    add_index :agents, [ :sso_tenant_id, :sso_subject ], unique: true,
      name: "index_agents_on_sso_tenant_and_subject"
  end
end
