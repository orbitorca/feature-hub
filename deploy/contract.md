# Deploy — app compatibility contract

Everything the platform needs to build and run your app — for ANY language or framework, and ANY kind of app. Read this before wiring any feature (auth, payments, …). Paste-ready version: [`prompt.md`](prompt.md).

## 1. What the platform runs

- Your repo (or zip) must have a **`Dockerfile` in the root**, starting `FROM <base-image>`, with a `CMD`/`ENTRYPOINT` that starts a **long-lived HTTP server**.
- The platform builds the image and runs ONE container with `PORT=8080`. Your server MUST **listen on `0.0.0.0` and `process.env.PORT`** (i.e. `0.0.0.0:8080`). Listening on `127.0.0.1`/`localhost` = unreachable → the deploy fails its health check. `EXPOSE` is irrelevant.
- The process must **stay running**. A container whose main process exits — a one-shot script, or a server that throws on boot — is a deploy failure. If your startup code can fail (e.g. a database call), it will **crash-loop**, not "deploy anyway": fix the cause.
- **Install dependencies with a PLAIN install, not a frozen one.** Use `npm install` (or `pnpm install` / `yarn install`) in the Dockerfile — it resolves dependencies without needing a committed lockfile. Use a FROZEN/clean install (`npm ci`, `pnpm install --frozen-lockfile`, `yarn --frozen-lockfile`, `pip … --require-hashes`) **only** when you ACTUALLY generated the lockfile by running a real install and committed it. **NEVER hand-write a lockfile** — a fabricated one fails `npm ci` with cryptic `ETARGET`/integrity errors (and `npm ci` doesn't accept `--frozen-lockfile`, that's a pnpm/yarn flag). When unsure, `npm install` is the safe default.

## 2. Static app vs. server app — pick correctly

- A **purely static** site (HTML/CSS/JS, no server process) is fine **only if it uses no server-only feature**.
- **Auth and Payments are server-only.** They use platform secrets and enforce checks where the end-user cannot tamper. **If you add auth or payments to a static/SPA app, you MUST add a backend** (any language — Node, Python, Go, PHP, Ruby, …) and make those calls from it. They cannot be done from the browser alone. When unsure, ship a small HTTP server and put the feature calls there.

## 3. Configuration & secrets

- Read all config from **environment variables**. Never hardcode or commit secrets.
- The platform injects and **locks** these (you cannot set them): `PORT` (always 8080), `DATABASE_URL` (if your app has a database), and anything starting with `META_` (feature brokers). Your OWN keys (e.g. an LLM API key) are added in the app's Env-vars panel and arrive as env vars too.
- Any `META_*` value is a **platform secret** — use it only in server-side code, never expose it to the browser.

## 4. Database (only if your app stores data)

- Connect via **`process.env.DATABASE_URL`** (a managed Postgres we run). Use the host/port from the string exactly as given — do not point at `localhost`, do not ship a database inside your image.
- **Do NOT use SSL for the database connection.** The link runs inside a private network, so the database does not offer SSL — if your client enables it you get `Error: The server does not support SSL connections` and the app crash-loops. In node-postgres pass `ssl: false` (or omit `ssl`); do not set `sslmode=require`. (Don't assume "managed Postgres ⇒ SSL" — here it's off by design.)
- The **`public` schema ALREADY EXISTS** and you create your tables in it. **Do NOT run `CREATE SCHEMA`** (not even `CREATE SCHEMA IF NOT EXISTS public`): your role is not the database owner/superuser, so it fails with `permission denied for database` and your app crash-loops on boot. Create tables directly:

  ```sql
  CREATE TABLE IF NOT EXISTS public.<name> ( ... );
  ```

  You have full rights **inside `public`** (create tables/indexes, read/write) — run your own migrations there, idempotently, on startup.
- If end-user accounts (auth) are enabled, an **`auth` schema** also appears in your database; it is the platform's and you get read-only (`SELECT`) on it. Keep your own tables in `public`; link a row to a user by the auth `user.id`.

## 5. Disk is ephemeral — persist in the database

- The container filesystem is **scratch space**: every deploy/restart starts from a clean image, and anything written locally is gone. This is by design — the app is **stateless**.
- Anything that must survive goes in your **database** (`DATABASE_URL`): user uploads, application state, records. Do NOT keep data in local files or SQLite — it silently disappears on the next deploy.
- Writing to `/tmp`/caches during the process's life is fine; just never treat the disk as storage.

## 6. Reserved

- The **`/__meta/*`** path prefix on your app's domain is the platform's — served before your app sees the request. Do NOT define routes under it.

## 7. Health (optional)

- If you expose `GET /healthz` → `200`, the platform uses it; otherwise it TCP-checks `:8080`.

## Pre-deploy checklist

- [ ] `Dockerfile` in root; `FROM` + `CMD` starting a long-lived HTTP server.
- [ ] Deps installed with a plain `npm install` (not `npm ci`) — unless you truly generated + committed a real lockfile.
- [ ] Listens on `0.0.0.0` and `process.env.PORT` (8080).
- [ ] Using auth or payments? → the app HAS a server, and those calls run server-side.
- [ ] Has a database? → connects via `DATABASE_URL`; tables created with `CREATE TABLE ... public.*` — **never `CREATE SCHEMA`**.
- [ ] Persistent data lives in the database — nothing important written to local files/SQLite (disk is wiped on every deploy).
- [ ] No secrets committed; every `META_*` used server-side only.
- [ ] No routes under `/__meta/*`.
