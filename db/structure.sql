CREATE TABLE "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE "active_storage_blobs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "filename" varchar NOT NULL, "content_type" varchar, "metadata" text, "service_name" varchar NOT NULL, "byte_size" bigint NOT NULL, "checksum" varchar, "created_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_active_storage_blobs_on_key" ON "active_storage_blobs" ("key") /*application='SharedInbox'*/;
CREATE TABLE "active_storage_attachments" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "record_type" varchar NOT NULL, "record_id" bigint NOT NULL, "blob_id" bigint NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_c3b3935057"
FOREIGN KEY ("blob_id")
  REFERENCES "active_storage_blobs" ("id")
);
CREATE INDEX "index_active_storage_attachments_on_blob_id" ON "active_storage_attachments" ("blob_id") /*application='SharedInbox'*/;
CREATE UNIQUE INDEX "index_active_storage_attachments_uniqueness" ON "active_storage_attachments" ("record_type", "record_id", "name", "blob_id") /*application='SharedInbox'*/;
CREATE TABLE "active_storage_variant_records" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "blob_id" bigint NOT NULL, "variation_digest" varchar NOT NULL, CONSTRAINT "fk_rails_993965df05"
FOREIGN KEY ("blob_id")
  REFERENCES "active_storage_blobs" ("id")
);
CREATE UNIQUE INDEX "index_active_storage_variant_records_uniqueness" ON "active_storage_variant_records" ("blob_id", "variation_digest") /*application='SharedInbox'*/;
CREATE TABLE "action_mailbox_inbound_emails" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "status" integer DEFAULT 0 NOT NULL, "message_id" varchar NOT NULL, "message_checksum" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_action_mailbox_inbound_emails_uniqueness" ON "action_mailbox_inbound_emails" ("message_id", "message_checksum") /*application='SharedInbox'*/;
CREATE TABLE "agents" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "email" varchar NOT NULL, "name" varchar NOT NULL, "password_digest" varchar NOT NULL, "role" varchar DEFAULT 'user' NOT NULL, "locale" varchar DEFAULT 'en' NOT NULL, "timezone" varchar DEFAULT 'UTC' NOT NULL, "notify_prefs" json DEFAULT '{}' NOT NULL, "session_token" varchar NOT NULL, "last_seen_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "muted_mailbox_ids" json DEFAULT '[]' NOT NULL /*application='Flow'*/);
CREATE UNIQUE INDEX "index_agents_on_email" ON "agents" ("email") /*application='SharedInbox'*/;
CREATE TABLE "mailboxes" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "address" varchar NOT NULL, "name" varchar NOT NULL, "from_name" varchar, "signature" text, "imap_host" varchar, "imap_port" integer DEFAULT 993, "imap_ssl" boolean DEFAULT TRUE NOT NULL, "imap_user" varchar, "imap_password" varchar, "imap_folder" varchar DEFAULT 'INBOX' NOT NULL, "smtp_host" varchar, "smtp_port" integer DEFAULT 587, "smtp_user" varchar, "smtp_password" varchar, "smtp_security" varchar DEFAULT 'starttls' NOT NULL, "uid_validity" integer, "last_uid" integer DEFAULT 0 NOT NULL, "last_fetched_at" datetime(6), "fetch_error" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "auth_kind" varchar DEFAULT 'password' NOT NULL /*application='Flow'*/, "oauth_refresh_token" varchar /*application='Flow'*/, "oauth_access_token" varchar /*application='Flow'*/, "oauth_expires_at" datetime(6) /*application='Flow'*/, "auto_reply_enabled" boolean DEFAULT FALSE NOT NULL /*application='Flow'*/, "auto_reply_body" text /*application='Flow'*/);
CREATE UNIQUE INDEX "index_mailboxes_on_address" ON "mailboxes" ("address") /*application='SharedInbox'*/;
CREATE TABLE "mailbox_accesses" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "agent_id" integer NOT NULL, "mailbox_id" integer NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_de737c4600"
FOREIGN KEY ("agent_id")
  REFERENCES "agents" ("id")
