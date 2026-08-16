import XCTest
@testable import K8Secret

// MARK: - Secret masking

/// The mask has two jobs that pull against each other: recognisable enough to
/// tell credentials apart, opaque enough to reveal nothing. These pin the
/// balance point.
final class SecretMaskTests: XCTestCase {

    func testLongValueShowsStartAndEnd() {
        XCTAssertEqual(KVRow.mask("sk_live_51MZqLwFj3aB9dK2m"), "sk_l••••••dK2m")
    }

    func testDotCountIsConstantRegardlessOfLength() {
        // A variable-width mask leaks length; six dots for a 12-char value and
        // six for a 200-char value must look identical in the middle.
        let short = KVRow.mask(String(repeating: "a", count: 12))
        let long = KVRow.mask(String(repeating: "a", count: 200))
        XCTAssertEqual(short.filter { $0 == "•" }.count, long.filter { $0 == "•" }.count)
    }

    func testExactlyTwelveCharactersIsMaskedWithEnds() {
        XCTAssertEqual(KVRow.mask("abcdefghijkl"), "abcd••••••ijkl")
    }

    func testShortValueIsFullyMasked() {
        // Showing 8 of 10 characters wouldn't be masking.
        let masked = KVRow.mask("hunter2000!")
        XCTAssertFalse(masked.contains("hunter"))
        XCTAssertFalse(masked.contains("2000"))
        XCTAssertEqual(masked, String(repeating: "•", count: 12))
    }

    func testShortMaskDoesNotLeakLengthEither() {
        XCTAssertEqual(KVRow.mask("ab"), KVRow.mask("abcdefghijk"))
    }

    func testEmptyValueSaysEmpty() {
        // An empty value masked as dots would claim a value exists.
        XCTAssertEqual(KVRow.mask(""), "(empty)")
    }
}

// MARK: - .env export

final class EnvExportTests: XCTestCase {

    func testBareValueStaysBare() {
        XCTAssertEqual(EnvExport.quote("redis://cache.internal:6379/0"),
                       "redis://cache.internal:6379/0")
    }

    func testSpacesAreQuoted() {
        XCTAssertEqual(EnvExport.quote("hello world"), "\"hello world\"")
    }

    func testHashWouldStartACommentSoItQuotes() {
        XCTAssertEqual(EnvExport.quote("abc#def"), "\"abc#def\"")
    }

    func testDollarWouldInterpolateSoItQuotes() {
        XCTAssertEqual(EnvExport.quote("pa$$word"), "\"pa$$word\"")
    }

