import Foundation
import CryptoKit

enum SocialCrypto {

    enum CryptoError: Error {
        case malformedWrapper
        case unknownPayloadType
        case invalidSignature
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
            c: combined.base64EncodedString(),
            pub: nil,
            sig: nil
        )
    }

    static func signatureMessage(for wrapper: SocialPayloadWrapper) -> Data? {
        guard let nonceData = Data(base64Encoded: wrapper.n),
              let combined = Data(base64Encoded: wrapper.c) else { return nil }
        return nonceData + combined
    }

    static func applySignature(_ sig: Data, publicKeyHex: String, to wrapper: SocialPayloadWrapper) -> SocialPayloadWrapper {
        SocialPayloadWrapper(v: 2, n: wrapper.n, c: wrapper.c, pub: publicKeyHex, sig: sig.base64EncodedString())
    }

    static func decrypt(_ wrapper: SocialPayloadWrapper, key: SymmetricKey) throws -> DecryptedPayload {
        if wrapper.v == 2 {
            guard let pubHex = wrapper.pub,
                  let sigB64 = wrapper.sig,
                  let pubData = dataFromHex(pubHex),
                  let sigData = Data(base64Encoded: sigB64),
                  let nonceData = Data(base64Encoded: wrapper.n),
                  let combined = Data(base64Encoded: wrapper.c) else {
                throw CryptoError.invalidSignature
            }
            let pubKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubData)
            guard pubKey.isValidSignature(sigData, for: nonceData + combined) else {
                throw CryptoError.invalidSignature
            }
        }

        guard wrapper.v == 1 || wrapper.v == 2,
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

    // MARK: - Private

    private static func dataFromHex(_ hex: String) -> Data? {
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
