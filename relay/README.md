# Kith Bridge — be the always-on home for your circle

A **bridge** keeps your circle's messages flowing even when people aren't online at the
same time. It's a zero-knowledge store-and-forward **mailbox**: every post is uploaded
**sealed** (end-to-end encrypted to the circle), and any member downloads it whenever
*they* come online. The sender and receiver never have to overlap — and the bridge
**cannot read anything**. It only ever holds opaque, circle-sealed blobs.

Because the mailbox speaks the S3 API, "hosting a bridge" just means **running (or
renting) an S3-compatible bucket** and pointing Kith at it. No custom server, no
account on anyone's platform, no plaintext anywhere.

## The easiest way: one command (self-hosted)

Runs MinIO (open-source, S3-compatible) on your machine — a Pi, a NAS, an old laptop,
or a cheap VPS — and prints the exact settings to paste into Kith.

```sh
curl -fsSL https://wemiller.com/apps/kith/bridge/install.sh | sh
# or, from this folder:
sh install.sh            # Docker (any OS)
sh install.sh --native   # native binary (Linux / macOS, no Docker)
```

Or with Docker Compose:

```sh
KITH_BRIDGE_USER=you KITH_BRIDGE_PASSWORD='a-strong-password' docker compose up -d
```

Then in the app: **You → Advanced → Storage → Custom S3 bucket**, paste the endpoint /
bucket / keys, and turn on **“Volunteer as tribute.”** That's it — your bucket is now
the circle's mailbox.

> To let people reach it from outside your home network, expose the port via a router
> port-forward, [Tailscale](https://tailscale.com), or a small VPS. The traffic is
> already sealed, so a plain HTTP endpoint is fine, but HTTPS (a reverse proxy) is nicer.

## The zero-maintenance way: a managed bucket

Don't want to run anything? Use any S3-compatible provider — you still hold the keys,
and the provider only ever sees sealed blobs:

| Provider | Endpoint example | Notes |
|---|---|---|
| **Cloudflare R2** | `<acct>.r2.cloudflarestorage.com` | no egress fees, generous free tier |
| **Backblaze B2** | `s3.us-west-004.backblazeb2.com` | cheap storage |
| **AWS S3** | `s3.amazonaws.com` | the original |
| **MinIO** (self-host) | `your-host:9000` | the install script above |

Create a bucket, make an access key, paste into Kith, enable "Volunteer as tribute."

## Want full decentralization? IPFS

You can back the mailbox with **IPFS** instead of a bucket: sealed blobs are pinned and
addressed by CID, and members fetch by CID even when the poster is offline — as long as
something keeps them pinned (your own IPFS node here, or a pinning service like
web3.storage / Pinata). It's the most "no-company-storage" option; it's also heavier and
slower than S3, so it's offered as an alternative backend rather than the default.
*(IPFS backend: in progress.)*

## Why this is safe

- **The bridge never sees your messages.** Everything is sealed to the circle with hybrid
  post-quantum crypto before it leaves a device. The bucket stores ciphertext only.
- **No Kith server.** This is *your* bucket (or your friend's). We host nothing.
- **Keys stay on-device.** Your S3 credentials live only in your device Keychain.
- **Revocable.** Block or remove a member and rotate the bucket key any time.

## How it fits together

```
  you ──post(sealed)──▶  bucket/mailbox/<circle>/<hash>  ◀──poll+get──  mom (later, offline-friendly)
        (S3 / R2 / B2 / MinIO / IPFS)   ← bridge holds only ciphertext
```

Every Kith client (iPhone, Mac, web) can both **write** to and **poll** the mailbox, so
any always-on device — even a browser tab left open — can be the bridge for its people.
