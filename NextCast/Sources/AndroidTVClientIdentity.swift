import Foundation
import Security

/// Generates a unique self-signed RSA client identity on the iPhone and
/// keeps it in Keychain. Never ships a shared private key in the app binary.
/// Android TV Remote v2 uses the RSA certificate for TLS and PIN verification.
enum AndroidTVClientIdentity {
    private static let tag = Data("uk.zeshanbarvi.nextcast.androidtv.key.v1".utf8)
    private static let certLabel = "Next Cast Android TV Remote Identity"

    static func identity() throws -> (SecIdentity, SecKey) {
        if let found = existingIdentity() { return found }
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag
            ]
        ]
        var cfError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attrs as CFDictionary, &cfError),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw failure("Could not create Android TV pairing key.")
        }
        guard let publicDER = SecKeyCopyExternalRepresentation(publicKey, &cfError) as Data? else {
            throw failure("Could not encode Android TV pairing public key.")
        }
        let signatureAlg = der(0x30, hex("06092a864886f70d01010b") + Data([0x05, 0x00]))
        let rsaAlg = der(0x30, hex("06092a864886f70d010101") + Data([0x05, 0x00]))
        let commonName = der(0x30, der(0x31,
            der(0x30, hex("0603550403") + der(0x0c, Data(certLabel.utf8)))))
        let start = utcString(Date().addingTimeInterval(-86400))
        let expiry = utcString(Date().addingTimeInterval(5 * 365 * 86400))
        let validity = der(0x30, der(0x17, Data(start.utf8)) + der(0x17, Data(expiry.utf8)))
        let subjectKey = der(0x30, rsaAlg + der(0x03, Data([0]) + publicDER))
        var serial = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial) == errSecSuccess else {
            throw failure("Could not generate pairing certificate serial.")
        }
        serial[0] &= 0x7f
        serial[0] |= 0x01
        let tbs = der(0x30,
            der(0xa0, der(0x02, Data([0x02]))) +
            der(0x02, Data(serial)) +
            signatureAlg + commonName + validity + commonName + subjectKey)
        guard let signature = SecKeyCreateSignature(privateKey,
            .rsaSignatureMessagePKCS1v15SHA256, tbs as CFData, &cfError) as Data? else {
            throw failure("Could not sign Android TV pairing certificate.")
        }
        let certBytes = der(0x30, tbs + signatureAlg + der(0x03, Data([0]) + signature))
        guard let cert = SecCertificateCreateWithData(nil, certBytes as CFData) else {
            throw failure("Android TV pairing certificate could not be decoded.")
        }
        let add: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: cert,
            kSecAttrLabel as String: certLabel
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw failure("Could not save Android TV identity in Keychain (OSStatus \(status)).")
        }
        guard let result = existingIdentity() else {
            throw failure("The TV certificate was saved, but iOS did not associate it with its private key.")
        }
        return result
    }

    private static func existingIdentity() -> (SecIdentity, SecKey)? {
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var keyRef: CFTypeRef?
        guard SecItemCopyMatching(keyQuery as CFDictionary, &keyRef) == errSecSuccess,
              let keyRef, CFGetTypeID(keyRef) == SecKeyGetTypeID() else { return nil }
        let key = keyRef as! SecKey
        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var identities: CFTypeRef?
        guard SecItemCopyMatching(identityQuery as CFDictionary, &identities) == errSecSuccess,
              let list = identities as? [SecIdentity] else { return nil }
        guard let pub = SecKeyCopyPublicKey(key),
              let ourPublicBytes = SecKeyCopyExternalRepresentation(pub, nil) as Data? else { return nil }
        for id in list {
            var certificate: SecCertificate?
            guard SecIdentityCopyCertificate(id, &certificate) == errSecSuccess,
                  let certificate,
                  let publicKey = SecCertificateCopyKey(certificate),
                  let bytes = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
                  bytes == ourPublicBytes else { continue }
            return (id, publicKey)
        }
        return nil
    }

    private static func der(_ tag: UInt8, _ data: Data) -> Data {
        let n = data.count
        let length: [UInt8]
        if n < 128 { length = [UInt8(n)] }
        else if n <= 255 { length = [0x81, UInt8(n)] }
        else if n <= 65535 { length = [0x82, UInt8(n >> 8), UInt8(n & 255)] }
        else {
            length = [0x84, UInt8((n >> 24) & 255), UInt8((n >> 16) & 255),
                      UInt8((n >> 8) & 255), UInt8(n & 255)]
        }
        return Data([tag] + length) + data
    }
    private static func hex(_ s: String) -> Data {
        var data = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            data.append(UInt8(s[i..<j], radix: 16)!)
            i = j
        }
        return data
    }
    private static func utcString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyMMddHHmmss'Z'"
        return f.string(from: date)
    }
    private static func failure(_ msg: String) -> NSError {
        NSError(domain: "NextCast.AndroidTV.Identity", code: 1,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