, CONSTRAINT "fk_rails_d78c2686fc"
FOREIGN KEY ("mailbox_id")
  REFERENCES "mailboxes" ("id")
);
CREATE INDEX "index_mailbox_accesses_on_agent_id" ON "mailbox_accesses" ("agent_id") /*application='SharedInbox'*/;
CREATE INDEX "index_mailbox_accesses_on_mailbox_id" ON "mailbox_accesses" ("mailbox_id") /*application='SharedInbox'*/;
CREATE UNIQUE INDEX "index_mailbox_accesses_on_agent_id_and_mailbox_id" ON "mailbox_accesses" ("agent_id", "mailbox_id") /*application='SharedInbox'*/;
CREATE TABLE "customers" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "email" varchar NOT NULL, "name" varchar, "emails" json DEFAULT '[]' NOT NULL, "phones" json DEFAULT '[]' NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_customers_on_email" ON "customers" ("email") /*application='SharedInbox'*/;
CREATE TABLE "messages" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "conversation_id" integer NOT NULL, "agent_id" integer, "kind" varchar NOT NULL, "message_id_header" varchar, "in_reply_to" varchar, "references_header" text, "from_email" varchar, "from_name" varchar, "to" json DEFAULT '[]' NOT NULL, "cc" json DEFAULT '[]' NOT NULL, "bcc" json DEFAULT '[]' NOT NULL, "body_text" text, "body_html" text, "status" varchar DEFAULT 'received' NOT NULL, "bounce" boolean DEFAULT FALSE NOT NULL, "auto_submitted" boolean DEFAULT FALSE NOT NULL, "sent_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "subject" varchar /*application='Flow'*/, CONSTRAINT "fk_rails_7f927086d2"
FOREIGN KEY ("conversation_id")
  REFERENCES "conversations" ("id")
, CONSTRAINT "fk_rails_3209a7ff53"
FOREIGN KEY ("agent_id")
  REFERENCES "agents" ("id")
);
CREATE INDEX "index_messages_on_conversation_id" ON "messages" ("conversation_id") /*application='SharedInbox'*/;
CREATE INDEX "index_messages_on_agent_id" ON "messages" ("agent_id") /*application='SharedInbox'*/;
CREATE INDEX "index_messages_on_conversation_id_and_created_at" ON "messages" ("conversation_id", "created_at") /*application='SharedInbox'*/;
CREATE INDEX "index_messages_on_message_id_header" ON "messages" ("message_id_header") /*application='SharedInbox'*/;
CREATE TABLE "inbound_dedups" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "mailbox_id" integer NOT NULL, "dedup_key" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_1b8e40543b"
FOREIGN KEY ("mailbox_id")
  REFERENCES "mailboxes" ("id")
);
CREATE INDEX "index_inbound_dedups_on_mailbox_id" ON "inbound_dedups" ("mailbox_id") /*application='SharedInbox'*/;
CREATE UNIQUE INDEX "index_inbound_dedups_on_mailbox_id_and_dedup_key" ON "inbound_dedups" ("mailbox_id", "dedup_key") /*application='SharedInbox'*/;
CREATE TABLE "tags" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "color" varchar DEFAULT '#8899aa' NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_tags_on_name" ON "tags" ("name") /*application='SharedInbox'*/;
CREATE TABLE "conversation_tags" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "conversation_id" integer NOT NULL, "tag_id" integer NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_86cc44d590"
FOREIGN KEY ("conversation_id")
  REFERENCES "conversations" ("id")
