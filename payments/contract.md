# Payments — HTTP contract

Managed payments (Stripe Connect broker). The app calls these; the platform holds the
keys, receives the webhooks, and owns the "paid" state — the app never touches Stripe.

- **Base:** `META_API_URL` (injected). **Auth:** `Authorization: Bearer ${META_APP_TOKEN}`.
- Money is the currency's minor unit (cents). Amounts/prices are configured by the owner
  in the dashboard; the app references a **price key**.

## Two questions the app can ask

The app never stores payment state itself — it reads it from us. There are exactly two reads:

1. **"Does this buyer have access right now?"** → `GET /paid`. For DURABLE things: a
   subscription that's active, or a one-off product they own. Binary, server-computed.
2. **"What did this buyer just buy that I still need to hand out?"** → `GET /purchases`.
   For CONSUMABLE things that stack: credits, coins, gold, extra lives. A ledger you drain.

Pick by the thing you sell, not by how you built the app.

## GET /products
The catalog the owner configured — call this to render pricing **dynamically**; the app
never hardcodes prices. Returns active products, each with its prices.

- Response: `{ "products": [ { "key": "pro", "name": "Pro", "kind": "one_time"|"subscription", "prices": [ { "key": "<price-key>", "amount": 1999, "currency": "usd", "interval": "month"|"year"|null, "trialDays": 14|null, "tier": "pro"|null } ] } ] }`
- Use a price `key` as the `price` in `POST /checkout`. It's stable across owner edits, so it's safe to keep in your code.

```bash
curl -s "$META_API_URL/products" -H "Authorization: Bearer $META_APP_TOKEN"
```

## POST /checkout
Start a Stripe-hosted checkout and get a redirect URL.

- Body: `{ "price": "<price-key from GET /products>", "user": "<buyer-id, optional>" }`
- Headers: `Idempotency-Key: <uuid>` (retry-safe — a repeat key returns the same session).
- Response: `{ "url": "https://checkout.stripe.com/…" }` → redirect the buyer.
- `user` = the app's own buyer id (email / auth id / guest token). Omit for guest checkout.

- The buyer's return URLs are set by the platform (your app's own domain) — you send nothing.

```bash
# price = a price "key" from GET /products (a price key, NOT the product key)
curl -sX POST "$META_API_URL/checkout" \
  -H "Authorization: Bearer $META_APP_TOKEN" \
  -H "Idempotency-Key: $(uuidgen)" \
  -H "Content-Type: application/json" \
  -d '{"price":"pro-9f2a1c3d","user":"user_123"}'
```

## GET /paid
The gate for DURABLE access (subscriptions, owned one-offs). Reads platform state (no
Stripe call) — fast enough for every request.

- Query: `?user=<buyer-id>&product=<optional-product-key>`
- Response: `{ "paid": true|false, "kind": "one_time"|"subscription"|null, "tier": "…"|null, "currentPeriodEnd": "<iso>"|null }`
- **Check on the server. Never trust the client.** Always pass `product=<KEY>`; without it
  `paid` means "paid for ANYTHING", so a cheap one-off could unlock a subscription feature.
- The platform computes expiry/renewal/cancellation — a lapsed, cancelled or past-due
  subscription returns `paid=false`, so the app never tracks time itself.

```bash
curl -s "$META_API_URL/paid?user=user_123&product=pro" -H "Authorization: Bearer $META_APP_TOKEN"
```

## GET /purchases
The ledger for CONSUMABLE value (credits, coins, gold, lives — anything that stacks per
purchase). Returns the buyer's completed, paid purchases from OUR records (webhook-sourced,
never a redirect) — newest first. Poll it; the platform pushes nothing.

- Query: `?user=<buyer-id>&since=<optional iso timestamp>`
- Response: `{ "purchases": [ { "id": "<uuid>", "productKey": "gold_large"|null, "kind": "one_time"|"subscription", "amount": 1999, "currency": "usd", "createdAt": "<iso>" } ] }`
- Each `id` is a **stable, unique** purchase id — it's the key that makes crediting exactly-once.

