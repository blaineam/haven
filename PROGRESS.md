# Haven — Live Progress

A running log of what's built, what's shipping, and what I'm working on right now.
Updated continuously. (Times in your local day.)

---

## 🆕 Latest wave (built, batched for next upload)
- **Group calls**: WebRTC calls went from 1:1 to **full-mesh group** (audio+video, E2EE
  DTLS-SRTP), every participant opening one peer connection to every other; signaling
  (SDP/ICE/invite/accept/hangup) still rides the sealed iroh channel — no call server.
- **VoIP PushKit**: calls ring even from a fully-killed/locked device (CallKit on
  iOS/Catalyst, in-app ringing on native macOS); echo cancellation on by default.
- **Screen share**: macOS via ScreenCaptureKit; iOS via a **ReplayKit broadcast
  extension** (`HavenBroadcast`) piping frames through App Group `group.com.blaineam.kith`.
- **Multi-identity switcher**: keep a roster of every identity you've used and jump
  between them, each with its **own per-identity profile** (name/photo/emoji/bio/link,
  namespaced by node-id). iCloud-Keychain backup/restore of identity history; transfer
  code + QR move-to-device.
- **Invisible Mac relay**: the in-app relay runs in-process (FFI); on macOS, closing the
  window keeps it relaying with **no dock icon** (accessory activation policy).
- **Pre-signed S3 mailbox**: members fetch via scoped pre-signed URLs and never hold the
  bucket credentials.
- **Native-macOS port started**: native-macOS FFI slice (`aarch64-apple-darwin`) added to
  the xcframework and a `HavenMac` target stood up (Phase 0; Catalyst still ships) — see
  `docs/MACOS-NATIVE-PORT.md`. A **native Android** client is also underway in `android/`.
- **Windows/Linux desktop started** (`desktop/`): a **Tauri 2** client — the Rust backend
  links the core *directly* (no UniFFI), the WebView2 UI is the GUI, and the **same binary
  runs headless as the circle relay** (`--headless`), like the invisible Mac relay. Backend
  compiles + unit tests pass; the headless relay is verified end-to-end (identity in the OS
  keychain → iroh node → relay link). GUI covers identity/profile/circles/feed/stories/DMs/
  QR-handshake/media-attach/relay-host. See `docs/WINDOWS-PORT.md`.

## 🚦 Shipping status

- **Live on TestFlight:** build 26
- **Built + committed, batched for next upload (one binary):** build 27
  - 🐛 Crash-on-open fix (panic contained at the Swift-callback boundary)
  - 🎞️ Real media optimization — 1080p video, ≤2560px photos (the toggle was cosmetic before; this is what fixes videos not sending)
  - 📦 Chunked media transfer (512KB sealed chunks → large videos send, flat memory)
  - 🔇 Silent mode · ❤️ double-tap heart · 🔈 tap-to-mute · 👀 see-who-reacted · 🕑 relative timestamps
  - Honest connection status on the You page
