class CreateCoreSchema < ActiveRecord::Migration[8.1]
  def change
    create_table :org_settings do |t|
      t.string :site_name, null: false, default: "Shared Inbox"
      t.string :base_url
      t.string :notify_from
      t.timestamps
    end

    create_table :agents do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "user"
      t.string :locale, null: false, default: "en"
      t.string :timezone, null: false, default: "UTC"
      t.json :notify_prefs, null: false, default: {}
      t.string :session_token, null: false
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :agents, :email, unique: true

    create_table :mailboxes do |t|
      t.string :address, null: false
      t.string :name, null: false
      t.string :from_name
      t.text :signature
      t.string :imap_host
      t.integer :imap_port, default: 993
      t.boolean :imap_ssl, null: false, default: true
      t.string :imap_user
      t.string :imap_password
      t.string :imap_folder, null: false, default: "INBOX"
      t.string :smtp_host
      t.integer :smtp_port, default: 587
      t.string :smtp_user
      t.string :smtp_password
      t.string :smtp_security, null: false, default: "starttls"
      t.integer :uid_validity
      t.integer :last_uid, null: false, default: 0
      t.datetime :last_fetched_at
      t.string :fetch_error
      t.timestamps
    end
    add_index :mailboxes, :address, unique: true

    create_table :mailbox_accesses do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :mailbox, null: false, foreign_key: true
      t.timestamps
    end
    add_index :mailbox_accesses, [ :agent_id, :mailbox_id ], unique: true

    create_table :customers do |t|
      t.string :email, null: false
      t.string :name
      t.json :emails, null: false, default: []
      t.json :phones, null: false, default: []
      t.timestamps
    end
    add_index :customers, :email, unique: true

    create_table :conversations do |t|
      t.references :mailbox, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.references :assignee, foreign_key: { to_table: :agents }
      t.integer :number, null: false
      t.string :subject, null: false, default: ""
      t.string :status, null: false, default: "active"
      t.string :preview, null: false, default: ""
      t.integer :messages_count, null: false, default: 0
      t.boolean :starred, null: false, default: false
      t.datetime :last_message_at
      t.timestamps
    end
    add_index :conversations, :number, unique: true
    add_index :conversations, [ :mailbox_id, :status, :last_message_at ]

    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :agent, foreign_key: true
      t.string :kind, null: false # inbound / outbound / note
      t.string :message_id_header
      t.string :in_reply_to
      t.text :references_header
      t.string :from_email
      t.string :from_name
      t.json :to, null: false, default: []
      t.json :cc, null: false, default: []
      t.json :bcc, null: false, default: []
      t.text :body_text
      t.text :body_html # sanitized
      t.string :status, null: false, default: "received" # outbound: queued/sent/failed; inbound: received
      t.boolean :bounce, null: false, default: false
      t.boolean :auto_submitted, null: false, default: false
      t.datetime :sent_at
      t.timestamps
    end
    add_index :messages, [ :conversation_id, :created_at ]
    # Dedup: one message per (mailbox via conversation) Message-ID; scoped per
    # conversation's mailbox is awkward in SQL, so store dedup key explicitly.
    add_index :messages, :message_id_header

    create_table :inbound_dedups do |t|
      t.references :mailbox, null: false, foreign_key: true
      t.string :dedup_key, null: false # Message-ID or content hash
      t.timestamps
    end
    add_index :inbound_dedups, [ :mailbox_id, :dedup_key ], unique: true

    create_table :tags do |t|
      t.string :name, null: false
      t.string :color, null: false, default: "#8899aa"
      t.timestamps
    end
    add_index :tags, :name, unique: true

    create_table :conversation_tags do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.timestamps
    end
    add_index :conversation_tags, [ :conversation_id, :tag_id ], unique: true

    create_table :saved_replies do |t|
      t.references :mailbox, foreign_key: true # null = global
      t.string :name, null: false
      t.text :body, null: false
      t.timestamps
    end

    create_table :drafts do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :conversation, foreign_key: true # null = new conversation draft
      t.references :mailbox, foreign_key: true
      t.json :to, null: false, default: []
      t.json :cc, null: false, default: []
      t.string :subject
      t.text :body
      t.timestamps
    end
    add_index :drafts, [ :agent_id, :conversation_id ], unique: true

    create_table :events do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :agent, foreign_key: true
      t.string :kind, null: false # assigned / unassigned / status_changed
      t.json :data, null: false, default: {}
      t.timestamps
    end
    add_index :events, [ :conversation_id, :created_at ]

    create_table :notifications do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.string :kind, null: false
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications, [ :agent_id, :read_at ]

    create_table :webhooks do |t|
      t.string :url, null: false
      t.string :secret, null: false
      t.json :events, null: false, default: []
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end

    create_table :api_tokens do |t|
      t.references :agent, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :scope, null: false, default: "read" # read / write
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :api_tokens, :token_digest, unique: true

    # SQLite FTS5 over message bodies + subject (E1); SearchIndex also ensures
    # it lazily, so this is just a fresh-install fast path. PG uses tsvector
    # queries instead (see SearchIndex).
    reversible do |dir|
      dir.up do
        unless connection.adapter_name.match?(/postg/i)
          execute <<~SQL
            CREATE VIRTUAL TABLE IF NOT EXISTS message_search USING fts5(
              subject, body, conversation_id UNINDEXED, message_id UNINDEXED
            );
          SQL
        end
      end
      dir.down { execute "DROP TABLE IF EXISTS message_search;" }
    end
  end
end
