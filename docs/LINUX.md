# Haven on Linux — desktop GUI + headless relay daemon

Haven runs on Linux in **two capacities**, sharing the same Rust core (`p2pcore` +
`haven-net`) as the iOS, macOS, and Android apps:

1. **Desktop GUI** (`desktop/`, Tauri 2) — a real iroh peer at feature parity with the
   iOS/macOS app: identity, circles, feed, stories, DMs, reactions/comments, in-app camera,
   media, **WebRTC audio/video/group calls + screen share**, music, system tray, native
   notifications, and BYO S3/R2 storage. The same binary also runs **headless as a relay**
   (`--headless`).
2. **Headless relay daemon** (`core/haven-relay`) — a tiny, dependency-free static binary
   (no WebKit, no GUI) that links one of your circles and serves it as an always-on
   connection relay + sealed-media mailbox. **This is the right thing to run on a Raspberry
   Pi or a server.** It only ever moves ciphertext.

> Which one do I want? A laptop/desktop/Steam Deck you use → the **GUI**. A Pi or
> headless box left running to keep your circle reachable → the **relay daemon**.

## Supported distributions

| Distro | GUI | Relay daemon | Recommended install |
|---|---|---|---|
| **Ubuntu** | ✅ x86_64 | ✅ | GUI: `.deb` / AppImage · Relay: `haven-relay` `.deb` or `install.sh` |
| **Debian** | ✅ x86_64 | ✅ | same as Ubuntu |
| **Raspberry Pi OS / Raspbian** | ⚠️ best-effort (arm64) | ✅ **primary role** | Relay: `install.sh` (arm64 / armv7 / armv6) or `.deb` |
| **Arch** | ✅ x86_64 / aarch64 | ✅ | AUR `haven-desktop` / `haven-relay` |
| **SteamOS / Steam Deck** | ✅ x86_64 | ✅ | GUI: **Flatpak** (Discover) · Relay: binary + systemd user service |

The GUI needs **WebKitGTK** + a glibc userland, so it targets desktop distros. The relay is a
**musl static binary** with no dependencies — it runs anywhere, including 32-bit Pis.

---

## Desktop GUI

### Ubuntu / Debian / Raspberry Pi OS (`.deb`)

```bash
sudo apt install ./Haven_0.1.0_amd64.deb      # or arm64 on a 64-bit Pi
haven-desktop                                  # launch (also in your app menu)
```

The `.deb` declares its runtime deps (`libwebkit2gtk-4.1-0`, `libgtk-3-0`,
`libayatana-appindicator3-1`) and recommends `pipewire` + `xdg-desktop-portal` for camera
and screen share. CI also produces an **AppImage** (no install — `chmod +x` and run) and an
`.rpm`.

### Arch (AUR)

```bash
git clone https://aur.archlinux.org/haven-desktop.git
cd haven-desktop && makepkg -si
```

The web UI is static and **embedded into the binary at compile time**, so the build needs no
Node/npm — just Rust + system WebKitGTK. (PKGBUILD source: `packaging/aur/haven-desktop/`.)

### SteamOS / Steam Deck (Flatpak)

SteamOS has an **immutable root filesystem**, so a `.deb`/AppImage won't persist across
updates — **Flatpak is the supported path**. From Desktop Mode:

```bash
flatpak install -y flathub org.gnome.Platform//47 org.gnome.Sdk//47
flatpak-builder --user --install --force-clean build-dir desktop/flatpak/com.blaineam.haven.yml
flatpak run com.blaineam.haven
```

Then add it to Game Mode via **"Add a Non-Steam Game."** The Flatpak grants the Camera and
ScreenCast portals (camera + screen share over PipeWire), audio, Wayland/X11, the Secret
Service for the identity seed, and a tray. See `desktop/flatpak/README.md`.

### Build from source (any distro)

```bash
# build deps (Debian/Ubuntu):
sudo apt install libwebkit2gtk-4.1-dev libgtk-3-dev libsoup-3.0-dev \
                 libayatana-appindicator3-dev librsvg2-dev patchelf file
cargo install tauri-cli --version '^2'
cd desktop/src-tauri
cargo tauri dev          # run the GUI
cargo tauri build        # → target/release/bundle/{deb,rpm,appimage}/
cargo run -- --headless  # run ONLY the relay
```

---

## Headless relay daemon

### One-line install (Ubuntu / Debian / Raspbian / Arch / SteamOS / Pi)

```bash
curl -fsSL https://wemiller.com/apps/haven/relay/install.sh | sh
```

`install.sh` auto-detects the arch and downloads the matching prebuilt static binary:

