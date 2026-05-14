import Foundation

struct Identity: Sendable, Equatable {
    let publicKey: Data
    var displayName: String

    var publicKeyHex: String {
        publicKey.map { String(format: "%02x", $0) }.joined()
    }
}
