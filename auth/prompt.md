# Auth — agent prompt

Paste this into the app's coding agent. It wires a managed authentication service that
runs beside the app; the app never hashes passwords or signs tokens. Full endpoint
reference: [`contract.md`](contract.md).

Unlike the other features, auth uses **no** `META_API_URL` and **no** `META_APP_TOKEN` —
the bearer token on these calls belongs to the app's end-user.

```
You have a managed Auth service for this app's end-users.
Two base URLs — do NOT hardcode either:
  - from SERVER code:  $META_AUTH_URL   (injected env var)
  - from the BROWSER:  /__meta/auth     (relative, on this app's own domain)
Do NOT hash passwords, do NOT create a users table, do NOT sign or verify JWTs yourself.

- Register:
    POST /signup   {"email","password"}  ->  200
    The account is INACTIVE until the user confirms their address. The platform sends
    that email. Tell the user to check their inbox; do not log them in yet.

- Log in (note: it is /token with a query param, there is no /login):
    POST /token?grant_type=password   {"email","password"}
      ->  200 { "access_token", "refresh_token", "expires_in" }
    The access_token EXPIRES after ~1h. You MUST implement refresh — skip it and EVERY user is
    silently logged out an hour after logging in. Keep the refresh_token. When a protected call
    starts returning 403 (the token expired), get a fresh pair:
      POST /token?grant_type=refresh_token   {"refresh_token"}  ->  200 { access_token, refresh_token }
    Store the NEW refresh_token, retry once. If the refresh itself is not 200, the session is
    over — clear the stored tokens and send the user back to log in. Don't leave them stuck.

- Protect a route (ALWAYS on the server):
    GET $META_AUTH_URL/user   with the caller's  Authorization: Bearer <access_token>
      ->  200 = valid; the body is the user.
    ANY other status = reject the request. An invalid token answers 403, NOT 401 —
    never test for 401 specifically, test for "not 200".
    Store user.id as the owner of every record this user creates.

- Password reset:
    POST /recover   {"email"}  ->  200 always, even for an unknown address (do not leak
    which emails exist). Show the same "check your inbox" message either way.

- The emailed link (confirmation AND reset) sends the user to your HOME PAGE with the
  session in the URL FRAGMENT, which never reaches your server:
      https://your-app.example.com/#access_token=...&refresh_token=...&type=recovery
  The fragment fields are named `access_token`, `refresh_token` and `type` — NOT `token`.
  Read `access_token`; a `token` param does not exist, and reading it makes the emailed link
  silently do nothing, breaking BOTH confirmation and password reset.
  On page load, parse window.location.hash (strip "#", then URLSearchParams):
    type=signup    -> address confirmed; store the session and log the user in.
    type=recovery  -> show a "set a new password" form, then
                      PUT /__meta/auth/user   Authorization: Bearer <access_token from the fragment>
                      {"password": "<new password>"}
  Then clear the fragment with history.replaceState so the token does not linger.

- Changing an address: PUT /user {"email"} mails BOTH the old and the new address; the
  change lands only when both are confirmed.

Reserved by the platform: the `/__meta/*` path prefix on this app's domain, the `auth`
schema in this app's database (you get SELECT on it — keep your own tables in `public`),
and the env vars PORT, DATABASE_URL and anything starting with META_.

Verify before finishing:
  1. POST /signup with a new address -> 200, and an email arrives.
  2. POST /token?grant_type=password BEFORE confirming -> not 200.
  3. Click the emailed link -> the home page reads the fragment -> login now returns a token.
  4. A protected route with a garbage token -> your server rejects it.
```
