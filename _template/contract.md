# <Feature> — HTTP contract

One-line description of what the feature does and what the platform brokers on the app's behalf.

- **Base:** `META_API_URL` (injected). **Auth:** `Authorization: Bearer ${META_APP_TOKEN}`.

> Status: target contract (implemented by the backend `<feature>` feature).

## <METHOD> /<path>
What it does.

- Body / Query: `{ … }`
- Headers: `Idempotency-Key` (on mutating POSTs)
- Response: `{ … }`

```bash
curl -sX <METHOD> "$META_API_URL/<path>" \
  -H "Authorization: Bearer $META_APP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ ... }'
```

## Mapping rules (any language/framework)
- <how the agent should wire this into a typical app: middleware, redirect, etc.>

## Errors
HTTP 4xx/5xx with `{ "error": { "code": "APP_ERROR.<DOMAIN>.<CODE>", "message": "…" } }`.

## Changelog
- _unreleased_ — initial skeleton.
