import Foundation
import CryptoKit

enum SocialCrypto {

    enum CryptoError: Error {
        case malformedWrapper
        case unknownPayloadType
    }

    static func encrypt(_ payload: DecryptedPayload, key: SymmetricKey) throws -> SocialPayloadWrapper {
        let plaintext = try payload.encoded()
        let nonce = AES.GCM.Nonce()
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        var combined = Data(box.ciphertext)
        combined.append(contentsOf: box.tag)
        return SocialPayloadWrapper(
            v: 1,
            n: Data(nonce).base64EncodedString(),
            c: combined.base64EncodedString()
        )
    }

    static func decrypt(_ wrapper: SocialPayloadWrapper, key: SymmetricKey) throws -> DecryptedPayload {
        guard wrapper.v == 1,
              let nonceData = Data(base64Encoded: wrapper.n),
              let combined = Data(base64Encoded: wrapper.c),
              combined.count >= 16 else {
            throw CryptoError.malformedWrapper
        }
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let ciphertext = combined.dropLast(16)
        let tag = combined.suffix(16)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let plaintext = try AES.GCM.open(box, using: key)
        let dto = try JSONDecoder().decode(DecryptedPayload.DTO.self, from: plaintext)
        guard let result = DecryptedPayload(dto: dto) else {
            throw CryptoError.unknownPayloadType
        }
        return result
    }

    static func sha256hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
