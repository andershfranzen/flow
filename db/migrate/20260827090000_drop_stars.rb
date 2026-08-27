class DropStars < ActiveRecord::Migration[8.1]
  def up
    drop_table :stars
  end

  def down
    create_table :stars do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.timestamps
      t.index [ :agent_id, :conversation_id ], unique: true
    end
  end
end
