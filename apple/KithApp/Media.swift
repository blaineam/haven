import SwiftUI
import AVFoundation
import UIKit

enum MediaKind: String {
    case image, video, audio
    var ext: String {
        switch self {
        case .image: return "jpg"
        case .video: return "mp4"
        case .audio: return "m4a"
        }
    }
    /// The kind is encoded in the ref prefix so a recipient knows how to render it.
    init?(ref: String) {
        if ref.hasPrefix("img_") { self = .image }
        else if ref.hasPrefix("vid_") { self = .video }
        else if ref.hasPrefix("aud_") { self = .audio }
        else { return nil }
    }
}

/// A piece of attached media held locally. Bytes are persisted to disk (so they
/// survive restarts) and are sealed E2E before they ever leave the device.
struct MediaItem: Identifiable {
    let id: String
    let kind: MediaKind
    let image: UIImage?   // the photo, or a video's poster frame
    let videoURL: URL?
}

/// Persistent, content-ref'd media store. Refs encode the kind (img_/vid_/aud_) so a
/// recipient who receives the bytes can reconstruct the item. Files live under
/// Application Support/kith-media so they survive app restarts and updates.
@MainActor
final class MediaStore: ObservableObject {
    static let shared = MediaStore()
    private var cache: [String: MediaItem] = [:]

    private var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kith-media", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func fileURL(_ ref: String) -> URL? {
        guard let kind = MediaKind(ref: ref) else { return nil }
        return dir.appendingPathComponent("\(ref).\(kind.ext)")
    }

    @discardableResult
    func addImage(_ image: UIImage) -> String {
        let ref = "img_\(UUID().uuidString)"
        if let data = image.jpegData(compressionQuality: 0.9), let url = fileURL(ref) {
            try? data.write(to: url)
        }
        cache[ref] = MediaItem(id: ref, kind: .image, image: image, videoURL: nil)
        return ref
    }

    @discardableResult
    func addVideo(url src: URL) -> String {
        let ref = "vid_\(UUID().uuidString)"
        if let dst = fileURL(ref) {
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: src, to: dst)
            cache[ref] = MediaItem(id: ref, kind: .video, image: Self.poster(for: dst), videoURL: dst)
        }
        return ref
    }

    /// Audio reuses `videoURL` as the file URL.
    @discardableResult
    func addAudio(url src: URL) -> String {
        let ref = "aud_\(UUID().uuidString)"
        if let dst = fileURL(ref) {
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: src, to: dst)
            cache[ref] = MediaItem(id: ref, kind: .audio, image: nil, videoURL: dst)
        }
        return ref
    }

    /// Do we already hold the bytes for this ref?
    func has(_ ref: String) -> Bool {
        if cache[ref] != nil { return true }
        guard let url = fileURL(ref) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Raw bytes for a ref (to seal + send to a peer who's missing it).
    func rawBytes(_ ref: String) -> Data? {
        guard let url = fileURL(ref) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Store media bytes received from a peer, reconstructing the item for rendering.
    func store(_ ref: String, _ bytes: Data) {
        guard let kind = MediaKind(ref: ref), let url = fileURL(ref) else { return }
        try? bytes.write(to: url)
        switch kind {
        case .image: cache[ref] = MediaItem(id: ref, kind: .image, image: UIImage(data: bytes), videoURL: nil)
        case .video: cache[ref] = MediaItem(id: ref, kind: .video, image: Self.poster(for: url), videoURL: url)
        case .audio: cache[ref] = MediaItem(id: ref, kind: .audio, image: nil, videoURL: url)
        }
    }

    func item(_ ref: String) -> MediaItem? {
        if let c = cache[ref] { return c }
        guard let kind = MediaKind(ref: ref), let url = fileURL(ref),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        let item: MediaItem
        switch kind {
        case .image: item = MediaItem(id: ref, kind: .image, image: UIImage(contentsOfFile: url.path), videoURL: nil)
        case .video: item = MediaItem(id: ref, kind: .video, image: Self.poster(for: url), videoURL: url)
        case .audio: item = MediaItem(id: ref, kind: .audio, image: nil, videoURL: url)
        }
        cache[ref] = item
        return item
    }

    /// Extract a poster frame so videos show something before playback.
    static func poster(for url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1080, height: 1080)
        guard let cg = try? gen.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}
