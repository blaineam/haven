import SwiftUI

/// Drives the live social demo: every action goes through the real hybrid-PQ
/// social engine (seal → open → feed) in `p2pcore`.
@MainActor
final class FeedStore: ObservableObject {
    @Published private(set) var items: [FeedItemFfi] = []
    private let demo: SocialDemo

    init(seed: Data) {
        demo = (try? SocialDemo(accountSeed: seed)) ?? {
            fatalError("SocialDemo requires a 32-byte seed")
        }()
        seedInitialContent()
        refresh()
    }

    private func now() -> UInt64 { UInt64(Date().timeIntervalSince1970 * 1000) }
    func refresh() { items = demo.feed() }

    func post(_ body: String) { _ = demo.post(body: body, createdAt: now()); refresh() }
    func comment(_ id: String, _ body: String) { _ = demo.comment(target: id, body: body, createdAt: now()); refresh() }
    func react(_ id: String, _ emoji: String) { _ = demo.react(target: id, emoji: emoji, createdAt: now()); refresh() }
    func edit(_ id: String, _ body: String) { _ = demo.edit(target: id, body: body, createdAt: now()); refresh() }
    func unsend(_ id: String) { _ = demo.unsend(target: id, createdAt: now()); refresh() }
    func friendReply(_ id: String) { _ = demo.friendComment(target: id, body: "👏 love it", createdAt: now()); refresh() }

    private func seedInitialContent() {
        let t = now()
        let welcome = demo.friendPost(body: "Welcome to Kith 🜂 — just us, no ads, no tracking.", createdAt: t)
        _ = demo.react(target: welcome, emoji: "❤️", createdAt: t + 1)
        let mine = demo.post(body: "First post. Our own little corner of the internet.", createdAt: t + 2)
        _ = demo.friendComment(target: mine, body: "This is so cozy.", createdAt: t + 3)
        _ = demo.friendReact(target: mine, emoji: "🎉", createdAt: t + 4)
    }
}

struct FeedView: View {
    @StateObject private var store: FeedStore
    @State private var compose = ""

    init(seed: Data) {
        _store = StateObject(wrappedValue: FeedStore(seed: seed))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                composer
                LazyVStack(spacing: 14) {
                    ForEach(store.items, id: \.id) { item in
                        PostCard(
                            item: item,
                            onReact: { store.react(item.id, $0) },
                            onComment: { store.comment(item.id, $0) },
                            onEdit: { store.edit(item.id, $0) },
                            onUnsend: { store.unsend(item.id) },
                            onFriendReply: { store.friendReply(item.id) }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Feed")
            .background(Color(.systemGroupedBackground))
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Share something…", text: $compose, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("composeField")
            Button {
                let t = compose.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                store.post(t)
                compose = ""
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("composeSend")
        }
        .padding()
    }
}

private struct PostCard: View {
    let item: FeedItemFfi
    let onReact: (String) -> Void
    let onComment: (String) -> Void
    let onEdit: (String) -> Void
    let onUnsend: () -> Void
    let onFriendReply: () -> Void

    @State private var commentText = ""
    @State private var showEdit = false
    @State private var editText = ""

    private let quickReactions = ["❤️", "😂", "🎉", "👍"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if item.unsent {
                Text("Message unsent")
                    .font(.subheadline).italic()
                    .foregroundStyle(.secondary)
            } else {
                Text(item.body).font(.body)
            }

            if !item.unsent {
                reactionsRow
                if !item.comments.isEmpty { commentsList }
                commentField
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .alert("Edit post", isPresented: $showEdit) {
            TextField("New text", text: $editText)
            Button("Save") { if !editText.isEmpty { onEdit(editText) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(item.isMe ? Color.accentColor : Color.pink)
                .frame(width: 30, height: 30)
                .overlay(Text(item.isMe ? "You" : "K").font(.caption2.bold()).foregroundStyle(.white))
            Text(item.isMe ? "You" : "kin·\(item.authorShort)")
                .font(.subheadline.weight(.semibold))
            if item.edited { Text("edited").font(.caption2).foregroundStyle(.secondary) }
            Spacer()
            Menu {
                if item.isMe && !item.unsent {
                    Button { editText = item.body; showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { onUnsend() } label: { Label("Unsend", systemImage: "arrow.uturn.backward") }
                }
                Button { onFriendReply() } label: { Label("Simulate friend reply", systemImage: "person.fill.badge.plus") }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
            }
        }
    }

    private var reactionsRow: some View {
        HStack(spacing: 8) {
            ForEach(item.reactions, id: \.emoji) { r in
                Text("\(r.emoji) \(r.count)")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(r.mine ? Color.accentColor.opacity(0.2) : Color(.secondarySystemFill))
                    .clipShape(Capsule())
            }
            Spacer()
            ForEach(quickReactions, id: \.self) { e in
                Button(e) { onReact(e) }.font(.body)
            }
        }
    }

    private var commentsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(item.comments, id: \.id) { c in
                HStack(alignment: .top, spacing: 6) {
                    Text(c.isMe ? "You:" : "kin·\(c.authorShort):")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if c.unsent {
                        Text("unsent").font(.caption).italic().foregroundStyle(.secondary)
                    } else {
                        Text(c.body).font(.caption)
                        if c.edited { Text("(edited)").font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer()
                }
            }
        }
        .padding(.leading, 4)
    }

    private var commentField: some View {
        HStack(spacing: 6) {
            TextField("Add a comment…", text: $commentText)
                .textFieldStyle(.roundedBorder).font(.caption)
            Button {
                let t = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                onComment(t)
                commentText = ""
            } label: { Image(systemName: "arrow.up.circle.fill") }
        }
    }
}
