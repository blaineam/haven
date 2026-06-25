# Group keying — access revocation + forward secrecy (PQ-preserving)

Status: **in progress** (increment 1 — core `groupkey` module landed + tested). This refines decision
**D3** (which named classical MLS) with a post-quantum-preserving design.

## Why not classical MLS (`mls-rs`)

The 2026-06 security audit found two structural gaps in the original "seal every event to each
recipient with the hybrid KEM" scheme (`social.rs`):

1. **No access revocation** — a removed/blocked member keeps the ability to decrypt content posted
   *after* their removal (every event is wrapped to their static KEM key; nothing rotates).
2. **No forward secrecy** — content keys wrap to long-term static KEM keys, so one seed compromise
   decrypts all history.

Classical MLS (RFC 9420, `mls-rs`) fixes both — but at two costs that are unacceptable for Haven:

- **It is not post-quantum.** MLS's standard ciphersuites are X25519/Ed25519/AES. Adopting it would
  *drop* the hybrid X25519+ML-KEM-768 / Ed25519+ML-DSA property that is Haven's headline guarantee
  ("harvest now, decrypt later" resistance). PQ-MLS is still research-stage.
- **It assumes ordered handshake delivery.** MLS epochs advance via Commits that every member must
  apply in order. Haven is **offline-first and eventually-consistent**: posts and key material gossip
  over iroh + relays + S3 mailboxes, arrive out of order, and a member can be offline for days. A
  strict per-message ratchet (TreeKEM) breaks under that delivery model.

## The design: epoch group keys distributed via the hybrid KEM ("circle ratchet")

This is the well-understood *sender-keys-with-rekey-on-membership-change* construction (the pre-MLS
WhatsApp/Signal-group approach), adapted to carry the epoch key over Haven's **hybrid PQ KEM** so the
post-quantum property is preserved end to end.

- Each circle has an ordered sequence of **epochs**. Epoch *E* has a random 32-byte `epoch_key`.
- A **KeyCommit** is a signed envelope that seals the epoch key to a specific member set, wrapping it
  per-recipient via the existing hybrid KEM (`encapsulate_to` → X25519+ML-KEM-768, AES-256-GCM). It
  carries `circle_id` + `epoch` in its authenticated payload. This is the *only* place the per-recipient
  KEM wrap is still used — once per epoch, not once per event.
- **Events** (posts/messages/media/comments/reactions/…) are sealed with a per-event key derived from
  the current epoch key: `event_key = HKDF(salt = epoch_key, ikm = event_id, info = "haven-event-key-v1")`,
  then AES-256-GCM, and hybrid-signed by the author. The envelope carries `circle_id` + `epoch` +
  ciphertext + signature — **no per-recipient wrapping**, so it is true group encryption and smaller.

### Membership change → new epoch (this is what gives revocation)

On **add** or **remove/block**, the actor (any current member; conflicts resolve by highest-epoch-then-
lowest-committer-id) generates a fresh random `epoch_key`, bumps the epoch number, and emits a KeyCommit
sealing it to the **new** member set:

- **Remove/block:** the removed node is not in the recipient set → never receives the new `epoch_key`
  → cannot derive any `event_key` for the new (or any later) epoch. Revocation is **cryptographic**,
  not advisory. (Their access to *already-delivered* past-epoch content cannot be retroactively pulled —
  that is inherent to E2EE and is documented as such.)
- **Add:** the new member is in the recipient set → gets the current `epoch_key` forward. Whether they
  also receive *past* epochs is exactly the existing **"Add & share history" vs "new posts only"**
  choice: share-history re-seals prior epoch keys to them; new-posts-only does not.

### Forward secrecy (bounded, by design)

True per-message FS (Double Ratchet) is incompatible with multi-recipient, offline, eventually-consistent
delivery. Instead:

- Epoch keys rotate on every membership change **and** on a periodic schedule (time/-volume based).
- Clients **delete** epoch keys older than the circle's retention window. A seed/device compromise then
  reveals only the *current* epoch plus retained-history epochs — not all history forever.

This is "bounded forward secrecy": strictly stronger than today (which has none), and the strongest the
delivery model admits without breaking offline use.

## Properties

| Property | Old (per-recipient static) | New (epoch group keys) |
|---|---|---|
| Post-quantum (hybrid) | ✅ | ✅ (KEM still wraps epoch keys) |
| Sender authentication | ✅ (hybrid sig) | ✅ (hybrid sig per event + per commit) |
| Access revocation on remove | ❌ | ✅ cryptographic (new epoch excludes them) |
| Forward secrecy | ❌ | ✅ bounded (rotation + retention-bounded deletion) |
| Offline / eventually-consistent | ✅ | ✅ (epochs are content-addressed, order-independent within an epoch) |
| Envelope size | O(members) per event | O(1) per event; O(members) once per epoch |

## Rollout (increments)

1. **Core `groupkey` module + tests** ← *this increment.* Epoch-key generation, KeyCommit seal/open
   (revocation proven by test), per-event key derivation, seal/open-under-epoch. Additive; nothing wired
   yet, so existing behavior is unchanged.
2. **Engine integration** (`p2pcore-ffi`): per-circle epoch-key store; `create_circle`/`add`/`remove`/
   `block` emit KeyCommits + rotate; `post`/`receive` use epoch sealing; history-share re-seals epochs.
3. **Wire/migration:** envelopes gain a version tag; circles bootstrap epoch 0 on first post under the
   new scheme; old envelopes still open (read-path compatibility) during migration.
4. **FFI + platforms:** the FFI surface change (if any) flows to iOS/macOS/Android/desktop — most call
   sites are unchanged because the engine hides epochs; new surface only for "rotate now".
5. **Relay:** unaffected (still ciphertext-only); KeyCommits ride the same transports as events.
6. **FS scheduling + retention-bounded key deletion**, then remove the legacy per-recipient event path.

## Test obligations (per increment)

- Revocation: a removed member cannot open a post sealed under the post-removal epoch (proven in #1).
- Add semantics: a new member opens current-epoch content; only sees history when history was shared.
- Round-trip: every member opens every same-epoch event; tamper/forgery rejected (GCM + signature).
- Offline: events from an epoch open regardless of arrival order, with or without later epochs present.
- Migration: a feed mixing legacy + epoch envelopes reduces correctly.
