# Operating Flow

## Backups

**SQLite (default).** A consistent backup runs nightly at 03:00 into
`storage/backups/` (last 7 kept) using SQLite's `VACUUM INTO` — safe under
concurrent writes, unlike copying the file. Run one manually:

```sh
docker compose exec web bin/backup
```

That protects against corruption and mistakes on the same disk. For real
disaster recovery, ship backups off the box — either sync `storage/backups/`
+ the attachment files elsewhere, or run [Litestream](https://litestream.io)
against `storage/production.sqlite3` and `storage/production_queue.sqlite3`
for continuous S3 replication.

**PostgreSQL.** Use your normal `pg_dump` schedule; the in-app backup job
no-ops.

## PostgreSQL instead of SQLite

Set `DATABASE_URL=postgres://user:pass@host/db` (see the commented `db`
service in `docker-compose.yml`). Flow then runs single-database: Solid Queue
tables live in the same schema and search uses PostgreSQL full-text queries
instead of FTS5. The full test suite runs against both adapters in CI.

Migrating an existing SQLite install to PostgreSQL is not automated yet —
it's a data copy exercise.

## Monitoring

`GET /health` returns JSON with per-mailbox fetch status **and queue depth**:

```json
{ "ok": true, "mailboxes": [...], "queue": { "pending": 0, "failed": 0, "oldest_pending_seconds": null } }
```

Alert on: `ok != true`, any `fetch_error`, `failed > 0`, or
`oldest_pending_seconds` above a few minutes — that last one is the "mail
silently stopped sending" detector.

Errors: subscribe in-process via a plugin (`Rails.error` reporter) — see
`examples/error_notifier` for a webhook-posting example that needs no gems.

## Upgrades

```sh
git pull
docker compose build
docker compose up -d   # migrations run on boot
```

Take a backup first. Downgrades are not supported once migrations have run.

## Retention & housekeeping

Raw inbound emails incinerate after 30 days (Action Mailbox default);
processing failures are kept 90 days for debugging, then purged nightly,
along with read notifications older than 90 days. Conversations, messages,
and attachments are kept forever — deleting is a product decision, not a
default.

## Resource notes

- The Compose file caps memory (web 768M, jobs 512M, idle 256M) and log size.
- SSE holds a thread per connected agent: raise `RAILS_MAX_THREADS` past 16
  for teams larger than ~12 concurrent agents.
- Multi-arch images: `docker buildx build --platform linux/amd64,linux/arm64 .`

## Security posture

TLS at your reverse proxy; strict CSP; sessions expire after 14 days idle
and on password change; login and sending are rate-limited; TOTP 2FA
per agent; mailbox credentials, OAuth tokens, and 2FA secrets encrypted at
rest with keys derived from `SECRET_KEY_BASE` (rotating it invalidates them —
re-enter mailbox credentials after a rotation); webhook deliveries refuse
private-network targets unless `FLOW_ALLOW_PRIVATE_WEBHOOKS=1`; attachments
capped at 25 MB out / 30 MB in; oversized inbound messages are skipped with
a log line.

## Sign in with Microsoft (SSO)

Reuses the same Entra app registration as Microsoft 365 mailbox OAuth. To enable:

1. In the Entra app registration, add a second redirect URI: `<base url>/auth/microsoft/callback`
   (the mailbox flow already uses `<base url>/oauth/callback`). The `openid email profile`
   scopes are requested at sign-in time; no extra API permissions are needed.
2. Settings -> Organisation -> "Sign in with Microsoft": enable the toggle. Optionally enable
   auto-provisioning and list the email domains allowed to self-create agent accounts
   (auto-provisioned accounts get the regular `user` role).
3. While SSO is enabled, password login is disabled for everyone ("one or the other").

Lockout recovery: if the Entra app breaks and nobody can sign in, start the server with
`FLOW_FORCE_PASSWORD_LOGIN=1` to temporarily re-allow password login, fix the app or disable
the toggle, then remove the variable.

Note: SSO sign-ins bypass Flow's built-in TOTP (Microsoft enforces its own MFA policies).