    func testQuotesAndBackslashesAreEscaped() {
        XCTAssertEqual(EnvExport.quote(#"say "hi" \now"#), #""say \"hi\" \\now""#)
    }

    func testNewlinesBecomeEscapes() {
        // A bare newline would split one value into two lines — a different
        // .env than the secret it came from.
        XCTAssertEqual(EnvExport.quote("line1\nline2"), "\"line1\\nline2\"")
    }

    func testEmptyValueIsQuotedNotVanishing() {
        XCTAssertEqual(EnvExport.quote(""), "\"\"")
    }

    func testRenderJoinsPairsInOrder() {
        let out = EnvExport.render([("A", "1"), ("B", "two words")])
        XCTAssertEqual(out, "A=1\nB=\"two words\"")
    }
}

// MARK: - Navigation model

final class NavigationModelTests: XCTestCase {

    func testEveryResourceTypeHasASidebarSlot() {
        // A resource type without a nav slot is unreachable — the compiler
        // can't catch that, so this does.
        let listed = NavGroup.all.flatMap(\.items).compactMap { dest -> ResourceType? in
            if case .resource(let t) = dest { return t }
            return nil
        }
        XCTAssertEqual(Set(listed), Set(ResourceType.allCases))
        XCTAssertEqual(listed.count, ResourceType.allCases.count, "no duplicates either")
    }

    func testOverviewAndEventsAreDestinations() {
        let items = NavGroup.all.flatMap(\.items)
        XCTAssertTrue(items.contains(.overview))
        XCTAssertTrue(items.contains(.events))
    }

    func testOverviewComesFirst() {
        // "Is anything wrong?" is the front door by design.
        XCTAssertEqual(NavGroup.all.first?.items.first, .overview)
    }

    func testDestinationTitlesAndIconsAreDistinct() {
        let items = NavGroup.all.flatMap(\.items)
        XCTAssertEqual(Set(items.map(\.title)).count, items.count, "titles collide")
        XCTAssertEqual(Set(items.map(\.icon)).count, items.count, "icons collide")
    }
}

// MARK: - Pressure thresholds

final class PressureThresholdTests: XCTestCase {

    func testQuietWhileHealthy() {
        XCTAssertEqual(Theme.pressure(0), Theme.ok)
        XCTAssertEqual(Theme.pressure(60), Theme.ok)
    }

    func testWarnsAboveSixty() {
        XCTAssertEqual(Theme.pressure(61), Theme.warn)
        XCTAssertEqual(Theme.pressure(85), Theme.warn)
    }

    func testCriticalAboveEightyFive() {
        XCTAssertEqual(Theme.pressure(86), Theme.bad)
        XCTAssertEqual(Theme.pressure(300), Theme.bad)
    }
}

// MARK: - CronJob parsing

final class CronJobParseTests: XCTestCase {

    private func item(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var base: [String: Any] = [
            "metadata": ["name": "nightly-reconcile", "namespace": "payments",
                         "creationTimestamp": "2026-08-01T02:00:00Z"],
            "spec": ["schedule": "0 2 * * *", "suspend": false],
            "status": ["lastScheduleTime": "2026-08-16T02:00:00Z",
                       "lastSuccessfulTime": "2026-08-16T02:00:41Z"],
        ]
        for (k, v) in overrides { base[k] = v }
        return base
    }

    func testParsesTheHappyPath() throws {
        let cj = try XCTUnwrap(K8sClient.parseCronJobStatic(item()))
        XCTAssertEqual(cj.name, "nightly-reconcile")
        XCTAssertEqual(cj.namespace, "payments")
        XCTAssertEqual(cj.schedule, "0 2 * * *")
        XCTAssertFalse(cj.suspended)
        XCTAssertEqual(cj.active, 0)
        XCTAssertTrue(cj.lastRunSucceeded)
    }

    func testSuspendedIsRead() throws {
        let cj = try XCTUnwrap(K8sClient.parseCronJobStatic(
            item(["spec": ["schedule": "* * * * *", "suspend": true]])))
        XCTAssertTrue(cj.suspended)
    }

    func testActiveJobsAreCounted() throws {
        let cj = try XCTUnwrap(K8sClient.parseCronJobStatic(
            item(["status": ["active": [["name": "a"], ["name": "b"]]]])))
        XCTAssertEqual(cj.active, 2)
    }

    func testScheduleWithoutSuccessMeansFailed() throws {
        // The controller records success *after* schedule; a schedule time with
        // no success time at/after it is a failed (or still-running) last run.
        let cj = try XCTUnwrap(K8sClient.parseCronJobStatic(
            item(["status": ["lastScheduleTime": "2026-08-16T02:00:00Z"]])))
        XCTAssertFalse(cj.lastRunSucceeded)
    }

    func testNeverRunIsNotFailed() throws {
        let cj = try XCTUnwrap(K8sClient.parseCronJobStatic(item(["status": [:]])))
        XCTAssertTrue(cj.lastRunSucceeded, "a cronjob that never ran hasn't failed")
        XCTAssertEqual(cj.lastRun, "never")
    }

    func testMissingScheduleIsRejected() {
        XCTAssertNil(K8sClient.parseCronJobStatic(
            item(["spec": [String: Any]()])), "a cronjob without a schedule isn't one")
    }

    func testMissingMetadataIsRejected() {
        XCTAssertNil(K8sClient.parseCronJobStatic(["spec": ["schedule": "* * * * *"]]))
    }
}

// MARK: - Ingress parsing

final class IngressParseTests: XCTestCase {

    private var full: [String: Any] {
        [
            "metadata": ["name": "api", "namespace": "payments",
                         "creationTimestamp": "2026-08-01T00:00:00Z"],
            "spec": [
                "ingressClassName": "nginx",
                "tls": [["hosts": ["api.payments.internal"]]],
                "rules": [[
                    "host": "api.payments.internal",
                    "http": ["paths": [
                        ["path": "/", "backend": ["service": ["name": "api", "port": ["number": 8080]]]],
                        ["path": "/webhooks", "backend": ["service": ["name": "api", "port": ["number": 8080]]]],
                    ]],
                ]],
            ],
        ]
    }

    func testParsesRulesFlat() throws {
        let ing = try XCTUnwrap(K8sClient.parseIngressStatic(full))
        XCTAssertEqual(ing.name, "api")
        XCTAssertEqual(ing.className, "nginx")
        XCTAssertEqual(ing.rules.count, 2)
        XCTAssertEqual(ing.rules[1].path, "/webhooks")
        XCTAssertEqual(ing.rules[0].serviceName, "api")
        XCTAssertEqual(ing.rules[0].servicePort, 8080)
        XCTAssertTrue(ing.tls)
        XCTAssertEqual(ing.primaryHost, "api.payments.internal")
    }

    func testNoTLSNoRules() throws {
        let ing = try XCTUnwrap(K8sClient.parseIngressStatic(
            ["metadata": ["name": "bare", "namespace": "default"], "spec": [String: Any]()]))
        XCTAssertFalse(ing.tls)
        XCTAssertTrue(ing.rules.isEmpty)
        XCTAssertEqual(ing.primaryHost, "—")
    }

    func testHostlessRuleBecomesWildcard() throws {
        let ing = try XCTUnwrap(K8sClient.parseIngressStatic([
            "metadata": ["name": "x", "namespace": "d"],
            "spec": ["rules": [["http": ["paths": [["path": "/",
                "backend": ["service": ["name": "s", "port": ["number": 80]]]]]]]]],
        ]))
        XCTAssertEqual(ing.rules.first?.host, "*")
    }
}

// MARK: - Destination behaviour on state

@MainActor
final class DestinationStateTests: XCTestCase {

    func testSelectingResourceKeepsDestinationInSync() async {
        let state = AppState()
        await state.selectResourceType(.cronjobs)
        XCTAssertEqual(state.selectedDestination, .resource(.cronjobs))
        XCTAssertEqual(state.selectedResourceType, .cronjobs)
    }

    func testSwitchingDestinationClearsSelections() async {
        let state = AppState()
        state.selectedCronJob = K8sCronJob(
            id: "a/b", name: "b", namespace: "a", schedule: "* * * * *",
            suspended: false, active: 0, lastScheduleTime: nil,
            lastSuccessfulTime: nil, createdAt: Date())
        await state.selectDestination(.overview)
        XCTAssertNil(state.selectedCronJob, "destination changes must not leak selections")
        XCTAssertEqual(state.selectedDestination, .overview)
    }

    func testScopedNamespaceNamesFollowScope() {
        let state = AppState()
        state.namespaces = [
            K8sNamespace(id: "a", name: "a", status: "Active"),
            K8sNamespace(id: "b", name: "b", status: "Active"),
        ]
        state.selectedNamespace = state.namespaces[0]
        XCTAssertEqual(state.scopedNamespaceNames, ["a"])
        state.allNamespaces = true
        XCTAssertEqual(state.scopedNamespaceNames, ["a", "b"])
    }

    func testSelectNamespaceLeavesAllScope() async {
        // Clicking a concrete namespace while in All must scope back down —
        // otherwise the checkmark says one thing and the lists say another.
        let state = AppState()
        state.allNamespaces = true
        let ns = K8sNamespace(id: "x", name: "x", status: "Active")
        state.namespaces = [ns]
        await state.selectNamespace(ns)
        XCTAssertFalse(state.allNamespaces)
    }

    /// Sidebar counts must describe the scope on screen. Arrays keep the last
    /// scope's rows until that type is revisited, so counting them blindly
    /// claimed 6 deployments in a namespace holding 2.
    func testSidebarCountIsNilForStaleScope() {
        let state = AppState()
        state.context = "ctx"
        state.selectedNamespace = K8sNamespace(id: "a", name: "alpha", status: "Active")
        state.deployments = [
            K8sDeployment(id: "alpha/one", name: "one", namespace: "alpha", replicas: 1,
                          readyReplicas: 1, availableReplicas: 1, updatedReplicas: 1,
                          images: [], strategy: "RollingUpdate", createdAt: Date(),
                          labels: [:], conditions: []),
        ]
        state.listScopeStamp[.deployments] = state.currentScopeKey
        XCTAssertEqual(state.sidebarCount(for: .deployments), 1)

        // Switching namespace invalidates the stamp: no number beats a wrong one.
        state.selectedNamespace = K8sNamespace(id: "b", name: "beta", status: "Active")
        XCTAssertNil(state.sidebarCount(for: .deployments),
                     "count must not describe a namespace the user left")

        // Unvisited types have no stamp at all.
        XCTAssertNil(state.sidebarCount(for: .pods))
    }

    func testClusterTintRoundTripsPerContext() {
        let state = AppState()
        state.context = "test-ctx-\(UUID().uuidString)"
        XCTAssertEqual(state.clusterTint, .ocean, "unset context defaults to ocean — the blue canvas is the app default")
        state.setClusterTint(.rose)
        state.clusterTint = .ocean         // simulate a stale in-memory value
        state.loadClusterTint()
        XCTAssertEqual(state.clusterTint, .rose)
        UserDefaults.standard.removeObject(forKey: "clusterTint.\(state.context)")
    }
}

// MARK: - Windows and onboarding

@MainActor
final class WindowIdentityTests: XCTestCase {
    /// SwiftUI keys a WindowGroup's windows by their value. When cluster
    /// windows were keyed by the bare context name, opening the same cluster
    /// twice only re-focused the first window — the serial is what makes ten
    /// windows onto one cluster possible.
    func testEveryOpenGetsItsOwnIdentity() {
        let a = ClusterRef.next("colima")
        let b = ClusterRef.next("colima")
        XCTAssertEqual(a.context, b.context)
        XCTAssertNotEqual(a, b, "two opens of one cluster must be two windows")
        XCTAssertNotEqual(a.hashValue, b.hashValue)
    }
}

final class GuidedTourTests: XCTestCase {
    /// Toolbar controls are hosted by NSToolbar and cannot publish an anchor.
    /// Every stop must therefore either be measurable in the content or carry
    /// a titlebar fallback, or it silently disappears from the tour.
    func testEveryStopCanBeShown() {
        XCTAssertEqual(tourSteps.count, 5)
        for step in tourSteps {
            let measurable = step.spot != .namespaceScope && step.spot != .search
            XCTAssertTrue(measurable || step.titlebar != nil,
                          "\(step.spot) can be neither measured nor placed")
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.body.isEmpty)
        }
    }

    func testTourIsOfferedOnceAndRemembered() {
        let key = Welcome.tourKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(Welcome.needsTour)
        Welcome.completeTour()
        XCTAssertFalse(Welcome.needsTour)
        if let previous { UserDefaults.standard.set(previous, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}

// MARK: - Launch smoke

final class AppearanceApplyTests: XCTestCase {
    /// SettingsView.apply runs inside App.init(), before AppKit populates the
    /// NSApp global — reaching for NSApp there crashed the app before its
    /// first frame. NSApplication.shared is the safe spelling; this pins that
    /// all three values survive being applied in a bare process context.
    func testApplyDoesNotCrashForAnyValue() {
        for value in ["light", "dark", "system", "garbage"] {
            SettingsView.apply(appearanceOverride: value)
        }
        SettingsView.apply(appearanceOverride: "system")   // leave neutral
    }
}
