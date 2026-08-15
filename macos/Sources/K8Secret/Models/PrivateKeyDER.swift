import Foundation

/// Normalises the private-key encodings found in real kubeconfigs into the forms
/// `SecKeyCreateWithData` actually accepts.
///
/// Security.framework is stricter than every other TLS stack here:
///
/// - RSA must be PKCS#1 (`RSAPrivateKey`)
/// - EC must be **ANSI X9.63** — the raw `04 || X || Y || K` blob
///
/// But kubeadm, k3s, colima, k0s and Rancher Desktop all write EC keys as **SEC1**
/// (`-----BEGIN EC PRIVATE KEY-----`, RFC 5915), and other tools emit PKCS#8
/// (`-----BEGIN PRIVATE KEY-----`) wrapping either algorithm. Handing those
/// straight to `SecKeyCreateWithData` returns nil, so no identity is built, no
/// client certificate is presented, and the API server answers 401 with nothing to
/// suggest the key was the problem. kubectl works on the same file because Go
/// parses SEC1 directly.
enum PrivateKeyDER {

    enum KeyKind {
        case rsa
        case ec
    }

    struct Normalized {
        let data: Data
        let kind: KeyKind
    }

    /// Convert a PEM/DER private key into the representation Security expects.
    static func normalize(pem: Data) -> Normalized? {
        let label = pemLabel(pem)
        let der = derBytes(from: pem)

        switch label {
        case "RSA PRIVATE KEY":
            return Normalized(data: der, kind: .rsa)          // already PKCS#1

        case "EC PRIVATE KEY":
            return x963(fromSEC1: der).map { Normalized(data: $0, kind: .ec) }

        case "PRIVATE KEY":
            return unwrapPKCS8(der)

        default:
            if let unwrapped = unwrapPKCS8(der) { return unwrapped }
            if let ec = x963(fromSEC1: der) { return Normalized(data: ec, kind: .ec) }
            return Normalized(data: der, kind: .rsa)
        }
    }

    // MARK: - PKCS#8

    /// PrivateKeyInfo ::= SEQUENCE { version INTEGER,
    ///                               algorithm AlgorithmIdentifier,
    ///                               privateKey OCTET STRING }
    private static func unwrapPKCS8(_ der: Data) -> Normalized? {
        var reader = DERReader(der)
        guard var body = reader.sequenceBody(),
              body.skip(tag: 0x02) != nil,                    // version
              var algorithm = body.sequenceBody(),
              let inner = body.value(tag: 0x04) else { return nil }

        guard let oid = algorithm.value(tag: 0x06) else { return nil }

        if oid == OID.ecPublicKey {
            return x963(fromSEC1: inner).map { Normalized(data: $0, kind: .ec) }
        }
        if oid == OID.rsaEncryption {
            return Normalized(data: inner, kind: .rsa)
        }
        return nil
    }

    // MARK: - SEC1 → X9.63

    /// ECPrivateKey ::= SEQUENCE { version INTEGER (1),
    ///                             privateKey OCTET STRING,
    ///                             parameters [0] ECParameters OPTIONAL,
    ///                             publicKey  [1] BIT STRING  OPTIONAL }
    ///
    /// X9.63 wants `publicKey || privateKey`, i.e. `04 || X || Y || K`.
    static func x963(fromSEC1 der: Data) -> Data? {
        var reader = DERReader(der)
        guard var body = reader.sequenceBody(),
              body.skip(tag: 0x02) != nil,
              let scalar = body.value(tag: 0x04) else { return nil }

        var publicKey: Data?
        while let (tag, value) = body.next() {
            guard tag == 0xA1 else { continue }               // [1] constructed
            var holder = DERReader(value)
            guard var bits = holder.value(tag: 0x03) else { continue }
            // BIT STRING's first byte counts unused trailing bits; always 0 here.
            if bits.first == 0x00 { bits = bits.dropFirst() }
            publicKey = Data(bits)
            break
        }

        // Without the public point we can't build X9.63 — deriving it needs EC
        // scalar multiplication, which Security won't do for a key it can't load.
        guard let publicKey, publicKey.first == 0x04 else { return nil }

        // The public point tells us the field size: 04 || X || Y.
        let fieldSize = (publicKey.count - 1) / 2
        guard scalar.count <= fieldSize else { return nil }
        let padded = Data(repeating: 0, count: fieldSize - scalar.count) + scalar

        return publicKey + padded
    }

    // MARK: - PEM

    private static func pemLabel(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8),
              let range = text.range(of: #"-----BEGIN ([A-Z0-9 ]+)-----"#, options: .regularExpression)
        else { return nil }
        return text[range]
            .replacingOccurrences(of: "-----BEGIN ", with: "")
            .replacingOccurrences(of: "-----", with: "")
    }

    private static func derBytes(from data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8), text.contains("-----BEGIN") else {
            return data
        }
        let base64 = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-----") }
            .joined()
        return Data(base64Encoded: base64) ?? data
    }

    private enum OID {
        /// 1.2.840.10045.2.1
        static let ecPublicKey = Data([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01])
        /// 1.2.840.113549.1.1.1
        static let rsaEncryption = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
    }
}

/// Just enough DER to walk the structures above — tag, length, value.
private struct DERReader {
    private let bytes: Data
    private var index: Data.Index

    init(_ data: Data) {
        bytes = data
        index = data.startIndex
    }

    mutating func next() -> (tag: UInt8, value: Data)? {
        guard index < bytes.endIndex else { return nil }
        let tag = bytes[index]
        index = bytes.index(after: index)

        guard let length = readLength(),
              let end = bytes.index(index, offsetBy: length, limitedBy: bytes.endIndex) else { return nil }

        let value = Data(bytes[index..<end])
        index = end
        return (tag, value)
    }

    mutating func value(tag: UInt8) -> Data? {
        guard let (actual, value) = next(), actual == tag else { return nil }
        return value
    }

    @discardableResult
    mutating func skip(tag: UInt8) -> Data? {
        value(tag: tag)
    }

    mutating func sequenceBody() -> DERReader? {
        guard let body = value(tag: 0x30) else { return nil }
        return DERReader(body)
    }

    private mutating func readLength() -> Int? {
        guard index < bytes.endIndex else { return nil }
        let first = bytes[index]
        index = bytes.index(after: index)

        if first & 0x80 == 0 { return Int(first) }            // short form

        let byteCount = Int(first & 0x7F)
        guard byteCount > 0, byteCount <= 4,
              let end = bytes.index(index, offsetBy: byteCount, limitedBy: bytes.endIndex)
        else { return nil }

        var length = 0
        for byte in bytes[index..<end] { length = (length << 8) | Int(byte) }
        index = end
        return length
    }
}
