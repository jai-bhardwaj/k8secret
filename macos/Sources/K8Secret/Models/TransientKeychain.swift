import Foundation
import Security

/// A throwaway keychain that exists only to hold a client-certificate identity for
/// the lifetime of this process.
///
/// macOS forms a `SecIdentity` only from a keychain-resident private key, so this
/// cannot be avoided outright — but it can be kept completely away from the user:
/// the file is created under the temporary directory with a random name and a
/// random password, is never added to the keychain search list, holds nothing but
/// the credentials already sitting in the user's kubeconfig, and is deleted when
/// the app quits.
///
/// Two calls are deliberately absent, because each one produces a password prompt:
///
/// - `SecKeychainSetSettings` — changing lock settings requires the password, so
///   macOS asks the user for it mid-connection.
/// - `SecKeychainUnlock` — unnecessary here; a keychain created with a known
///   password is already unlocked for the process that created it.
final class TransientKeychain: @unchecked Sendable {
    static let shared = TransientKeychain()

    private let lock = NSLock()
    private var keychain: SecKeychain?
    private let path: String
    private let password: [UInt8]

    private init() {
        path = NSTemporaryDirectory() + "k8secret-\(UUID().uuidString).keychain"
        password = Array(UUID().uuidString.utf8)
    }

    func get() -> SecKeychain? {
        lock.lock()
        defer { lock.unlock() }
        if let keychain { return keychain }

        // Sweep keychains left by a previous run that exited without cleanup (a
        // crash, or a kill). Without this they accumulate in the temp directory
        // one per launch.
        Self.removeStaleKeychains(excluding: path)

        var created: SecKeychain?
        // The password has to sit in a stable buffer: these APIs take it as an
        // UnsafeRawPointer, and a Swift String bridged inline is only valid for the
        // duration of the call.
        let status = password.withUnsafeBufferPointer { buffer in
            SecKeychainCreate(path, UInt32(buffer.count), buffer.baseAddress, false, nil, &created)
        }
        guard status == errSecSuccess, let created else { return nil }

        keychain = created
        return created
    }

    /// Delete leftover K8Secret keychains from earlier runs of this app.
    private static func removeStaleKeychains(excluding current: String) {
        let tmp = NSTemporaryDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: tmp) else { return }
        for entry in entries where entry.hasPrefix("k8secret-") && entry.contains(".keychain") {
            let full = (tmp as NSString).appendingPathComponent(entry)
            guard full != current else { continue }
            try? FileManager.default.removeItem(atPath: full)
        }
    }

    /// Remove the keychain and its file. Called on app termination.
    func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        if let keychain {
            SecKeychainDelete(keychain)
        }
        try? FileManager.default.removeItem(atPath: path)
        keychain = nil
    }
}

extension TransientKeychain {
    /// An access policy that lets any application use the item without prompting.
    ///
    /// The default ACL binds to the creating app's code signature, and this app is
    /// ad-hoc signed — the signature changes with every build, the stored ACL stops
    /// matching, and macOS asks for a keychain password on every handshake.
    func promptlessAccess(label: String) -> SecAccess? {
        var access: SecAccess?
        guard SecAccessCreate(label as CFString, nil, &access) == errSecSuccess,
              let access else { return nil }

        var aclList: CFArray?
        guard SecAccessCopyACLList(access, &aclList) == errSecSuccess,
              let acls = aclList as? [SecACL] else { return access }

        for acl in acls {
            // A nil application list means "any application, no prompt".
            SecACLSetContents(acl, nil, "" as CFString, SecKeychainPromptSelector(rawValue: 0))
        }
        return access
    }
}
