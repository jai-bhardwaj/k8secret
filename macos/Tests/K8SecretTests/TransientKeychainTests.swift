import XCTest
import Security
@testable import K8Secret

/// Lifecycle of the throwaway keychain that holds a client-certificate identity.
///
/// Every prompt this app has shown the user came from this area, and none of them
/// were reproducible from the code alone — they came from *state left behind*: a
/// registration without a file, a keychain deleted out from under a running
/// instance. These pin the rules that keep that from happening.
final class TransientKeychainTests: XCTestCase {

    private let prefix = "k8secret-kc-"

    private func tempKeychainPaths() -> [String] {
        let tmp = NSTemporaryDirectory()
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: tmp)) ?? []
        return entries
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".keychain") }
            .map { (tmp as NSString).appendingPathComponent($0) }
    }

    /// Stand in for a keychain left behind by a process that is gone.
    @discardableResult
    private func makeOrphan(pid: pid_t) throws -> String {
        let path = NSTemporaryDirectory() + "\(prefix)\(pid)-\(UUID().uuidString).keychain"
        var kc: SecKeychain?
        let pw = Array("orphan-test-password".utf8)
        let status = pw.withUnsafeBufferPointer {
            SecKeychainCreate(path, UInt32($0.count), $0.baseAddress, false, nil, &kc)
        }
        try XCTSkipUnless(status == errSecSuccess, "cannot create a keychain in this environment")
        return path
    }

    private func cleanUp(_ path: String) {
        var kc: SecKeychain?
        if SecKeychainOpen(path, &kc) == errSecSuccess, let kc { SecKeychainDelete(kc) }
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Orphans

    func testAKeychainFromADeadProcessIsRemoved() throws {
        // A pid that cannot be running. Left behind, these accumulate one per
        // launch and their dangling registrations produce password prompts.
        let orphan = try makeOrphan(pid: 999_999)
        defer { cleanUp(orphan) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan))

        // Called directly: the singleton sweeps once at first use, so going
        // through get() would be testing whichever test ran first.
        TransientKeychain.removeOrphanedKeychains(excluding: "/nonexistent")

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan),
                       "a keychain whose owning process is gone should be swept")
    }

    func testAKeychainBelongingToALiveProcessIsLeftAlone() throws {
        // Our own pid stands in for a second running instance. Deleting a live
        // instance's keychain breaks its TLS mid-session — which is the prompt
        // this whole type exists to avoid.
        let live = try makeOrphan(pid: ProcessInfo.processInfo.processIdentifier)
        defer { cleanUp(live) }

        TransientKeychain.removeOrphanedKeychains(excluding: "/nonexistent")

        XCTAssertTrue(FileManager.default.fileExists(atPath: live),
                      "a running instance's keychain must survive another instance starting")
    }

    func testTheSweepDoesNotTouchThisProcessesOwnKeychain() {
        let mine = TransientKeychain.shared.get()
        XCTAssertNotNil(mine)

        // A second get() re-runs the sweep; ours has to survive it.
        let again = TransientKeychain.shared.get()
        XCTAssertNotNil(again, "the keychain must still be usable after a sweep")
    }

    // MARK: - Access policy

    func testAccessPolicyIsCreated() throws {
        let access = try XCTUnwrap(
            TransientKeychain.shared.promptlessAccess(label: "test"),
            "without an access policy every key use prompts for a password"
        )

        var acls: CFArray?
        XCTAssertEqual(SecAccessCopyACLList(access, &acls), errSecSuccess)
        XCTAssertFalse((acls as? [SecACL] ?? []).isEmpty, "policy should carry ACL entries")
    }

    // MARK: - Locking

    /// `SecKeychainCreate` sets `lockOnSleep`, and it cannot be turned off —
    /// `SecKeychainSetSettings` prompts even on a keychain we created and hold
    /// unlocked. So the keychain *will* lock behind our back, and the only thing
    /// standing between that and a password prompt is unlocking it ourselves.
    func testAKeychainThatHasLockedIsReopenedWithoutPrompting() throws {
        let keychain = try XCTUnwrap(TransientKeychain.shared.get())

        // What sleep does to us, done deterministically.
        XCTAssertEqual(SecKeychainLock(keychain), errSecSuccess)

        var locked = SecKeychainStatus()
        XCTAssertEqual(SecKeychainGetStatus(keychain, &locked), errSecSuccess)
        XCTAssertEqual(locked & UInt32(kSecUnlockStateStatus), 0,
                       "precondition: the keychain should now be locked")

        XCTAssertTrue(TransientKeychain.shared.ensureUnlocked(),
                      "we hold this keychain's password; failing to use it is what makes macOS ask the user")

        var after = SecKeychainStatus()
        XCTAssertEqual(SecKeychainGetStatus(keychain, &after), errSecSuccess)
        XCTAssertNotEqual(after & UInt32(kSecUnlockStateStatus), 0,
                          "a locked keychain at handshake time is exactly the prompt users reported")
    }

    /// The guard has to be cheap, because it runs on every TLS handshake.
    func testUnlockingAnAlreadyUnlockedKeychainIsANoOp() throws {
        _ = try XCTUnwrap(TransientKeychain.shared.get())

        XCTAssertTrue(TransientKeychain.shared.ensureUnlocked())
        XCTAssertTrue(TransientKeychain.shared.ensureUnlocked(),
                      "repeated calls must stay silent and succeed")
    }

    // MARK: - Naming

    func testKeychainIsNamedWithTheOwningProcess() {
        _ = TransientKeychain.shared.get()

        let mine = tempKeychainPaths().filter {
            ($0 as NSString).lastPathComponent
                .hasPrefix("\(prefix)\(ProcessInfo.processInfo.processIdentifier)-")
        }
        XCTAssertFalse(mine.isEmpty,
                       "the pid in the filename is how a sweep tells an orphan from a live instance")
    }

    func testKeychainLivesInTempAndNotTheUsersKeychainFolder() {
        _ = TransientKeychain.shared.get()

        for path in tempKeychainPaths() {
            XCTAssertTrue(path.hasPrefix(NSTemporaryDirectory()),
                          "must never be written near the user's real keychains")
        }
    }

    func testKeychainIsNotAddedToTheSearchList() throws {
        _ = TransientKeychain.shared.get()

        var list: CFArray?
        try XCTSkipUnless(SecKeychainCopySearchList(&list) == errSecSuccess, "no search list available")
        let searchList = (list as? [SecKeychain]) ?? []

        for keychain in searchList {
            var pathBuffer = [CChar](repeating: 0, count: 2048)
            var length = UInt32(pathBuffer.count)
            guard SecKeychainGetPath(keychain, &length, &pathBuffer) == errSecSuccess else { continue }
            let path = String(cString: pathBuffer)
            XCTAssertFalse(path.contains(prefix),
                           "a transient keychain in the search list would affect every app")
        }
    }
}
