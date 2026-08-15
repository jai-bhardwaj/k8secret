import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

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
                    .animation(.easeOut(duration: 0.2), value: state.toastMessage)
                }
            }
            .frame(maxHeight: .infinity)

            StatusBarView()
        }
        .background {
            // Invisible ⌘K hook, per-window so multi-window stays independent.
            Button("") { state.paletteOpen.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
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
            } detail: {
                detailColumn
            }
            .toolbar { scopeToolbar }
        }
    }

    /// The namespace scope control: a filter in the toolbar, not a place in
    /// the sidebar. "All Namespaces" aggregates lists with a namespace badge
    /// per row; selecting any row scopes back into its own namespace.
    @ToolbarContentBuilder
    private var scopeToolbar: some ToolbarContent {
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
                HStack(spacing: 5) {
                    Text("namespace")
                        .foregroundStyle(.secondary)
                    Text(state.allNamespaces ? "all" : (state.selectedNamespace?.name ?? "—"))
                        .fontWeight(.semibold)
                }
                .font(.callout)
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
        HStack(spacing: 8) {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .red : .green)
            Text(message)
                .font(.system(.caption, design: .monospaced))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}
