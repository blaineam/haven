import Foundation
import Security

/// Owns the user's Kith account. Persists only the 32-byte master seed in the
/// Keychain; the full identity (all hybrid-PQ keys) is derived from it on launch.
@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var account: Account

    private static let service = "com.blaineam.kith"
    private static let seedKey = "account-master-seed"

    init() {
        if let seed = Self.loadSeed(), let restored = try? Account.fromSeed(seed: seed) {
            account = restored
        } else {
            let fresh = Account.generate()
            Self.saveSeed(fresh.secretSeed())
            account = fresh
        }
    }

    /// Wipe the identity and create a new one (for testing / "start over").
    func reset() {
        Self.deleteSeed()
        let fresh = Account.generate()
        Self.saveSeed(fresh.secretSeed())
        account = fresh
    }

    // MARK: - Keychain

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: seedKey,
        ]
    }

    private static func saveSeed(_ data: Data) {
        deleteSeed()
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func loadSeed() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func deleteSeed() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
