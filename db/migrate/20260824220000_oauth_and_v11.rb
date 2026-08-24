class OauthAndV11 < ActiveRecord::Migration[8.1]
  def change
    change_table :mailboxes, bulk: true do |t|
      t.string :auth_kind, null: false, default: "password" # password / microsoft / google
      t.string :oauth_refresh_token
      t.string :oauth_access_token
      t.datetime :oauth_expires_at
      t.boolean :auto_reply_enabled, null: false, default: false
      t.text :auto_reply_body
    end

    change_table :org_settings, bulk: true do |t|
      t.string :ms_client_id
      t.string :ms_client_secret
      t.string :ms_tenant, null: false, default: "common"
      t.string :google_client_id
      t.string :google_client_secret
    end

    add_column :agents, :muted_mailbox_ids, :json, null: false, default: []
    add_reference :conversations, :merged_into, foreign_key: { to_table: :conversations }
    add_column :messages, :subject, :string # forwards override the conversation subject
  end
end
