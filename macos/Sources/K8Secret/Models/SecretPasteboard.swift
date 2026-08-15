import AppKit
import Foundation

/// Clipboard writes for sensitive values.
///
/// A plain `NSPasteboard.setString(_:forType: .string)` is the worst possible way
/// to hand someone a secret: clipboard-manager apps archive it to disk, and
/// Universal Clipboard syncs it to every other device signed into the same Apple
/// account. Both happen silently and both outlive the app.
///
/// Marking the item with the community-standard `org.nspasteboard.ConcealedType`
/// is the opt-out clipboard managers honour, and the value is cleared again after
/// a short window so it doesn't sit in the pasteboard indefinitely.
enum SecretPasteboard {
    /// Recognised by clipboard managers (Alfred, Raycast, Maccy, Paste, …) as
    /// "do not record this".
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// How long a copied secret stays on the clipboard before being cleared.
    static let clearAfter: TimeInterval = 45

    private static var pendingClear: DispatchWorkItem?

    /// Copy a secret value, hidden from clipboard history and auto-cleared.
    static func copySecret(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        pasteboard.setString("", forType: concealedType)

        scheduleClear(of: value, on: pasteboard)
    }

    /// Copy a value that isn't sensitive (an image tag, a cluster IP, a log dump).
    /// Kept here so call sites make the sensitive/not-sensitive choice explicitly.
    static func copyPlain(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private static func scheduleClear(of value: String, on pasteboard: NSPasteboard) {
        pendingClear?.cancel()

        let changeCountAtCopy = pasteboard.changeCount
        let work = DispatchWorkItem {
            // Only clear if nothing else has taken the clipboard since — otherwise
            // we'd wipe something the user copied afterwards.
            guard pasteboard.changeCount == changeCountAtCopy else { return }
            pasteboard.clearContents()
        }
        pendingClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + clearAfter, execute: work)
    }
}
