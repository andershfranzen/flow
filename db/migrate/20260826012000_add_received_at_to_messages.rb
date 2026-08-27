class AddReceivedAtToMessages < ActiveRecord::Migration[8.1]
  def up
    add_column :messages, :received_at, :datetime
    execute "UPDATE messages SET received_at = COALESCE(sent_at, created_at) WHERE kind = 'inbound'"
  end

  def down
    remove_column :messages, :received_at
  end
end
