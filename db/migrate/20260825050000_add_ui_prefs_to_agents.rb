class AddUiPrefsToAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :ui_prefs, :json, null: false, default: {}
  end
end
