# Deploy — agent prompt

Paste this into the app's coding agent BEFORE wiring any feature. It makes any app deployable on the platform, in any language. Full reference: [`contract.md`](contract.md).

```
This app deploys as ONE Docker container on a hosting platform. Make it comply:

- Put a Dockerfile in the repo root (FROM <base>, CMD starting a long-lived HTTP server).
- The server MUST listen on 0.0.0.0 and process.env.PORT (the platform sets PORT=8080).
  Never bind 127.0.0.1/localhost. The process must stay running — if it exits or throws
  on boot it crash-loops (it will NOT "deploy anyway").
- Install deps with a PLAIN install (npm install / pnpm install / yarn install) — it needs
  no committed lockfile. Use a frozen/clean install (npm ci, --frozen-lockfile) ONLY if you
  really generated + committed the lockfile. NEVER hand-write a lockfile (a fake one fails
  npm ci with ETARGET/integrity errors). Unsure → npm install.
- Read all config from environment variables; never hardcode or commit secrets. The
  platform injects and locks PORT, DATABASE_URL, and any META_* var. Anything named META_*
  is a SECRET — use it only in server-side code, never in the browser.

- Is this a static/SPA site with no server? Auth and Payments are SERVER-ONLY (they use a
  secret token and enforce checks the user must not bypass). If you add either, you MUST
  add a small backend (any language) and call them from there — you cannot do it in the
  browser.

- Database (only if you store data): connect via process.env.DATABASE_URL (managed
  Postgres). Do NOT enable SSL — the DB link is on a private network and does not offer
  SSL (node-postgres: `ssl: false`; never `sslmode=require`), otherwise you get "server
  does not support SSL connections" and crash-loop. The `public` schema ALREADY EXISTS —
  create your tables in it with `CREATE TABLE IF NOT EXISTS public.<name> (...)`. Do NOT
  run `CREATE SCHEMA` (you are not the DB owner → it fails with "permission denied for
  database" and the app crash-loops). If accounts are enabled, an `auth` schema appears
  and is read-only to you — keep your tables in `public`, link by the auth user.id.

- The container disk is EPHEMERAL — every deploy/restart starts from a clean image and
  local writes are lost. Persist everything that matters in the database (DATABASE_URL):
  no user uploads, SQLite or data files on disk. /tmp scratch during a process's life is
  fine.

- The `/__meta/*` path prefix on your domain is reserved by the platform — do not add
  routes under it.
```
