import SwiftUI
import AVKit

/// AVPlayerLayer-backed surface with no system chrome. `.resizeAspect` letterboxes — the whole
/// frame is always visible, never cropped.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        return v
    }
    func updateUIView(_ v: PlayerLayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}

/// Inline video with custom, chrome-free controls:
///  • **hold** (long-press) to pause while held, release to resume
///  • **horizontal drag** to scrub (shows a thin progress bar + time)
/// A quick tap is intentionally not captured here, so it still toggles mute on the parent post.
struct GestureVideoPlayer: View {
    let player: AVPlayer

    @State private var progress: Double = 0      // 0…1
    @State private var duration: Double = 0
    @State private var scrubbing = false
    @State private var interacting = false
    @State private var wasPlaying = false
    @State private var startProgress: Double = 0
    @State private var observed: (AVPlayer, Any)?

    var body: some View {
        GeometryReader { geo in
            VideoSurface(player: player)
                .overlay(alignment: .bottom) {
                    if scrubbing { scrubBar.padding(8) }
                }
                .contentShape(Rectangle())
                .gesture(holdAndScrub(width: geo.size.width))
        }
        .onAppear(perform: addObserver)
        .onDisappear(perform: removeObserver)
    }

    private var scrubBar: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.3))
                    Capsule().fill(.white).frame(width: g.size.width * progress)
                }
            }
            .frame(height: 4)
            Text(timeLabel).font(.caption2.monospacedDigit()).foregroundStyle(.white)
        }
        .padding(8)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var timeLabel: String {
        func f(_ s: Double) -> String { let v = max(0, s); return String(format: "%d:%02d", Int(v) / 60, Int(v) % 60) }
        return "\(f(progress * duration)) / \(f(duration))"
    }

    private func holdAndScrub(width: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !interacting {
                    interacting = true
                    wasPlaying = player.timeControlStatus == .playing
                    startProgress = progress
                    player.pause()
                }
                if let drag, abs(drag.translation.width) > 6, width > 0 {
                    scrubbing = true
                    let pct = min(1, max(0, startProgress + drag.translation.width / width))
                    progress = pct
                    seek(to: pct)
                }
            }
            .onEnded { _ in
                interacting = false
                scrubbing = false
                if wasPlaying { player.play() }
            }
    }

    private func seek(to pct: Double) {
        guard duration > 0 else { return }
        player.seek(to: CMTime(seconds: pct * duration, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func addObserver() {
        removeObserver()   // never stack observers / leave a stale one
        if let d = player.currentItem?.duration.seconds, d.isFinite { duration = d }
        let token = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { time in
            if duration <= 0, let d = player.currentItem?.duration.seconds, d.isFinite { duration = d }
            if !scrubbing, duration > 0 { progress = time.seconds / duration }
        }
        observed = (player, token)   // remember the EXACT player this token belongs to
    }
    private func removeObserver() {
        // Remove from the player the observer was actually added to — SwiftUI can recycle this
        // view onto a different `player`, and removing a token from the wrong player throws
        // (the iPad crash on tab-away). Only ever remove once.
        if let (p, token) = observed { p.removeTimeObserver(token); observed = nil }
    }
}
