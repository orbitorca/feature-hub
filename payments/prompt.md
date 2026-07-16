# Payments — agent prompt

Paste this into the app's coding agent. It wires a managed payments service; the
platform is the broker (keys, webhooks, and the "paid" state live with us). Full
endpoint reference: [`contract.md`](contract.md).

```
You have a managed Payments API at $META_API_URL, authenticated with
  Authorization: Bearer $META_APP_TOKEN
$META_APP_TOKEN is a SECRET: use it ONLY in server-side code, NEVER in the browser, in
client JS, or in any response. Every call below runs on YOUR SERVER — if this app is
static/SPA-only, add a small backend for them first (see ../deploy/contract.md).
Do NOT integrate Stripe directly, do NOT store card data, do NOT build webhooks —
the platform handles all of that.

- See what's for sale (the owner configures products/prices dynamically):
    GET $META_API_URL/products
      -> { "products": [ { "key", "name", "kind", "prices": [ { "id", "amount", "currency", "interval", "tier" } ] } ] }
    Build your pricing page from this; pass a price "id" as "price" in /checkout below.
    NEVER hardcode a price id or product key — read them LIVE from /products every time, on
    EVERY purchase path (one-off buttons AND the subscribe button alike). Any id you saw in
    an example, a catalog snapshot, or a previous run is reference-only and will NOT match at
    runtime — a hardcoded id makes /checkout fail with "Invalid UUID". One code path: fetch
    /products, find the product/price you want by its KEY, use that price's live id.

- Sell something (server-side):
    POST $META_API_URL/checkout   { "price": "<live price-id from /products>", "user": "<your-user-id>" }
    (send an Idempotency-Key header)  ->  { "url": "..." }
    Redirect the buyer to that url (Stripe-hosted checkout).

There are two ways to hand over what was bought. Pick by WHAT you sell:

A) DURABLE access — a subscription/plan, or a one-off product they then own.
   Gate it on the SERVER, never in the browser:
     GET $META_API_URL/paid?user=<your-user-id>&product=<product-KEY>  ->  { "paid": true|false, ... }
   Only serve the paid feature when paid == true. ALWAYS pass product=<KEY>; without it
   /paid means "paid for ANYTHING", so a cheap one-off could unlock a subscription feature.
   Gate on the product KEY, never a price id.
   Server-authoritative means the browser must not be able to reach the paid content on
   its own: do NOT ship the premium code/data to the client and merely hide it in JS —
   withhold it on the server until /paid is true. We compute expiry/renewal/cancellation
   for you (a lapsed/cancelled/past-due subscription returns paid=false); never track time
   yourself.
   Right after the buyer returns from checkout, /paid may still be false for a moment — the
   payment is confirmed by a webhook (the source of truth), which can land a beat after the
   redirect. Don't show a hard "locked / access denied" on return; poll /paid briefly (a few
   times over a few seconds) and show a "confirming your payment…" state until it flips true.
   If the app is CLIENT-RENDERED (a browser game, an SPA) you cannot hide the client code —
   anyone can read it. So don't gate the code; gate the SERVER ACTION or STATE the paid
   thing depends on: saving progress, submitting a score, unlocking a level server-side,
   generating premium content, joining multiplayer. Each such endpoint calls /paid first and
   refuses when false. A paid feature with no server-side action to gate isn't enforceable —
   give it one (e.g. progress/score lives on the server) rather than trusting the browser.

B) CONSUMABLE value that STACKS — credits, coins, gold, extra lives (buying twice = twice
   as much). /paid is binary and can't count, so use the purchase ledger instead:
     GET $META_API_URL/purchases?user=<your-user-id>
       -> { "purchases": [ { "id", "productKey", "kind", "amount", "currency", "createdAt" } ] }
   These are completed, paid purchases from OUR records (not a redirect you could fake).
   Grant each EXACTLY ONCE using the database, so double-polling can't double-credit:
     1) once, create a table:   granted_purchases(id PRIMARY KEY)
     2) for each purchase p returned:
          INSERT INTO granted_purchases(id) VALUES (p.id) ON CONFLICT DO NOTHING
          if that INSERT created a new row -> credit the user. Decide HOW MUCH from
             p.productKey, NOT from p.amount. p.amount is the MONEY paid, in cents — it is
             NOT your unit count; crediting it gives hundreds of units for one small pack.
             Map the KEY to the units you sell: e.g. credits_10 -> +10 credits, gold_large -> +1000 gold.
          otherwise -> already granted, skip
   The PRIMARY KEY is what makes it exactly-once — not your logic. Poll /purchases after the
   buyer returns from checkout and/or on a light interval; there's no push and no rush (a
   missed poll just grants on the next one). Do NOT credit from the checkout redirect.

- Let a subscriber manage billing (change card / cancel), server-side:
    POST $META_API_URL/portal { "user": "..." }  ->  { "url": "..." }  ; link the buyer there.

Notes:
- Treat ANY 2xx as success. POST /checkout answers 201, so an "=== 200" check reads a
  SUCCESSFUL checkout (with the url) as a failure. Use response.ok, not an exact status.
- `user` is YOUR own id for the buyer (email, auth user id, anything). For guest
  checkout, omit it. Use the SAME id everywhere and store it on your own records.
- Business buyers (NIP/VAT number + invoice) are handled at checkout automatically
  when the owner turned that on — you don't add anything.
- To DISPLAY status only (not to gate), GET /entitlement?user=&product= returns
  { status: active|canceled|past_due|expired, currentPeriodEnd, ... } for banners like
  "renews on …" / "payment failed". The gate is always /paid.
```
