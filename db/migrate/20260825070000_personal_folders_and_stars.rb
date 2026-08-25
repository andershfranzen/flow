class PersonalFoldersAndStars < ActiveRecord::Migration[8.1]
  def up
    create_table :personal_folders do |t|
      t.references :agent, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: "#5522fa"
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :personal_folders, [ :agent_id, :name ], unique: true

    create_table :personal_folder_items do |t|
      t.references :personal_folder, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.timestamps
    end
    add_index :personal_folder_items, [ :personal_folder_id, :conversation_id ], unique: true,
              name: "index_personal_folder_items_uniqueness"

    # Stars become personal (they were wrongly global in v1).
    create_table :stars do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.timestamps
    end
    add_index :stars, [ :agent_id, :conversation_id ], unique: true

    # Best-effort data migration: an existing global star becomes the
    # assignee's personal star; unassigned starred conversations lose the
    # star (there is no owner to give it to).
    starred = Struct.new(:id, :assignee_id)
    select_rows("SELECT id, assignee_id FROM conversations WHERE starred = #{quoted_true} AND assignee_id IS NOT NULL").each do |id, assignee_id|
      execute sanitize_sql([ "INSERT INTO stars (agent_id, conversation_id, created_at, updated_at) VALUES (?, ?, ?, ?)",
                             assignee_id, id, Time.current, Time.current ])
    end

    remove_column :conversations, :starred
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def sanitize_sql(arr) = ActiveRecord::Base.sanitize_sql(arr)
  def quoted_true = connection.quoted_true
end
