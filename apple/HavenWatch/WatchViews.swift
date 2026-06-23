import SwiftUI

// MARK: - Conversations list

/// Recent DM threads + circle feeds. Tap a row to open the thread.
struct WatchConversationsView: View {
    @EnvironmentObject private var client: WatchConnectivityClient
    @State private var path: [WatchThread] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if client.threads.isEmpty {
                    Section {
                        Text(client.reachable ? "No conversations yet." : "Open Haven on your iPhone to sync.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(client.threads) { thread in
                    NavigationLink(value: thread) { WatchThreadRow(thread: thread) }
                }
            }
            .navigationTitle("Haven")
            .navigationDestination(for: WatchThread.self) { thread in
                WatchThreadView(threadId: thread.id, title: thread.title)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { client.refresh() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .refreshable { client.refresh() }
        }
        .onAppear {
            // Screenshot harness: jump straight into a thread for the hero shot.
            if ProcessInfo.processInfo.environment["HAVENWATCH_DEMO_SCENE"] == "thread",
               path.isEmpty, let first = client.threads.first {
                path = [first]
            }
        }
    }
}

private struct WatchThreadRow: View {
    let thread: WatchThread

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: thread.isDM ? "person.fill" : "sparkles")
                    .font(.caption2)
                    .foregroundStyle(thread.isDM ? Color.pink : Color.purple)
                Text(thread.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if thread.timestamp > 0 {
                    Text(watchRelativeTime(thread.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if !thread.subtitle.isEmpty {
                Text(thread.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Thread

/// A thread's recent messages with reply (dictation / canned) + tap-to-react.
struct WatchThreadView: View {
    let threadId: String
    let title: String
    @EnvironmentObject private var client: WatchConnectivityClient
    @State private var showReply = false
    @State private var reactingTo: WatchMessage?

    private var messages: [WatchMessage] {
        client.openThread?.threadId == threadId ? (client.openThread?.messages ?? []) : []
    }

    var body: some View {
        List {
            if messages.isEmpty {
                Text(client.loadingThread ? "Loading…" : "No messages yet.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(messages) { msg in
                WatchMessageRow(message: msg)
                    .onTapGesture { reactingTo = msg }
            }
            Section {
                Button {
                    showReply = true
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left.fill")
                }
                .tint(.pink)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { client.openThread(threadId) }
        .sheet(isPresented: $showReply) {
            WatchReplyView(threadId: threadId) { showReply = false }
                .environmentObject(client)
        }
        .sheet(item: $reactingTo) { msg in
            WatchReactionPicker { emoji in
                client.react(threadId: threadId, messageId: msg.id, emoji: emoji)
                reactingTo = nil
            }
        }
    }
}

private struct WatchMessageRow: View {
    let message: WatchMessage

    var body: some View {
        VStack(alignment: message.isMe ? .trailing : .leading, spacing: 2) {
            if !message.isMe {
                Text(message.author)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                if message.hasMedia { Image(systemName: "paperclip").font(.caption2) }
                Text(message.body.isEmpty && message.hasMedia ? "Attachment" : message.body)
                    .font(.body)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(message.isMe ? Color.pink.opacity(0.35) : Color.gray.opacity(0.25),
                        in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 4) {
                if !message.reactions.isEmpty {
                    Text(message.reactions).font(.caption2)
                }
                Text(watchRelativeTime(message.timestamp))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isMe ? .trailing : .leading)
        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
    }
}

// MARK: - Reply (dictation / Scribble via TextField + canned replies)

struct WatchReplyView: View {
    let threadId: String
    var onDone: () -> Void
    @EnvironmentObject private var client: WatchConnectivityClient
    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // The watchOS keyboard/dictation/Scribble all feed this field.
                TextField("Message", text: $text)
                    .submitLabel(.send)
                    .onSubmit(send)

                Button(action: send) {
                    Label("Send", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .tint(.pink)

                Divider()
                Text("Quick replies").font(.caption2).foregroundStyle(.secondary)
                ForEach(WatchQuickReplies.all, id: \.self) { canned in
                    Button {
                        client.sendReply(threadId: threadId, body: canned)
                        onDone()
                    } label: {
                        Text(canned).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Reply")
    }

    private func send() {
        client.sendReply(threadId: threadId, body: text)
        onDone()
    }
}

// MARK: - Reaction picker

struct WatchReactionPicker: View {
    var onPick: (String) -> Void
    private let columns = [GridItem(.adaptive(minimum: 44))]

    var body: some View {
        ScrollView {
            Text("React").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(WatchQuickReplies.reactions, id: \.self) { emoji in
                    Button { onPick(emoji) } label: {
                        Text(emoji).font(.title2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }
}
