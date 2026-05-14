import Foundation
import CryptoKit
import Observation

@Observable @MainActor
final class IdentityStore {

    private(set) var identity: Identity?
    private(set) var loadError: Error?

    private static let keychain = Keychain(
        service: "dev.MaroMushii.Khorshid",
        account: "identity.ed25519"
    )
    private static let displayNameKey = "identity.displayName"
    private static let defaultDisplayName = "Anonymous"

    private var privateKey: Curve25519.Signing.PrivateKey?

    func start() {
        do {
            let key = try Self.loadOrGenerate()
            privateKey = key
            identity = Identity(
                publicKey: key.publicKey.rawRepresentation,
                displayName: Self.loadDisplayName()
            )
        } catch {
            loadError = error
        }
    }

    func sign(_ data: Data) throws -> Data {
        guard let privateKey else { throw IdentityError.notReady }
        return try privateKey.signature(for: data)
    }

    func voteId(for targetId: String) -> String {
        guard let privateKey else { return "" }
        var hasher = SHA256()
        hasher.update(data: privateKey.rawRepresentation)
        hasher.update(data: Data(targetId.utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func setDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? Self.defaultDisplayName : trimmed
        UserDefaults.standard.set(value, forKey: Self.displayNameKey)
        if var current = identity {
            current.displayName = value
            identity = current
        }
    }

    #if DEBUG
    func resetForTesting() {
        try? Self.keychain.delete()
        UserDefaults.standard.removeObject(forKey: Self.displayNameKey)
        privateKey = nil
        identity = nil
        loadError = nil
        start()
    }
    #endif

    // MARK: - Helpers

    private static func loadOrGenerate() throws -> Curve25519.Signing.PrivateKey {
        if let data = try keychain.read() {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        }
        let fresh = Curve25519.Signing.PrivateKey()
        try keychain.write(fresh.rawRepresentation)
        return fresh
    }

    private static func loadDisplayName() -> String {
        UserDefaults.standard.string(forKey: displayNameKey) ?? defaultDisplayName
    }
}

enum IdentityError: Error, LocalizedError {
    case notReady

    var errorDescription: String? {
        switch self {
        case .notReady: return "Identity is not ready yet."
        }
    }
}
