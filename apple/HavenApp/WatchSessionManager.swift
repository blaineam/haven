#if canImport(WatchConnectivity)
import Foundation
import Combine
import WatchConnectivity

/// iPhone-side bridge to the HavenWatch companion.
///
/// The phone holds the iroh node + identity; the Watch is a thin client. We vend recent DM
/// threads / circle posts and accept quick replies + reactions, routing them through
/// `FeedStore` on the main actor. Nothing here runs the Rust node — it's purely a read/relay
/// surface over what the phone already has.
///
/// This file only compiles where WatchConnectivity exists (iOS) — on native macOS the whole
/// file is empty, so HavenMac stays untouched.
final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()
    private override init() { super.init() }

    private var session: WCSession { WCSession.default }
    private var feedObserver: AnyCancellable?

    func start() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
        // Keep the Watch's thread list live: re-push a snapshot whenever the feed changes,
        // debounced so a burst of inbound events coalesces into one transfer.
        Task { @MainActor in
            self.feedObserver = FeedStore.shared.objectWillChange
                .debounce(for: .seconds(0.6), scheduler: RunLoop.main)
                .sink { [weak self] in self?.pushSnapshot() }
        }
    }

    // MARK: - Outbound

    /// Push the latest thread list to the Watch as the application context (the system keeps
    /// only the most recent, delivered whenever the Watch next becomes reachable). Cheap to
    /// call on every feed change.
    @MainActor func pushSnapshot() {
        guard WCSession.isSupported(), session.activationState == .activated, session.isPaired else { return }
        let msg = WatchCodec.encode(.snapshot, Self.buildSnapshot())
        try? session.updateApplicationContext(msg)
    }

    /// Mirror a phone-side local notification to the Watch so it surfaces there too.
    func mirrorNotification(title: String, body: String, dedupeKey: String) {
        guard WCSession.isSupported(), session.activationState == .activated, session.isWatchAppInstalled else { return }
        let notice = WatchNotice(title: title, body: body, dedupeKey: dedupeKey)
        session.transferUserInfo(WatchCodec.encode(.notify, notice))
    }

    // MARK: - Snapshot building (on the main actor — FeedStore is @MainActor)

    @MainActor static func buildSnapshot() -> WatchSnapshot {
        let store = FeedStore.shared
        var threads: [WatchThread] = []
        for c in store.dmCircles {
            let last = store.messages(in: c.id).last
            threads.append(WatchThread(id: c.id, title: store.dmPartnerName(c.id),
                                       subtitle: preview(last), timestamp: last?.createdAt ?? 0,
                                       isDM: true, unread: 0))
        }
        for c in store.feedCircles {
            let last = store.messages(in: c.id).last
            threads.append(WatchThread(id: c.id, title: c.name,
                                       subtitle: preview(last), timestamp: last?.createdAt ?? 0,
                                       isDM: false, unread: 0))
        }
        threads.sort { $0.timestamp > $1.timestamp }
        return WatchSnapshot(threads: threads, generatedAt: nowMs())
    }

    @MainActor static func buildThread(_ threadId: String) -> WatchThreadDetail {
        let store = FeedStore.shared
        let isDM = threadId.hasPrefix("dm:")
        let title = isDM ? store.dmPartnerName(threadId)
                         : (store.circles.first { $0.id == threadId }?.name ?? "Circle")
        let items = Array(store.messages(in: threadId).suffix(40))
        // Thumbnail only the most recent media-bearing messages so the WCSession payload stays small.
        let thumbIds = Set(items.filter { !$0.media.isEmpty }.suffix(12).map { $0.id })
        let messages = items.map { item -> WatchMessage in
            let (thumb, isVideo) = thumbIds.contains(item.id) ? watchThumbnail(item.media) : (nil, false)
            return WatchMessage(id: item.id,
                                author: item.isMe ? "You" : item.authorShort,
                                isMe: item.isMe,
                                body: item.unsent ? "Message unsent" : item.body,
                                timestamp: item.createdAt,
                                hasMedia: !item.media.isEmpty,
                                reactions: reactionSummary(item.reactions),
                                thumbnail: thumb,
                                isVideo: isVideo)
        }
        return WatchThreadDetail(threadId: threadId, title: title, isDM: isDM, messages: messages)
    }

    /// A tiny JPEG thumbnail (+ isVideo flag) of a post's first renderable media, for the Watch — so
    /// posts show the actual photo instead of a generic "Attachment" row. Kept small (≤120px, low
    /// quality ≈ a few KB) to stay well under the WCSession message cap.
    @MainActor private static func watchThumbnail(_ refs: [String]) -> (Data?, Bool) {
        for ref in refs {
            guard let item = MediaStore.shared.item(ref), let img = item.image else { continue }
            let small = MediaStore.downscale(img, maxDimension: 120)
            if let data = small.jpegData(compressionQuality: 0.5) {
                return (data, item.kind == .video)
            }
        }
        return (nil, false)
    }

    private static func preview(_ item: FeedItemFfi?) -> String {
        guard let item else { return "" }
        if item.unsent { return "Message unsent" }
        if !item.body.isEmpty { return item.body }
        if !item.media.isEmpty { return "📎 Attachment" }
        if item.music != nil { return "🎵 Song" }
        return ""
    }

    private static func reactionSummary(_ reactions: [ReactionFfi]) -> String {
        reactions.map { "\($0.emoji)\($0.count)" }.joined(separator: " ")
    }

    private static func nowMs() -> UInt64 { UInt64(Date().timeIntervalSince1970 * 1000) }

    // MARK: - Inbound routing

    @MainActor private func apply(_ message: [String: Any], reply: (([String: Any]) -> Void)?) {
        switch WatchCodec.kind(of: message) {
        case .requestSnapshot:
            reply?(WatchCodec.encode(.snapshot, Self.buildSnapshot()))
        case .requestThread:
            if let req = WatchCodec.decode(WatchThreadRequest.self, from: message) {
                reply?(WatchCodec.encode(.thread, Self.buildThread(req.threadId)))
            }
        case .quickReply:
            if let r = WatchCodec.decode(WatchReply.self, from: message) {
                FeedStore.shared.sendMessage(to: r.threadId, r.body)
                reply?(WatchCodec.encode(.thread, Self.buildThread(r.threadId)))
            }
        case .react:
            if let r = WatchCodec.decode(WatchReaction.self, from: message) {
                FeedStore.shared.reactMessage(in: r.threadId, r.messageId, r.emoji)
                reply?(WatchCodec.encode(.thread, Self.buildThread(r.threadId)))
            }
        default:
            reply?([:])
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.pushSnapshot() }
    }
    // iOS requires these two so the session can re-activate after switching watches.
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message, reply: nil) }
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in self.apply(message, reply: replyHandler) }
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.apply(userInfo, reply: nil) }
    }
}
#endif
