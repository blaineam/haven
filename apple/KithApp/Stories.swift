import SwiftUI
import AVKit

/// Full-screen story viewer: progress bars, auto-advance, tap left/right to navigate.
/// Stories are ordinary posts flagged `story` with a 24h retention, so they expire
/// on their own — no special server, just the existing retention rule.
struct StoryViewer: View {
    let stories: [FeedItemFfi]
    @State var index: Int
    let friendName: String
    @Environment(\.dismiss) private var dismiss
    @State private var progress = 0.0
    private let duration = 5.0
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if stories.indices.contains(index) {
                content(stories[index]).ignoresSafeArea()
                overlay(stories[index])
            }
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { prev() }
                Color.clear.contentShape(Rectangle()).onTapGesture { next() }
            }
        }
        .statusBarHidden()
        .onReceive(tick) { _ in
            progress += 0.05 / duration
            if progress >= 1 { next() }
        }
    }

    @ViewBuilder private func content(_ s: FeedItemFfi) -> some View {
        if let ref = s.media.first, let m = MediaStore.shared.item(ref) {
            if m.kind == .video, let url = m.videoURL {
                VideoPlayer(player: AVPlayer(url: url))
            } else if let img = m.image {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                missing
            }
        } else {
            missing
        }
    }

    private var missing: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white.opacity(0.6))
            Text("Loading…").foregroundStyle(.white.opacity(0.6)).font(.caption)
        }
    }

    private func overlay(_ s: FeedItemFfi) -> some View {
        VStack {
            HStack(spacing: 4) {
                ForEach(stories.indices, id: \.self) { i in
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.3))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white)
                                    .frame(width: geo.size.width * (i < index ? 1 : (i == index ? progress : 0)))
                            }
                    }
                    .frame(height: 3)
                }
            }
            .padding(.horizontal).padding(.top, 12)
            HStack {
                Text(s.isMe ? "Your story" : (ContactsStore.shared.name(forNodePrefix: s.authorShort) ?? friendName))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(relativeTimeShort(s.createdAt)).font(.caption2).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                }
            }
            .padding()
            if !s.body.isEmpty {
                Spacer()
                Text(s.body).foregroundStyle(.white).padding()
                    .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12)).padding()
            }
            Spacer()
        }
    }

    private func next() {
        progress = 0
        if index + 1 < stories.count { index += 1 } else { dismiss() }
    }
    private func prev() {
        progress = 0
        if index > 0 { index -= 1 }
    }
}
