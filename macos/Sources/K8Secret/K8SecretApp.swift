import SwiftUI

@main
struct K8SecretApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var showUpdateSheet = false

    init() {
        SettingsView.apply(
            appearanceOverride: UserDefaults.standard.string(forKey: "appearanceOverride") ?? "system")
        // vNext canvas chrome: every window becomes one gradient world — the
        // titlebar is transparent and content extends under it. Applied on
        // every key/became-visible transition (idempotent) because a
        // representable's async hook races window attachment.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didUpdateNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let w = note.object as? NSWindow,
                      w.styleMask.contains(.titled),
                      !w.titlebarAppearsTransparent else { return }
                MainActor.assumeIsolated {
                    w.titlebarAppearsTransparent = true
                    w.titleVisibility = .hidden
                    w.styleMask.insert(.fullSizeContentView)
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
            }
            // Remove the throwaway keychain holding any client-cert identity.
            TransientKeychain.shared.cleanup()
        }
    }

    var body: some Scene {
        // Default window — connects to last-used or current context
        WindowGroup(id: "cluster") {
            ClusterWindow(initialContext: nil)
                .frame(minWidth: 900, minHeight: 600)
                .sheet(isPresented: $showUpdateSheet) {
                    UpdateSheetView(checker: UpdateChecker.shared)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 720)
        .commands {
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
                        showUpdateSheet = true
                    }
                }
            }

            CommandGroup(replacing: .newItem) {
                // ⌘N is a cluster chooser (the Postico/Terminal model): pick
                // the context first, then get a window bound to it. ⇧⌘N keeps
                // the old "clone this window's context" behavior.
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

        // ⌘N cluster chooser — a small fixed launcher listing every context.
        WindowGroup(id: "launcher") {
            LauncherView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Context-specific window — opened via openWindow(id:value:)
        WindowGroup(id: "cluster-ctx", for: String.self) { $ctx in
            ClusterWindow(initialContext: ctx)
                .frame(minWidth: 900, minHeight: 600)
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
                if ProcessInfo.processInfo.environment["K8SECRET_UITEST_LAUNCHER"] == "1" {
                    openWindow(id: "launcher")
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
