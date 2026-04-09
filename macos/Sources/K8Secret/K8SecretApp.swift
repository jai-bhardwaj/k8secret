import SwiftUI

@main
struct K8SecretApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var showUpdateSheet = false

    var body: some Scene {
        // Default window — connects to last-used or current context
        WindowGroup(id: "cluster") {
            ClusterWindow(initialContext: nil)
                .frame(minWidth: 900, minHeight: 600)
                .sheet(isPresented: $showUpdateSheet) {
                    UpdateSheetView(checker: UpdateChecker.shared)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
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
                Button("New Window") {
                    openWindow(id: "cluster")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        // Context-specific window — opened via openWindow(id:value:)
        WindowGroup(id: "cluster-ctx", for: String.self) { $ctx in
            ClusterWindow(initialContext: ctx)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
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
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 900, height: 600)
    }
}

/// Each window owns its own AppState, so multiple windows = multiple independent clusters.
struct ClusterWindow: View {
    let initialContext: String?
    @State private var state: AppState

    init(initialContext: String?) {
        self.initialContext = initialContext
        self._state = State(initialValue: AppState(initialContext: initialContext))
    }

    var body: some View {
        ContentView()
            .environment(state)
            .navigationTitle(windowTitle)
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
