class CustomersTeamsSignatures < ActiveRecord::Migration[8.1]
  def change
    add_column :customers, :company, :string
    add_column :customers, :notes, :text
    add_column :agents, :signature, :text

    create_table :teams do |t|
      t.string :name, null: false
      t.integer :rr_index, null: false, default: 0
      t.timestamps
    end
    add_index :teams, :name, unique: true

    create_table :team_members do |t|
      t.references :team, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true
      t.timestamps
    end
    add_index :team_members, [ :team_id, :agent_id ], unique: true
  end
end
