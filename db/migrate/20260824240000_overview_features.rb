class OverviewFeatures < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_reads do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.datetime :last_read_at, null: false
      t.timestamps
    end
    add_index :conversation_reads, [ :agent_id, :conversation_id ], unique: true

    add_column :conversations, :snoozed_until, :datetime
    add_index :conversations, :snoozed_until
  end
end