, CONSTRAINT "fk_rails_11d8014418"
FOREIGN KEY ("tag_id")
  REFERENCES "tags" ("id")
);
CREATE INDEX "index_conversation_tags_on_conversation_id" ON "conversation_tags" ("conversation_id") /*application='SharedInbox'*/;
CREATE INDEX "index_conversation_tags_on_tag_id" ON "conversation_tags" ("tag_id") /*application='SharedInbox'*/;
CREATE UNIQUE INDEX "index_conversation_tags_on_conversation_id_and_tag_id" ON "conversation_tags" ("conversation_id", "tag_id") /*application='SharedInbox'*/;
CREATE TABLE "saved_replies" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "mailbox_id" integer, "name" varchar NOT NULL, "body" text NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_450741d2e2"
FOREIGN KEY ("mailbox_id")
  REFERENCES "mailboxes" ("id")
);
CREATE INDEX "index_saved_replies_on_mailbox_id" ON "saved_replies" ("mailbox_id") /*application='SharedInbox'*/;
CREATE TABLE "drafts" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "agent_id" integer NOT NULL, "conversation_id" integer, "mailbox_id" integer, "to" json DEFAULT '[]' NOT NULL, "cc" json DEFAULT '[]' NOT NULL, "subject" varchar, "body" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_82621d69e2"
FOREIGN KEY ("agent_id")
  REFERENCES "agents" ("id")
, CONSTRAINT "fk_rails_e1fd7770df"
FOREIGN KEY ("conversation_id")
  REFERENCES "conversations" ("id")
, CONSTRAINT "fk_rails_5a006091c0"
FOREIGN KEY ("mailbox_id")
  REFERENCES "mailboxes" ("id")
);
CREATE INDEX "index_drafts_on_agent_id" ON "drafts" ("agent_id") /*application='SharedInbox'*/;
CREATE INDEX "index_drafts_on_conversation_id" ON "drafts" ("conversation_id") /*application='SharedInbox'*/;
CREATE INDEX "index_drafts_on_mailbox_id" ON "drafts" ("mailbox_id") /*application='SharedInbox'*/;
CREATE UNIQUE INDEX "index_drafts_on_agent_id_and_conversation_id" ON "drafts" ("agent_id", "conversation_id") /*application='SharedInbox'*/;
CREATE TABLE "events" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "conversation_id" integer NOT NULL, "agent_id" integer, "kind" varchar NOT NULL, "data" json DEFAULT '{}' NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_5e1f00574f"
FOREIGN KEY ("conversation_id")
  REFERENCES "conversations" ("id")
, CONSTRAINT "fk_rails_bf8f42a708"
FOREIGN KEY ("agent_id")
  REFERENCES "agents" ("id")
);
CREATE INDEX "index_events_on_conversation_id" ON "events" ("conversation_id") /*application='SharedInbox'*/;
CREATE INDEX "index_events_on_agent_id" ON "events" ("agent_id") /*application='SharedInbox'*/;
CREATE INDEX "index_events_on_conversation_id_and_created_at" ON "events" ("conversation_id", "created_at") /*application='SharedInbox'*/;
CREATE TABLE "notifications" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "agent_id" integer NOT NULL, "conversation_id" integer NOT NULL, "kind" varchar NOT NULL, "read_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_8625a3b3de"
FOREIGN KEY ("agent_id")
  REFERENCES "agents" ("id")
