# Auth — HTTP contract

Managed user accounts for the app's **end-users**. The auth service runs inside the app's
own container group and stores its users in the app's own database. The app never hashes a
password, signs a token, or creates a users table.

> **This feature does not follow the hub's default conventions.** There is no
> `META_API_URL` and no `META_APP_TOKEN`: auth is not brokered through the platform, it
> runs next to the app. The bearer token on these calls is the **end-user's**, not the app's.

## Two base URLs — pick by who is calling

| Caller | Base | Why |
|---|---|---|
| The app's **server** code | `$META_AUTH_URL` (injected env var) | a private loopback address inside the app's container group |
| The **browser** (your frontend) | `/__meta/auth` — relative, on the app's own domain | `META_AUTH_URL` is not reachable from outside the group |

Paths below are shown without a base. Prepend whichever applies. Send
`Content-Type: application/json` on every POST/PUT.

## POST /signup
Creates an account. The account is **inactive** until the user confirms their address —
the platform sends that email, the app sends nothing.

- Body: `{ "email": "...", "password": "..." }`
- Response: `200` with the created user.

```bash
curl -sX POST "$META_AUTH_URL/signup" \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"..."}'
```

## POST /token?grant_type=password
Logs a **confirmed** user in. Note the query parameter — there is no `/login`.

- Body: `{ "email": "...", "password": "..." }`
- Response: `200` `{ "access_token": "...", "refresh_token": "...", "expires_in": 3600 }`
- An unconfirmed account does **not** return `200`.

```bash
curl -sX POST "$META_AUTH_URL/token?grant_type=password" \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"..."}'
```

## POST /token?grant_type=refresh_token
The `access_token` expires after `expires_in` seconds (≈1h). Keep the `refresh_token` from
login and exchange it for a fresh pair — you never re-ask for the password.

- Body: `{ "refresh_token": "..." }`
- Response: `200` `{ "access_token": "...", "refresh_token": "...", "expires_in": 3600 }` — a NEW
  refresh token too; store it and discard the old one.
- Anything other than `200` (expired/rotated refresh token) → the session is over; send the
  user back to log in.

```bash
curl -sX POST "$META_AUTH_URL/token?grant_type=refresh_token" \
  -H "Content-Type: application/json" \
  -d '{"refresh_token":"..."}'
```

## GET /user — this is how you validate a token
There is **no** token-introspection endpoint. To check an incoming
`Authorization: Bearer <access_token>`, replay it against `/user`:

- `200` → the token is valid; the body is the user. Read the field named `id` (a stable UUID) —
  it is `id`, not `sub` — and use it as the owner of the app's own rows:
  `{ "id": "<uuid>", "email": "user@example.com", "role": "authenticated", ... }`.
- **Any other status → reject.** An invalid token answers **`403`**, not `401`, so never
  test for `401` specifically.

Do this on the **server**. Never trust a token you only decoded client-side.

```bash
curl -s "$META_AUTH_URL/user" -H "Authorization: Bearer $ACCESS_TOKEN"
```

## PUT /user
Updates the signed-in user. `{"password":"..."}` takes effect immediately.
`{"email":"..."}` starts an email change: the platform mails **both** the old and the new
address, and the change lands only once both are confirmed.

```bash
curl -sX PUT "$META_AUTH_URL/user" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"password":"new-password"}'
```

## POST /recover
Starts a password reset. **Always answers `200`**, even for an address with no account —
so the app cannot be used to discover which emails are registered. Show the same
"check your inbox" message either way.

- Body: `{ "email": "..." }`

```bash
curl -sX POST "$META_AUTH_URL/recover" \
  -H "Content-Type: application/json" -d '{"email":"user@example.com"}'
```

## The emailed link — the session comes back in the URL **fragment**

Every email the platform sends (confirmation, password reset, email change) contains a
link. When the user clicks it, the auth service redirects (`303`) to the app's **home
page** with the session in the URL fragment:

```
https://your-app.example.com/#access_token=eyJ...&refresh_token=...&expires_in=3600&type=recovery
```

A fragment is **never sent to the server**. The app must read it in the browser:

1. On page load, take `window.location.hash`, strip the leading `#`, parse it with
   `URLSearchParams`.
2. `type=signup` → the address is confirmed. Store the session; the user is logged in.
3. `type=recovery` → show a "set a new password" form, then call
   `PUT /__meta/auth/user` with `Authorization: Bearer <access_token from the fragment>`
   and body `{"password":"..."}`.
4. `type=email_change` → the address is confirmed. The change completes when the other
   mailbox confirms too.
5. Clear the fragment afterwards (`history.replaceState`) so the token does not linger in
   the address bar or in `document.referrer`.

An app that looks for a query string instead of a fragment will silently break every
password reset: the user lands on the home page and nothing happens.

## Mapping rules (any language/framework)
- **Protect a route:** read `Authorization`, call `GET /user` with it from the server,
  serve only on `200`. Store `user.id` as a foreign key on the app's rows.
- **Sign-up flow:** `POST /signup` → tell the user to check their inbox. Do not log them
  in; login fails until they confirm.
- **Reset flow:** a form that calls `POST /recover` → the "check your inbox" message →
  the fragment handler above.
- **Never** write a `users` table, hash a password, or verify a JWT yourself.
- The app's database gets a schema named `auth`, owned by the auth service. The app has
  `SELECT` on it (join your rows to `auth.users` by `user_id`) and nothing more. Keep the
  app's own tables and migrations in `public`.
- `/__meta/*` on the app's domain belongs to the platform. Do not define routes there.

## Errors
Non-2xx responses carry the auth service's own JSON body. Do **not** branch on its error
strings — they are not part of any stability promise. Branch on the status code:
`200` = success, anything else = failure. A bad or expired end-user token gives `403`.

Enabling the feature can fail from the dashboard with
`{ "error": { "code": "APP_ERROR.APP_AUTH.<CODE>" } }`: `DATABASE_REQUIRED` (the app
declared no database), `DATABASE_NOT_READY` (deploy the app once first), `NOT_AVAILABLE`
(the platform environment has no auth image configured).

## Changelog
- 2026-07-10 — initial contract. `POST /signup`, `POST /token?grant_type=password`,
  `POST /recover`, `GET /user` (validation: `200` = valid, `403` = invalid), `PUT /user`.
  Emailed links redirect to the app root with the session in the URL fragment.
