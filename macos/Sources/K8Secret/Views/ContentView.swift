import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false

    var body: some View {
        @Bindable var state = state

        return VStack(spacing: 0) {
            UpdateBannerView(checker: UpdateChecker.shared)

            ZStack {
                switch state.connectionState {
                case .connecting:
                    connectingView
                case .disconnected(let message):
                    DisconnectedView(message: message)
                case .connected:
                    mainView
                }

                // ⌘K command palette
                if state.paletteOpen {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture { state.paletteOpen = false }
                    CommandPaletteView()
                        .padding(.top, 60)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Toast overlay
                if let msg = state.toastMessage {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ToastView(message: msg, isError: state.toastIsError)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 40)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(Theme.spring, value: state.toastMessage)
                }
            }
            .frame(maxHeight: .infinity)

            StatusBarView()
        }
        .background {
            // Invisible per-window shortcuts: ⌘K palette, ⌘, settings.
            Button("") { state.paletteOpen.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
            Button("") { showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(state)
        }
        .motion(Motion.panel, value: state.paletteOpen)
        .task {
            await state.connect()
            await UpdateChecker.shared.checkForUpdates()
        }
        // Single confirmation surface for every irreversible action, so a new
        // destructive operation can't ship without one by simply forgetting to add
        // an alert to its own view.
        .alert(
            state.confirmAction?.title ?? "",
            isPresented: Binding(
                get: { state.confirmAction != nil },
                set: { if !$0 { state.confirmAction = nil } }
            ),
            presenting: state.confirmAction
        ) { action in
            Button("Cancel", role: .cancel) { state.confirmAction = nil }
            Button(action.confirmLabel, role: action.destructive ? .destructive : nil) {
                let work = action.action
                state.confirmAction = nil
                Task { await work() }
            }
        } message: { action in
            Text(action.message)
        }
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Connecting to cluster...")
                .foregroundStyle(.secondary)
                .font(.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var mainView: some View {
        // Overview and Events are single-pane destinations; resources keep the
        // three-column list + detail. Two split views, one sidebar — the
        // sidebar's state lives in AppState so nothing is lost switching.
        switch state.selectedDestination {
        case .overview:
            NavigationSplitView {
                SidebarView()
            } detail: {
                OverviewView()
            }
            .toolbar { scopeToolbar }
        case .events:
            NavigationSplitView {
                SidebarView()
            } detail: {
                EventsFeedView()
            }
            .toolbar { scopeToolbar }
        case .resource:
            NavigationSplitView {
                SidebarView()
            } content: {
                contentColumn
                    .background(Theme.panel)
            } detail: {
                detailColumn
                    .background(Theme.panel)
            }
            .toolbar { scopeToolbar }
        }
    }

    /// The namespace scope control: a filter in the toolbar, not a place in
    /// the sidebar. "All Namespaces" aggregates lists with a namespace badge
    /// per row; selecting any row scopes back into its own namespace.
    @ToolbarContentBuilder
    private var scopeToolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            // The prototype's search field: the ⌘K affordance lives in the
            // toolbar so the palette is discoverable, not a secret handshake.
            Button {
                state.paletteOpen = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                    Text("Jump to any resource…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("⌘K")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("Jump to any resource or action (⌘K)")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings (⌘,)")
        }
        ToolbarItem(placement: .navigation) {
            Menu {
                Button {
                    Task { await state.selectNamespaceScope(all: true) }
                } label: {
                    HStack {
                        Text("All Namespaces")
                        if state.allNamespaces { Spacer(); Image(systemName: "checkmark") }
                    }
                }
                Divider()
                ForEach(state.filteredNamespaces) { ns in
                    Button {
                        Task {
                            state.selectedNamespace = ns
                            await state.selectNamespace(ns)
                        }
                    } label: {
                        HStack {
                            Text(ns.name)
                            if !state.allNamespaces && state.selectedNamespace?.id == ns.id {
                                Spacer(); Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                // One concatenated Text: toolbar Menu labels flatten HStacks
                // and dropped the name entirely.
                (Text("namespace ").foregroundStyle(.secondary)
                 + Text(state.allNamespaces ? "all" : (state.selectedNamespace?.name ?? "—")).bold())
                    .font(.callout)
                    .lineLimit(1)
            }
            .help("Scope every list to one namespace, or all of them")
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch state.selectedResourceType {
        case .secrets:
            SecretsListView()
        case .deployments:
            DeploymentsListView()
        case .pods:
            PodsListView()
        case .services:
            ServicesListView()
        case .configmaps:
            ConfigMapsListView()
        case .cronjobs:
            CronJobsListView()
        case .ingresses:
            IngressesListView()
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch state.selectedResourceType {
        case .secrets:
            SecretDetailView()
        case .deployments:
            DeploymentDetailView()
        case .pods:
            PodDetailView()
        case .services:
            ServiceDetailView()
        case .configmaps:
            ConfigMapDetailView()
        case .cronjobs:
            CronJobDetailView()
        case .ingresses:
            IngressDetailView()
        }
    }
}

struct ToastView: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 0) {
            // The prototype's left status bar: state as form before words.
            RoundedRectangle(cornerRadius: 2)
                .fill(isError ? Theme.bad : Theme.ok)
                .frame(width: 3)
                .padding(.vertical, 2)
            Text(message)
                .font(.system(size: 12.5))
                .lineLimit(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: 340, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.lineStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .accessibilityLabel("\(isError ? "Error" : "Done"): \(message)")
    }
}
