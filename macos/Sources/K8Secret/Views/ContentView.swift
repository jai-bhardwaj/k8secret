import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    /// The launch sequence owns the window until it has actually played —
    /// connecting to a local cluster takes ~200ms, which is not a launch
    /// experience, it's a flicker.
    @State private var bootDone = false
    @State private var showFirstRun = Welcome.needsFirstRun
    @State private var showWhatsNew = false
    @Environment(\.openWindow) private var openWindow
    /// Live content width, driving the prototype's breakpoints: <1120 narrows
    /// the list column, <980 auto-collapses the rail, <780 goes single-pane.
    @State private var contentWidth: CGFloat = 1200


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
                if !bootDone {
                    BootView(context: state.context)
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                }
                switch state.connectionState {
                case .connecting:
                    connectingView
                        .opacity(bootDone ? 1 : 0)
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

                // Cluster switcher — rises from the status bar it was clicked
                // in (the VS Code quick-pick pattern). No scrim: a transparent
                // tap-catcher closes it, the canvas stays undimmed.
                if state.clusterSwitcherOpen {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { state.clusterSwitcherOpen = false }
                    ClusterSwitcherPanel()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 10)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // First run / what's new — the app introducing itself.
                if showFirstRun {
                    scrim {}
                    FirstRunView(
                        contexts: state.availableContexts,
                        onPick: { ctx in
                            Welcome.completeFirstRun()
                            withAnimation(Theme.easeOut) { showFirstRun = false }
                            Task { await state.switchContext(ctx) }
                        },
                        onSkip: {
                            Welcome.completeFirstRun()
                            withAnimation(Theme.easeOut) { showFirstRun = false }
                        })
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                } else if showWhatsNew {
                    scrim {}
                    WhatsNewView {
                        Welcome.markVersionSeen()
                        withAnimation(Theme.easeOut) { showWhatsNew = false }
                    }
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
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
        .sheet(isPresented: Binding(
            get: { UpdateChecker.shared.sheetRequested },
            set: { UpdateChecker.shared.sheetRequested = $0 }
        )) {
            UpdateSheetView(checker: UpdateChecker.shared)
                .environment(state)
        }
        .motion(Motion.panel, value: state.paletteOpen)
        .motion(Motion.panel, value: state.settingsOpen)
        .motion(Motion.panel, value: state.confirmAction != nil)
        .motion(Motion.panel, value: state.clusterSwitcherOpen)
        .task {
            UITestTour.startIfRequested(state: state)
            // Debug-only: hold the boot sequence on screen long enough to
            // capture it (same contract as the tour — inert normally).
            // Play the launch sequence and connect concurrently; the window
            // opens when both are done, so the animation is always seen and
            // never costs the user time on a slow cluster.
            let hold = Double(ProcessInfo.processInfo.environment["K8SECRET_UITEST_BOOT"] ?? "") ?? 1.9
            async let played: Void = Task.sleep(for: .seconds(hold))
            await state.connect()
            try? await played
            withAnimation(.easeOut(duration: 0.5)) { bootDone = true }
            // Debug-only surfacing, same contract as the tour.
            switch ProcessInfo.processInfo.environment["K8SECRET_UITEST_WELCOME"] {
            case "first": showFirstRun = true
            case "whatsnew": showWhatsNew = true
            default: showWhatsNew = Welcome.needsWhatsNew
            }
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
        BootView(context: state.context)
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
        // Overview and Events are single-pane; resources are list + detail —
        // or list OR detail below the compact breakpoint.
        HStack(spacing: 0) {
            VNextSidebar(autoCollapsed: contentWidth < 980)
            Group {
                switch state.selectedDestination {
                case .overview:
                    OverviewView()
                case .events:
                    EventsFeedView()
                case .resource:
                    if contentWidth < 780 {
                        compactResource
                    } else {
                        HStack(spacing: 0) {
                            contentColumn
                                .frame(width: contentWidth < 1120 ? 280 : 320)
                                .frame(maxHeight: .infinity, alignment: .top)
                            detailColumn
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.size.width, initial: true) { _, w in
                        contentWidth = w
                    }
            }
        }
        .onChange(of: currentSelectionID) { _, new in
            // In compact mode, picking a row pushes the detail pane.
            if contentWidth < 780, new != nil {
                withAnimation(Theme.easeOut) { state.compactShowDetail = true }
            }
        }
        .onChange(of: state.selectedResourceType) { _, _ in
            state.compactShowDetail = false
        }
        .toolbar { scopeToolbar }
        .toolbarBackground(.hidden, for: .windowToolbar)
    }

    /// Single-pane resources below ~780pt: the list fills the pane; selecting
    /// pushes the detail with a back chevron, like the prototype's compact
    /// media query.
    @ViewBuilder
    private var compactResource: some View {
        if state.compactShowDetail {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        withAnimation(Theme.easeOut) { state.compactShowDetail = false }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text(state.selectedResourceType.rawValue)
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(Theme.text2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                detailColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            contentColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    /// The id of whatever is selected in the current resource type — compact
    /// navigation watches this to know a row was picked.
    private var currentSelectionID: String? {
        switch state.selectedResourceType {
        case .secrets: state.selectedSecret?.id
        case .deployments: state.selectedDeployment?.id
        case .pods: state.selectedPod?.id
        case .services: state.selectedService?.id
        case .configmaps: state.selectedConfigMap?.id
        case .cronjobs: state.selectedCronJob?.id
        case .ingresses: state.selectedIngress?.id
        }
    }

    /// The prototype's titlebar, verbatim: [toggle] [context pill] [namespace
    /// pill] ————— [search pill] [settings]. Every control is a translucent
    /// capsule on the canvas (plain button styles — never native toolbar
    /// chrome), and the search is pushed flush right by a flexible spacer.
    @ToolbarContentBuilder
    private var scopeToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(Theme.easeOut) { state.sidebarCollapsed.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("\\", modifiers: .command)
            .help("\(state.sidebarCollapsed ? "Show" : "Hide") sidebar (⌘\\)")
        }
        // No context pill here: the cluster switcher lives in the status bar
        // (click "Connected · <ctx>"), and identity is already everywhere —
        // the tint paints the whole canvas.
        ToolbarItem(placement: .navigation) {
            NamespaceScopeButton()
        }
        // The prototype's .tb-spacer: a flexible space pushing everything
        // after it to the trailing edge.
        ToolbarItem(placement: .automatic) { Spacer() }
        // Trailing group, like the prototype's right cluster after .tb-spacer.
        ToolbarItemGroup(placement: .primaryAction) {
            // The prototype's search field: the ⌘K affordance lives in the
            // titlebar so the palette is discoverable, not a secret handshake.
            Button {
                state.paletteOpen = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text3)
                    Text("Jump to any resource…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text3)
                        .lineLimit(1)
                        .padding(.trailing, 26)
                    Text("⌘K")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.lineStrong, lineWidth: 1))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5.5)
                .background(Theme.inset, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Jump to any resource or action (⌘K)")

            Button {
                state.settingsOpen = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
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

/// The titlebar's pill grammar: a translucent capsule on the canvas with a
/// soft ring — never native toolbar chrome. `strong` uses the stronger ring
/// (the prototype's line-strong on the context/namespace pills).
struct TitlebarPill<Content: View>: View {
    var strong = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 7) { content }
            .padding(.horizontal, 13)
            .padding(.vertical, 5.5)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(strong ? Theme.lineStrong : Theme.line, lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// The namespace scope: a real scope picker, not a flat menu — clusters have
/// hundreds of namespaces, so the popover opens with a filter field focused,
/// "All Namespaces" pinned above a scrolling, clipped list.
struct NamespaceScopeButton: View {
    @Environment(AppState.self) private var state
    @State private var open = false
    @State private var query = ""
    @FocusState private var filterFocused: Bool

    var body: some View {
        Button {
            query = ""
            open.toggle()
        } label: {
            TitlebarPill(strong: true) {
                (Text("namespace ").foregroundStyle(Theme.text2)
                 + Text(state.allNamespaces ? "all" : (state.selectedNamespace?.name ?? "—"))
                    .bold().foregroundStyle(Theme.text))
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 150)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.text3)
            }
        }
        .buttonStyle(.plain)
        .help("Scope every list to one namespace, or all of them")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 6) {
                TextField("Filter namespaces…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($filterFocused)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                scopeRow(name: "All Namespaces",
                         selected: state.allNamespaces,
                         count: state.namespaces.count) {
                    Task { await state.selectNamespaceScope(all: true) }
                    open = false
                }
                Divider().padding(.horizontal, 10)

                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(matches) { ns in
                            scopeRow(name: ns.name,
                                     selected: !state.allNamespaces && state.selectedNamespace?.id == ns.id,
                                     count: nil) {
                                Task {
                                    state.selectedNamespace = ns
                                    await state.selectNamespace(ns)
                                }
                                open = false
                            }
                        }
                        if matches.isEmpty {
                            Text("No matches")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.tertiary)
                                .padding(8)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(maxHeight: 260)
                .padding(.bottom, 6)
            }
            .frame(width: 260)
            .onAppear { filterFocused = true }
        }
    }

    private var matches: [K8sNamespace] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return state.filteredNamespaces }
        return state.filteredNamespaces.filter { $0.name.lowercased().contains(q) }
    }

    private func scopeRow(name: String, selected: Bool, count: Int?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(selected ? 1 : 0)
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 4)
    }
}

/// The cluster switcher: a glass panel rising from the status bar's
/// "Connected · <ctx>" segment. Rows switch this window's context in place;
/// the footer opens the ⌘N launcher for a new window instead.
struct ClusterSwitcherPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CLUSTER")
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(state.availableContexts, id: \.self) { ctx in
                SwitcherRow(
                    name: ctx,
                    tint: tint(for: ctx),
                    isCurrent: ctx == state.context
                ) {
                    state.clusterSwitcherOpen = false
                    guard ctx != state.context else { return }
                    Task { await state.switchContext(ctx) }
                }
            }

            Divider().overlay(Theme.line).padding(.vertical, 4)

            SwitcherRow(name: "Open a cluster in a new window…", tint: nil, isCurrent: false,
                        shortcut: "⌘N") {
                state.clusterSwitcherOpen = false
                openWindow(id: "launcher")
            }
            .padding(.bottom, 6)
        }
        .frame(width: 300)
        .floatGlass(radius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func tint(for ctx: String) -> Theme.ClusterTint {
        let raw = UserDefaults.standard.string(forKey: "clusterTint.\(ctx)") ?? ""
        return Theme.ClusterTint(rawValue: raw) ?? .default
    }

    private struct SwitcherRow: View {
        let name: String
        let tint: Theme.ClusterTint?
        let isCurrent: Bool
        var shortcut: String?
        let action: () -> Void

        @State private var hovering = false
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            Button(action: action) {
                HStack(spacing: 9) {
                    if let tint {
                        Circle()
                            .fill(tint.color)
                            .frame(width: 9, height: 9)
                            .shadow(color: tint.color.opacity(0.6), radius: 3)
                    }
                    Text(name)
                        .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if isCurrent {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.text2)
                    }
                    if let shortcut {
                        Text(shortcut)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.text3)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(hovering ? Color.white.opacity(scheme == .dark ? 0.09 : 0.45) : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
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
                .lineLimit(1)
                .fixedSize()
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
