class CreateFollowers < ActiveRecord::Migration[8.1]
  def change
    create_table :followers do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.timestamps
    end
    add_index :followers, [ :agent_id, :conversation_id ], unique: true
  end
end
