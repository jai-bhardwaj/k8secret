import XCTest
import Security

/// Base class for every suite that can reach the transient keychain.
///
/// A test that regresses keychain handling must fail, not ask. Without this,
/// a regression in the unlock path surfaces as a SecurityAgent password dialog:
/// the run hangs until a human answers, and if the run is killed instead, the
/// pending request outlives the process — securityd re-presents the dialog to
/// whoever is at the machine, long after xctest is gone. That exact zombie
/// prompt has been observed once; this is what prevents the second one.
///
/// `SecKeychainSetUserInteractionAllowed(false)` is process-wide: any keychain
/// operation that would have prompted fails with `errSecInteractionNotAllowed`
/// instead, which XCTest reports as an ordinary failure. Restored on teardown
/// so nothing leaks into whatever runs in this process afterwards.
class PromptFreeTestCase: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        SecKeychainSetUserInteractionAllowed(false)
    }

    override func tearDownWithError() throws {
        SecKeychainSetUserInteractionAllowed(true)
        try super.tearDownWithError()
    }
}
