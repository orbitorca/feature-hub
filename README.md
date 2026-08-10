# OrbitOrca Feature Hub

Language-agnostic HTTP contracts + agent prompts for adding OrbitOrca features
(payments and auth now; email / files later) to an app. The app's OWN coding agent
(Cursor, Bolt, Lovable, Claude Code, …) reads a feature's `prompt.md` + `contract.md`
and wires the calls in whatever language/framework the app uses. No SDK, no vendor keys,
no webhooks in the app — the platform runs the hard parts.

## Start here: [`deploy/`](deploy/)
Before wiring ANY feature, make the app deployable — read [`deploy/contract.md`](deploy/contract.md). It is language- and framework-agnostic and covers the things every app gets wrong: it must be a long-lived HTTP server on `0.0.0.0:$PORT`; **auth and payments are server-only, so a static/SPA app needs a backend added**; and the database rules (`public` already exists → `CREATE TABLE`, never `CREATE SCHEMA`). Skipping this is the #1 cause of a deploy that crash-loops.

## How it works
1. The owner enables a feature in the OrbitOrca dashboard.
2. The platform injects the feature's env vars into the app and redeploys it.
3. The agent reads this hub — [`deploy/`](deploy/) first, then the feature — and wires the HTTP calls.

## Two kinds of feature

Features differ in **where they run**, and that changes how the app calls them.

**Brokered** (`payments`) — the platform runs the provider on the app's behalf and holds
the keys, the webhooks and the source of truth.
- **Base URL:** `META_API_URL` (injected) — prepend it to every path.
- **Auth:** `Authorization: Bearer ${META_APP_TOKEN}` — the **app's** token, on every call.
- **Idempotency:** send an `Idempotency-Key` header on mutating POSTs so a retry is safe.
- **Never** store card data, hold provider keys, or build webhooks — the platform does all
  of that.

**Edge** (`auth`) — the service runs inside the app's own container group, with its data in
the app's own database.
- **Base URL:** `META_AUTH_URL` from server code; the relative path `/__meta/auth` from the
  browser. There is no `META_API_URL` here.
- **Auth:** the bearer token belongs to the **end-user**, not to the app. `META_APP_TOKEN`
  is not used.

## Conventions (all features)
- **JSON** in and out.
- **Branch on the status code, never on an error string.** `200` = success.
- Platform errors are HTTP 4xx/5xx with
  `{ "error": { "code": "APP_ERROR.<DOMAIN>.<CODE>", "message": "…" } }`.
- **Reserved by the platform, in every app:** the `/__meta/*` path prefix on the app's
  domain, and the env vars `PORT`, `DATABASE_URL` and anything starting with `META_`.

## Structure
- One subfolder per feature: `prompt.md` (paste/inject into the agent) + `contract.md`
  (endpoints, curl, mapping rules).
- `_template/` — copy it to start a new feature.

## Features
- [`deploy/`](deploy/) — **read first.** Make any app deployable: Dockerfile, `0.0.0.0:$PORT`, static-vs-server decision, env/secrets, database rules.
- [`payments/`](payments/) — sell one-off + subscriptions, gate paid features,
  B2B invoices (NIP/VAT). Brokered: Stripe Connect.
- [`auth/`](auth/) — end-user accounts, login, password reset, email change. Edge: runs
  beside the app, users live in the app's own database.
- (later) `email/`, `files/`, …

---
Commits: English, one-line Conventional Commits, no AI/agent trailer — same standard
as the rest of OrbitOrca.
