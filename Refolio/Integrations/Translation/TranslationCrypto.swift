import CommonCrypto
import CryptoKit
import Foundation

enum TranslationCryptoError: Error {
    case invalidAESKey
    case encryptionFailed(Int32)
}

enum TranslationCrypto {
    static func md5Hex(_ value: String) -> String {
        let data = Data(value.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func aesECBPKCS7Base64URL(_ value: String, key: String) throws -> String {
        let keyData = Data(key.utf8)
        guard keyData.count == kCCKeySizeAES128 else {
            throw TranslationCryptoError.invalidAESKey
        }

        let input = Data(value.utf8)
        let outputCapacity = input.count + kCCBlockSizeAES128
        var output = Data(count: outputCapacity)
        var outputLength = 0
        let status: CCCryptorStatus = keyData.withUnsafeBytes { keyBuffer in
            input.withUnsafeBytes { inputBuffer in
                output.withUnsafeMutableBytes { outputBuffer in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBuffer.baseAddress,
                        keyData.count,
                        nil,
                        inputBuffer.baseAddress,
                        input.count,
                        outputBuffer.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw TranslationCryptoError.encryptionFailed(status)
        }

        output.removeSubrange(outputLength..<output.count)
        return output.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }
}