| `uname -m` | Target |
|---|---|
| `x86_64` | `x86_64-unknown-linux-musl` |
| `aarch64` / `arm64` (64-bit Pi OS, Arm servers) | `aarch64-unknown-linux-musl` |
| `armv7l` (32-bit Raspbian, Pi 2/3/4) | `armv7-unknown-linux-musleabihf` |
| `armv6l` (Pi Zero / Pi 1) | `arm-unknown-linux-musleabihf` |

Then attach it to a circle (the app shows the link under **You → Advanced → Relay → Add a
relay**):

```bash
haven-relay run --link "haven-relay://circle#...."   # first run; saves the link
haven-relay run                                       # restart later; reuses it
```

### As a `.deb` (Debian/Ubuntu/Raspbian)

```bash
sudo apt install ./haven-relay_0.0.1_amd64.deb   # also arm64 / armhf
# attach to a circle once, then enable the hardened system service:
sudo -u haven-relay HOME=/var/lib/haven-relay haven-relay run --link "<code>"   # Ctrl-C after "saved"
sudo systemctl enable --now haven-relay
journalctl -u haven-relay                          # the relay node id is in the log
```

The `.deb` ships a locked-down systemd **system** service that runs as a dedicated
`haven-relay` user with `ProtectSystem=strict`, `PrivateDevices`, `NoNewPrivileges`, etc.
(`relay/debian/haven-relay.service`).

### As an AUR package (Arch / SteamOS desktop)

```bash
git clone https://aur.archlinux.org/haven-relay.git
cd haven-relay && makepkg -si
sudo systemctl enable --now haven-relay
```

### systemd service variants

- **System** (boot, no login) — shipped in the `.deb`/AUR pkg; source at
  `relay/debian/haven-relay.service`.
- **Per-user** (no root, needs `loginctl enable-linger`) — `relay/haven-relay.service`:
  ```bash
  mkdir -p ~/.config/systemd/user && cp relay/haven-relay.service ~/.config/systemd/user/
  loginctl enable-linger "$USER"
  systemctl --user enable --now haven-relay
  ```

---

## Feature parity — Apple API → Linux

The GUI is at parity with iOS/macOS; here is how each Apple-specific capability is realized
(see also [`ANDROID-PARITY.md`](ANDROID-PARITY.md) — the same portable approach):

| iOS/macOS feature | Linux (Tauri / WebKitGTK) |
|---|---|
| Crypto / identity / circles / feed / DMs / stories | **Same `haven_ffi` crate**, linked directly (no FFI hop) — identical engine |
| iroh P2P transport + mesh relay | Same `haven-net` crate; native iroh peer in-process |
| Keychain (seed storage) | OS **Secret Service** via `keyring` (keys never leave the device) |
| In-app camera + story capture | `getUserMedia` (V4L2) + `MediaRecorder`; sealed in Rust before send |
| Photo/video picker | Tauri dialog + XDG portal |
| WebRTC audio/video/group calls | `RTCPeerConnection` full-mesh in the WebView; SDP/ICE signaled over the sealed iroh channel — no call server |
| **Screen share** | `getDisplayMedia` → on Wayland/SteamOS routes through `xdg-desktop-portal` ScreenCast (PipeWire); replaces the outgoing video track |
| Apple Music on posts | **Portable music ref**: local audio = full inline playback; streaming = deep-link out (no Apple Music API on Linux) |
| Notifications | `tauri-plugin-notification` (libnotify / XDG) + system tray; **no push server** (honors the zero-recurring-cost mandate) |
| CloudKit favorites/resume | Mailbox-based prefs blob (circle-sealed), same as Android |
| BYO storage | Shared `core/haven-s3` SigV4 client |

### Known limitations on Linux

- **Screenshot-protected secret messages**: Linux has no reliable cross-compositor screenshot
  block, so this is best-effort only (unlike iOS's secure field / Android's `FLAG_SECURE`).
- **GUI on Raspberry Pi**: builds for arm64 but camera/calls/perf parity on Pi hardware is a
  stretch — a Pi's real role here is the **relay daemon**, which runs great on all Pis.

---

## CI & release artifacts

- [`.github/workflows/desktop.yml`](../.github/workflows/desktop.yml) — tests the core +
  desktop, builds Windows (`.msi`/NSIS) and Linux (`.deb`/`.rpm`/AppImage), and a
  **Flatpak** for SteamOS.
- [`.github/workflows/relay-release.yml`](../.github/workflows/relay-release.yml) —
  cross-builds the `haven-relay` static binary for x86_64 / aarch64 / armv7 / armv6 (musl, via
  `cargo-zigbuild`) + macOS, builds `.deb`s, and publishes them as the
  `haven-relay-<target>` release assets that `relay/install.sh` downloads.
