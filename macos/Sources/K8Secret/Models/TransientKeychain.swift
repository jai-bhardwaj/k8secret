import Foundation
import Security

/// A throwaway keychain that exists only to hold a client-certificate identity for
/// the lifetime of this process.
///
/// macOS forms a `SecIdentity` only from a keychain-resident private key, so this
/// cannot be avoided outright — but it can be kept completely away from the user:
/// the file lives in the temporary directory under a random name with a random
/// password, is never added to the keychain search list, holds nothing but the
/// credentials already sitting in the user's kubeconfig, and is removed on exit.
///
/// Three things here exist specifically to stop password prompts, each of which
/// caused one:
///
/// - **No `SecKeychainSetSettings`.** Verified: it prompts even on a keychain
///   this process just created and still holds unlocked, returning
///   `errSecUserCanceled` when the prompt is refused. So auto-lock cannot be
///   turned off, and the lock below has to be handled rather than prevented.
/// - **`SecKeychainUnlock` before every use.** A new keychain is unlocked, but
///   `SecKeychainCreate` sets `lockOnSleep`, so the first time the machine
///   sleeps it locks — and the next TLS handshake needs the private key, finds
///   it locked, and asks the *user* for a random password that only ever
///   existed in this process's memory. We hold that password, so we unlock with
///   it. This was previously omitted as "unnecessary because a new keychain is
///   already unlocked", which is true only until the machine sleeps.
/// - **Orphans are unregistered, not just deleted.** `SecKeychainCreate` registers
///   the keychain with the security subsystem. A process that dies without
///   `SecKeychainDelete` — killed, crashed, force-quit — leaves that registration
///   behind pointing at a file. Deleting only the file leaves a dangling
///   registration, and later keychain work trips over it and prompts. Orphans are
///   opened and properly deleted.
///
/// The filename carries the owning process id so a sweep can tell an orphan from a
/// keychain another *live* instance is using. Deleting a running instance's
/// keychain would break its TLS mid-session — and produce exactly the prompt this
/// type is trying to avoid.
final class TransientKeychain: @unchecked Sendable {
    static let shared = TransientKeychain()

    private let lock = NSLock()
    private var keychain: SecKeychain?
    private let path: String
    private let password: [UInt8]

    private static let prefix = "k8secret-kc-"
    private static let suffix = ".keychain"

    private init() {
        path = NSTemporaryDirectory()
            + "\(Self.prefix)\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)\(Self.suffix)"
        password = Array(UUID().uuidString.utf8)
    }

    func get() -> SecKeychain? {
        lock.lock()
        defer { lock.unlock() }
        if let keychain { return keychain }

        // Clear out keychains left by runs that never got to clean up. Doing this
        // before creating ours keeps them from accumulating one per launch.
        Self.removeOrphanedKeychains(excluding: path)

        var created: SecKeychain?
        // The password has to sit in a stable buffer: these APIs take it as an
        // UnsafeRawPointer, and a Swift String bridged inline is only valid for the
        // duration of the call — so the keychain would be created with a password
        // that nothing could reproduce.
        let status = password.withUnsafeBufferPointer { buffer in
            SecKeychainCreate(path, UInt32(buffer.count), buffer.baseAddress, false, nil, &created)
        }
        guard status == errSecSuccess, let created else { return nil }

        // Belt and braces for the paths `applicationWillTerminate` doesn't cover.
        Self.installExitHandler()

        keychain = created
        return created
    }

    /// Unlock the keychain with the password this process generated for it.
    ///
    /// Called before every use of the identity rather than once at creation:
    /// `lockOnSleep` is on and cannot be turned off (see the note on
    /// `SecKeychainSetSettings` above), so the keychain locks itself behind our
    /// back whenever the machine sleeps. Unlocking with a password we already
    /// hold is silent; leaving it locked is what makes macOS ask the user.
    ///
    /// Cheap enough for the handshake path: the status check is a local call and
    /// the unlock only runs when the keychain has actually locked.
    @discardableResult
    func ensureUnlocked() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let keychain else { return false }

