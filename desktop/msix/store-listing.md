# Haven — Microsoft Store listing

<!-- Source of truth for the Store listing text. The release.yml `desktop` job submits the MSIX via
     the Microsoft Store submission API; paste/sync these fields in Partner Center (or wire them into
     the msstore submission payload). Screenshots: see desktop/Tools/capture_screenshots.ps1 — they
     must be captured on Windows (the Tauri/WebView2 GUI doesn't run on macOS). -->

## name
Haven

## short_title
Haven

## description
Haven is a private social network for the people who actually matter. No ads. No tracking. No algorithm deciding what you see. No company server holding your memories.

Everything you share is end-to-end encrypted with hybrid post-quantum cryptography and travels directly between your devices — over the internet, or over your local network when you're together. Even we can't read it.

• Private circles — share with family and close friends in separate, invite-only circles
• Posts, photos, videos & stories — with an easy composer and a song
• Direct messages & group voice/video calls — peer-to-peer, with no call server in the middle
• Screen sharing in calls
• Disappearing posts — you decide how long things stick around
• Bring your own storage, or run a relay — no recurring cost
• No account, no phone number, no email — your identity lives only on your device

Haven is a stronghold for the people you love. It's built so that no one — not advertisers, not data brokers, not even the people who made it — can get between you and your circle.

## features
- End-to-end encrypted, post-quantum
- No account, no tracking, no servers
- Private invite-only circles
- Peer-to-peer voice & video calls with screen share
- Stories and disappearing posts
- Bring your own storage / self-host a relay

## whats_new
First Windows release. The desktop app matches the iPhone and Mac apps — circles, stories, direct
messages, and peer-to-peer calls — with a native-feeling window.

## search_terms
private, encrypted, family, friends, circle, secure, messaging, calls, no ads, post-quantum

## category
Social

## privacy_policy_url
https://wemiller.com/privacy/

## support_contact
https://wemiller.com/

## notes_for_certification
Haven is a serverless, peer-to-peer, end-to-end encrypted social app. There is no account or login —
the app generates a local identity on first launch. To exercise it, two installs add each other via an
invite link/QR (Connect), then posts, messages, and calls travel directly device-to-device. No data is
collected or sent to the developer. All user content is end-to-end encrypted between members of private
invite-only circles, so there is no server-side content for the developer to access or moderate; users
approve who joins and can remove or block any member. Encryption uses standard published algorithms
(X25519 + ML-KEM-768, Ed25519 + ML-DSA, AES-256-GCM); no proprietary cryptography.
