import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow


    var body: some View {
        @Bindable var state = state

        return ZStack {
            // The canvas: one luminous gradient world behind everything,
            // painted by the cluster tint (ocean by default). The module wash
            // layers the destination's hue over it, replaying only when the
            // destination actually changes (identity-keyed).
            Theme.CanvasBackground(
                tint: state.clusterTint,
                hero: heroCanvasActive
            )
            ModuleWashView(moduleKey: state.selectedDestination.moduleKey)

            VStack(spacing: 0) {
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
                    scrim { state.paletteOpen = false }
                    CommandPaletteView()
                        .padding(.top, 60)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Settings — an in-window glass panel, not an NSSheet: sheets
                // are separate windows, so material glass there would sample
                // the desktop instead of our canvas.
                if state.settingsOpen {
                    scrim { state.settingsOpen = false }
                    SettingsView()
                        .transition(.scale(scale: 0.94).combined(with: .offset(y: 14)).combined(with: .opacity))
                }

                // Confirm dialog — same reasoning as settings.
                if let action = state.confirmAction {
                    scrim { state.confirmAction = nil }
                    ConfirmDialogView(action: action)
                        .transition(.scale(scale: 0.94).combined(with: .offset(y: 14)).combined(with: .opacity))
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
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background {
            // Invisible per-window shortcuts: ⌘K palette, ⌘, settings.
            Button("") { state.paletteOpen.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
            Button("") { state.settingsOpen = true }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        }
        .motion(Motion.panel, value: state.paletteOpen)
        .motion(Motion.panel, value: state.settingsOpen)
        .motion(Motion.panel, value: state.confirmAction != nil)
        .task {
            UITestTour.startIfRequested(state: state)
            await state.connect()
            await UpdateChecker.shared.checkForUpdates()
        }
    }

    /// The dim behind any floating panel: gentle, so the canvas stays alive
    /// behind the glass (the prototype's 34% scrim rule).
    private func scrim(dismiss: @escaping () -> Void) -> some View {
        Color.black.opacity(0.30)
            .ignoresSafeArea()
            .onTapGesture(perform: dismiss)
            .transition(.opacity)
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

    /// Overview gets the brighter hero canvas, like the prototype.
    private var heroCanvasActive: Bool {
        if case .connected = state.connectionState,
           state.selectedDestination == .overview { return true }
        return false
    }

    @ViewBuilder
    private var mainView: some View {
        // The prototype's layout, verbatim: a custom rail beside content on
        // one shared canvas — no NavigationSplitView, no opaque columns.
        // Overview and Events are single-pane; resources are list + detail.
        HStack(spacing: 0) {
            VNextSidebar()
            Group {
                switch state.selectedDestination {
                case .overview:
                    OverviewView()
                case .events:
                    EventsFeedView()
                case .resource:
                    HStack(spacing: 0) {
                        contentColumn
                            .frame(width: 320)
                            .frame(maxHeight: .infinity, alignment: .top)
                        detailColumn
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .toolbar { scopeToolbar }
        .toolbarBackground(.hidden, for: .windowToolbar)
    }

    /// The namespace scope control: a filter in the toolbar, not a place in
    /// the sidebar. "All Namespaces" aggregates lists with a namespace badge
    /// per row; selecting any row scopes back into its own namespace.
    @ToolbarContentBuilder
    private var scopeToolbar: some ToolbarContent {
        // The prototype's titlebar order: sidebar toggle, then context pill
        // (beside the traffic lights), then the namespace scope.
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(Theme.easeOut) { state.sidebarCollapsed.toggle() }
            } label: {
                Label("Toggle Sidebar", systemImage: "sidebar.left")
            }
            .keyboardShortcut("\\", modifiers: .command)
            .help("\(state.sidebarCollapsed ? "Show" : "Hide") sidebar (⌘\\)")
        }
        ToolbarItem(placement: .navigation) {
            Menu {
                ForEach(state.availableContexts, id: \.self) { ctx in
                    Button {
                        Task { await state.switchContext(ctx) }
                    } label: {
                        HStack {
                            Text(ctx)
                            if ctx == state.context { Spacer(); Image(systemName: "checkmark") }
                        }
                    }
                    .disabled(ctx == state.context)
                }
                Divider()
                Menu("Open in New Window") {
                    ForEach(state.availableContexts, id: \.self) { ctx in
                        Button {
                            openWindow(id: "cluster-ctx", value: ctx)
                        } label: {
                            Label(ctx, systemImage: "macwindow.badge.plus")
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(state.clusterTint.color)
                        .frame(width: 7, height: 7)
                    Text(state.context)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .help("Kubeconfig context — the dot is this cluster's tint from Settings")
        }
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
                state.settingsOpen = true
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

/// The per-module hue wash: a soft radial of the destination's identity color
/// bleeding from the top-trailing corner over the canvas. Keyed by module so
/// SwiftUI replaces (and re-fades) it only when the destination changes —
/// background polls reuse the same identity and cause zero visual churn.
struct ModuleWashView: View {
    let moduleKey: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        EllipticalGradient(
            stops: [
                .init(color: Theme.moduleHue(moduleKey, scheme: scheme).opacity(0.34), location: 0),
                .init(color: .clear, location: 0.72),
            ],
            center: UnitPoint(x: 0.80, y: -0.12),
            startRadiusFraction: 0,
            endRadiusFraction: 0.85
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .id(moduleKey)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.7), value: moduleKey)
    }
}

/// The single confirmation surface for every irreversible action — an
/// in-window luminous glass dialog matching the prototype: title, message,
/// soft Cancel, white-pill confirm (red text when destructive).
struct ConfirmDialogView: View {
    @Environment(AppState.self) private var state
    let action: AppState.ConfirmAction

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(action.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(action.message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { state.confirmAction = nil }
                    .buttonStyle(Theme.SoftPill())
                    .keyboardShortcut(.cancelAction)
                Button(action.confirmLabel) {
                    let work = action.action
                    state.confirmAction = nil
                    Task { await work() }
                }
                .buttonStyle(DangerAwarePill(destructive: action.destructive))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 430)
        .popGlass(radius: 22)
    }

    /// White pill; destructive actions keep the white pill but speak in red —
    /// the prototype's dialog grammar.
    struct DangerAwarePill: ButtonStyle {
        let destructive: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(destructive ? Color(hex: 0xC6423B) : Color(hex: 0x231646))
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Capsule().fill(.white))
                .shadow(color: .black.opacity(0.32), radius: 9, y: 4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Theme.spring, value: configuration.isPressed)
        }
    }
}

/// Makes the titlebar part of the canvas: transparent titlebar + full-size
/// content, so the window is one gradient world and the toolbar pills float
/// on it (the prototype's chrome).
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        Self.configureWhenAttached(v, attempts: 0)
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        Self.configureWhenAttached(nsView, attempts: 0)
    }

    /// The view can be created before it's in a window; retry briefly until
    /// the window exists (observed: nil on the first main-queue hop).
    private static func configureWhenAttached(_ v: NSView, attempts: Int) {
        DispatchQueue.main.async { [weak v] in
            guard let v else { return }
            guard let w = v.window else {
                if attempts < 20 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        configureWhenAttached(v, attempts: attempts + 1)
                    }
                }
                return
            }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
        }
    }
}

struct ToastView: View {
    let message: String
    let isError: Bool
    // Scheme from AppKit's effectiveAppearance, not the environment: both the
    // colorScheme environment and dynamic NSColors misreport inside this
    // transition subtree (observed light in a provably dark window).
    private var scheme: ColorScheme { Theme.currentScheme }

    var body: some View {
        HStack(spacing: 0) {
            // The prototype's left status bar: state as form before words.
            RoundedRectangle(cornerRadius: 2)
                .fill(isError ? Theme.bad(scheme) : Theme.ok(scheme))
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
        .background {
            // Glass toast: material + veil, colors scheme-resolved by hand
            // because this subtree renders detached (see `scheme` above).
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(scheme == .dark ? 0.18 : 0.45), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .accessibilityLabel("\(isError ? "Error" : "Done"): \(message)")
    }
}
