# <Feature> — agent prompt

Paste this into the app's coding agent. Keep it short and imperative — it wires HTTP
calls to a managed service; the platform is the broker. Full reference: [`contract.md`](contract.md).

```
You have a managed <Feature> API at $META_API_URL, authenticated with
  Authorization: Bearer $META_APP_TOKEN
Wire these HTTP calls. Do NOT integrate the provider directly, do NOT store secrets,
do NOT build webhooks — the platform handles all of that.

- <Action>:
    <METHOD> $META_API_URL/<path>  { ... }  ->  { ... }
    <one line on what to do with the result>
```