- ⏳ Holding uploads ~24h (hit Apple's daily upload limit) — everything below rolls into the same single build.

## ✅ Proven working (device-to-device, user + mom)
Post-quantum E2E identity · invite QR + scanner + verified handshake · **two-way messaging over internet AND nearby Bluetooth/Wi-Fi mesh** · encrypted media · persistence · circle management · retention · Apple Music · scroll-driven playback.

---

## ✅ Multi-circle — DONE (committed, tested)
- [x] Engine: `HavenSocial` holds multiple circles (each its own group / event-log / seen-set)
- [x] Persistence: per-circle state on disk + legacy-format migration
- [x] Wire protocol: Hello/Event carry a circle id; received events route to the right circle
- [x] FeedStore + UI: circle switcher in the feed title, per-circle feed, create circle
- [x] Circle propagation: a Hello for an unknown circle auto-creates it (verified sender), so it forms on their side
- [x] CircleView: add existing contacts to a circle / leave a circle

---

## ✅ Mesh relay (#13) — DONE
Relay frame (type 9): an internet-connected nearby phone forwards a sealed frame it can't read toward its destination (cleartext routing header, E2E payload), re-floods nearby (ttl-bounded), msg-id dedup. Posts + handshakes originate relays.

## ✅ Direct messages (#9) — DONE
A DM = a private 2-person circle (reuses the whole E2E + delivery + mesh stack).
Messages list, contact picker, chat-bubble thread; DMs hidden from the feed switcher.

## ✅ Stories (#10) — DONE
`story` flag on posts (24h retention auto-expiry); stories tray (rings) at the top of the feed; full-screen viewer with progress bars + tap nav.

## ✅ Video mute + trim (#3) — DONE
Attached video chips get a Trim (system editor) + Mute-audio (strip audio track) menu.

## ✅ Notifications (#6) — DONE
Local-only, no server/third party. BGAppRefreshTask wakes → syncs → local notification for anything new; live inbound notifies directly (deduped, foreground-suppressed).

## ✅ Calls, sync & stories overhaul (DONE, builds green)
- **WebRTC calls** (replaces audio-over-iroh): `WebRTCCall` (PeerConnection, DTLS-SRTP E2EE
  media), signaling (SDP + ICE) over the existing sealed channel, STUN for NAT, CallKit UI,
  Metal video views. Audio + video, 1:1. (Device-verify; Catalyst-safe — WebRTC has a
  catalyst slice, call code `#if`'d out.)
- **Push-inline sync** — small sealed events ride *in* the push (`ev`); the NSE stashes them
  in the shared Keychain and the app ingests on next sync — no mailbox round-trip, relay stays
  zero-knowledge. Mailbox is the backstop for media + APNs-coalesced catch-up.
- **Multi-device** — the relay now keeps **multiple device tokens per identity** (was one), so
  every linked device gets pushes; authored events self-sync via a silent push to your own
  devices. "Link a new device" surfaces the transfer-code/QR. (Worker needs redeploy.)
- **Story camera overhaul**: portrait lock, caption controls above the keyboard, pinch-zoom +
  reposition media (framing travels in the spec), per-line highlight + glow/shadow/neon caption
  styles, **multi-clip capture** (90s cap, segment progress bars, review → trash / capture-more
  / share-all), **dual-camera PiP** (front+back via AVCaptureMultiCamSession, chosen corner).

## ✅ This session — profile, circles, links, polish (DONE, builds green)
A batch of UX + privacy features (app + NSE compile clean for the simulator):
- **Profile business card**: name + bio + link, signed & shared E2E (`my_signed_profile`
  now carries a JSON card; `verify_profile_card`, backward-tolerant of legacy name-only).
- **You tab redesign**: it's your profile + posts now; Settings live behind a ⚙️ gear.
  Blocked people moved out of Advanced into regular Settings.
- **Per-circle privacy**: Spotlight indexing and a **Face ID lock** are per-circle (was a
  single global Spotlight toggle). A locked circle is hidden from Spotlight and its push
  notifications are redacted (the NSE reads the locked set from the shared Keychain).
- **Circle settings view** (⚙️ in the circle): rename the circle, privacy toggles, leave.
- **Discover circle members** not in your My Circle, with an Add button; **remove from a
  circle without blocking** (distinct from Block).
- **Links**: post/comment/bio links render as tappable text + native Open Graph preview
  cards, opening an **in-app browser** (address bar, back/forward, reload, open-in-Safari,
  share, close).
- **Link a new device** section (shares the identity via the transfer-code/QR; local
  device-to-device sync is the remaining M2b piece).
- **Polish**: tapping any post toggles global mute (removed the toolbar mute button + the
  Silent-mode setting); compose fields no longer clip multi-line text (rounded rect, not a
  capsule); the now-playing equalizer bars animate when playback starts after the view
  exists (DM song chip); a successful send clears a stale "last send error"; **last seen**
  times persist across launches and update on inbound DMs.

## ✅ Notification Service Extension (#51) — DONE (device-test pending)
Reliable, decrypted push without giving any server our content. The blind Cloudflare relay
forwards a per-recipient **sealed** banner (`e`); the new `HavenNotificationService` extension
opens it on-device — even on the lock screen — via a seed-only FFI (`open_sealed_with_seed`),
reading the master seed from a **shared Keychain access group** (the authoritative seed item
never moves; we mirror a read-only copy). Worker switched from a throttled silent wake to an
**alert + mutable-content** push (no duplicate local banner). Builds green (app + extension,
simulator); live APNs decryption verifies on a physical device + signed extension profile.

## ✅ macOS — DONE (Mac Catalyst)
Same engine + SwiftUI app builds + runs on macOS (Apple Silicon). Added the macabi Rust slice; guarded the one iOS-only API. Mac Catalyst build green.

## ✅ Modern story camera — DONE
Instagram-style: live camera (tap=photo, hold=video, flip, library), then a composer to add a **song** + an easy **caption**, then Share to story. Viewer plays the song while watching.

## ❌ Web client — ABANDONED (native-only)
A browser can't be an iroh peer (no raw UDP / hole-punching), so a web client only works as a
thin client of a *publicly-hosted* relay — not worth it. Dropped 2026-06-22. `web/` is now a
clean **invite-landing / app-promo** page only (opens `haven://` invites in the native app);
the WASM client + `web/engine/` were removed. Android will come as a **native** UniFFI client.

## ✅ Shared circle store (#12) — DONE
seal_bytes/open_bytes group primitive + a real SigV4 S3 client + "Volunteer as tribute": a member keeps a circle-sealed (host can't read) copy of media in their bucket and re-serves it P2P to anyone missing it. No cred sharing.

## ✅ P2P voice calls (#11) — DONE (device-test pending)
CallKit UI + invite/accept/hangup signaling + 16 kHz audio, all over the existing P2P transport — no call server. Call button in DM threads + in-call overlay. Live audio quality needs on-device testing (no mic/CallKit in the simulator); video is the follow-on.

---

## 🎉 The whole backlog is done
Multi-circle · Mesh relay · Direct messages · Stories + modern camera (song + caption) · Video trim/mute · Notifications (blind APNs relay + on-device NSE decrypt) · macOS (Mac Catalyst; native port started) · Shared "volunteer" store + pre-signed mailbox · P2P voice + video + **group** calls + screen share · Multi-identity switcher · Invisible Mac relay.

(The web client was abandoned — a browser can't be an iroh peer; `web/` is now just an invite-landing page.)

Everything builds (iOS + Mac Catalyst), Rust + UI tests green, all committed + pushed.
**Next:** device-test the new features (esp. calls + camera), then batch-upload to App Store Connect once the daily limit resets.

---

## 👀 How to watch progress
- **This file** on GitHub — updated as each box above is checked.
- **Commit feed** — github.com/blaineam/haven — every piece is a pushed commit with a clear message.
- **Task board** in your Claude app — live status of each item.
