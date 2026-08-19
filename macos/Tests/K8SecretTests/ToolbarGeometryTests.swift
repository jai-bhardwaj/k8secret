import XCTest
import AppKit
@testable import K8Secret

/// Where a toolbar control is, measured through AppKit.
///
/// The app's own menus hang off toolbar pills, and the guided tour spotlights
/// them, so both depend on `ToolbarGeometry.rect` answering in the coordinates
/// SwiftUI lays out in. The case that broke is full screen: macOS moves the
/// titlebar into a window of its own, so a toolbar item's `convert(_:to: nil)`
/// stops answering about *our* window — and the old arithmetic, which measured
/// those coordinates against our window's height, put the namespace menu 845pt
/// down a 900pt screen, off the bottom edge.
///
/// A test can't put a window into full screen, but it can reproduce what full
/// screen does: host the item's view in a second window somewhere else on the
/// screen. That is the whole of the bug.
final class ToolbarGeometryTests: XCTestCase {

    /// Keeps a toolbar's single item alive and hands it back on demand.
    private final class OneItem: NSObject, NSToolbarDelegate {
        static let id = NSToolbarItem.Identifier("pill")
        let item: NSToolbarItem

        init(view: NSView) {
            item = NSToolbarItem(itemIdentifier: Self.id)
            item.view = view
            super.init()
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.id] }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.id] }
        func toolbar(_ toolbar: NSToolbar,
                     itemForItemIdentifier id: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { item }
    }

    /// A flipped host, as NSHostingView is — the conversion has to land in
    /// SwiftUI's top-left origin, not AppKit's bottom-left one.
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    private var windows: [NSWindow] = []
    private var delegate: OneItem?

    /// AppKit still releases a closed window itself unless told not to, and
    /// ARC is holding one too — so closing one of these without this is a
    /// double free, and the test process dies with SIGSEGV rather than a
    /// failure.
    private func keep(_ window: NSWindow) -> NSWindow {
        window.isReleasedWhenClosed = false
        windows.append(window)
        return window
    }

    /// A toolbar builds its default items lazily; nothing here is ever on
    /// screen, so the item is inserted explicitly when that hasn't happened.
    private func attach(_ toolbar: NSToolbar, to window: NSWindow) {
        window.toolbar = toolbar
        if toolbar.items.isEmpty {
            toolbar.insertItem(withItemIdentifier: OneItem.id, at: 0)
        }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // No window server (a remote shell, say) means no windows to measure.
        guard NSScreen.main != nil else {
            throw XCTSkip("no window server — skipping AppKit geometry tests")
        }
    }

    override func tearDown() {
        windows.forEach { $0.close() }
        windows = []
        delegate = nil
        super.tearDown()
    }

    /// Builds an app window whose toolbar hosts `pill`, and returns it.
    private func appWindow(frame: NSRect, hosting pill: NSView) -> NSWindow {
        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentView = FlippedView(frame: NSRect(origin: .zero, size: frame.size))
        let toolbar = NSToolbar(identifier: "test")
        let delegate = OneItem(view: pill)
        self.delegate = delegate
        toolbar.delegate = delegate
        attach(toolbar, to: window)
        return keep(window)
    }

    // MARK: -

    /// The windowed case, which always worked: the item lives in the window it
    /// is measured against, and the answer is its top-left offset inside it.
    @MainActor
    func testAnItemInOurOwnWindowIsMeasuredFromTheContentViewsTopLeft() throws {
        let pill = NSView(frame: NSRect(x: 128, y: 681, width: 158, height: 26))
        let window = appWindow(frame: NSRect(x: 170, y: 90, width: 1100, height: 720),
                               hosting: pill)
        window.contentView?.addSubview(pill)

        let rect = try XCTUnwrap(ToolbarGeometry.rect(ofHostedItem: 0, in: window))
        // The content view is flipped, so the subview's own frame is already
        // in the coordinates the answer should come back in.
        XCTAssertEqual(rect.origin.x, 128, accuracy: 0.5)
        XCTAssertEqual(rect.origin.y, 681, accuracy: 0.5)
        XCTAssertEqual(rect.width, 158, accuracy: 0.5)
        XCTAssertEqual(rect.height, 26, accuracy: 0.5)
    }

    /// Full screen, reproduced: the item is hosted in a *different* window,
    /// sitting across the top of the screen, exactly as
    /// `NSToolbarFullScreenWindow` does. The answer must still be relative to
    /// the app window's content view.
    @MainActor
    func testAnItemHostedInAnotherWindowIsStillMeasuredInOurs() throws {
        // App window filling a 1440x900 origin-anchored area.
        let app = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                           styleMask: [.titled, .fullSizeContentView],
                           backing: .buffered, defer: false)
        app.contentView = FlippedView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        _ = keep(app)

        // The titlebar's own window: 55pt tall, along the top of the app's.
        let bar = keep(NSWindow(contentRect: NSRect(x: 0, y: 845, width: 1440, height: 55),
                                styleMask: [.borderless], backing: .buffered, defer: false))
        let pill = NSView(frame: NSRect(x: 50, y: 16, width: 158, height: 26))
        let toolbar = NSToolbar(identifier: "test")
        let delegate = OneItem(view: pill)
        self.delegate = delegate
        toolbar.delegate = delegate
        attach(toolbar, to: app)
        // After the toolbar has taken the view: this is the move full screen
        // makes, and doing it in this order is what stops AppKit putting the
        // view back into the app window's own hierarchy.
        pill.removeFromSuperview()
        bar.contentView?.addSubview(pill)
        pill.frame = NSRect(x: 50, y: 16, width: 158, height: 26)

        let rect = try XCTUnwrap(ToolbarGeometry.rect(ofHostedItem: 0, in: app))

        // The bar's top edge is the app window's top edge, and the pill's top
        // sits 13pt below it (55 - 16 - 26), so 13 is the answer — the same
        // number the app measures in a windowed frame. The old arithmetic
        // answered 900 - 42 = 858 here, and that is the bug: the menu hung
        // from a rectangle 858pt down a 900pt screen.
        XCTAssertEqual(rect.origin.x, 50, accuracy: 0.5)
        XCTAssertEqual(rect.origin.y, 13, accuracy: 0.5,
                       "a toolbar hosted outside the window must still be measured inside it")
        XCTAssertLessThan(rect.maxY, 100,
                          "the menu hangs from this rectangle — it belongs at the top of the window")
    }

    /// A window that isn't at the screen's origin. Converting through the
    /// screen only works if both hops use the same space; getting one of them
    /// wrong shows up as an offset equal to the window's position.
    @MainActor
    func testMeasurementIsIndependentOfWhereTheWindowSitsOnScreen() throws {
        let pillA = NSView(frame: NSRect(x: 40, y: 12, width: 158, height: 26))
        let a = appWindow(frame: NSRect(x: 0, y: 0, width: 900, height: 600), hosting: pillA)
        a.contentView?.addSubview(pillA)
        let first = try XCTUnwrap(ToolbarGeometry.rect(ofHostedItem: 0, in: a))

        let pillB = NSView(frame: NSRect(x: 40, y: 12, width: 158, height: 26))
        let b = appWindow(frame: NSRect(x: 317, y: 204, width: 900, height: 600), hosting: pillB)
        b.contentView?.addSubview(pillB)
        let second = try XCTUnwrap(ToolbarGeometry.rect(ofHostedItem: 0, in: b))

        XCTAssertEqual(first.origin.x, second.origin.x, accuracy: 0.5)
        XCTAssertEqual(first.origin.y, second.origin.y, accuracy: 0.5)
    }
}
