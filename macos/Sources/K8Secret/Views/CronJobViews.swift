import SwiftUI

// MARK: - List

struct CronJobsListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
        PaneHeader(
            title: "CronJobs",
            subtitle: "\(state.cronJobs.count) \(state.allNamespaces ? "across all namespaces" : "in " + (state.selectedNamespace?.name ?? "—"))")
        FilterField(prompt: "Filter cronjobs…", text: $state.cronJobSearch)
        List(state.filteredCronJobs) { cj in
            CronJobRow(cronJob: cj, showNamespace: state.allNamespaces)
                .vnextRow(isSelected: state.selectedCronJob?.id == cj.id)
                .onTapGesture { state.selectedCronJob = cj }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Theme.line)
                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        }
        .vnextKeyboardSelection(items: state.filteredCronJobs, selection: $state.selectedCronJob)
        .overlay {
            if state.isInitialLoad {
                ProgressView()
            } else if state.cronJobs.isEmpty {
                EmptyPane(icon: "clock", title: "No CronJobs",
                          message: state.allNamespaces ? "No cronjobs in any namespace." : "No cronjobs in this namespace.")
            } else if state.filteredCronJobs.isEmpty {
                EmptyPane(icon: "magnifyingglass", title: "No matches",
                          message: "No results for “\(state.cronJobSearch)”.")
            }
        }
        }
        .vnextListPane()
        .motion(Motion.listChange, value: state.cronJobs)
    }
}

struct CronJobRow: View {
    let cronJob: K8sCronJob
    var showNamespace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle()
                    .fill(cronJob.suspended ? Theme.warn : (cronJob.lastRunSucceeded ? Theme.ok : Theme.bad))
                    .frame(width: 8, height: 8)
                Text(cronJob.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                if showNamespace {
                    NamespaceBadge(name: cronJob.namespace)
                }
                Spacer(minLength: 4)
                statusPill
                Text(cronJob.age)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                MetricChip(icon: "clock", text: cronJob.schedule, hue: nil, truncates: true)
                Spacer(minLength: 4)
                Text("last \(cronJob.lastRun)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cronJob.name), \(cronJob.schedule), last run \(cronJob.lastRun)\(cronJob.suspended ? ", suspended" : "")")
    }

    @ViewBuilder
    private var statusPill: some View {
        if cronJob.suspended {
            StatusPill(text: "Suspended", color: Theme.warn)
        } else if cronJob.active > 0 {
            StatusPill(text: "Running", color: Theme.accent, pulses: true)
        } else if cronJob.lastRunSucceeded {
            StatusPill(text: "Idle", color: Theme.ok)
        } else {
            StatusPill(text: "LastFailed", color: Theme.bad)
        }
    }
}

// MARK: - Detail

struct CronJobDetailView: View {
    @Environment(AppState.self) private var state

    enum DetailTab: String, CaseIterable { case overview = "Overview", yaml = "YAML" }
    @State private var tab = DetailTab.overview

