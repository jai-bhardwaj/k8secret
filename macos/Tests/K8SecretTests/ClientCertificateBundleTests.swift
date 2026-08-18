import XCTest
import Security
@testable import K8Secret

/// The bundle we hand to Security must be one Security will actually read.
///
/// `buildPKCS12` shells out to `/usr/bin/openssl`, and it used to take that
/// tool's *default* encryption. Security.framework only imports the legacy
/// PKCS#12 algorithms; Apple's LibreSSL still defaults to them, so this worked
/// on the machines it was written on — but the default belongs to whichever
/// openssl the machine happens to ship. OpenSSL 3.x defaults to AES-256-CBC
/// with a SHA-256 MAC, and `SecPKCS12Import` rejects that with
/// errSecPkcs12VerifyFailure (-25264) — a status whose message blames the
/// password, which is generated moments earlier and used once.
///
/// What the user sees when this breaks is three steps removed from the cause:
/// no identity is built, so no client certificate is presented, so the API
/// server drops the handshake, so URLSession reports that a secure connection
/// could not be made — pointing at the cluster rather than at us.
final class ClientCertificateBundleTests: XCTestCase {

    /// A throwaway certificate and key, made the way a kubeconfig's would be.
    private func makeCertificateAndKey(algorithm: [String]) throws -> (cert: Data, key: Data) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("k8secret-bundle-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let certPath = dir.appendingPathComponent("cert.pem").path
        let keyPath = dir.appendingPathComponent("key.pem").path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["req", "-x509", "-nodes", "-days", "1",
                             "-subj", "/CN=k8secret-test/O=system:masters",
                             "-keyout", keyPath, "-out", certPath] + algorithm
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try XCTSkipUnless(process.terminationStatus == 0, "openssl could not generate a test key")

        return (try Data(contentsOf: URL(fileURLWithPath: certPath)),
                try Data(contentsOf: URL(fileURLWithPath: keyPath)))
    }

    private func assertImportable(_ algorithm: [String], _ label: String) throws {
        let material = try makeCertificateAndKey(algorithm: algorithm)
        let bundle = try XCTUnwrap(
            K8sTLSDelegate.buildPKCS12(certPEM: material.cert, keyPEM: material.key),
            "\(label): could not build a PKCS#12 bundle at all")

        var items: CFArray?
        let status = SecPKCS12Import(
            bundle.data as CFData,
            [kSecImportExportPassphrase as String: bundle.passphrase] as CFDictionary,
            &items)

        XCTAssertEqual(status, errSecSuccess,
                       "\(label): Security rejected our bundle — "
                       + ((SecCopyErrorMessageString(status, nil) as String?) ?? "?")
                       + ". The PKCS#12 algorithms are probably no longer pinned to the "
                       + "legacy set Security accepts.")

        let identity = (items as? [[String: Any]])?.first?[kSecImportItemIdentity as String]
        XCTAssertNotNil(identity, "\(label): imported, but with no usable identity")
    }

    /// RSA — what kubeadm writes.
    func testAnRSAIdentityImports() throws {
        try assertImportable(["-newkey", "rsa:2048"], "RSA")
    }

    /// EC — what k3s and colima write, which is most local clusters.
    ///
    /// `ec_param_enc:named_curve` is not decoration. Without it openssl writes the
    /// curve as explicit parameters, and Security rejects such a key outright with
    /// errSecInvalidKey — so a test that omits it fails against material no real
    /// cluster produces. Every kubeconfig checked writes the named curve.
    func testAnECIdentityImports() throws {
        try assertImportable(["-newkey", "ec",
                              "-pkeyopt", "ec_paramgen_curve:prime256v1",
                              "-pkeyopt", "ec_param_enc:named_curve"], "EC")
    }
}
