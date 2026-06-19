import SwiftUI
import CryptoKit
import Security

/// Where the user's media is stored. iCloud is the default (their own quota); they can
/// also bring their own S3-compatible bucket, or connect a cloud drive over OAuth.
/// Crucially: Kith never hosts any API keys or client secrets — S3 keys live in the
/// Keychain on-device, and drive logins use OAuth 2.0 + PKCE (public clients, no secret).
enum StorageProvider: String, CaseIterable, Identifiable {
    case icloud, s3, googleDrive, dropbox
    var id: String { rawValue }
    var title: String {
        switch self {
        case .icloud: return "Your iCloud"
        case .s3: return "Custom S3 bucket"
        case .googleDrive: return "Google Drive"
        case .dropbox: return "Dropbox"
        }
    }
    var icon: String {
        switch self {
        case .icloud: return "icloud.fill"
        case .s3: return "externaldrive.fill"
        case .googleDrive: return "tray.full.fill"
        case .dropbox: return "shippingbox.fill"
        }
    }
}

@MainActor
final class StorageStore: ObservableObject {
    static let shared = StorageStore()

    @Published var provider: StorageProvider { didSet { d.set(provider.rawValue, forKey: "kith.storage.provider") } }
    @Published var s3Endpoint: String { didSet { d.set(s3Endpoint, forKey: "kith.s3.endpoint") } }
    @Published var s3Region: String { didSet { d.set(s3Region, forKey: "kith.s3.region") } }
    @Published var s3Bucket: String { didSet { d.set(s3Bucket, forKey: "kith.s3.bucket") } }
    @Published var s3AccessKey: String { didSet { Keychain.set(s3AccessKey, for: "s3AccessKey") } }
    @Published var s3Secret: String { didSet { Keychain.set(s3Secret, for: "s3Secret") } }

    private let d = UserDefaults.standard
    private init() {
        provider = StorageProvider(rawValue: d.string(forKey: "kith.storage.provider") ?? "") ?? .icloud
        s3Endpoint = d.string(forKey: "kith.s3.endpoint") ?? ""
        s3Region = d.string(forKey: "kith.s3.region") ?? "us-east-1"
        s3Bucket = d.string(forKey: "kith.s3.bucket") ?? ""
        s3AccessKey = Keychain.get("s3AccessKey") ?? ""
        s3Secret = Keychain.get("s3Secret") ?? ""
    }

    var s3Configured: Bool { !s3Endpoint.isEmpty && !s3Bucket.isEmpty && !s3AccessKey.isEmpty && !s3Secret.isEmpty }
}

struct StorageSettingsView: View {
    @ObservedObject private var store = StorageStore.shared
    @State private var connecting: StorageProvider?

    var body: some View {
        ZStack {
            KithBackground()
            Form {
                Section {
                    ForEach(StorageProvider.allCases) { p in
                        Button { store.provider = p } label: {
                            HStack {
                                Label(p.title, systemImage: p.icon).foregroundStyle(.primary)
                                Spacer()
                                if store.provider == p { Image(systemName: "checkmark").foregroundStyle(KithTheme.pink) }
                            }
                        }
                    }
                } header: { Text("Where your media lives") }
                footer: { Text("Your media is end-to-end encrypted before it's stored anywhere. Kith never holds your keys or any provider secrets.") }

                if store.provider == .s3 { s3Section }
                if store.provider == .googleDrive || store.provider == .dropbox { oauthSection }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var s3Section: some View {
        Section {
            TextField("Endpoint (e.g. s3.amazonaws.com)", text: $store.s3Endpoint).autocorrectionDisabled().textInputAutocapitalization(.never)
            TextField("Region", text: $store.s3Region).autocorrectionDisabled().textInputAutocapitalization(.never)
            TextField("Bucket", text: $store.s3Bucket).autocorrectionDisabled().textInputAutocapitalization(.never)
            TextField("Access key id", text: $store.s3AccessKey).autocorrectionDisabled().textInputAutocapitalization(.never)
            SecureField("Secret access key", text: $store.s3Secret)
            if store.s3Configured {
                Label("Saved on this device", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.caption)
            }
        } header: { Text("Your S3-compatible bucket") }
        footer: { Text("Works with AWS S3, Cloudflare R2, Backblaze B2, MinIO, etc. Keys are stored only in this device's Keychain — never on any server.") }
    }

    private var oauthSection: some View {
        Section {
            Button {
                connecting = store.provider
            } label: {
                Label("Connect \(store.provider.title)", systemImage: "link")
            }
        } footer: {
            Text("Connects securely with OAuth (PKCE) — you sign in on \(store.provider.title)'s own page. Kith never sees your password and stores no client secret; only a token kept in your Keychain.")
        }
        .sheet(item: $connecting) { p in OAuthConnectSheet(provider: p) }
    }
}

/// The OAuth connect flow uses PKCE (a *public* client) so there is no client secret
/// to host. Full token exchange + upload lands with the storage/send path (M5); the
/// PKCE values and the security shape are here now.
struct OAuthConnectSheet: View {
    let provider: StorageProvider
    @Environment(\.dismiss) private var dismiss
    private let verifier = PKCE.verifier()

    var body: some View {
        ZStack {
            KithBackground()
            VStack(spacing: 18) {
                Image(systemName: provider.icon).font(.system(size: 44)).foregroundStyle(KithTheme.brand)
                Text("Connect \(provider.title)").font(.title3.bold())
                Text("You'll sign in on \(provider.title)'s own page. Kith uses OAuth 2.0 with PKCE — a public client with **no secret to store anywhere**. We only keep an access token, in your Keychain.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("PKCE challenge: \(PKCE.challenge(verifier).prefix(16))…")
                    .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                Button("Continue") { dismiss() }.buttonStyle(BrandButtonStyle())
                Button("Cancel") { dismiss() }.foregroundStyle(.secondary)
            }
            .padding(30)
        }
        .presentationDetents([.medium])
    }
}

/// OAuth 2.0 PKCE helpers (public client — no secret).
enum PKCE {
    static func verifier() -> String { base64url(randomBytes(32)) }
    static func challenge(_ verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
    private static func randomBytes(_ n: Int) -> Data {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return Data(b)
    }
    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Minimal Keychain string store for storage credentials/tokens.
enum Keychain {
    private static let service = "com.blaineam.kith.storage"
    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let d = item as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
