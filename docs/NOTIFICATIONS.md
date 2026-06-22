# Notifications: reliable, safe, and as decentralized as iOS allows

## Why background fetch doesn't work (and never really will)

`BGAppRefreshTask` is **best-effort and iOS-controlled** — the system decides if/when to run
it based on usage, battery, and Low Power Mode, and for many users it runs rarely or never.
There is no way to make it reliable. The **only** mechanism that reliably wakes a killed iOS
app is **APNs push**. So reliable notifications require *some* server that can send a push.

## The design: a "blind" push relay (zero-knowledge content)

We can keep it safe and minimal even though a server is involved — the same model Signal/
WhatsApp use:

1. Each device registers its **APNs device token** ↔ its **Haven node id** (pseudonymous)
   with a tiny relay. No name, email, or content — just `token ↔ nodeId`.
2. When a message/post is authored for an offline recipient, the **sender (or the mailbox)**
   asks the relay: *"wake node Z with this sealed blob."*
3. The relay sends an APNs push with `mutable-content: 1` and the **encrypted** blob.
4. The recipient's **Notification Service Extension (NSE)** decrypts it on-device and writes
   the real notification text. The relay only ever moves **ciphertext**.

The relay sees: device tokens, timing, and recipient node ids (metadata) — **never content**.
That's the honest limit: iOS push *cannot* be fully decentralized (Apple is the gatekeeper;
only the holder of the app's APNs key can send). But content stays E2E, and **we** run the
relay, not a third-party SDK like OneSignal.

## Hosting: cheapest + scales instantly → **Cloudflare Workers**

APNs itself is **free** (Apple doesn't charge per push). The only cost is the thing that
*sends* the push. Ranked for "cheap + scales easily and quickly":

| Option | Cost | Scale | Notes |
|---|---|---|---|
| **Cloudflare Workers** ✅ | **Free** to 100k req/day; **$5/mo** = 10M req | Instant, global edge, zero servers | Mint the APNs **ES256 JWT** with WebCrypto from the `.p8` key; `fetch()` to `api.push.apple.com` over HTTP/2. Store `token↔nodeId` in **Workers KV** (free tier) or **D1**. |
| Fly.io / Render / Railway | ~$0–5/mo tiny container | Manual-ish | A small Node/Rust service; simplest mental model, but you manage a process. |
| AWS Lambda + API GW + DynamoDB | pay-per-call, ~free at low vol | Auto | More moving parts + cold starts. |
| A $5 VPS | $5/mo | You scale it | Simplest to write, doesn't auto-scale. |

**Recommendation: Cloudflare Workers.** A circle-scale app fits the **free tier**; if it ever
grows, **$5/mo handles 10M pushes**. No server to babysit, global, scales automatically. Use
**token auth** (one `.p8` AuthKey works for all your apps; JWT valid ~1h, cache it in the
Worker).

### Worker shape (sketch)
- `POST /register { nodeId, token, env }` → KV `put(nodeId, {token,env})`
- `POST /notify  { nodeId, ciphertext }` → look up token → sign JWT (ES256, `.p8`) → `fetch`
  `https://api.push.apple.com/3/device/<token>` with `apns-push-type: alert`,
  `apns-topic: com.blaineam.kith`, body `{ aps:{ "mutable-content":1, alert:{...stub...} }, e:<ciphertext> }`
- Rotate/cache the JWT; nothing is logged.

## App side (the work in Haven)
1. **Add a Notification Service Extension target** — decrypts `e` against the circle/contact
   keys (reuse the Rust core via the same XCFramework) and rewrites the alert body.
2. **Register for remote notifications**, send `deviceToken ↔ myNodeId` to the Worker `/register`.
3. **On send to an offline peer**, call `/notify` (the mailbox upload path is the natural place).
4. Keep local-notifications + the (now crash-fixed) background refresh as a fallback.

## Decision status
This is **#51** — previously parked. Given background fetch is confirmed unworkable, this is
now the recommended path: **self-run Cloudflare Worker + NSE, encrypted payloads.** Cost ≈ $0
to start, $5/mo at real scale. Not fully decentralized (impossible on iOS), but zero-knowledge
on content and operated by us, not a vendor.
