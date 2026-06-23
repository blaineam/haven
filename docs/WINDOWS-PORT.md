# Windows (and Linux) desktop port — Tauri 2

**Goal:** ship Haven on Windows as a real native client at **feature parity with iOS** —
a GUI app *and* a headless relay, exactly like the macOS target is meant to be — built on
the **same Rust core** the iPhone and Android apps use.

**Stack:** [Tauri 2](https://tauri.app) (Rust backend + WebView2 frontend). Chosen because:

- The backend is Rust, so it links the shared core (`haven_ffi`, which re-exports
  `p2pcore` + `haven-net`) **directly as a crate — no UniFFI hop**. The iroh peer runs in
  the native process, not the browser, so the "a browser can't be an iroh peer" problem
  that killed the web client (see [`WEB-PARITY.md`](WEB-PARITY.md)) does **not** apply here.
- WebView2 (Edge/Chromium) gives camera (`getUserMedia`), WebRTC, `<video>`/`<audio>`, and
  an in-app browser for free — the media-heavy parity features that would fight a
  pure-native or immediate-mode GUI.
- One binary doubles as the **headless relay/mailbox** (`--headless`), like the invisible
  Mac relay.
- Packages to **MSIX/MSI/NSIS** for the Microsoft Store (the $10 one-time, zero-recurring
  distribution mandate), and gives a Linux build (AppImage/deb) nearly for free later.

> The Rust core is platform-agnostic; nothing in `core/` changes for Windows. This is a
> **UI + platform-glue** project, the same shape as the Android port.

## Layout

```
desktop/
  src-tauri/            Rust backend (the "FeedStore"/"HavenNet" equivalent)
    src/
      main.rs           entry; --headless → relay, else GUI
      lib.rs            Tauri builder + run_headless()
      wire.rs           byte-exact port of the Wire protocol (interop with iOS/Android)
      engine.rs         port of Android HavenNet.kt: HavenSocial + HavenNode, handshake,
                        persistence, mailbox poll, relay hosting, media chunks
      store.rs          seed in the OS secure store (Credential Manager / Keychain /
                        Secret Service) + prefs.json + state blob
      localmedia.rs     content-addressed, sealed-at-rest media store
      commands.rs       the invoke() surface the WebView calls
    tauri.conf.json     window + bundle (msi/nsis) config
    icons/              brand icon set (make_icons.py)
  ui/                   static WebView2 frontend (no bundler)
    index.html  styles.css  app.js
    vendor/             qrcode.js (QR show) + jsQR.js (camera scan)
```

## Build / run (dev, on any OS)

```bash
# one-time
cargo install tauri-cli --version '^2'

cd desktop/src-tauri
cargo tauri dev          # launches the GUI (native WebView)
cargo run -- --headless  # runs ONLY the relay, prints a relay node id to share
```

`cargo tauri dev` works on macOS/Linux too (native WebView), so the whole UI + core
integration is developed and verified locally, then cross-built for Windows.

## Build (Windows artifact)

- **On Windows:** `cargo tauri build` → `.msi` + NSIS `.exe` in `target/release/bundle/`.
  Add an `msix` target for Store submission.
- **Cross from macOS/Linux:** `cargo tauri build --target x86_64-pc-windows-msvc` via
  [`cargo-xwin`], or a Windows CI runner (preferred for signing + MSIX).

## Parity table (iOS → Windows/Tauri)

| iOS feature | Windows approach | Status |
|---|---|---|
| Crypto / identity / circles / feed reducer | Same `haven_ffi` crate, linked directly | **Done** — identical engine |
| iroh P2P transport + mesh relay | Same `haven-net` crate (native) | **Done** |
| Wire protocol (Hello/Event/MediaReq/Chunk/Relay) | `wire.rs`, byte-exact | **Done** (Hello/Event/Media wired; call frames reserved) |
| Keychain key storage | OS secure store via `keyring` (Credential Manager) | **Done** |
| Persistence + multi-circle + DMs | `engine.rs` + `store.rs` | **Done** |
| Posts / comments / reactions / edit / unsend | commands + feed reducer | **Done** |
| Stories (24h) | story flag + viewer | **Done** |
| QR invite show + camera scan + verified handshake | `qrcode.js` + `jsQR` + WebView camera | **Done** |
| Photo/video attach + inline render | HTML file pick → downscale → sealed local store → `data:` URL | **Done** (image downscale in JS; video transcode TODO) |
| Circle relay / mailbox (host + adopt) + offline delivery | `RelayServerHandle` in-process + `RelayClient`; `--headless` | **Done** |
| Cross-device media bytes (frame 3/5 chunks) | ported in `engine.rs` | **Done** (device-test pending) |
| Local notifications | Tauri event → toast; native toast/tray TODO | **Partial** |
| Apple Music | portable track refs + deep-link (no inline catalog playback) | **Redesign** — same as Android |
| Audio/video/group calls (WebRTC) | WebView2 `RTCPeerConnection`; signaling over the sealed iroh channel (frames 10–18) | **TODO** (Wave) |
| Screen share | WebRTC `getDisplayMedia` | **TODO** |
| Sensitive content blur | per-circle `flag_sensitive` (already in core); no on-device classifier | **Partial** |
| S3 BYO-bucket / pre-signed pool | move SigV4 into the core (shared) then expose | **TODO** (parity with Android step 3) |
| Nearby offline mesh | no desktop equivalent of MultipeerConnectivity; later via local mDNS/BLE | **Deferred** |
| Push (APNs/FCM) | n/a — desktop stays running; headless relay covers offline | **n/a** |

## Remaining milestones (recommended order)

1. **Compile + run green** on the host, verify identity/feed/QR/relay round-trips.
2. **Cross-device interop test**: Windows ↔ iPhone ↔ Android text post + DM over iroh.
3. **WebRTC calls** in WebView2 (audio → video → group), signaling over frames 10–18.
4. **Native notifications + tray menu** (quit/relay toggle) — the proper background relay.
5. **Shared SigV4 mailbox in the core** (retires per-platform S3 clients; helps all clients).
6. **MSIX packaging + code signing + Microsoft Store** submission.
7. **Linux build** (AppImage/deb) — nearly free from the same crate.

## Notes / gotchas

- `windows_subsystem = "windows"` is intentionally **not** set yet so `--headless` can
  print to the console on Windows; the Store/GUI build will attach-console conditionally.
- The seed lives in the OS secure store; `load_seed()` distinguishes *no entry* (new
  device) from a locked/error read so a transient failure never clobbers an identity
  (same rule as the iOS Keychain locked-read fix).
- Media refs are `sha256(plaintext)` and stored **sealed at rest** — byte-compatible with
  iOS `MediaStore` / Android `LocalMedia`, so the cross-device chunk fetch interops.

[`cargo-xwin`]: https://github.com/rust-cross/cargo-xwin
