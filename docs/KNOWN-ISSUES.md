# Known issues and limitations (v1)

Listed per the plan's definition of done: known bugs are documented, not silent.

## Threading
- Threading walks `In-Reply-To`/`References`, then falls back to
  (mailbox, customer, normalised subject) within 30 days. Mail clients that
  strip both headers *and* rewrite the subject start a new conversation.
- Subject normalisation strips `Re:/Fwd:/SV:/AW:/VS:` prefixes only; other
  locales' prefixes start new conversations.
- A reply that arrives before its parent finishes processing can miss the
  join (rare; the fetch loop is serial per mailbox).

## Charsets / MIME
- Bodies are converted to UTF-8 with replacement characters for invalid
  bytes; exotic charsets may show `�` rather than fail.
- RFC 2047 subject decoding is whatever the `mail` gem supports.
- `message/rfc822` bounce parts are grepped for the original Message-ID
  rather than fully parsed.

## Fetching
- First connect starts from "now" (UIDNEXT); it does not import mailbox
  history. A UIDVALIDITY reset re-syncs from the server's current state and
  relies on dedup to avoid duplicates.
- Poll interval is 30s; IMAP IDLE is planned.
- Microsoft 365 requires the OAuth flow (basic auth is disabled by
  Microsoft); this needs an Entra ID app registration by the operator.
- The OAuth flows are tested against stubbed token endpoints; report issues
  with real tenants (first-party testing needs a real M365/Google account).

## Attachments
- Attachment serving has no HTTP Range support yet: video previews play but
  seeking long videos is limited. Office formats (docx/xlsx) have no in-app
  preview — they download.

## Operational
- Presence/collision state is in-memory in the web process: correct for the
  single-web-container Compose setup, resets on deploy.
- Conversation numbers come from `max(number)+1` under SQLite's single
  writer; fine at this scale.
- SSE holds one Puma thread per connected agent; `RAILS_MAX_THREADS` is 16
  in the Compose setup. Raise it for teams larger than ~12 concurrent agents.
