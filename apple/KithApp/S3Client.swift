import Foundation
import CryptoKit

/// A tiny, dependency-free S3 client (AWS SigV4, path-style) for the circle's shared
/// media store. It only ever moves **sealed** bytes: everything uploaded is already
/// end-to-end encrypted to the circle, so the bucket host (even if it's another member
/// "volunteering as tribute") stores opaque blobs it cannot read. Keys/secrets live
/// only in the device Keychain (see StorageStore) — never on any Kith server.
///
/// Works with AWS S3, Cloudflare R2, Backblaze B2, MinIO, etc.
struct S3Client {
    let endpoint: String      // e.g. "s3.amazonaws.com" or "<acct>.r2.cloudflarestorage.com"
    let region: String
    let bucket: String
    let accessKey: String
    let secret: String

    @MainActor
    init?(_ s: StorageStore) {
        guard s.s3Configured else { return nil }
        endpoint = s.s3Endpoint.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        region = s.s3Region.isEmpty ? "us-east-1" : s.s3Region
        bucket = s.s3Bucket
        accessKey = s.s3AccessKey
        secret = s.s3Secret
    }

    /// Build a path-style object URL: https://<endpoint>/<bucket>/<key>
    private func url(for key: String) -> URL? {
        URL(string: "https://\(endpoint)/\(bucket)/\(encodePath(key))")
    }

    // MARK: - Public API

    func putObject(key: String, data: Data) async throws {
        var req = try signedRequest(method: "PUT", key: key, payload: data)
        req.httpBody = data
        let (_, resp) = try await URLSession.shared.data(for: req)
        try check(resp, "PUT \(key)")
    }

    func getObject(key: String) async throws -> Data {
        let req = try signedRequest(method: "GET", key: key, payload: Data())
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, "GET \(key)")
        return data
    }

    func headObject(key: String) async -> Bool {
        guard let req = try? signedRequest(method: "HEAD", key: key, payload: Data()) else { return false }
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    private func check(_ resp: URLResponse, _ what: String) throws {
        guard let http = resp as? HTTPURLResponse else { throw S3Error.bad("no response: \(what)") }
        guard (200..<300).contains(http.statusCode) else { throw S3Error.bad("\(what) → HTTP \(http.statusCode)") }
    }

    // MARK: - SigV4

    private func signedRequest(method: String, key: String, payload: Data) throws -> URLRequest {
        guard let u = url(for: key) else { throw S3Error.bad("bad url") }
        let now = Date()
        let amzDate = Self.iso8601.string(from: now)        // 20250101T000000Z
        let dateStamp = String(amzDate.prefix(8))            // 20250101
        let host = endpoint
        let payloadHash = sha256Hex(payload)

        let canonicalURI = "/\(bucket)/\(encodePath(key))"
        let canonicalHeaders = "host:\(host)\nx-amz-content-sha256:\(payloadHash)\nx-amz-date:\(amzDate)\n"
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalRequest = [method, canonicalURI, "", canonicalHeaders, signedHeaders, payloadHash].joined(separator: "\n")

        let scope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = ["AWS4-HMAC-SHA256", amzDate, scope, sha256Hex(Data(canonicalRequest.utf8))].joined(separator: "\n")

        let signingKey = hmacChain(dateStamp: dateStamp)
        let signature = hmac(signingKey, Data(stringToSign.utf8)).map { String(format: "%02x", $0) }.joined()

        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var req = URLRequest(url: u)
        req.httpMethod = method
        req.setValue(host, forHTTPHeaderField: "Host")
        req.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        req.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        return req
    }

    private func hmacChain(dateStamp: String) -> SymmetricKey {
        let kDate = hmac(SymmetricKey(data: Data("AWS4\(secret)".utf8)), Data(dateStamp.utf8))
        let kRegion = hmac(SymmetricKey(data: kDate), Data(region.utf8))
        let kService = hmac(SymmetricKey(data: kRegion), Data("s3".utf8))
        let kSigning = hmac(SymmetricKey(data: kService), Data("aws4_request".utf8))
        return SymmetricKey(data: kSigning)
    }

    private func hmac(_ key: SymmetricKey, _ data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }
    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    /// Percent-encode each path segment but keep "/" as a separator (S3 keys are path-like).
    private func encodePath(_ key: String) -> String {
        key.split(separator: "/", omittingEmptySubsequences: false).map { seg in
            seg.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? String(seg)
        }.joined(separator: "/")
    }

    private static let unreserved: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "-._~")
        return s
    }()
    private static let iso8601: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()
}

enum S3Error: Error, LocalizedError {
    case bad(String)
    var errorDescription: String? { if case .bad(let m) = self { return m } else { return "S3 error" } }
}
