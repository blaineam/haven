import Foundation
import Security

/// A *read-only mirror* of the 32-byte master seed, stored in a shared Keychain access
/// group so the Notification Service Extension (a separate process, often running on the
/// lock screen) can decrypt a push payload with `openSealedWithSeed`.
///
/// Why a mirror and not the primary item: `AccountStore` keeps the authoritative seed in
/// the app's own (bundle-id) access group exactly as it always has — touching that item's
/// location risks losing an existing user's identity (see the keychain-locked-read class of
/// bug we already hardened against). So instead the app *additionally* writes a copy here,
/// in `…kith.shared`, which both the app and the extension can read. The extension only ever
/// reads; it never creates or overwrites identity.
///
/// **At rest the mirror is Secure-Enclave-wrapped**, exactly like the primary seed: the app
/// generates a P-256 Enclave key *in the shared access group* (so the NSE can use it too),
/// encrypts the seed to its public half, and stores only the ECIES ciphertext. The NSE opens
/// the blob with the same Enclave key — `.privateKeyUsage` needs no user presence, so a push
/// still decrypts on the lock screen — but a raw Keychain dump of the shared group yields
/// nothing. On the Simulator / no-Enclave hardware it falls back to the plaintext mirror.
///
/// Accessibility is `AfterFirstUnlockThisDeviceOnly` — readable once the device has been
/// unlocked at least once (so a lock-screen push still decrypts), never syncs to iCloud.
enum SharedSeed {
    /// Full keychain access group = team prefix (`$(AppIdentifierPrefix)` in the
    /// entitlements) + the shared group id. Both the app and the NSE declare this group.
    private static let accessGroup = "8ZVSPZYSVF.com.blaineam.kith.shared"
    private static let service = "com.blaineam.kith"
    private static let account = "account-master-seed-shared"

    /// Enclave key pinned to the shared group: the app creates + seals, the NSE only opens.
    private static let box = SecureEnclaveBox(tag: "com.blaineam.kith.shared-se-key",
                                              accessGroup: accessGroup)

    private static func base() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }

    /// App side: mirror the real seed into the shared group, Secure-Enclave-wrapped where the
    /// hardware allows. Idempotent (delete-then-add).
    static func write(_ seed: Data) {
        guard seed.count == 32 else { return }
        SecItemDelete(base() as CFDictionary)
        var add = base()
        // SE-wrap when available; otherwise store the raw seed (Simulator / no-Enclave). The two
        // are trivially distinguishable on read by length (a 32-byte seed vs. a larger blob).
        add[kSecValueData as String] = box.seal(seed) ?? seed
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    /// NSE side (and app): read the mirrored seed, unwrapping the SE blob via the shared Enclave
    /// key. `nil` if absent, if the device hasn't been unlocked since boot, or if the Enclave
    /// can't unwrap right now — the NSE then shows a generic alert rather than decrypted text.
    static func read() -> Data? {
        var q = base()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let blob = item as? Data else { return nil }
        if blob.count == 32 { return blob }                      // legacy / Simulator plaintext.
        if case .ok(let seed) = box.open(blob), seed.count == 32 { return seed }
        return nil
    }

    /// Remove the mirror (e.g. on identity reset). Safe to call when nothing is stored.
    static func clear() {
        SecItemDelete(base() as CFDictionary)
    }
}