**Grant each purchase exactly once (the whole trick).** Keep a tiny table keyed on that
`id`; insert-if-new; apply the effect ONLY when the insert created a row. The database's
uniqueness — not your code — guarantees a purchase is never double-credited, even if you
poll twice, redirect twice, or run two servers.

```sql
CREATE TABLE granted_purchases (id TEXT PRIMARY KEY);   -- once, at setup
```

```
for each p in GET /purchases?user=<id>:
    inserted = INSERT INTO granted_purchases (id) VALUES (p.id) ON CONFLICT DO NOTHING
    if inserted:                      # first time we've seen this purchase
        # decide how much from p.productKey, NOT p.amount (p.amount is the MONEY paid, in cents).
        # YOU own the map — keep a lookup { productKey: units } in your app; don't parse the key name.
        credit the user by mapping p.productKey → your units (e.g. { gold_large: 1000, credits_10: 10 })
    # else: already granted — do nothing
```

```bash
curl -s "$META_API_URL/purchases?user=user_123" -H "Authorization: Bearer $META_APP_TOKEN"
```

When to poll: right after the buyer returns from checkout, and/or on a light interval /
next request. `since` lets you fetch only what's new. There's no rush — a purchase stays in
the feed, so a missed poll just grants on the next one.

## POST /portal
Stripe billing portal for a subscriber to change card / cancel (hosted on the owner's account).
- Body: `{ "user": "<buyer-id>" }` → `{ "url": "…" }` → redirect the subscriber there.
- Subscription-only: a buyer who never subscribed returns **404 `NO_BILLING_CUSTOMER`** (nothing to manage).

## Mapping rules (any language/framework)
- **Paywall = a server-side guard.** Before serving a paid feature, call `GET /paid` with the
  logged-in buyer's id; render/allow only when `paid == true`. In a web framework this is a
  middleware/decorator on the protected route.
- **Consumables = drain `GET /purchases` with the insert-if-new table above.** Never credit
  from a checkout redirect or a client call — only from the server-side feed.
- **Buy button → `/checkout` → redirect.** Never render Stripe Elements or collect card data.
- **Store the platform's `user` value** (whatever you pass) as the buyer key on your own records.

## B2B (NIP / VAT + invoice)
When the owner enabled business purchases, `/checkout` automatically collects the buyer's
tax id (NIP/VAT — Stripe auto-detects the type from the number + billing country), collects a
billing address, and issues an invoice. **The app does nothing extra** — it's a checkout-level
setting, not an API change.

## Errors
HTTP 4xx/5xx with `{ "error": { "code": "APP_ERROR.PAYMENTS.<CODE>", "message": "…" } }`.
Common: `ACCOUNT_NOT_READY` (owner hasn't finished Stripe onboarding), `PRICE_NOT_FOUND`,
`PRODUCT_NOT_FOUND`, `NO_BILLING_CUSTOMER` (/portal for a non-subscriber). A bad/expired
`META_APP_TOKEN` returns **401 Unauthorized**.

## GET /entitlement (optional, display-only)
Same query as `/paid`, but a richer read for showing status text — never for gating.
- Response: `{ "status": "active"|"canceled"|"past_due"|"expired"|null, "kind": …, "tier": …, "currentPeriodEnd": … }`
- Use it only to render a banner ("renews on …", "payment failed"). The gate is always `/paid`.

## Changelog
- _unreleased_ — `GET /products`, `POST /checkout` (one-off + subscription,
  Idempotency-Key, B2B), `GET /paid` (durable gate), `GET /purchases` (consumables ledger,
  exactly-once via a caller-side insert-if-new table), `POST /portal`, `GET /entitlement`
  (display-only). `/checkout` takes a price **key** (stable across owner edits); return URLs are platform-set.
