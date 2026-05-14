import Foundation
import CryptoKit
import Observation

@Observable @MainActor
final class PATPool {

    private(set) var isReady = false

    private static let remoteURL = URL(
        string: "https://raw.githubusercontent.com/MaroMushii/Khorshid/refs/heads/main/pats.json"
    )!
    private static let cacheKey = "patpool.pats"

    // Hardcoded fallback — populated at build time by project owner.
    private static let hardcoded: [String] = []

    private var available: [String] = []
    private var exhausted: Set<String> = []

    func start() {
        Task { await load() }
    }

    /// Returns a random non-exhausted token, or nil if the pool is empty.
    func token() -> String? {
        available.filter { !exhausted.contains($0) }.randomElement()
    }

    /// Call on HTTP 401, 403, or 429 to remove a token from this session's pool.
    func markExhausted(_ token: String) {
        exhausted.insert(token)
    }

    // MARK: - Private

    private func load() async {
        if let fetched = await fetchRemote() {
            available = fetched
            UserDefaults.standard.set(fetched, forKey: Self.cacheKey)
        } else if let cached = UserDefaults.standard.stringArray(forKey: Self.cacheKey),
                  !cached.isEmpty {
            available = cached
        } else {
            available = Self.hardcoded
        }
        isReady = true
    }

    private func fetchRemote() async -> [String]? {
        guard let (data, response) = try? await URLSession.shared.data(from: Self.remoteURL),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let doc = try? JSONDecoder().decode(PATsDoc.self, from: data),
              !doc.pats.isEmpty else {
            return nil
        }
        return doc.pats.compactMap(Self.decode)
    }

    // XOR-obfuscated tokens: base64(token ^ SHA256("khorshid-pat-pool-v1"))
    private static let xorKey: [UInt8] = {
        let digest = SHA256.hash(data: Data("khorshid-pat-pool-v1".utf8))
        return Array(digest)
    }()

    private static func decode(_ encoded: String) -> String? {
        guard let data = Data(base64Encoded: encoded) else { return nil }
        let bytes = data.enumerated().map { i, b in b ^ xorKey[i % xorKey.count] }
        return String(bytes: bytes, encoding: .utf8)
    }
}

private struct PATsDoc: Decodable {
    let v: Int
    let pats: [String]
}