        var status = SecKeychainStatus()
        guard SecKeychainGetStatus(keychain, &status) == errSecSuccess else { return false }
        if status & UInt32(kSecUnlockStateStatus) != 0 { return true }

        return password.withUnsafeBufferPointer { buffer in
            SecKeychainUnlock(keychain, UInt32(buffer.count), buffer.baseAddress, true) == errSecSuccess
        }
    }

    /// An access policy that lets any application use the item without prompting.
    ///
    /// The default ACL binds to the creating app's code signature, and this app is
    /// ad-hoc signed — the signature changes with every build, the stored ACL stops
    /// matching, and macOS challenges for a password on every TLS handshake.
    ///
    /// Granting "any application" is safe precisely because this keychain is
    /// process-private, randomly named and keyed, absent from the search list, and
    /// destroyed on exit: nothing else can find it, and it does not outlive the app.
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

    /// Unregister and remove this process's keychain.
    func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        if let keychain {
            SecKeychainDelete(keychain)
        }
        try? FileManager.default.removeItem(atPath: path)
        keychain = nil
    }

    // MARK: - Orphans

    /// Remove keychains belonging to K8Secret processes that are no longer running.
    ///
    /// Deliberately leaves alone any keychain whose owning process is still alive:
    /// a second window or a second launch is a normal thing to do, and pulling the
    /// keychain out from under a running instance breaks its client-certificate
    /// TLS and prompts the user.
    /// Non-private so the sweep rules can be tested directly: the singleton only
    /// sweeps once, at first use, so it can't be exercised through `get()`.
    static func removeOrphanedKeychains(excluding current: String) {
        let tmp = NSTemporaryDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: tmp) else { return }

        for entry in entries where entry.hasPrefix(prefix) && entry.hasSuffix(suffix) {
            let full = (tmp as NSString).appendingPathComponent(entry)
            guard full != current else { continue }

            if let pid = owningProcessID(of: entry), isRunning(pid) { continue }
            unregisterAndRemove(at: full)
        }

        // Older builds used a different naming scheme and carried no process id.
        // Those can only be from a previous run, so they always go.
        for entry in entries where entry.hasPrefix("k8secret-") && entry.contains(".keychain")
            && !entry.hasPrefix(prefix) {
            unregisterAndRemove(at: (tmp as NSString).appendingPathComponent(entry))
        }
    }

    /// `k8secret-kc-<pid>-<uuid>.keychain`
    private static func owningProcessID(of filename: String) -> pid_t? {
        let body = filename.dropFirst(prefix.count)
        guard let dash = body.firstIndex(of: "-") else { return nil }
        return pid_t(body[body.startIndex..<dash])
    }

    private static func isRunning(_ pid: pid_t) -> Bool {
        // Signal 0 tests for existence without delivering anything. EPERM means the
        // process exists but isn't ours, which still counts as running.
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Delete through the security subsystem, then remove any remaining file.
    ///
    /// Removing the file alone leaves the registration `SecKeychainCreate` made,
    /// and that dangling entry is what later produces an unexplained password
    /// prompt.
    private static func unregisterAndRemove(at path: String) {
        var existing: SecKeychain?
        if SecKeychainOpen(path, &existing) == errSecSuccess, let existing {
            SecKeychainDelete(existing)
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Exit

    private static var exitHandlerInstalled = false

    /// `applicationWillTerminate` doesn't run for every way an app can end.
    /// `atexit` covers normal exits that skip it; a hard kill still can't be
    /// caught, which is what the orphan sweep above is for.
    private static func installExitHandler() {
        guard !exitHandlerInstalled else { return }
        exitHandlerInstalled = true
        atexit {
            TransientKeychain.shared.cleanup()
        }
    }
}
