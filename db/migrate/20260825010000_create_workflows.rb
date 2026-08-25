class CreateWorkflows < ActiveRecord::Migration[8.1]
  def change
    create_table :workflows do |t|
      t.string :name, null: false
      t.boolean :enabled, null: false, default: true
      t.string :trigger, null: false, default: "message.inbound"
      t.references :mailbox, foreign_key: true # null = all mailboxes
      t.string :match_type, null: false, default: "all" # all / any
      t.json :conditions, null: false, default: []
      t.json :actions, null: false, default: []
      t.integer :position, null: false, default: 0
      t.integer :runs_count, null: false, default: 0
      t.datetime :last_run_at
      t.timestamps
    end
    add_index :workflows, [ :enabled, :trigger, :position ]
  end
end
