import SwiftUI

/// Identifies one cluster window. The serial is what lets the *same* cluster
/// be opened in several windows at once: SwiftUI keys a `WindowGroup`'s
/// windows by their value, so without it, picking "colima" a second time only
/// re-focuses the first window instead of opening another.
struct ClusterRef: Hashable, Codable {
    var context: String
    var serial: Int

    @MainActor private static var counter = 0

    /// A fresh identity, so every open is genuinely a new window.
    @MainActor
    static func next(_ context: String) -> ClusterRef {
        counter += 1
        return ClusterRef(context: context, serial: counter)
    }
}

@main
struct K8SecretApp: App {
    init() {
        SettingsView.apply(
            appearanceOverride: UserDefaults.standard.string(forKey: "appearanceOverride") ?? "system")
        // vNext canvas chrome: every window becomes one gradient world — the
        // titlebar is transparent and content extends under it. Applied on
        // every key/became-visible transition (idempotent) because a
        // representable's async hook races window attachment.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didUpdateNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let w = note.object as? NSWindow, w.styleMask.contains(.titled) else { return }
                MainActor.assumeIsolated {
                    // Each of the three is checked on its own. The guard used to
                    // read `!w.titlebarAppearsTransparent` and skip the whole
                    // block, treating one property as a proxy for all three —
                    // so once transparency was set, `.fullSizeContentView` could
                    // never be restored. Anything that dropped it later (a
                    // fullscreen toggle, a tab merge, AppKit rebuilding the frame)
                    // left the content no longer extending under the titlebar,
                    // and the gradient stopped short of the top of the window:
                    // a transparent strip across the top showing whatever sat
                    // behind it.
                    //
                    // These run on didUpdate, which is frequent, so each one is a
                    // cheap comparison and assigns only when it actually differs.
                    if !w.titlebarAppearsTransparent { w.titlebarAppearsTransparent = true }
                    if w.titleVisibility != .hidden { w.titleVisibility = .hidden }
                    if !w.styleMask.contains(.fullSizeContentView) {
                        w.styleMask.insert(.fullSizeContentView)
                    }
                }
            }
        }
        // Clean up port forwards when the app terminates
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { _ in
            // Delivered on the main queue, so main-actor state is safe to touch here.
            MainActor.assumeIsolated {
                PortForwardManager.shared.stopAll()
                // macOS 14 has no memory-only PKCS#12 import, so anything it
                // forced into the keychain is taken back out here.
                ImportedIdentities.removeAll()
            }
        }
    }

    var body: some Scene {
        // Default window — connects to last-used or current context
        WindowGroup(id: "cluster") {
            ClusterWindow(initialContext: nil)
                .frame(minWidth: 660, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 720)
        .commands {
            WindowCommands()
            CommandGroup(replacing: .appInfo) {
                Button("About K8Secret") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        NSApplication.AboutPanelOptionKey.applicationName: "K8Secret",
                        NSApplication.AboutPanelOptionKey.applicationVersion: AppConstants.version,
                    ])
                }

                Divider()

                Button("Check for Updates...") {
                    Task {
                        await UpdateChecker.shared.checkForUpdates()
                        UpdateChecker.shared.sheetRequested = true
                    }
                }
            }
        }

        // ⌘N cluster chooser. A `Window`, not a `WindowGroup`: the chooser is
        // a singleton, so pressing ⌘N ten times raises the one chooser instead
        // of stacking ten identical ones.
        Window("Open a Cluster", id: "launcher") {
            LauncherView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Context-specific windows — opened via openWindow(id:value:). Keyed
        // by ClusterRef so any number of them can be open at once, including
        // several onto the same cluster in different namespaces.
        WindowGroup(id: "cluster-ctx", for: ClusterRef.self) { $ref in
            ClusterWindow(initialContext: ref?.context)
                .frame(minWidth: 660, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 720)

        // Log stream window
        WindowGroup(id: "log-stream", for: LogStreamID.self) { $logID in
            if let logID {
                LogStreamWindow(logID: logID)
            } else {
                Text("No log stream specified")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 900, height: 600)
    }
}

/// Debug-only latch: the probe below runs in the *first* window only. Without
/// it every window it opens would open nine more.
@MainActor
enum MultiWindowProbe {
    static var fired = false
}

/// The File menu's window commands. These live in their own `Commands` type
/// on purpose: `@Environment(\.openWindow)` read from the `App` struct itself
/// resolves before any scene exists and silently does nothing when invoked —
/// which is exactly how ⌘N stopped opening anything. Read from a `Commands`
/// conformer it is bound to a live scene.
struct WindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // ⌘N is a cluster chooser (the Postico/Terminal model): pick the
            // context first, then get a window bound to it. ⇧⌘N clones the
            // current window's cluster straight away.
            Button("New Window…") {
                openWindow(id: "launcher")
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Window with Current Context") {
                openWindow(id: "cluster")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}

/// Each window owns its own AppState, so multiple windows = multiple independent clusters.
struct ClusterWindow: View {
    let initialContext: String?
    @Environment(\.openWindow) private var openWindow
    @State private var state: AppState

    init(initialContext: String?) {
        self.initialContext = initialContext
        self._state = State(initialValue: AppState(initialContext: initialContext))
    }

    var body: some View {
        ContentView()
            .environment(state)
            .navigationTitle(windowTitle)
            .background(WindowConfigurator())
            .task {
                // Debug-only (same contract as UITestTour): surface the ⌘N
                // launcher so it can be screenshot-verified without input.
                // Debug-only: render the app mark to PNGs for the icon set, so
                // the icon is the same artwork the launch assembles rather than
                // a drawing of it that drifts.
                if let dir = ProcessInfo.processInfo.environment["K8SECRET_RENDER_ICON"] {
                    for side in [16, 32, 64, 128, 256, 512, 1024] {
                        let canvas = CGFloat(side)
                        let renderer = ImageRenderer(
                            content: ClusterMark(size: canvas * 0.94)
                                .frame(width: canvas, height: canvas))
                        renderer.scale = 1
                        guard let image = renderer.nsImage,
                              let tiff = image.tiffRepresentation,
                              let rep = NSBitmapImageRep(data: tiff),
                              let png = rep.representation(using: .png, properties: [:]) else { continue }
                        try? png.write(to: URL(fileURLWithPath: dir)
                            .appendingPathComponent("mark-\(side).png"))
                    }
                    NSApplication.shared.terminate(nil)
                }
                if ProcessInfo.processInfo.environment["K8SECRET_UITEST_LAUNCHER"] == "1" {
                    openWindow(id: "launcher")
                }
                // Debug-only: prove the multi-window path opens N independent
                // cluster windows, including several onto the same context.
                if let n = Int(ProcessInfo.processInfo.environment["K8SECRET_UITEST_WINDOWS"] ?? ""), n > 0,
                   !MultiWindowProbe.fired {
                    MultiWindowProbe.fired = true
                    let names = (try? KubeConfig.load().contexts.map(\.name)) ?? []
                    guard !names.isEmpty else { return }
                    for i in 0..<n {
                        openWindow(id: "cluster-ctx", value: ClusterRef.next(names[i % names.count]))
                        try? await Task.sleep(for: .milliseconds(120))
                    }
                }
            }
    }

    private var windowTitle: String {
        switch state.connectionState {
        case .connected:
            return state.context.isEmpty ? "K8Secret" : "K8Secret — \(state.context)"
        case .connecting:
            return "K8Secret — Connecting…"
        case .disconnected:
            return "K8Secret — Disconnected"
        }
    }
}
