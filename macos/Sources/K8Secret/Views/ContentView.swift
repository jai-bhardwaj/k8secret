import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    /// The launch sequence owns the window until it has actually played —
    /// connecting to a local cluster takes ~200ms, which is not a launch
    /// experience, it's a flicker.
    @State private var bootDone = false
    /// The app is not in the view tree until the launch hands over — connect()
    /// finishes long before the sequence does, and without this the whole
    /// interface renders behind the launch.
    @State private var appVisible = false
    /// The launch's words leave before the app arrives.
    @State private var launchCopyGone = false
    /// The flight: the mark leaves the launch composition for the rail slot.
    @State private var markHandedOff = false
    /// True once it has arrived — the rail draws its own icon from here on and
    /// the flying copy retires. Both are the same mark on the same rectangle,
    /// so the swap is invisible.
    @State private var markLanded = false
    /// The mark's entrance in the launch composition.
    @State private var markAssembled = false
    @State private var showFirstRun = Welcome.needsFirstRun
    @State private var showWhatsNew = false
    @Environment(\.openWindow) private var openWindow
    /// Live content width, driving the prototype's breakpoints: <1120 narrows
    /// the list column, <980 auto-collapses the rail, <780 goes single-pane.
    @State private var contentWidth: CGFloat = 1200
    @Environment(\.colorScheme) private var scheme
    /// This window, so the namespace menu can measure the toolbar pill it
    /// hangs from — AppKit knows where toolbar items are, SwiftUI does not.
    @State private var hostWindow: NSWindow?


    var body: some View {
        @Bindable var state = state

        return ZStack {
            // The canvas: one luminous gradient world behind everything,
            // painted by the cluster tint (ocean by default). The module wash
            // layers the destination's hue over it, replaying only when the
            // destination actually changes (identity-keyed).
            Theme.CanvasBackground(
                tint: state.clusterTint,
                // The launch is the hero moment: it gets the full canvas from
                // the first frame, rather than the flatter connecting-state
                // one that then bloomed into a gradient once connect returned.
                hero: heroCanvasActive || !appVisible
            )
            ModuleWashView(moduleKey: state.selectedDestination.moduleKey)

            VStack(spacing: 0) {
            UpdateBannerView(checker: UpdateChecker.shared)

            ZStack {
                // Mounted from the first frame, hidden with opacity — never
                // with `if`. Inserting the app later would install its toolbar
                // later, and the window's top inset arrives with the toolbar:
                // the content would lay out under the titlebar and then slide
                // down through it, colliding with the toolbar pills on the way.
                Group {
                    switch state.connectionState {
                    case .connecting:
                        connectingView
                    case .disconnected(let message):
                        DisconnectedView(message: message)
                    case .connected:
                        mainView
                    }
                }
                .opacity(appVisible ? 1 : 0)

                if !bootDone {
                    BootView(context: state.context,
                             phase: state.launchPhase,
                             copyGone: launchCopyGone)
                        // Centred in the window, not inside the app's chrome.
                        // SwiftUI installs the NSToolbar a frame or two after
                        // the first layout, which grows the top safe area by
                        // the toolbar's height — and a composition centred in
                        // that area visibly slid down when it arrived.
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(2)
                }

                // ⌘K command palette.
                //
                // Every floating layer below owns its animation, scoped to its
                // own `ZStack`. Driving them from a modifier on the app's root
                // put each open and close in the same transaction as whatever
                // else was changing — and this app polls the cluster every
                // second, so a refresh landing mid-transition would interrupt
                // it. That is what made closing a panel look like it stuttered.
                ZStack {
                    if state.paletteOpen {
                        scrim { state.paletteOpen = false }
                        CommandPaletteView()
                            .padding(.top, 60)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(Motion.panel, value: state.paletteOpen)

                // Settings — an in-window glass panel, not an NSSheet: sheets
                // are separate windows, so material glass there would sample
                // the desktop instead of our canvas.
                ZStack {
                    if state.settingsOpen {
                        scrim { state.settingsOpen = false }
                        SettingsView()
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }
                .animation(Motion.panel, value: state.settingsOpen)

                // Confirm dialog — same reasoning as settings.
                ZStack {
                    if let action = state.confirmAction {
                        scrim { state.confirmAction = nil }
                        ConfirmDialogView(action: action)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }
                .animation(Motion.panel, value: state.confirmAction != nil)

                // Namespace menu — hangs from the toolbar pill, drawn on our
                // own canvas rather than in a native popover.
                ZStack {
                    if state.namespaceMenuOpen {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .onTapGesture { state.namespaceMenuOpen = false }
                        NamespaceMenuPanel()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .offset(x: namespaceMenuOrigin.x, y: namespaceMenuOrigin.y)
                            .ignoresSafeArea()
                            .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
                    }
                }
                .animation(Motion.panel, value: state.namespaceMenuOpen)

                // Cluster switcher — rises from the status bar it was clicked
                // in (the VS Code quick-pick pattern). No scrim: a transparent
                // tap-catcher closes it, the canvas stays undimmed.
                ZStack {
                    if state.clusterSwitcherOpen {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .onTapGesture { state.clusterSwitcherOpen = false }
                        ClusterSwitcherPanel()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(.leading, 10)
                            .padding(.bottom, 8)
                            // The same grammar as the namespace menu: it grows
                            // from the corner it is anchored to, rather than
                            // sliding in from off-screen.
                            .transition(.scale(scale: 0.96, anchor: .bottomLeading).combined(with: .opacity))
                    }
                }
                .animation(Motion.panel, value: state.clusterSwitcherOpen)

                // First run / what's new — the app introducing itself.
                if showFirstRun {
                    scrim {}
                    FirstRunView(
                        contexts: state.availableContexts,
                        onPick: { ctx in
                            Welcome.completeFirstRun()
                            withAnimation(Theme.easeOut) { showFirstRun = false }
                            Task {
                                await state.switchContext(ctx)
                                await startTour()
                            }
                        },
                        onSkip: {
                            Welcome.completeFirstRun()
                            withAnimation(Theme.easeOut) { showFirstRun = false }
                            Task { await startTour() }
                        })
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                } else if showWhatsNew {
                    scrim {}
                    WhatsNewView { takeTour in
                        Welcome.markVersionSeen()
                        withAnimation(Theme.easeOut) { showWhatsNew = false }
                        // Skipping is an answer, not a deferral: recording it
                        // stops the app asking again on the next patch.
                        if !takeTour { Welcome.completeTour() }
                        if takeTour {
                            Task {
                                // Let the panel clear before the spotlight lands.
                                try? await Task.sleep(for: .milliseconds(320))
                                withAnimation(Theme.easeOut) { state.tourStep = 0 }
                            }
                        }
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
            .overlayPreferenceValue(MarkSlotKey.self) { slots in
                flightLayer(slots)
            }


            StatusBarView()
                .opacity(appVisible ? 1 : 0)
            }
        }
        .overlayPreferenceValue(TourSpotKey.self) { spots in
            // At window level on purpose: the tour spotlights the status bar
            // too, which lives outside the content stack.
            // Ignoring the safe area here is what keeps the spotlight honest:
            // the scrim covers the titlebar, so the rectangles it punches out
            // must be measured in that same full-window space.
            GeometryReader { proxy in
                if state.tourStep != nil {
                    GuidedTourView(step: Binding(get: { state.tourStep },
                                                 set: { state.tourStep = $0 }),
                                   spots: spots,
                                   toolbarSpots: toolbarSpots,
                                   proxy: proxy)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        // Every accent in this window follows its cluster's canvas.
        .environment(\.clusterAccent, state.clusterTint.accent(scheme))
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
        .background(WindowReader { hostWindow = $0 })
        .task {
            UITestTour.startIfRequested(state: state)
            // The launch is a first impression, not a per-window tax. Windows
            // two through ten of a session open straight into the app and just
            // connect — nobody wants to watch the ceremony ten times.
            guard !LaunchCeremony.played else {
                appVisible = true
                markLanded = true
                bootDone = true
                await state.connect()
                await UpdateChecker.shared.checkForUpdates()
                return
            }
            LaunchCeremony.played = true
            // Debug-only: hold the boot sequence on screen long enough to
            // capture it (same contract as the tour — inert normally).
            // Play the launch sequence and connect concurrently; the window
            // opens when both are done, so the animation is always seen and
            // never costs the user time on a slow cluster.
            let hold = Double(ProcessInfo.processInfo.environment["K8SECRET_UITEST_BOOT"] ?? "") ?? 1.7
            async let played: Void = Task.sleep(for: .seconds(hold))
            await state.connect()
            try? await played
            // Four beats: the words leave, the app fades up in the space they
            // vacated, the mark flies to its slot in the rail, and the launch
            // retires once the mark is home.
            withAnimation(.easeOut(duration: 0.30)) { launchCopyGone = true }
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.easeOut(duration: 0.50)) { appVisible = true }
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.spring(response: 0.82, dampingFraction: 0.88)) { markHandedOff = true }
            try? await Task.sleep(for: .milliseconds(820))
            // No animation: the rail's own mark occupies the identical
            // rectangle, so handing over is a swap nobody can see.
            markLanded = true
            bootDone = true
            // Debug-only surfacing, same contract as the tour.
            switch ProcessInfo.processInfo.environment["K8SECRET_UITEST_WELCOME"] {
            case "first": showFirstRun = true
            case "whatsnew": showWhatsNew = true
            case "whatsnewtour":
                // Debug-only: the update panel, then the hand-off it offers.
                showWhatsNew = true
                try? await Task.sleep(for: .seconds(2))
                Welcome.markVersionSeen()
                withAnimation(Theme.easeOut) { showWhatsNew = false }
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(Theme.easeOut) { state.tourStep = 0 }
                // Then walk it, so the motion between stops can be watched.
                for stop in 1...4 {
                    try? await Task.sleep(for: .seconds(2))
                    state.tourStep = stop
                }
            case "nsmenu": state.namespaceMenuOpen = true
            case "switcher": state.clusterSwitcherOpen = true
            case "settings": state.settingsOpen = true
            case "confirm":
                state.confirm(title: "Restart web?",
                              message: "A rolling restart replaces every pod in this deployment, one batch at a time.",
                              confirmLabel: "Restart",
                              destructive: false) {}
            case "logs":
                // Debug-only: land in a pod's live log window.
                await state.selectResourceType(.pods)
                for _ in 0..<25 where state.pods.isEmpty {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                if let pod = state.pods.first(where: { $0.phase == "Running" }) ?? state.pods.first {
                    state.selectedPod = pod
                    openWindow(value: LogStreamID(context: state.context,
                                                  namespace: pod.namespace,
                                                  pod: pod.name,
                                                  container: pod.containers.first?.name ?? ""))
                }
            case "bulk":
                await state.selectResourceType(.secrets)
                for _ in 0..<25 where state.secrets.isEmpty {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                if let secret = state.secrets.first {
                    state.selectedSecret = secret
                    await state.selectSecret(secret)
                    state.showBulkImport = true
                }
            case "show":
                // Debug-only: land on a resource type with its first row
                // selected, so any pane can be screenshot-verified.
                if let raw = ProcessInfo.processInfo.environment["K8SECRET_UITEST_SHOW"],
                   let type = ResourceType(rawValue: raw) {
                    await state.selectNamespaceScope(all: true)
                    await state.selectResourceType(type)
                    // Wait for the list rather than guessing at a delay.
                    for _ in 0..<25 where state.count(of: type) == 0 {
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                    switch type {
                    case .deployments: state.selectedDeployment = state.deployments.first
                    case .pods:
                        state.selectedPod = state.pods.first
                        if ProcessInfo.processInfo.environment["K8SECRET_UITEST_TAB"] == "yaml" {
                            state.podDetailTab = .yaml
                        }
                    case .services: state.selectedService = state.services.first
                    case .configmaps: state.selectedConfigMap = state.configMaps.first
                    case .cronjobs: state.selectedCronJob = state.cronJobs.first
                    case .ingresses: state.selectedIngress = state.ingresses.first
                    case .secrets: if let hit = state.secrets.first {
                        state.selectedSecret = hit
                        await state.selectSecret(hit)
                    }
                    }
                }
            case "closetest":
                // Debug-only: open each layer and close it again, so the
                // closing animation can be captured (pair with SLOWMO).
                state.namespaceMenuOpen = true
                try? await Task.sleep(for: .seconds(2))
                state.namespaceMenuOpen = false
                try? await Task.sleep(for: .seconds(3))
                state.clusterSwitcherOpen = true
                try? await Task.sleep(for: .seconds(2))
                state.clusterSwitcherOpen = false
            case "settingsclose":
                state.settingsOpen = true
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(Motion.panel) { state.settingsOpen = false }
            case "tour":
                state.tourStep = Int(ProcessInfo.processInfo.environment["K8SECRET_UITEST_TOURSTEP"] ?? "") ?? 0
            default:
                showWhatsNew = Welcome.needsWhatsNew
                // Someone who has used the app before the tour existed still
                // gets it — once, and never in the middle of an update note.
                if !showWhatsNew && !showFirstRun { await startTour() }
            }
            await UpdateChecker.shared.checkForUpdates()
        }
    }

    /// The toolbar controls the tour points at, measured through AppKit —
    /// NSToolbar hosts them outside the view tree, so no preference can see
    /// them, and a stop that can't be measured used to leave the spotlight on
    /// whatever it lit last.
    private var toolbarSpots: [TourSpot: CGRect] {
        let window = hostWindow ?? NSApp.keyWindow
        var out: [TourSpot: CGRect] = [:]
        if let pill = ToolbarGeometry.rect(ofHostedItem: ToolbarGeometry.namespacePill, in: window) {
            out[.namespaceScope] = pill
        }
        if let search = ToolbarGeometry.rect(ofHostedItem: ToolbarGeometry.searchPill, in: window) {
            out[.search] = search
        }
        return out
    }

    /// Where the namespace menu hangs: directly under its pill, measured from
    /// the live toolbar so it stays put at any window width and never guesses.
    private var namespaceMenuOrigin: CGPoint {
        guard let pill = ToolbarGeometry.rect(ofHostedItem: ToolbarGeometry.namespacePill,
                                              in: hostWindow ?? NSApp.keyWindow) else {
            return CGPoint(x: 120, y: 46)
        }
        return CGPoint(x: pill.minX, y: pill.maxY + 6)
    }

    /// The guided tour opens once the app has settled — a coach mark landing
    /// on a control that is still animating reads as broken.
    private func startTour() async {
        guard Welcome.needsTour else { return }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(Theme.easeOut) { state.tourStep = 0 }
    }

    /// The launch mark, drawn exactly once for the whole app. It assembles on
    /// the launch slot, then flies to the rail slot when the app takes over.
    /// Position and scale both come from measured rectangles, so it lands on
    /// the Overview icon to the pixel rather than near it.
    @ViewBuilder
    private func flightLayer(_ slots: [MarkSlot: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            let launch = slots[.launch].map { proxy[$0] }
            let rail = slots[.rail].map { proxy[$0] }
            // Falling back to the launch slot keeps a disconnected window —
            // which has no rail — from flinging the mark to the origin.
            if !markLanded, let target = markHandedOff ? (rail ?? launch) : launch {
                ClusterMark(size: Self.markSize, assembly: markAssembled ? 1 : 0)
                    .scaleEffect((markAssembled ? 1 : 0.92) * target.width / Self.markSize)
                    .shadow(color: .black.opacity(markHandedOff ? 0 : 0.45), radius: 22, y: 16)
                    .position(x: target.midX, y: target.midY)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.7 * Motion.scale, dampingFraction: 0.68)) {
                markAssembled = true
            }
        }
    }

    /// Drawn at one size and scaled by transform — the mark stays vector-sharp
    /// through the flight instead of being re-laid-out every frame.
    private static let markSize: CGFloat = 168

    /// The dim behind any floating panel: gentle, so the canvas stays alive
    /// behind the glass (the prototype's 34% scrim rule).
    private func scrim(dismiss: @escaping () -> Void) -> some View {
        Color.black.opacity(0.30)
            .ignoresSafeArea()
            .onTapGesture(perform: dismiss)
            .transition(.opacity)
    }

    private var connectingView: some View {
        // After launch, a reconnect shows the mark quietly rather than
        // replaying the whole sequence.
        VStack(spacing: 18) {
            ClusterMark(size: 96)
            Text("Reaching \(state.context.isEmpty ? "your cluster" : state.context)")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.text2)
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
        // Overview and Events are single-pane; resources are list + detail —
        // or list OR detail below the compact breakpoint.
        HStack(spacing: 0) {
            VNextSidebar(autoCollapsed: contentWidth < 980,
                         markLanded: markLanded)
                // Measured from a leaf in the background: setting the
                // preference on the sidebar itself would replace everything
                // its own rows publish, and the Secrets stop would vanish.
                .background { Color.clear.tourSpot(.rail) }
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
            .modifier(LaunchHidden(shown: appVisible))
        }
        // No context pill here: the cluster switcher lives in the status bar
        // (click "Connected · <ctx>"), and identity is already everywhere —
        // the tint paints the whole canvas.
        ToolbarItem(placement: .navigation) {
            NamespaceScopeButton()
                .modifier(LaunchHidden(shown: appVisible))
                .tourSpot(.namespaceScope)
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
            .modifier(LaunchHidden(shown: appVisible))
            .tourSpot(.search)

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
            .modifier(LaunchHidden(shown: appVisible))
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

    var body: some View {
        Button {
            state.namespaceMenuOpen.toggle()
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
                    .rotationEffect(.degrees(state.namespaceMenuOpen ? 180 : 0))
            }
        }
        .buttonStyle(.plain)
        .help("Scope every list to one namespace, or all of them")
    }
}

/// The namespace menu: the app's own glass panel, hung under the toolbar pill.
///
/// This was the one native `.popover` left in the app. Everything else — the
/// cluster switcher, the palette, settings, confirmations — is drawn in-window
/// on the canvas, and the popover was both the odd one out visually and the
/// one menu whose rows would not take a click.
struct NamespaceMenuPanel: View {
    @Environment(AppState.self) private var state
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    /// Always present, as in the prototype: a cluster's namespace list is the
    /// one menu you arrive at knowing what you want.
    private let searchable = true

    private static let maxRows: CGFloat = 260
    private var estimatedRows: CGFloat { CGFloat(matches.count) * 29 }
    @State private var rowsHeight: CGFloat?

    private struct RowsHeight: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private var matches: [K8sNamespace] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return state.filteredNamespaces }
        return state.filteredNamespaces.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("NAMESPACE")
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.text3)
                Spacer()
                if state.filteredNamespaces.count > 1 {
                    Text(query.isEmpty
                         ? "\(state.filteredNamespaces.count)"
                         : "\(matches.count) of \(state.filteredNamespaces.count)")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if searchable {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.text3)
                    TextField("Filter namespaces…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .focused($searchFocused)
                        .onSubmit { activate() }
                        .onChange(of: query) { _, _ in highlighted = 0 }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Theme.inset, in: Capsule())
                .overlay(Capsule().strokeBorder(
                    searchFocused ? state.clusterTint.color.opacity(0.85) : Theme.line,
                    lineWidth: searchFocused ? 1.5 : 1))
                .shadow(color: searchFocused ? state.clusterTint.color.opacity(0.35) : .clear,
                        radius: 6)
                .animation(Motion.stateChange, value: searchFocused)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            NamespaceRow(name: "All namespaces",
                         detail: totalPods.map(String.init),
                         accent: state.clusterTint.color,
                         isCurrent: state.allNamespaces,
                         isHighlighted: false) {
                Task { await state.selectNamespaceScope(all: true) }
                close()
            }

            Divider().overlay(Theme.line).padding(.vertical, 4)

            if matches.isEmpty {
                Text("No namespace matches “\(query)”.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                ScrollViewReader { scroller in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, ns in
                                NamespaceRow(name: ns.name,
                                             detail: state.namespacePodCounts[ns.name].map(String.init),
                                             accent: state.clusterTint.color,
                                             isCurrent: !state.allNamespaces && state.selectedNamespace?.id == ns.id,
                                             isHighlighted: searchable && index == highlighted) {
                                    Task {
                                        state.selectedNamespace = ns
                                        await state.selectNamespace(ns)
                                    }
                                    close()
                                }
                                .id(ns.id)
                            }
                        }
                        .background {
                            GeometryReader { g in
                                Color.clear.preference(key: RowsHeight.self, value: g.size.height)
                            }
                        }
                    }
                    // Same as the cluster switcher: measured, clamped, and
                    // clipped by a fixed frame.
                    .frame(height: min(rowsHeight ?? estimatedRows, Self.maxRows))
                    .animation(nil, value: rowsHeight)
                    .onPreferenceChange(RowsHeight.self) { rowsHeight = $0 }
                    .onAppear {
                        searchFocused = searchable
                        if let current = state.selectedNamespace?.id {
                            scroller.scrollTo(current, anchor: .center)
                        }
                        Task { await state.loadNamespacePodCounts() }
                    }
                    .onChange(of: highlighted) { _, new in
                        guard matches.indices.contains(new) else { return }
                        withAnimation(Motion.stateChange) { scroller.scrollTo(matches[new].id, anchor: .center) }
                    }
                }
            }
        }
        .padding(.bottom, 6)
        .frame(width: 280)
        .popGlass(radius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .tourSpot(.namespaceScope)
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onExitCommand { close() }
    }


    private func move(_ delta: Int) {
        guard !matches.isEmpty else { return }
        highlighted = min(max(0, highlighted + delta), matches.count - 1)
    }

    private func activate() {
        guard matches.indices.contains(highlighted) else { return }
        let ns = matches[highlighted]
        Task {
            state.selectedNamespace = ns
            await state.selectNamespace(ns)
        }
        close()
    }

    private func close() {
        // No explicit transaction: the layer that presents this panel owns the
        // animation, so open and close can't disagree about it.
        state.namespaceMenuOpen = false
    }

    /// Pods across every namespace — the total the "All namespaces" row shows.
    private var totalPods: Int? {
        guard !state.namespacePodCounts.isEmpty else { return nil }
        return state.namespacePodCounts.values.reduce(0, +)
    }

    private struct NamespaceRow: View {
        let name: String
        let detail: String?
        let accent: Color
        let isCurrent: Bool
        let isHighlighted: Bool
        let action: () -> Void

        @State private var hovering = false
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                        .opacity(isCurrent ? 1 : 0)
                    Text(name)
                        .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text3)
                            .help("Pods running here")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(hovering || isHighlighted
                            ? Color.white.opacity(scheme == .dark ? 0.09 : 0.45) : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}

/// The cluster switcher: a glass panel rising from the status bar's
/// "Connected · <ctx>" segment. Rows switch this window's context in place;
/// the footer opens the ⌘N launcher for a new window instead.
struct ClusterSwitcherPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""
    @State private var highlighted = 0
    /// nil until the rows have been measured; the estimate covers the first
    /// frame so the panel never opens at one size and settles at another.
    @State private var rowsHeight: CGFloat?
    @FocusState private var searchFocused: Bool

    private struct RowsHeight: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    /// Search earns its place once the list stops fitting in a glance. Below
    /// that it would be a field asking you to type the name of the one thing
    /// already on screen.
    private var searchable: Bool { state.availableContexts.count > 4 }

    private var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return ordered }
        return ordered.filter { $0.lowercased().contains(q) }
    }

    /// Long lists lead with the current cluster and the ones used recently;
    /// everything else follows in the kubeconfig's own order.
    private var ordered: [String] {
        let all = state.availableContexts
        guard grouped else { return all }
        var lead = [state.context]
        lead += AppState.recentContexts.filter { $0 != state.context && all.contains($0) }
        return lead.filter(all.contains) + all.filter { !lead.contains($0) }
    }

    /// Where the "recent" divide falls. Below this the whole list is visible
    /// at a glance and grouping would be ceremony.
    private var grouped: Bool { state.availableContexts.count > 8 }

    /// The tallest the list may grow before it scrolls.
    private static let maxRows: CGFloat = 244

    /// Close enough for one frame; the measurement below is what actually
    /// sizes the panel, so this never has to be exactly right.
    private var estimatedRows: CGFloat {
        CGFloat(matches.count) * 29 + (leadCount > 0 ? 44 : 0)
    }

    /// How many rows belong to the lead group.
    private var leadCount: Int {
        guard grouped, query.isEmpty else { return 0 }
        let all = state.availableContexts
        var lead = Set([state.context])
        lead.formUnion(AppState.recentContexts.filter { all.contains($0) })
        return min(lead.count, 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CLUSTER")
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.text3)
                Spacer()
                // With a handful of clusters the count is noise; with thirty
                // it is the difference between scrolling and searching.
                if state.availableContexts.count > 1 {
                    Text(query.isEmpty
                         ? "\(state.availableContexts.count)"
                         : "\(matches.count) of \(state.availableContexts.count)")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if searchable {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.text3)
                    TextField("Filter clusters…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .focused($searchFocused)
                        .onSubmit { activate() }
                        .onChange(of: query) { _, _ in highlighted = 0 }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Theme.inset, in: Capsule())
                .overlay(Capsule().strokeBorder(
                    searchFocused ? state.clusterTint.color.opacity(0.85) : Theme.line,
                    lineWidth: searchFocused ? 1.5 : 1))
                .shadow(color: searchFocused ? state.clusterTint.color.opacity(0.35) : .clear,
                        radius: 6)
                .animation(Motion.stateChange, value: searchFocused)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }

            if matches.isEmpty {
                Text("No cluster matches “\(query)”.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                // A rounded shell with the scroller inside it: the scrollbar
                // can never ride over the panel's corners.
                ScrollViewReader { scroller in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.element) { index, ctx in
                                if leadCount > 0, index == 0 || index == leadCount {
                                    Text(index == 0 ? "RECENT" : "ALL CLUSTERS")
                                        .font(.system(size: 9, weight: .semibold))
                                        .kerning(0.8)
                                        .foregroundStyle(Theme.text3)
                                        .padding(.horizontal, 12)
                                        .padding(.top, index == 0 ? 2 : 8)
                                        .padding(.bottom, 3)
                                }
                                SwitcherRow(
                                    name: ctx,
                                    tint: tint(for: ctx),
                                    isCurrent: ctx == state.context,
                                    isHighlighted: searchable && index == highlighted
                                ) {
                                    pick(ctx)
                                }
                                .id(ctx)
                            }
                        }
                        .background {
                            GeometryReader { g in
                                Color.clear.preference(key: RowsHeight.self, value: g.size.height)
                            }
                        }
                    }
                    // Measured, then clamped: the panel is exactly as tall as
                    // its rows until they reach the cap, at which point the
                    // scroller takes over. The scroller keeps a fixed frame so
                    // its rows are clipped to the panel — sizing it to content
                    // instead let them draw straight out over the window.
                    .frame(height: min(rowsHeight ?? estimatedRows, Self.maxRows))
                    .animation(nil, value: rowsHeight)
                    .onPreferenceChange(RowsHeight.self) { rowsHeight = $0 }
                    .onAppear {
                        searchFocused = searchable
                        // Debug-only, same contract as the tour hooks.
                        if let seeded = ProcessInfo.processInfo.environment["K8SECRET_UITEST_CLUSTERQUERY"] {
                            query = seeded
                        }
                        scroller.scrollTo(state.context, anchor: .center)
                    }
                    .onChange(of: highlighted) { _, new in
                        guard matches.indices.contains(new) else { return }
                        withAnimation(Motion.stateChange) { scroller.scrollTo(matches[new], anchor: .center) }
                    }
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
        .popGlass(radius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .tourSpot(.clusterSwitcher)
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onExitCommand { state.clusterSwitcherOpen = false }
    }

    private func move(_ delta: Int) {
        guard !matches.isEmpty else { return }
        highlighted = min(max(0, highlighted + delta), matches.count - 1)
    }

    private func activate() {
        guard matches.indices.contains(highlighted) else { return }
        pick(matches[highlighted])
    }

    private func pick(_ ctx: String) {
        state.clusterSwitcherOpen = false
        guard ctx != state.context else { return }
        Task { await state.switchContext(ctx) }
    }

    private func tint(for ctx: String) -> Theme.ClusterTint {
        let raw = UserDefaults.standard.string(forKey: "clusterTint.\(ctx)") ?? ""
        return Theme.ClusterTint(rawValue: raw) ?? .default
    }

    private struct SwitcherRow: View {
        let name: String
        let tint: Theme.ClusterTint?
        let isCurrent: Bool
        var isHighlighted = false
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
                            .foregroundStyle(tint?.color ?? Theme.text2)
                    }
                    if let shortcut {
                        Text(shortcut)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.text3)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(hovering || isHighlighted
                            ? Color.white.opacity(scheme == .dark ? 0.09 : 0.45) : .clear)
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
            // No frame, all shadow. A titled window paints a pale hairline
            // around itself and a backdrop under the content; against a canvas
            // that runs to the edges, that hairline is the only thing between
            // the app and the desktop, and it reads as a seam. Clearing the
            // window's own background removes it — the content is still masked
            // to the window's rounded corners — and leaves the drop shadow to
            // do the separating, which is what it is for.
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.invalidateShadow()
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
                .fill(.clear)
                .background(LiveMaterial().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
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


/// Hands the enclosing NSWindow back to SwiftUI. Toolbar items live in AppKit,
/// so anything that needs to line up with them needs the window to ask.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onWindow(v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}
