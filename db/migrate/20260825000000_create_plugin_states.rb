class CreatePluginStates < ActiveRecord::Migration[8.1]
  def change
    create_table :plugin_states do |t|
      t.string :name, null: false
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :plugin_states, :name, unique: true
  end
end
