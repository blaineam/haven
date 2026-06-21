import SwiftUI
import AVKit

struct ZoomTarget: Identifiable {
    let id = UUID()
    let refs: [String]
    let index: Int
}

/// Full-screen media viewer: swipe between a post's photos/videos, pinch + drag to
/// zoom, double-tap to zoom, swipe down to dismiss.
struct MediaZoomViewer: View {
    let refs: [String]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var dismissOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(1 - min(0.6, abs(dismissOffset) / 600)).ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(refs.enumerated()), id: \.offset) { i, ref in
                    ZoomablePage(ref: ref).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: refs.count > 1 ? .automatic : .never))
            .offset(y: dismissOffset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { v in if abs(v.translation.height) > abs(v.translation.width) { dismissOffset = v.translation.height } }
                    .onEnded { v in
                        if abs(v.translation.height) > 140 { dismiss() }
                        else { withAnimation(.spring()) { dismissOffset = 0 } }
                    }
            )

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                            .padding(10).background(.black.opacity(0.4), in: Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .statusBarHidden()
    }
}

/// One pinch/drag-zoomable photo or (muted-tap-to-play) video.
private struct ZoomablePage: View {
    let ref: String
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Group {
            if let m = MediaStore.shared.item(ref) {
                if m.kind == .video, let url = m.videoURL {
                    VideoPlayer(player: AVPlayer(url: url))
                } else if let img = m.image {
                    Image(uiImage: img).resizable().scaledToFit()
                        .scaleEffect(scale).offset(offset)
                        .gesture(zoomGesture.simultaneously(with: panGesture))
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                if scale > 1 { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }
                                else { scale = 2.5; lastScale = 2.5 }
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { v in scale = max(1, min(5, lastScale * v)) }
            .onEnded { _ in lastScale = scale; if scale <= 1 { withAnimation { offset = .zero; lastOffset = .zero } } }
    }
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { v in if scale > 1 { offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) } }
            .onEnded { _ in lastOffset = offset }
    }
}
