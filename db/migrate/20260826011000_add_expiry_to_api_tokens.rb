class AddExpiryToApiTokens < ActiveRecord::Migration[8.1]
  LIFETIME = 90.days

  def up
    add_column :api_tokens, :expires_at, :datetime

    select_all("SELECT id, created_at FROM api_tokens WHERE expires_at IS NULL").each do |row|
      created_at = Time.zone.parse(row["created_at"].to_s) || Time.current
      expires_at = connection.quote(created_at + LIFETIME)
      execute "UPDATE api_tokens SET expires_at = #{expires_at} WHERE id = #{row["id"].to_i}"
    end

    change_column_null :api_tokens, :expires_at, false
    add_index :api_tokens, :expires_at
  end

  def down
    remove_index :api_tokens, :expires_at
    remove_column :api_tokens, :expires_at
  end
end