, CONSTRAINT "fk_rails_c566f523da"
FOREIGN KEY ("conversation_id")
  REFERENCES "conversations" ("id")
);
CREATE INDEX "index_notifications_on_agent_id" ON "notifications" ("agent_id") /*application='SharedInbox'*/;
CREATE INDEX "index_notifications_on_conversation_id" ON "notifications" ("conversation_id") /*application='SharedInbox'*/;
CREATE INDEX "index_notifications_on_agent_id_and_read_at" ON "notifications" ("agent_id", "read_at") /*application='SharedInbox'*/;
CREATE TABLE "webhooks" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "url" varchar NOT NULL, "secret" varchar NOT NULL, "events" json DEFAULT '[]' NOT NULL, "enabled" boolean DEFAULT TRUE NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE "api_tokens" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "agent_id" integer NOT NULL, "name" varchar NOT NULL, "token_digest" varchar NOT NULL, "scope" varchar DEFAULT 'read' NOT NULL, "last_used_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_46da76b30a"
FOREIGN KEY ("agent_id")
  REFERENCES "agents" ("id")
);
CREATE INDEX "index_api_tokens_on_agent_id" ON "api_tokens" ("agent_id") /*application='SharedInbox'*/;
CREATE UNIQUE INDEX "index_api_tokens_on_token_digest" ON "api_tokens" ("token_digest") /*application='SharedInbox'*/;
CREATE VIRTUAL TABLE message_search USING fts5(
  subject, body, conversation_id UNINDEXED, message_id UNINDEXED
)
/* message_search(subject,body,conversation_id,message_id) */;
CREATE TABLE 'message_search_data'(id INTEGER PRIMARY KEY, block BLOB);
CREATE TABLE 'message_search_idx'(segid, term, pgno, PRIMARY KEY(segid, term)) WITHOUT ROWID;
CREATE TABLE 'message_search_content'(id INTEGER PRIMARY KEY, c0, c1, c2, c3);
CREATE TABLE 'message_search_docsize'(id INTEGER PRIMARY KEY, sz BLOB);
CREATE TABLE 'message_search_config'(k PRIMARY KEY, v) WITHOUT ROWID;
CREATE TABLE "org_settings" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "site_name" varchar DEFAULT 'Flow' NOT NULL, "base_url" varchar, "notify_from" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "ms_client_id" varchar /*application='Flow'*/, "ms_client_secret" varchar /*application='Flow'*/, "ms_tenant" varchar DEFAULT 'common' NOT NULL /*application='Flow'*/, "google_client_id" varchar /*application='Flow'*/, "google_client_secret" varchar /*application='Flow'*/);
CREATE TABLE "conversations" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "mailbox_id" integer NOT NULL, "customer_id" integer NOT NULL, "assignee_id" integer, "number" integer NOT NULL, "subject" varchar DEFAULT '' NOT NULL, "status" varchar DEFAULT 'active' NOT NULL, "preview" varchar DEFAULT '' NOT NULL, "messages_count" integer DEFAULT 0 NOT NULL, "starred" boolean DEFAULT FALSE NOT NULL, "last_message_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "merged_into_id" integer, CONSTRAINT "fk_rails_b0388c9502"
FOREIGN KEY ("assignee_id")
  REFERENCES "agents" ("id")
, CONSTRAINT "fk_rails_a72440fed6"
FOREIGN KEY ("customer_id")
  REFERENCES "customers" ("id")
, CONSTRAINT "fk_rails_15ac80a23a"
FOREIGN KEY ("mailbox_id")
  REFERENCES "mailboxes" ("id")
, CONSTRAINT "fk_rails_009f633a91"
FOREIGN KEY ("merged_into_id")
  REFERENCES "conversations" ("id")
);
CREATE INDEX "index_conversations_on_mailbox_id" ON "conversations" ("mailbox_id") /*application='Flow'*/;
CREATE INDEX "index_conversations_on_customer_id" ON "conversations" ("customer_id") /*application='Flow'*/;
CREATE INDEX "index_conversations_on_assignee_id" ON "conversations" ("assignee_id") /*application='Flow'*/;
CREATE UNIQUE INDEX "index_conversations_on_number" ON "conversations" ("number") /*application='Flow'*/;
CREATE INDEX "idx_on_mailbox_id_status_last_message_at_3ae194d729" ON "conversations" ("mailbox_id", "status", "last_message_at") /*application='Flow'*/;
CREATE INDEX "index_conversations_on_merged_into_id" ON "conversations" ("merged_into_id") /*application='Flow'*/;
INSERT INTO "schema_migrations" (version) VALUES
('20260824220000'),
('20260824210000'),
('20260824190000'),
('20260824180932'),
('20260824180931');

