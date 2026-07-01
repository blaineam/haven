# Haven — App Store metadata

<!-- Edit, then sync: rocket meta Haven   (preview first: rocket meta Haven --dry-run) -->

## name
Haven 〇

## subtitle
Encrypted circles, no servers

## description
Haven is a private social network for the people who actually matter. No ads. No tracking. No algorithm deciding what you see. No company server holding your memories.

Everything you share is end-to-end encrypted with hybrid post-quantum cryptography and travels directly between your devices — over the internet, or over Bluetooth and Wi‑Fi when you're together offline. Even we can't read it.

• Private circles — share with family and close friends in separate, invite‑only circles
• Posts, photos, videos & stories — with a modern camera, easy captions, and a song
• Direct & group messages — with sender names, timestamps, and delivery checks, plus scheduled and screenshot‑protected secret messages
• Group voice & video calls — 1:1 and group, with screen sharing, peer‑to‑peer, no call server in the middle
• All your devices in sync — start on iPhone, pick up on iPad or Mac; your posts and messages follow you
• Disappearing posts — you decide how long things stick around
• Nearby sharing — works with no internet at all, phone to phone
• Bring your own storage — keep memories alive on your own S3 bucket or a relay you run
• No account, no phone number, no email — your identity lives only on your device

Haven is a stronghold for the people you love. It's built so that no one — not advertisers, not data brokers, not even the people who made it — can get between you and your circle.

## keywords
private,encrypted,family,friends,circle,secure,messaging,offline,stories,calls,no ads,quantum

## promotional_text
A private, end‑to‑end encrypted home for your closest people. No ads, no tracking, no servers — just your people.

## whats_new
What's new:
• Your own devices now stay in sync — posts and messages you make on one device show up on the rest
• Group DMs show who sent each message, when, and whether it was delivered
• Pin up to 6 conversations to the top of Messages and reorder them your way
• Group voice & video calls with screen sharing — still peer‑to‑peer, no call server
• Scheduled messages and screenshot‑protected secret messages
• Smoother, faster feed scrolling

Native on iPhone, iPad, and Mac — with Android and Windows/Linux desktop apps too.

## marketing_url
https://wemiller.com/apps/haven/

## support_url
https://wemiller.com/

## privacy_policy_url
https://wemiller.com/privacy/

## review_notes
Haven is a serverless, peer-to-peer, end-to-end encrypted social app for small private circles. There is no central server and no login.

HOW TO EXERCISE IT
On first launch the app generates a local identity (no account, phone number, or email is required or collected). Because content is shared only between devices that have added each other, the easiest way to review is with two devices: on device A tap the Connect tab → "Invite a friend" to show a QR/invite link; on device B choose Connect → scan the QR (or open the invite link). Once connected, posts, photos, stories, direct messages, and voice calls travel directly device-to-device — over the internet, or over Bluetooth/Wi-Fi when nearby and offline. If only one device is available, the app still launches, generates an identity, and the full UI (feed, composer, camera, circles, settings) is navigable; peer features simply have no peer to talk to.

USER-GENERATED CONTENT & SAFETY (Guideline 1.2)
All content is end-to-end encrypted between members of a private, invite-only circle, and is encrypted on-device before it ever leaves. The developer operates no server that can see content and logs nothing, so there is no copy of user content to moderate or to report to — server-side filtering/reporting is not technically possible in a zero-knowledge peer-to-peer system. User safety is instead enforced entirely client-side and is robust: a user approves every person who joins (nothing arrives from strangers), and can BLOCK a member and REMOVE them from a circle at any time. Removal/blocking is cryptographically enforced — a removed member is excluded from the circle's new encryption epoch and cannot decrypt anything posted afterward, not merely hidden. Developer contact info is published in the app and in this listing.

ENCRYPTION / EXPORT COMPLIANCE
Haven uses only standard, published cryptographic algorithms (X25519 + ML-KEM-768 key exchange, Ed25519 + ML-DSA signatures, AES-256-GCM, HKDF-SHA256) — no proprietary cryptography. Info.plist sets ITSAppUsesNonExemptEncryption = NO; the app qualifies for the standard exemption and no French declaration applies.

NOTIFICATIONS
Push uses a self-hosted relay (a Cloudflare Worker) that is BLIND: it forwards an already-encrypted payload and cannot read it; a Notification Service Extension decrypts it on-device into the banner. No content is stored on any server.

## review_first_name
Blaine

## review_last_name
Miller

## review_phone
+16616177188

## review_email
blaine@wemiller.com
