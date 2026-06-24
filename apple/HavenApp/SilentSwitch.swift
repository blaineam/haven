#if os(iOS)
import AudioToolbox
import QuartzCore
import Foundation

/// Best-effort detection of the hardware ring/silent switch. iOS exposes **no** API for it, so we
/// use the well-known trick: play a short, genuinely silent system sound and time it. When the
/// switch is set to silent the system suppresses the sound and the completion fires almost
/// instantly; when the ringer is on it "plays" for the sound's full duration. We use this once at
/// launch to seed the post-audio autoplay default (silenced → start muted; ringer on → autoplay).
///
/// Limitations (honest): it's a heuristic, it can't be exercised in the Simulator (no switch), and
/// MusicKit/Apple-Music playback itself ignores the switch by design — this only gates whether we
/// *auto-start* the music, which is the behavior the product wants.
enum SilentSwitch {
    /// Length of the silent probe sound. Suppressed playback returns in well under half of this.
    private static let probeSeconds = 0.45

    /// A genuinely-silent PCM WAV written to temp once, reused thereafter. No bundled asset needed.
    private static func probeURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("haven-silent-probe.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let sampleRate = 8000
        let frames = Int(Double(sampleRate) * probeSeconds)
        let dataBytes = frames * 2   // 16-bit mono
        var d = Data()
        func le32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func le16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); le32(UInt32(36 + dataBytes)); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); le32(16); le16(1); le16(1)   // PCM, mono
        le32(UInt32(sampleRate)); le32(UInt32(sampleRate * 2)); le16(2); le16(16)
        d.append(contentsOf: Array("data".utf8)); le32(UInt32(dataBytes))
        d.append(Data(count: dataBytes))   // pure silence
        return (try? d.write(to: url)) == nil ? nil : url
    }

    /// Calls back (on the main queue) with `true` if the device appears to be silenced. Always
    /// calls back — `false` if the probe can't run (so the default is "audible / autoplay").
    static func detectSilenced(_ completion: @escaping (Bool) -> Void) {
        guard let url = probeURL() else { completion(false); return }
        var sid: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &sid) == noErr else { completion(false); return }
        let start = CACurrentMediaTime()
        AudioServicesPlaySystemSoundWithCompletion(sid) {
            let elapsed = CACurrentMediaTime() - start
            AudioServicesDisposeSystemSoundID(sid)
            DispatchQueue.main.async { completion(elapsed < probeSeconds * 0.5) }
        }
    }
}
#endif
