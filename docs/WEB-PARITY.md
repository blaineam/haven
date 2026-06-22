# Haven Web — full client + always-on community relay

**Goal:** a single browser tab is (1) a full-featured Haven client at parity with iOS and
(2) an always-on community relay/cache — open a tab, leave it open, and your circle stays
warm. Fully **serverless** (no public host).

## The hard constraint (drives everything)
Browsers **cannot accept inbound connections or do raw UDP/QUIC.** A native iroh node can
relay because it can *listen*; a browser tab cannot. So the tab is a *smart always-on client +
cache*, not a socket-listening server.

## Relay model — WebRTC mesh + mailbox keeper (decided 2026-06-22)
- **WebRTC mesh:** tabs form a browser↔browser P2P mesh (RTCPeerConnection + data channels).
  Signaling rides the existing **shared mailbox** (no signaling server). The open tab relays
  envelopes/media among web peers it's connected to.
- **Mailbox keeper:** the tab continuously syncs + caches the circle's shared mailbox (pull new
  envelopes, retain media, re-serve to web peers over WebRTC). This is what "keeps the community
  warm" without a host.
- **Native interop:** native iOS peers benefit *via the shared mailbox* (both read/write it).
  Live native↔web (calls, direct relay) requires **WebRTC added to the iOS side later** — iOS
  currently speaks iroh, not WebRTC. Tracked as a cross-platform follow-up.

## Phases
1. **Engine parity (Rust `haven-wasm`).** Expose the full `p2pcore` surface the iOS app uses:
   stories, DMs (threads + secret messages), circles (multi-circle, membership), comments +
   reactions, edit/unsend, profile. Today the wasm only exports: identity, contacts, post, feed,
   receive, sync_envelopes. Rebuild via `wasm-pack build --target web --out-name haven_wasm`.
2. **Web UI parity.** Build the SPA (feed with the 9:16 story canvas, stories tray + viewer, DMs,
   composer, circle switcher, reactions, profiles, media positioning). Mirror iOS look.
3. **Networking in the browser.** Mailbox sync loop (S3 via the engine + the user's bucket creds);
   WebRTC mesh: peer discovery + offer/answer/ICE over the mailbox; data channels for envelopes.
4. **Calls + video calls.** WebRTC media channels (getUserMedia + RTCPeerConnection); signaling
   over the mailbox. Browser↔browser first.
5. **Relay role.** Always-on: keep syncing the mailbox, hold the WebRTC mesh, cache + re-serve
   media. A small "relay mode" UI (status, peers connected, content cached).

## Verification
Use the `preview_*` tools (dev server at `web/`) per phase. Each phase ships behind a build that
loads `web/index.html` against the regenerated `haven_wasm`.

## Cross-platform debt (explicit)
- iOS WebRTC (so native↔web calls + live relay work) — separate effort on the Apple side.
- This reverses the prior "stabilize Apple first" plan — intentional pivot per the user.
