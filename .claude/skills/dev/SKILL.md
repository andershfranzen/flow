---
name: dev
description: Spin up, drive, and iterate on the Flow dev environment (Rails API + Solid Queue + Vue/Vite SPA). Use whenever asked to run, start, screenshot, or verify the app locally, or before iterating on frontend/backend changes.
---

# Flow development environment

Verified cold-start from a fresh Linux container. Everything is scripted —
do not hand-roll the steps the scripts already do.

## Spin up

```sh
bin/setup     # first run, idempotent: PostgreSQL (or SQLite fallback), gems,
              # npm ci, database, Solid Queue tables, seed data
bin/dev       # foreman: Rails API :3111 + bin/jobs worker + Vite HMR :5173
```

- Run `bin/dev` in the background and wait until both
  `curl -sf localhost:3111/up` and `curl -sf localhost:5173/` succeed
  (~20 s; Vite is the slower one).
- `bin/setup` finds PostgreSQL by trying, in order: unix socket as current
  user, `postgres@127.0.0.1` (trust), password `postgres`, password `ci`.
  It starts the server first (`service postgresql start` on Linux,
  `brew services start` on macOS), creates `flow_development` +
  `flow_test`, and writes both URLs to `.env` (gitignored).
- `.env` is loaded by config/boot.rb, so ad-hoc `bin/rails runner/console/test`
  all hit the right databases: dev commands → `flow_development`, tests →
  `flow_test` (via TEST_DATABASE_URL). Real env vars always win over `.env`.
- No PostgreSQL reachable → automatic SQLite fallback in `storage/`.
- `bin/setup --reset` drops and rebuilds the dev database (reseeds).

## Seeded login (development only)

- Admin: `admin@flow.local` / `flowdev123` (sees all mailboxes)
- Agent: `sam@flow.local` / `flowdev123` (Support + Sales via MailboxAccess)
- 5 demo conversations across Support/Sales mailboxes, tags `billing`/`bug`.
  Seeds only run when no agent exists (idempotent).

## Iterating

- Frontend: edit `frontend/src/**` — Vite HMR applies instantly on :5173.
  Work against :5173 (its proxy forwards /api, /mcp, /rails, /oauth, /auth,
  /health to :3111 with `changeOrigin: false` — required for CSRF).
- Backend: Rails reloads app code per request; restart `bin/dev` only for
  initializer/config/gem changes. Job classes are cached by the running
  worker — restart after editing `app/jobs/**` or `app/services` used by jobs.
- Production bundle: `npm --prefix frontend run build` writes hashed assets
  into `public/` and rewrites `public/index.html`. `public/index.html` is
  committed, `public/assets` is gitignored — after frontend changes that
  ship, rebuild and commit the new `index.html`.

## Driving the app headlessly (screenshots, smoke checks)

Playwright 1.56 is installed globally; Chromium is pre-provisioned
(`PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers` — never `playwright install`).
In an `.mjs` script import it by absolute path (NODE_PATH does not apply
to ESM):

```js
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs'
const page = await (await chromium.launch()).newPage({ viewport: { width: 1440, height: 900 } })
await page.goto('http://localhost:5173/', { waitUntil: 'networkidle' })
await page.fill('input[type="email"]', 'admin@flow.local')
await page.fill('input[type="password"]', 'flowdev123')
await page.getByRole('button', { name: /log in/i }).click()   // NOT button[type=submit]
await page.waitForURL('**/inbox**')
```

Conversation rows: click by visible subject text (`page.getByText('…')`).
Always read the screenshot you take — a blank frame means launch failed.

## Tests

```sh
bin/rails test                  # backend; uses flow_test, dev data untouched
npm --prefix frontend test      # node --test (format helpers etc.)
bin/e2e-greenmail               # live IMAP/SMTP round trip — needs Docker
```

CI runs the backend suite on both SQLite and PostgreSQL; run both locally
for DB-sensitive changes (SQLite: `DATABASE_URL= TEST_DATABASE_URL= bin/rails test`).

## Gotchas already solved — don't rediscover

- Fresh PostgreSQL databases lack Solid Queue tables (they're not in
  schema.rb): `bin/rails flow:ensure_queue_tables` creates them; bin/setup
  and bin/docker-entrypoint already call it.
- `gem install foreman` under rbenv needs `rbenv rehash`; bin/dev handles it.
- Rails must listen on 3111 — the Vite proxy target is hardcoded.
- The recurring FetchAllMailboxesJob runs every 30 s but skips the seeded
  mailboxes (no IMAP credentials) — the jobs log staying quiet is normal.
