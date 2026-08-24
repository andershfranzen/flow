# Flow

A small, self-hosted, **email-first shared inbox**: IMAP in, SMTP out, a web
UI for a team, an HTTP API, webhooks, and an MCP server — all in core, all
**MIT**. No paid modules, no `enterprise/` directory, no per-seat fee.

Your mail stays in your mailbox. Flow is an **overlay**: it fetches
`support@example.com` over IMAP and replies through the same account's SMTP.
Leaving Flow never requires an export ritual — the mail was always yours.

- **Stack**: Rails 8 + SQLite + Solid Queue · Vue 3 + Vite + Pinia · no Redis
- **Extensible**: REST API (everything the UI can do), signed webhooks,
  MCP tools, and in-process plugins — see [docs/EXTENDING.md](docs/EXTENDING.md)
- **License**: [MIT](LICENSE) on every file in the tree

## Install (Docker Compose)

```sh
git clone <this repo> flow && cd flow
export SECRET_KEY_BASE=$(openssl rand -hex 64)   # keep this safe — it also encrypts mailbox passwords
export APP_URL=https://inbox.example.com          # behind your TLS reverse proxy
docker compose up -d --build
docker compose exec web bin/create-admin you@example.com "Your Name"
```

Open the app, log in, go to **Settings → Mailboxes**, add your mailbox's IMAP
and SMTP credentials (for Gmail: an app password, `imap.gmail.com` /
`smtp.gmail.com`), and press **Test connection**. New mail appears within ~30
seconds.

TLS is assumed at a reverse proxy (Caddy, nginx, Traefik) in front of port
3000; Flow sets secure cookies and expects `X-Forwarded-Proto`.

## Backup

Everything lives in the `flow_storage` volume (SQLite databases +
attachments). Backup = copy the volume. Restore = put it back.

## CLI

```sh
bin/create-admin EMAIL NAME [PASSWORD]   # first admin, more admins
bin/fetch-now [MAILBOX_ADDRESS]          # fetch immediately instead of waiting for the poll
bin/send-test MAILBOX_ADDRESS TO_EMAIL   # verify SMTP settings
```

Inside Compose, prefix with `docker compose exec web`.

## API, webhooks, MCP

Everything the UI can do, the API can do. Create a token under **Settings →
API tokens**, then:

```sh
curl -H "Authorization: Bearer si_..." https://inbox.example.com/api/conversations
```

Webhooks POST signed JSON on inbound/outbound mail, assignment, and status
changes. The MCP server at `POST /mcp` exposes `search`, `get_thread`,
`draft_reply`, `send`, `list_mailboxes`, `assign` — bring your own MCP client
and model; core never calls an LLM. Details and a hello-world bot:
[docs/EXTENDING.md](docs/EXTENDING.md).

## Development

```sh
bundle install
bin/rails db:prepare
(cd frontend && npm install && npm run dev) &   # Vite on 5173, proxies /api to Rails
bin/rails server                                 # API on 3000
bin/jobs                                         # Solid Queue worker (fetch/send)
bin/rails test                                   # backend test suite
```

`GET /health` reports the database and the last successful fetch per mailbox.

## Known limitations

See [docs/KNOWN-ISSUES.md](docs/KNOWN-ISSUES.md) — threading and charset
edge cases are listed there, not hidden.
