# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_27_090000) do
  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_checksum", null: false
    t.string "message_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "last_seen_at"
    t.string "locale", default: "en", null: false
    t.json "muted_mailbox_ids", default: [], null: false
    t.string "name", null: false
    t.json "notify_prefs", default: {}, null: false
    t.boolean "otp_required", default: false, null: false
    t.string "otp_secret"
    t.string "password_digest", null: false
    t.string "role", default: "user", null: false
    t.string "session_token", null: false
    t.text "signature"
    t.string "sso_subject"
    t.string "sso_tenant_id"
    t.string "timezone", default: "UTC", null: false
    t.json "ui_prefs", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_agents_on_email", unique: true
    t.index ["sso_tenant_id", "sso_subject"], name: "index_agents_on_sso_tenant_and_subject", unique: true
  end

  create_table "api_tokens", force: :cascade do |t|
    t.integer "agent_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.string "scope", default: "read", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_api_tokens_on_agent_id"
    t.index ["expires_at"], name: "index_api_tokens_on_expires_at"
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
  end

  create_table "conversation_reads", force: :cascade do |t|
    t.integer "agent_id", null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_read_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "conversation_id"], name: "index_conversation_reads_on_agent_id_and_conversation_id", unique: true
    t.index ["agent_id"], name: "index_conversation_reads_on_agent_id"
    t.index ["conversation_id"], name: "index_conversation_reads_on_conversation_id"
  end

  create_table "conversation_tags", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.integer "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "tag_id"], name: "index_conversation_tags_on_conversation_id_and_tag_id", unique: true
    t.index ["conversation_id"], name: "index_conversation_tags_on_conversation_id"
    t.index ["tag_id"], name: "index_conversation_tags_on_tag_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.integer "assignee_id"
    t.datetime "created_at", null: false
    t.integer "customer_id", null: false
    t.datetime "last_message_at"
    t.integer "mailbox_id", null: false
    t.integer "merged_into_id"
    t.integer "messages_count", default: 0, null: false
    t.integer "number", null: false
    t.string "preview", default: "", null: false
    t.datetime "snoozed_until"
    t.string "status", default: "active", null: false
    t.string "subject", default: "", null: false
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_conversations_on_assignee_id"
    t.index ["customer_id"], name: "index_conversations_on_customer_id"
    t.index ["mailbox_id", "status", "last_message_at"], name: "idx_on_mailbox_id_status_last_message_at_3ae194d729"
    t.index ["mailbox_id"], name: "index_conversations_on_mailbox_id"
    t.index ["merged_into_id"], name: "index_conversations_on_merged_into_id"
    t.index ["number"], name: "index_conversations_on_number", unique: true
    t.index ["snoozed_until"], name: "index_conversations_on_snoozed_until"
  end

  create_table "customers", force: :cascade do |t|
    t.string "company"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.json "emails", default: [], null: false
    t.string "name"
    t.text "notes"
    t.json "phones", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_customers_on_email", unique: true
  end

  create_table "drafts", force: :cascade do |t|
    t.integer "agent_id", null: false
    t.text "body"
    t.json "cc", default: [], null: false
    t.integer "conversation_id"
    t.datetime "created_at", null: false
    t.integer "mailbox_id"
    t.string "subject"
    t.json "to", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "conversation_id"], name: "index_drafts_on_agent_id_and_conversation_id", unique: true
    t.index ["agent_id"], name: "index_drafts_on_agent_id"
    t.index ["conversation_id"], name: "index_drafts_on_conversation_id"
    t.index ["mailbox_id"], name: "index_drafts_on_mailbox_id"
  end

  create_table "events", force: :cascade do |t|
    t.integer "agent_id"
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.json "data", default: {}, null: false
    t.string "kind", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_events_on_agent_id"
    t.index ["conversation_id", "created_at"], name: "index_events_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_events_on_conversation_id"
  end

  create_table "followers", force: :cascade do |t|
    t.integer "agent_id", null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "conversation_id"], name: "index_followers_on_agent_id_and_conversation_id", unique: true
    t.index ["agent_id"], name: "index_followers_on_agent_id"
    t.index ["conversation_id"], name: "index_followers_on_conversation_id"
  end

  create_table "inbound_dedups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dedup_key", null: false
    t.integer "mailbox_id", null: false
    t.datetime "updated_at", null: false
    t.index ["mailbox_id", "dedup_key"], name: "index_inbound_dedups_on_mailbox_id_and_dedup_key", unique: true
    t.index ["mailbox_id"], name: "index_inbound_dedups_on_mailbox_id"
  end

  create_table "mailbox_accesses", force: :cascade do |t|
    t.integer "agent_id", null: false
    t.datetime "created_at", null: false
    t.integer "mailbox_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "mailbox_id"], name: "index_mailbox_accesses_on_agent_id_and_mailbox_id", unique: true
    t.index ["agent_id"], name: "index_mailbox_accesses_on_agent_id"
    t.index ["mailbox_id"], name: "index_mailbox_accesses_on_mailbox_id"
  end

  create_table "mailboxes", force: :cascade do |t|
    t.string "address", null: false
    t.string "auth_kind", default: "password", null: false
    t.text "auto_reply_body"
    t.boolean "auto_reply_enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.string "fetch_error"
    t.string "from_name"
    t.string "imap_folder", default: "INBOX", null: false
    t.string "imap_host"
    t.string "imap_password"
    t.integer "imap_port", default: 993
    t.boolean "imap_ssl", default: true, null: false
    t.string "imap_user"
    t.datetime "last_fetched_at"
    t.integer "last_uid", default: 0, null: false
    t.string "name", null: false
    t.string "oauth_access_token"
    t.datetime "oauth_expires_at"
    t.string "oauth_refresh_token"
    t.text "signature"
    t.string "smtp_host"
    t.string "smtp_password"
    t.integer "smtp_port", default: 587
    t.string "smtp_security", default: "starttls", null: false
    t.string "smtp_user"
    t.integer "uid_validity"
    t.datetime "updated_at", null: false
    t.index ["address"], name: "index_mailboxes_on_address", unique: true
  end

  create_table "messages", force: :cascade do |t|
    t.integer "agent_id"
    t.boolean "auto_submitted", default: false, null: false
    t.json "bcc", default: [], null: false
    t.text "body_html"
    t.text "body_text"
    t.boolean "bounce", default: false, null: false
    t.json "cc", default: [], null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "from_email"
    t.string "from_name"
    t.string "in_reply_to"
    t.string "kind", null: false
    t.string "message_id_header"
    t.datetime "received_at"
    t.text "references_header"
    t.datetime "sent_at"
    t.string "status", default: "received", null: false
    t.string "subject"
    t.json "to", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_messages_on_agent_id"
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["message_id_header"], name: "index_messages_on_message_id_header"
  end

  create_table "notifications", force: :cascade do |t|
    t.integer "agent_id", null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.datetime "read_at"
    t.datetime "updated_at", null: false
    t.index ["agent_id", "read_at"], name: "index_notifications_on_agent_id_and_read_at"
    t.index ["agent_id"], name: "index_notifications_on_agent_id"
    t.index ["conversation_id"], name: "index_notifications_on_conversation_id"
  end

  create_table "org_settings", force: :cascade do |t|
    t.string "base_url"
    t.datetime "created_at", null: false
    t.boolean "crm_enabled", default: false, null: false
    t.string "crm_url", default: "", null: false
    t.text "default_signature"
    t.string "google_client_id"
    t.string "google_client_secret"
    t.boolean "mcp_enabled", default: false, null: false
    t.string "ms_client_id"
    t.string "ms_client_secret"
    t.boolean "ms_sso_enabled", default: false, null: false
    t.string "ms_tenant", default: "common", null: false
    t.string "notify_from"
    t.string "site_name", default: "Flow", null: false
    t.string "sso_allowed_domains", default: "", null: false
    t.boolean "sso_auto_provision", default: false, null: false
    t.json "theme", default: {}, null: false
    t.datetime "updated_at", null: false
  end

  create_table "personal_folder_items", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.integer "personal_folder_id", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_personal_folder_items_on_conversation_id"
    t.index ["personal_folder_id", "conversation_id"], name: "index_personal_folder_items_uniqueness", unique: true
    t.index ["personal_folder_id"], name: "index_personal_folder_items_on_personal_folder_id"
  end

  create_table "personal_folders", force: :cascade do |t|
    t.integer "agent_id", null: false
    t.string "color", default: "#5522fa", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "name"], name: "index_personal_folders_on_agent_id_and_name", unique: true
    t.index ["agent_id"], name: "index_personal_folders_on_agent_id"
  end

  create_table "plugin_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.text "settings"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_plugin_states_on_name", unique: true
  end

  create_table "saved_replies", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "mailbox_id"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["mailbox_id"], name: "index_saved_replies_on_mailbox_id"
  end

  create_table "tags", force: :cascade do |t|
    t.string "color", default: "#8899aa", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "team_members", force: :cascade do |t|
    t.integer "agent_id", null: false
    t.datetime "created_at", null: false
    t.integer "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_team_members_on_agent_id"
    t.index ["team_id", "agent_id"], name: "index_team_members_on_team_id_and_agent_id", unique: true
    t.index ["team_id"], name: "index_team_members_on_team_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "rr_index", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_teams_on_name", unique: true
  end

  create_table "webhooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.json "events", default: [], null: false
    t.string "secret", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
  end

  create_table "workflows", force: :cascade do |t|
    t.json "actions", default: [], null: false
    t.json "conditions", default: [], null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "last_run_at"
    t.integer "mailbox_id"
    t.string "match_type", default: "all", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "runs_count", default: 0, null: false
    t.string "trigger", default: "message.inbound", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled", "trigger", "position"], name: "index_workflows_on_enabled_and_trigger_and_position"
    t.index ["mailbox_id"], name: "index_workflows_on_mailbox_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "agents"
  add_foreign_key "conversation_reads", "agents"
  add_foreign_key "conversation_reads", "conversations"
  add_foreign_key "conversation_tags", "conversations"
  add_foreign_key "conversation_tags", "tags"
  add_foreign_key "conversations", "agents", column: "assignee_id"
  add_foreign_key "conversations", "conversations", column: "merged_into_id"
  add_foreign_key "conversations", "customers"
  add_foreign_key "conversations", "mailboxes"
  add_foreign_key "drafts", "agents"
  add_foreign_key "drafts", "conversations"
  add_foreign_key "drafts", "mailboxes"
  add_foreign_key "events", "agents"
  add_foreign_key "events", "conversations"
  add_foreign_key "followers", "agents"
  add_foreign_key "followers", "conversations"
  add_foreign_key "inbound_dedups", "mailboxes"
  add_foreign_key "mailbox_accesses", "agents"
  add_foreign_key "mailbox_accesses", "mailboxes"
  add_foreign_key "messages", "agents"
  add_foreign_key "messages", "conversations"
  add_foreign_key "notifications", "agents"
  add_foreign_key "notifications", "conversations"
  add_foreign_key "personal_folder_items", "conversations"
  add_foreign_key "personal_folder_items", "personal_folders"
  add_foreign_key "personal_folders", "agents"
  add_foreign_key "saved_replies", "mailboxes"
  add_foreign_key "team_members", "agents"
  add_foreign_key "team_members", "teams"
  add_foreign_key "workflows", "mailboxes"
end