    var body: some View {
        if let cj = state.selectedCronJob {
            VStack(spacing: 0) {
                header(cj)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                UnderlineTabBar(tabs: DetailTab.allCases.map { ($0, $0.rawValue) }, selection: $tab)
                    .padding(.top, 6)
                switch tab {
                case .yaml:
                    ResourceYAMLView(type: .cronjobs, namespace: cj.namespace, name: cj.name)
                case .overview:
                    ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statGrid(cj)
                    scheduleNote(cj)
                    recentRuns(cj)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .navigationTitle(cj.name)
        } else {
            ContentUnavailableView {
                Label("No CronJob Selected", systemImage: "clock")
            } description: {
                Text("Choose a cronjob to see its schedule and trigger runs.")
            }
        }
    }

    private func header(_ cj: K8sCronJob) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                headerInfo(cj)
                Spacer(minLength: 12)
                headerActions(cj)
            }
            VStack(alignment: .leading, spacing: 10) {
                headerInfo(cj)
                HStack(spacing: 8) { headerActions(cj) }
            }
        }
    }

    private func headerInfo(_ cj: K8sCronJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DetailBreadcrumb(type: "cronjobs")
                .padding(.bottom, 2)
            HStack(spacing: 10) {
                Text(cj.name)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                .kerning(-0.25)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if cj.suspended { StatusPill(text: "Suspended", color: Theme.warn) }
            }
        }
    }

    @ViewBuilder
    private func headerActions(_ cj: K8sCronJob) -> some View {
        Button(cj.suspended ? "Resume" : "Suspend") {
            toggleSuspend(cj)
        }
        .buttonStyle(Theme.SoftPill())
        Button("Run now") {
            runNow(cj)
        }
        .buttonStyle(Theme.PrimaryPill())
        .disabled(cj.suspended)
        .help(cj.suspended ? "Resume the schedule before running" : "Start a job outside the schedule")
    }

    private func statGrid(_ cj: K8sCronJob) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            StatCard(label: "Schedule", value: cj.schedule, mono: true)
            StatCard(label: "Last run", value: cj.lastRun,
                     valueColor: cj.lastRunSucceeded ? nil : Theme.bad)
            StatCard(label: "Next run", value: cj.suspended ? "—" : cj.nextRunLabel, mono: true)
            StatCard(label: "Active now", value: "\(cj.active)")
            StatCard(label: "Age", value: cj.age)
        }
    }

    /// The prototype's Recent runs table: Started / Result / Duration.
    @ViewBuilder
    private func recentRuns(_ cj: K8sCronJob) -> some View {
        let runs = state.cronJobRuns
            .filter { $0.ownerCronJob == cj.name }
            .sorted { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
            .prefix(6)
        if !runs.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("RECENT RUNS")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.text3)
                    .padding(.bottom, 4)
                HStack(spacing: 12) {
                    Text("STARTED").frame(maxWidth: .infinity, alignment: .leading)
                    Text("RESULT").frame(width: 100, alignment: .leading)
                    Text("DURATION").frame(width: 80, alignment: .leading)
                }
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Theme.text3)
                ForEach(Array(runs)) { run in
                    HStack(spacing: 12) {
                        Text(run.startTime.map { formatAge($0) + " ago" } ?? "—")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Group {
                            if run.active {
                                StatusPill(text: "Running", color: Theme.warn, pulses: true)
                            } else if run.succeeded {
                                StatusPill(text: "Succeeded", color: Theme.ok)
                            } else {
                                StatusPill(text: "Failed", color: Theme.bad)
                            }
                        }
                        .frame(width: 100, alignment: .leading)
                        Text(run.duration)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.text2)
                            .frame(width: 80, alignment: .leading)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func scheduleNote(_ cj: K8sCronJob) -> some View {
        Text(cj.suspended
             ? "Suspended — scheduled runs are skipped until you resume. Anything already running finishes normally."
             : "Run now starts a job outside the schedule; the scheduled runs are unaffected.")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
    }

    private func toggleSuspend(_ cj: K8sCronJob) {
        if cj.suspended {
            // Resuming restores what the user already chose; no confirmation.
            Task { await state.setCronJobSuspended(cj, suspended: false) }
        } else {
            state.confirm(
                title: "Suspend \(cj.name)?",
                message: "Scheduled runs stop until you resume. Nothing currently running is affected.",
                confirmLabel: "Suspend",
                destructive: false
            ) { [state] in
                await state.setCronJobSuspended(cj, suspended: true)
            }
        }
    }

    private func runNow(_ cj: K8sCronJob) {
        state.confirm(
            title: "Run \(cj.name) now?",
            message: "Starts a job outside its \(cj.schedule) schedule. The scheduled runs are unaffected.",
            confirmLabel: "Run now",
            destructive: false
        ) { [state] in
            await state.runCronJobNow(cj)
        }
    }

}
