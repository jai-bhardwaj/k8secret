import Foundation
import Security

// Process-scoped temporary keychain used to import client-cert private keys.
//
// SecPKCS12Import on macOS persists imported items in the user's login
// keychain unless an explicit keychain is provided. Each update to this
// ad-hoc signed app produces a new signature, so the ACL on previously
// imported keys no longer matches and macOS prompts for the login
// keychain password on every TLS handshake. Importing into a fresh
// per-process keychain side-steps both the prompt and the pollution.
final class TempKeychain: @unchecked Sendable {
    static let shared = TempKeychain()

    private let lock = NSLock()
    private var keychain: SecKeychain?
    private let path: String
    private let password: String

    private init() {
        path = NSTemporaryDirectory() + "k8secret-\(UUID().uuidString).keychain-db"
        password = UUID().uuidString
    }

    func get() -> SecKeychain? {
        lock.lock()
        defer { lock.unlock() }
        if let kc = keychain { return kc }

        var kc: SecKeychain?
        let pwLen = UInt32(password.utf8.count)
        let status = SecKeychainCreate(path, pwLen, password, false, nil, &kc)
        guard status == errSecSuccess, let created = kc else { return nil }

        SecKeychainUnlock(created, pwLen, password, true)
        var settings = SecKeychainSettings(
            version: 1,
            lockOnSleep: false,
            useLockInterval: false,
            lockInterval: UInt32.max
        )
        SecKeychainSetSettings(created, &settings)

        keychain = created
        return created
    }

    func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        if let kc = keychain {
            SecKeychainDelete(kc)
        }
        try? FileManager.default.removeItem(atPath: path)
        keychain = nil
    }
}
