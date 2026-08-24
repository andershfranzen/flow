# Shared Inbox — initial plan

Working title. Rename before the first public commit. This is a **no-profit, MIT, modern-stack** shared mailbox in the shape of [FreeScout](https://freescout.net)’s **core**, not its module shop and not Chatwoot.

Inspired by FreeScout (folders, collision, fetch), Help Scout (conversation as the unit of work), Postal/Haraka (mail is a pipeline), and Chatwoot’s API-first instinct — without Chatwoot’s `enterprise/` split.

## What this is

A small, self-hosted **email-first help desk**: IMAP in, SMTP out, a web UI for a team, an HTTP API, and MCP in core.

People run it because they own the mail, there is no per-seat fee, and they can **script or fork anything**. Amazon may host it. That is the MIT deal.

## The hole

| Project | License reality | Shape |
|---|---|---|
| FreeScout | AGPL-3.0 + paid modules | Light, email-first |
| Chatwoot | MIT **core**, proprietary `enterprise/` | Heavy, omnichannel, open-core |
| n8n | Fair-code (Sustainable Use), not OSI | Automation, not a mailbox |
| Zammad | AGPL | Full ITSM |

The gap is **light + OSI-permissive on the whole tree + not open-core + scriptable**. That combination is the product. It is a commons gap, not a SaaS pitch.

## License

- **MIT on every file in the tree.** One `LICENSE`. No `.ee.` files, no second license, no CLA that assigns copyright to a company.
- Bolt-ons are ordinary code (a folder, an HTTP webhook, an MCP tool). Not a store, not a license key.
- Contributions under MIT, same as the repo.

If a dependency is not MIT/Apache/BSD, it does not go in core without an explicit exception listed here.

## How to read this document

**v1** is what must exist for two agents to share `support@example.com` in production on a $5 VPS. **Later** is real software we will likely write, not a fantasy backlog — listed so we do not pretend a shared inbox is four tables.

Configurable means **code, API, and MCP**, not four hundred checkboxes.

## Decided

These are closed. Do not re-litigate in implementation unless the plan is edited.

| Topic | Decision |
|---|---|
| Motive | No-profit open-source commons. MIT is the product. |
| License | MIT on the **whole tree**. No CLA assigning copyright to a company. No `enterprise/`, no `.ee.`, no second license. |
| Shape | FreeScout **core** (email shared inbox), not the module shop, not Chatwoot. |
| Tenancy | One organisation per install. |
| Inbound | **IMAP overlay** of an existing mailbox. Not MX-to-Rails. Not Gmail-forward-to-the-app as the setup. |
| Action Mailbox | Allowed as the **processor** after IMAP fetch (raw RFC822 → `InboundEmail` → our models). Not as the v1 onboarding. |
| Outbound | SMTP as the mailbox address, queued (never on the HTTP request). |
| Backend | Rails 8 API, Active Record, SQLite, Solid Queue, no Redis in v1. |
| Frontend | **Vue 3 + Vite + Pinia**, `<script setup>`. SPA. Rails serves the built assets in production. Not Hotwire as the inbox. |
| MCP | Official `mcp` gem, mounted on Rails. Tools in core. **No vendor LLM in core.** |
| Extensibility | HTTP API + webhooks + MCP in v1. Bolt-ons are ordinary code. |
| Mail bar | Gmail + one ordinary IMAP (Fastmail or cPanel). |
| Transcript | Newest-last. |
| Conversation numbers | Global per install (`#142`). |
| Tags, saved replies, API | Core, not paid modules. |
| Compose | `web` (Puma) + `jobs` (Solid Queue) + volume. |

Chatwoot is also Rails + Vue. Ignore that. Same ecosystem, different license and product.

---

## System shape

One organisation per install (no multi-tenant SaaS). Many mailboxes, many agents.

```
                    IMAP/SMTP (and later OAuth)
                              |
                         Mail pipeline (Rails)
                    fetch → parse → thread → store
                              |
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
   Solid Queue           Rails API              MCP (gem `mcp`)
   (fetch, send,         + JS SPA               mounted on Rails
    webhooks, notify)    (Vite)                 stdio and/or HTTP
                              │
                         SQLite file
                      + attachment store
```

v1 is **Rails + Puma** for HTTP, **Solid Queue** in the same image (Puma plugin or a `bin/jobs` process in Compose). Do not start with Redis, Sidekiq, or a mesh of services. Split a dedicated worker container when IMAP fetch blocks the web process.

### Why inbound is IMAP, not Action Mailbox MX

Action Mailbox’s happy path is **ingress**: mail is *delivered to Rails* (Postfix pipe, or Mailgun/Postmark/SES HTTP). That means changing **MX** or forwarding the whole inbox at the provider.

This project is a **shared-inbox overlay**, like FreeScout and Help Scout: the customer already has `support@firma.dk` on Gmail / Fastmail / cPanel. They paste IMAP (and later OAuth). They do **not** move the domain’s mail to us. Overlay is the product.

Consequences of MX-to-Rails as v1:

- Setup is DNS and an MTA, not “connect this mailbox.”
- Replies still SMTP-as-the-address, but inbound no longer lives in the user’s real mailbox unless they also keep a copy — two sources of truth.
- Gmail “forward to the app” wrecks SPF/DKIM on the copy and is a worse onboarding than IMAP.

**What Action Mailbox is still good for:** after IMAP fetch, feed the raw RFC822 into `ActionMailbox::InboundEmail` for Message-ID idempotency, Active Storage of the raw message, and a processor that creates our `Message`/`Thread`. That is an implementation detail of **A2/A6/A9**, not a change of product. Use it if it is less code than a hand-rolled parser job. Do not expose “point MX here” as the v1 setup.

IMAP/SMTP remain the **source of truth for mail**. The app is a view, a team layer, and a send path. Leaving must not require an export ritual for the messages themselves.

---

## Data model

Core records. Everything else is a field, a join, or a later table.

| Record | Holds |
|---|---|
| **OrgSettings** | Site name, base URL, outbound notify-from, secret key |
| **Agent** | Email, name, password hash, role (admin / user), locale, timezone, notify prefs, last seen |
| **Mailbox** | Address, name, IMAP, SMTP, signature, fetch cursor (UIDVALIDITY + UID), from-name, permissions |
| **MailboxAccess** | Agent ↔ mailbox (access yes/no; admin implied) |
| **Customer** | Primary email (unique), name, emails[], phones optional |
| **Thread** | Mailbox, customer, subject, number, status, assignee, preview, counts, starred, timestamps |
| **Message** | Thread, direction (in/out/note), raw headers needed for threading, Message-ID, in-reply-to, from/to/cc/bcc, text, sanitized HTML, attachments, bounce flag |
| **Attachment** | Message, filename, mime, size, storage key, content-id (for inline) |
| **Tag** | Name, colour; global in v1 (FreeScout’s model) |
| **ThreadTag** | Thread ↔ tag |
| **SavedReply** | Mailbox or global, name, body with `{{customer.name}}` etc. |
| **Draft** | Agent, thread or new, body, to/cc, attachments — unsent |
| **Event** | Thread timeline that is not mail (assigned, moved, merged) — keep small |
| **Webhook** | URL, secret, event types, enabled |
| **ApiToken** | Agent, hash, scopes |

Jobs live in **Solid Queue**’s tables, not a hand-rolled `Job` model.

**Thread status (v1):** `active` · `pending` (waiting on customer) · `closed` · `spam` · `trash`.

**Built-in folders (computed, not a table in v1):** Unassigned, Mine, Assigned (to anyone), Closed, Spam, Trash, Starred, Drafts. Counts = active conversations except where the folder is Closed/Spam/Trash.

Customers: email address is the key. No CRM product in v1. Merge of two customers is later.

---

## Components to build

Each item is a real unit of work. **v1** / **v1.1** / **later**.

### A. Mail pipeline

This is the product. UI without this is a todo list.

| # | Component | What it does | When |
|---|---|---|---|
| A1 | **Mailbox secrets** | Store IMAP/SMTP passwords encrypted at rest (app secret). Never log them. Test-connection button. | v1 |
| A2 | **IMAP fetch loop** | Per mailbox: connect, SELECT, fetch new UIDs since cursor, handle UIDVALIDITY reset, backoff on error, no overlapping fetch for the same mailbox. Poll first (e.g. 30s). Preferred implementation: job stores raw RFC822, then **Action Mailbox** `InboundEmail` for Message-ID idempotency and Active Storage of the raw message; a mailbox processor creates `Thread` / `Message`. Product setup is still “paste IMAP,” never “point MX here.” | v1 |
| A3 | **IMAP IDLE** | Push-ish fetch where the server supports it. | v1.1 |
| A4 | **POP3** | FreeScout has it; skip unless someone needs it. | later |
| A5 | **OAuth mail** | Gmail and Microsoft 365 (XOauth2 / Graph). App-password IMAP is dying. | v1.1 (Gmail bar still via app password or OAuth if required) |
| A6 | **MIME parse** | Decode multipart, charset, RFC 2047 subjects. Use a library. | v1 |
| A7 | **HTML sanitizer** | Incoming HTML is hostile. Strip script, remote tracking optional, safe subset for display. XSS here is a help-desk CVE. | v1 |
| A8 | **Plain-text extract** | Always store a text body for search, MCP, and quotes. | v1 |
| A9 | **Dedup** | Unique on `(mailbox, Message-ID)` when present; fallback hash of (from, date, subject, snippet). Fetch must be idempotent. | v1 |
| A10 | **Threading** | Walk `In-Reply-To` and `References` to existing Message-IDs. Fallback: same mailbox + normalised subject + customer within a window. Document failures. | v1 |
| A11 | **New vs reply** | First message opens a thread + number. Replies attach. CC’d stranger reply: keep original customer (FreeScout got this wrong for years). | v1 |
| A12 | **Inbound recipients** | Parse To/Cc/Bcc; match mailbox address (plus-addressing `support+foo@`). | v1 |
| A13 | **Loop / flood guard** | Ignore mail from our own outbound Message-IDs; cap new threads per mailbox per minute; skip auto-submitted (`Auto-Submitted`, `X-Auto-Response-Suppress`, List-Unsubscribe noise as a flag not a drop). | v1 |
| A14 | **Bounce handler** | Detect DSN / `mailer-daemon`; mark last outbound as bounced; do not open a new customer thread for every bounce. | v1 |
| A15 | **Outbound compose** | Build MIME: text+HTML, attachments, In-Reply-To, References, Message-ID we generate, Thread-Topic if cheap. Library, not hand-rolled. | v1 |
| A16 | **SMTP send queue** | Never send on the HTTP request. Job: send, record, retry with backoff, dead-letter after N. | v1 |
| A17 | **From / reply-to** | Send from mailbox address. Optional display name. Reply-To = mailbox. | v1 |
| A18 | **CC / BCC on send** | Include on outbound; store on the message. | v1 |
| A19 | **Signature** | Per mailbox, appended on send unless stripped. Per-agent signature later. | v1 |
| A20 | **Inline images** | Paste screenshot → CID; embed on send (FreeScout paid module; we do the common case in core). | v1 |
| A21 | **Open / click tracking** | Privacy-hostile. Off. Package later if ever. | no |
| A22 | **DKIM sign** | Optional later; most people send via a provider that already signs. | later |
| A23 | **S/MIME & PGP** | FreeScout module. Out of core. | later |
| A24 | **Move/delete on IMAP** | After fetch, optional mark-seen or move to processed folder. Dangerous; off by default. | later |

v1 mail bar: **Gmail** and **one ordinary IMAP** (Fastmail or cPanel). Everything else is best-effort until it breaks a user we care about.

### B. Conversations (the work surface)

| # | Component | What it does | When |
|---|---|---|---|
| B1 | **Thread list** | Per folder, paginated, preview, assignee, age, unread/active styling. | v1 |
| B2 | **Thread view** | Full transcript, notes vs mail visually distinct, **newest-last**. | v1 |
| B3 | **Conversation number** | Monotonic per install or per mailbox. Human-referable (`#142`). | v1 |
| B4 | **Assign / unassign** | To an agent with mailbox access. Event on the timeline. | v1 |
| B5 | **Status changes** | Active / pending / closed / spam / trash. Closing from reply is one action. | v1 |
| B6 | **Internal notes** | Not emailed. Markdown or a small subset of HTML. | v1 |
| B7 | **Reply editor** | HTML or markdown-to-HTML. Quote previous. To/Cc editable. | v1 |
| B8 | **Drafts** | Autosave per agent per thread. Conflict: last-write-wins v1. | v1 |
| B9 | **Saved replies** | Insert into editor. Variables: `{{customer.name}}`, `{{agent.name}}`, `{{mailbox.name}}`. FreeScout charges for this; it is core here. | v1 |
| B10 | **Tags** | Add/remove on a thread; filter list by tag. Core, not a module. | v1 |
| B11 | **Star / follow** | Star = mine bookmark. Follow = notify even if not assignee (v1.1 if time-boxed). | star v1, follow v1.1 |
| B12 | **Collision detection** | Presence: “Ada is viewing”. Soft lock optional later. Heartbeat + TTL. | v1 |
| B13 | **Live list refresh** | New mail appears without a full reload (SSE or websocket or short poll). | v1 |
| B14 | **Merge threads** | Two threads, same customer, concatenate; keep one number; redirect the other. | v1.1 |
| B15 | **Move mailbox** | Reassign thread to another mailbox the agent can access. | v1.1 |
| B16 | **Forward** | Send the transcript (or last message) to an external address as a new outbound. | v1.1 |
| B17 | **New conversation** | Agent-initiated mail to a customer (and optionally several To:). | v1 |
| B18 | **Snooze** | Hide until a timestamp; job reopens. | later |
| B19 | **Mentions** | `@agent` in a note → notify. | later |
| B20 | **Phone / SMS tickets** | Not email. Out. | later / never in core |
| B21 | **Checklists, kanban, time tracking** | FreeScout modules. Packages, not core. | later |

### C. People

| # | Component | What it does | When |
|---|---|---|---|
| C1 | **Agent CRUD** | Admin creates agents. Invite-by-email later. | v1 |
| C2 | **Roles** | `admin` (all mailboxes, settings) and `user` (granted mailboxes only). No “see only assigned” in v1 (that was a FreeScout CVE class). | v1 |
| C3 | **Mailbox ACLs** | Which agents see which mailbox. | v1 |
| C4 | **Authn** | Email + password via `has_secure_password` (bcrypt). Session cookie, HttpOnly, Secure, SameSite. CSRF for the cookie-authenticated SPA (token or SameSite strategy documented). | v1 |
| C5 | **Session hygiene** | Logout, password change invalidates, brute-force delay. | v1 |
| C6 | **Customer page** | Threads for this email, name edit. | v1 |
| C7 | **Customer merge** | Two emails, one person. | later |
| C8 | **Teams** | Assign to a group. | later |
| C9 | **OIDC / SAML / LDAP / OAuth login** | Packages. | later |
| C10 | **End-user portal** | Customer logs in to see tickets. | later |

### D. Notifications

| # | Component | What it does | When |
|---|---|---|---|
| D1 | **Preferences** | Per agent: new unassigned, assigned to me, customer reply on mine, note on mine. | v1 |
| D2 | **In-app unread** | Badge / list of unseen events. | v1 |
| D3 | **Email-to-agent** | Transactional notify from a configured SMTP (can be the mailbox or a global). | v1 |
| D4 | **Browser push** | Web Push. | later |
| D5 | **Mute per mailbox** | Admins otherwise drown. | v1.1 |
| D6 | **Auto-reply to customer** | “We got your mail” once per thread. Loop-safe. Off by default. | v1.1 |
| D7 | **Out of office** | Agent-level. Easy to loop. Later. | later |

### E. Search and files

| # | Component | What it does | When |
|---|---|---|---|
| E1 | **Search** | SQLite FTS on subject + text body + customer email/name. Filter mailbox, status, assignee. | v1 |
| E2 | **Attachment store** | Files on disk (or local volume), not in SQLite BLOBs. Keyed by id. Size cap. | v1 |
| E3 | **Attachment download** | Authz: agent must see the mailbox. | v1 |
| E4 | **Meilisearch / etc.** | Optional later if FTS hurts. | later |

### F. Jobs, realtime, ops internals

| # | Component | What it does | When |
|---|---|---|---|
| F1 | **Solid Queue** | Fetch, send, webhook, notify. At-least-once. Idempotent jobs. SQLite-backed in v1 (Rails 8). No Redis. | v1 |
| F2 | **Scheduler** | Wake fetch, retry, snooze (when we have it). | v1 |
| F3 | **Health** | `GET /health` — db, last successful fetch per mailbox. | v1 |
| F4 | **Structured logs** | JSON to stdout. No secrets. Request id. | v1 |
| F5 | **Metrics** | Optional Prometheus later. | later |
| F6 | **Realtime bus** | SSE is enough for collision + list refresh in v1. | v1 |

### G. HTTP API, webhooks, MCP

The opposite of FreeScout’s paid API module: **if the UI can do it, the API can do it**, in v1.

| # | Component | What it does | When |
|---|---|---|---|
| G1 | **REST API** | CRUD-ish for mailboxes (admin), threads, messages, agents, tags, saved replies. Pagination, errors as JSON. | v1 |
| G2 | **API tokens** | Per agent, hashed at rest, scoped (read / write). | v1 |
| G3 | **Webhooks** | POST JSON on: thread.created, message.inbound, message.outbound, thread.assigned, thread.status. HMAC secret. Retry. | v1 |
| G4 | **MCP server** | Official Ruby SDK (`mcp` gem, Apache-2.0). Tools: `search`, `get_thread`, `draft_reply`, `send`, plus `list_mailboxes`, `assign` if cheap. Auth = token. **No vendor LLM in core** — the MCP *client* brings the model. `draft_reply` returns thread context (and optionally a local template), not an OpenAI call. Mounted in Rails ([SDK Rails example](https://github.com/modelcontextprotocol/ruby-sdk/tree/main/examples/rails)). | v1 |
| G5 | **MCP transports** | Streamable HTTP on the Rails app (`/mcp`). Optional stdio wrapper that calls the same tools for local agents. Single-process Puma for HTTP MCP (SDK keeps session state in memory). | v1 |
| G6 | **Webhook hello-world** | Documented: on inbound, POST a note via API. Proves “no PR to core.” | v1 |

### H. Web UI surfaces

Not a design system. One layout: mailbox rail, folder list, thread list, thread pane.

| # | Surface | When |
|---|---|---|
| H1 | Login / logout | v1 |
| H2 | Inbox shell (mailbox switcher, folders, counts) | v1 |
| H3 | Thread list + thread pane (can be one page, list|detail) | v1 |
| H4 | Reply / note / draft composer | v1 |
| H5 | Customer side panel | v1 |
| H6 | Settings: org | v1 |
| H7 | Settings: agents | v1 |
| H8 | Settings: mailbox (IMAP/SMTP/signature/test) | v1 |
| H9 | Settings: my profile + notification prefs | v1 |
| H10 | Settings: saved replies, tags, webhooks, tokens | v1 |
| H11 | Search results | v1 |
| H12 | Keyboard shortcuts (j/k, e to close, r to reply) | v1.1 — Help Scout DNA, small |
| H13 | Responsive layout (usable on a phone browser) | v1 |
| H14 | Dark mode | later as CSS; not a module |
| H15 | Installer wizard | skip if Compose + env is the install |
| H16 | i18n | English UI in v1; string-extract so Danish/etc. can land without a rewrite |
| H17 | Screen-reader structure | Semantic HTML from the start; not a pass at the end |
| H18 | **Vue app shell** | Vue Router: login, inbox, settings. Pinia: session, mailbox, thread list, presence, draft. | v1 |
| H19 | **API client** | `fetch` to Rails, cookie session, CSRF header as documented in C4. | v1 |
| H20 | **SSE client** | Subscribe to collision + list refresh; reconnect with backoff. | v1 |

### I. Security (core, not a module)

FreeScout grew extra-security as a paid add-on. Ours is boring and in core.

| # | Component | When |
|---|---|---|
| I1 | TLS assumed at reverse proxy; document it | v1 |
| I2 | HTML sanitizer (A7), CSRF, session flags (C4) | v1 |
| I3 | Attachment type allow/deny (no `.html` served as HTML) | v1 |
| I4 | Rate limit login and send | v1 |
| I5 | Secret encryption (A1) | v1 |
| I6 | Do not run as root; Compose user | v1 |
| I7 | IP allowlist, CAPTCHA | later / proxy |
| I8 | 2FA for agents | later |

### J. Ship and operate

| # | Component | When |
|---|---|---|
| J1 | `docker-compose.yml` — `web` + `jobs`, volume for db and files | v1 |
| J2 | Env / credentials — `SECRET_KEY_BASE`, `APP_URL`, `PORT` | v1 |
| J3 | Migrations — Active Record, run on boot / release | v1 |
| J4 | README — install, mailbox setup, backup (copy the volume) | v1 |
| J5 | Rails runner / `bin/` — `create-admin`, `fetch-now`, `send-test` | v1 |
| J6 | Backup/restore notes | v1 |
| J7 | Postgres driver | later |
| J8 | Multi-arch image | later |

### K. Explicitly not core (packages or never)

Live chat, WhatsApp, Telegram, Facebook, Slack-as-channel, knowledge base, end-user portal, reports/wallboards, CRM, WooCommerce, Jira, LDAP, SAML, white-label, custom homepage, satisfaction ratings, time tracking, kanban, custom fields, custom folders, workflows/SLA, faster-search sidecar, mobile native apps, GDPR “module” (we just obey GDPR: export/delete agent+customer data via API — **v1.1** a JSON export of a customer).

---

## Stack

Frozen. Do not shop.

| Piece | Choice | Why |
|---|---|---|
| Backend | **Ruby on Rails 8** (API) | Models, jobs, mail, MCP mount |
| Frontend | **Vue 3 + Vite + Pinia** (`<script setup>`) | MIT; list/detail/presence UI; lighter than React |
| Serve | Rails serves the built SPA in production; Vite proxy in dev | One origin, simple cookies |
| DB | SQLite via Active Record | A file. Postgres later (`J7`) |
| Queue | **Solid Queue** | Rails 8 default; SQLite; no Redis in v1 |
| Mail fetch | `net-imap`; raw RFC822 into Action Mailbox processor | Overlay IMAP; AM for idempotency/raw store |
| Mail parse | `mail` gem / Action Mailbox | Do not write MIME |
| Mail send | `Mail` / Net::SMTP (Action Mailer only as a wrapper) | Same as fetch: libraries |
| Files | Active Storage on disk (local volume) | Attachments + raw inbound |
| MCP | Official `mcp` gem, mounted in Rails | Apache-2.0; first-party Rails example |
| Realtime | SSE from Rails (not websocket in v1) | Collision + list refresh |
| Search | SQLite FTS5 | Enough until it is not |
| Auth | `has_secure_password` (bcrypt) + cookie session | See C4 |
| Ship | Docker Compose: `web` (Puma) + `jobs` (Solid Queue) + volume | Two processes, one image |

Svelte is a bit lighter; React is what models emit most. Vue is the middle. Frozen.

Hotwire/Turbo is not the v1 UI.

### Repo layout (v1)

```
/
  LICENSE                 MIT
  PLAN.md
  README.md
  Dockerfile
  docker-compose.yml
  Gemfile
  config/
  db/migrate/
  app/
    models/
    mailboxes/            Action Mailbox routing / processors
    jobs/                 fetch, send, webhook, notify
    controllers/api/
    mcp/                  tool classes
    services/             threading, sanitizer, bounce
  frontend/               Vue 3 + Vite + Pinia
    src/pages/
    src/stores/
    src/components/
  storage/                sqlite + attachments (volume)
  bin/                    create-admin, fetch-now, jobs
```

## v1 definition of done

Two agents, one mailbox, Gmail (or the second IMAP):

1. Customer mail becomes a thread in Unassigned.
2. Agent A assigns to Agent B; B is notified.
3. Both opening the thread see collision.
4. B replies; customer receives it in Gmail; the reply is on the thread.
5. A note stays internal.
6. Search finds the subject.
7. MCP: search → get_thread → send (or draft) with a token.
8. `docker compose up` on a clean machine is the install.

Known threading/charset bugs are listed, not silent.

## Build cut (about 8 weeks)

Slip **scope**, not the definition of done. Map to components.

| Slice | Components | Done when |
|---|---|---|
| 0. Repo | J1–J4, I6 | MIT `LICENSE`, this plan, Rails boots, SQLite migrates, Vite hello-page |
| 1. Identity | C1–C5, H1, H6–H7, I2, I4 | Admin creates an agent; login/logout; brute-force delay |
| 2. Mailbox + fetch | A1–A2, A6–A9, A12, F1–F2, H8 | Test connection; IMAP fetch → (Action Mailbox) → rows; fetch twice does not duplicate |
| 3. Threads | A10–A11, A13, B1–B3, H2–H3, H13 | Grouped threads; list + pane; numbers |
| 4. Reply | A15–A20, B4–B8, B17, F1 | SMTP via queue; Gmail receives; draft autosave |
| 5. Team | B9–B12, C3, D1–D3, H4–H5, H9–H10 | Assign, notes, collision, saved replies, tags, notify |
| 6. Bounce + hygiene | A14, E1–E3, B5, H11 | Bounce does not become a fake customer; search works; files download authorised |
| 7. API + MCP + hooks | G1–G6, F3–F4, F6, J5 | Four MCP tools + webhooks + health + CLI |
| 8. Compose | J1–J6, H16 structure | Clean-machine install; backup is “copy the volume” |

**v1.1 (after someone uses it):** A3 IDLE, A5 OAuth, B14–B16 merge/move/forward, B11 follow, D5–D6 mute + optional auto-reply, C7 merge customers, H12 shortcuts, customer JSON export.

## What we are not rewriting

Do not reimplement Help Scout or Zendesk. Do not copy FreeScout’s PHP or module catalog. Do not add a second license “for sustainability.” Sustainability is that the core stays small enough that one person can keep it.

## Open

Only the public **name** (must not be “FreeScout”). Everything else in **Decided**.
