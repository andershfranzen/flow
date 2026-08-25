# Changelog

## 1.0.0 — 2026-08-25

First stable release. Highlights:

- **Email-first shared inbox**: IMAP in / SMTP out (password or Microsoft 365 /
  Google OAuth), threading, HTML email with server-side sanitization,
  attachments with previews, drafts, snooze, tags, saved replies with
  variables, personal folders, per-agent stars, full-text search (SQLite FTS5
  or PostgreSQL tsvector).
- **Collaboration**: assignment, teams with round-robin, internal notes,
  @-presence ("is viewing"), notifications with an in-app panel, collision
  hints.
- **Automation**: n8n-style drag-and-drop workflow builder (triggers,
  conditions, actions), outbound webhooks with HMAC signatures, auto-replies.
- **Sign in with Microsoft (OIDC)** with domain-gated auto-provisioning, or
  email + password with TOTP two-factor. One or the other, switchable.
- **Agent-native MCP**: 25 tools covering the entire product — an AI agent
  with an admin token can set up a fresh Flow end to end. Configurable kill
  switch in settings.
- **Extensible**: WordPress-style plugins (install from a git URL), REST API
  with scoped tokens, webhooks, MCP.
- **Brandable**: company logo, org-wide color themes with a styled picker.
- **Operable**: Docker Compose deployment, `/health` with queue + fetch
  staleness, optional Sentry, nightly backups with a tested restore path,
  retention policies, CI on SQLite + PostgreSQL + a live-IMAP e2e suite.

MIT licensed. No open core, no paid tier.
