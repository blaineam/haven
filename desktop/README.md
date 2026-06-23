# Haven for Windows & Linux (Tauri 2)

A native desktop client at feature parity with iOS — **and** a headless circle relay — in
one binary, built on the same Rust core as the iPhone and Android apps.

Because the backend is Rust, it links the shared core (`haven_ffi` → `p2pcore` +
`haven-net`) **directly, with no UniFFI hop**. The iroh peer runs in the native process,
so this is a real peer, not a thin web client. The WebView2/WebKit frontend (`ui/`) gives
camera, WebRTC, and media playback for free.

```
src-tauri/   Rust backend
  src/wire.rs       byte-exact port of the Hello/Event/Media wire protocol (interop)
  src/engine.rs     port of Android HavenNet.kt: HavenSocial + HavenNode, handshake,
                    persistence, mailbox poll, relay hosting, media chunks
  src/store.rs      seed in the OS secure store + prefs.json + state blob
  src/localmedia.rs content-addressed, sealed-at-rest media (matches iOS/Android refs)
  src/commands.rs   the invoke() surface
  src/lib.rs        Tauri builder + run_headless()
ui/          static WebView frontend (no bundler): index.html, styles.css, app.js
             vendor/  qrcode.js (QR show) + jsQR.js (camera scan)
```

## Run (dev — works on macOS/Linux too, via the native WebView)

```bash
cargo install tauri-cli --version '^2'      # one-time
cd src-tauri
cargo tauri dev                              # GUI
cargo run -- --headless                      # relay only (prints a relay node id)
```

## Build (Windows artifact)

On Windows: `cargo tauri build` → `.msi` + NSIS installer (add an `msix` target for the
Microsoft Store). Cross-compile from macOS/Linux via `cargo-xwin` or a Windows CI runner.

See [`../docs/WINDOWS-PORT.md`](../docs/WINDOWS-PORT.md) for the full parity table and the
remaining milestones (WebRTC calls, native notifications/tray, MSIX/Store, Linux packages).

## Status

Done: project scaffold; backend compiles + unit/integration tests pass; the headless relay
runs end-to-end (identity in the OS keychain → iroh node → relay link); GUI covers identity,
profile, circles, feed (post/comment/react/edit/unsend), stories, DMs, QR show+camera-scan
handshake, photo/video attach, contacts/pending/block, and relay host/adopt; **WebRTC
audio/video/group calls** (full mesh in the WebView, signaling on the sealed channel);
**native notifications + system tray** (show / host relay / quit); **BYO S3/R2/B2 bucket**
mailbox via the shared `core/haven-s3` SigV4 client; and **CI** building Windows + Linux
installers.

Live-device-test pending: cross-device media-byte chunks, calls, and a real S3 bucket.
Not yet: screen share, MSIX/Microsoft Store packaging, on-device sensitive-content classifier.
