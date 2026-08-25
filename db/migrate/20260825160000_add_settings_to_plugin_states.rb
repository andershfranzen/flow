class AddSettingsToPluginStates < ActiveRecord::Migration[8.1]
  def change
    add_column :plugin_states, :settings, :text
  end
end
