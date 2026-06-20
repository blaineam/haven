import Foundation

/// The "volunteer as tribute" shared circle store. A member who turns this on keeps a
/// sealed copy of the circle's media in their own S3 bucket and re-serves it to anyone
/// who's missing it — so memories survive even when the original sender is offline.
///
/// Security: every blob is sealed to the *circle* (seal_circle_media), so the bucket
/// host stores only opaque bytes it cannot read, and a fetched blob is verified against
/// the circle roster before it's opened. No credentials are ever shared between members
/// — the volunteer simply acts as a durable, always-available media source over the
/// existing P2P media protocol. Keys live only in the device Keychain.
@MainActor
enum SharedStore {
    static var isVolunteering: Bool { StorageStore.shared.shareCircleMedia && S3Client(StorageStore.shared) != nil }

    private static func key(_ ref: String) -> String { "kith/media/\(ref)" }

    /// Seal a locally-held media blob to the circle and upload it (idempotent).
    static func backup(ref: String, circleId: String, social: KithSocial) async {
        guard isVolunteering, let s3 = S3Client(StorageStore.shared),
              let raw = MediaStore.shared.rawBytes(ref) else { return }
        if await s3.headObject(key: key(ref)) { return }   // already stored
        guard let sealed = try? social.sealCircleMedia(circleId: circleId, data: raw) else { return }
        try? await s3.putObject(key: key(ref), data: sealed)
    }

    /// Fetch a blob from the bucket and open it for whichever circle it belongs to.
    static func restore(ref: String, circleIds: [String], social: KithSocial) async -> Data? {
        guard let s3 = S3Client(StorageStore.shared) else { return nil }
        guard let sealed = try? await s3.getObject(key: key(ref)) else { return nil }
        for cid in circleIds {
            if let data = social.openCircleMedia(circleId: cid, sealed: sealed) { return data }
        }
        return nil
    }
}
