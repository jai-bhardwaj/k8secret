import Foundation
import AppKit

struct PortForward: Identifiable {
    let id = UUID()
    let context: String
    let namespace: String
    let target: String        // e.g. "svc/jobs-dashboard" or "pod/app-xyz"
    let displayName: String   // e.g. "jobs-dashboard" or "app-xyz"
    let remotePort: Int
    var localPort: Int
    var status: Status = .starting
    var error: String?
    var retryCount: Int = 0
    /// Whether the browser has already been opened for this forward.
    ///
    /// kubectl announces readiness twice — once for IPv4 and once for IPv6:
    ///
    ///     Forwarding from 127.0.0.1:18080 -> 80
    ///     Forwarding from [::1]:18080 -> 80
    ///
    /// The readability handler fires per chunk of output, so both lines were
    /// treated as "ready" and each opened a tab. That is the two-tabs bug.
    var hasOpenedBrowser = false
    /// Path opened in the browser for this forward, e.g. `/dashboard`.
    ///
    /// A forwarded port is rarely useful at its root: a jobs dashboard lives at
    /// /admin/queues, an API's docs at /docs. Without this, every open landed on
    /// / and the user retyped the rest of the URL every time.
    var path: String = ""

    enum Status {
        case starting
        case active
        case reconnecting
        case failed
    }

    static let maxRetries = 5

    var localURL: String {
        "http://localhost:\(localPort)" + PortForward.normalize(path)
    }

    /// A path as typed, made safe to append to an origin.
    ///
    /// Users type `admin`, `/admin`, and `admin/` interchangeably and mean the
    /// same thing. Anything with a scheme or host in it is refused rather than
    /// repaired — pasting a full URL here would otherwise send the browser
    /// somewhere other than the tunnel, which is the one thing this must not do.
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "/" else { return "" }
        guard !trimmed.contains("://"), !trimmed.hasPrefix("//") else { return "" }
        let withSlash = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        // Percent-encoding is left to whatever the user typed if they already
        // did it; only the characters that cannot appear literally are escaped.
        return withSlash.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed.union(CharacterSet(charactersIn: "?#&=%+"))
        ) ?? withSlash
    }

    /// Two forwards are the same only if they point at the same target in the same
    /// namespace of the same cluster.
    func matches(_ other: PortForward) -> Bool {
        context == other.context
            && namespace == other.namespace
            && target == other.target
            && remotePort == other.remotePort
    }
}

@MainActor
@Observable
final class PortForwardManager {
    static let shared = PortForwardManager()

    private(set) var forwards: [PortForward] = []
    private var processes: [UUID: Process] = [:]

    /// Remembered landing paths, keyed by cluster + namespace + target + port.
    ///
    /// The path is a property of the service, not of one tunnel: the dashboard
    /// is at /admin/queues every time you forward it. Keeping it in defaults
    /// means setting it once, and keying it by the same four fields that make
    /// two forwards the same target means staging's /admin cannot leak into
    /// production's.
    private static func pathKey(context: String, namespace: String,
                                target: String, remotePort: Int) -> String {
        "portForwardPath.\(context)|\(namespace)|\(target)|\(remotePort)"
    }

    func savedPath(context: String, namespace: String, target: String, remotePort: Int) -> String {
        UserDefaults.standard.string(
            forKey: Self.pathKey(context: context, namespace: namespace,
                                 target: target, remotePort: remotePort)) ?? ""
    }

    /// Remember a path, and apply it to a forward that is already running so the
    /// change takes effect on the next open rather than the next restart.
    func setPath(_ path: String, context: String, namespace: String,
                 target: String, remotePort: Int) {
        let key = Self.pathKey(context: context, namespace: namespace,
                               target: target, remotePort: remotePort)
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }
        for i in forwards.indices where forwards[i].context == context
            && forwards[i].namespace == namespace
            && forwards[i].target == target
            && forwards[i].remotePort == remotePort {
            forwards[i].path = trimmed
        }
    }

    /// Start a port forward to a service
    func forwardService(context: String, namespace: String, serviceName: String, remotePort: Int) {
        let localPort = findFreePort()
        let pf = PortForward(
            context: context,
            namespace: namespace,
            target: "svc/\(serviceName)",
            displayName: serviceName,
            remotePort: remotePort,
            localPort: localPort,
            path: savedPath(context: context, namespace: namespace,
                            target: "svc/\(serviceName)", remotePort: remotePort)
        )

        // Check if already forwarding this target+port. Context and namespace are
        // part of the identity: `svc/api` in staging and `svc/api` in production
        // are different targets, and matching on name alone silently handed the
        // user the wrong cluster's forward.
        if let existing = forwards.first(where: { $0.matches(pf) && ($0.status == .active || $0.status == .starting) }) {
            if existing.status == .active { openInBrowser(existing.localURL) }
            return
        }

        // Remove any failed forwards for the same target
        forwards.removeAll { $0.matches(pf) && $0.status == .failed }

        forwards.append(pf)
        startProcess(for: pf.id, context: context, namespace: namespace,
                     target: "svc/\(serviceName)", localPort: localPort, remotePort: remotePort)
    }

    /// Start a port forward to a pod
    func forwardPod(context: String, namespace: String, podName: String, remotePort: Int) {
        let localPort = findFreePort()
        let pf = PortForward(
            context: context,
            namespace: namespace,
            target: "pod/\(podName)",
            displayName: podName,
            remotePort: remotePort,
            localPort: localPort,
            path: savedPath(context: context, namespace: namespace,
                            target: "pod/\(podName)", remotePort: remotePort)
        )

        if let existing = forwards.first(where: { $0.matches(pf) && ($0.status == .active || $0.status == .starting) }) {
            if existing.status == .active { openInBrowser(existing.localURL) }
            return
        }

        forwards.removeAll { $0.matches(pf) && $0.status == .failed }

        forwards.append(pf)
        startProcess(for: pf.id, context: context, namespace: namespace,
                     target: "pod/\(podName)", localPort: localPort, remotePort: remotePort)
    }

    /// Stop a specific port forward
    func stop(id: UUID) {
        if let process = processes[id] {
            process.terminate()
            processes.removeValue(forKey: id)
        }
        forwards.removeAll { $0.id == id }
    }

    /// Stop all port forwards
    func stopAll() {
        for (_, process) in processes {
            process.terminate()
        }
        processes.removeAll()
        forwards.removeAll()
    }

    /// The forward for a specific service port in a specific place.
    ///
    /// Context and namespace are part of the lookup. Matching on service name and
    /// port alone meant `svc/api` in staging and `svc/api` in production resolved
    /// to whichever forward happened to exist, so a second window could show — and
    /// open — the other cluster's tunnel.
    func forward(context: String, namespace: String, target: String, remotePort: Int) -> PortForward? {
        forwards.first {
            $0.context == context
                && $0.namespace == namespace
                && $0.target == target
                && $0.remotePort == remotePort
        }
    }

    /// Open URL in default browser
    func openInBrowser(_ url: String) {
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private

    private func startProcess(for id: UUID, context: String, namespace: String,
                              target: String, localPort: Int, remotePort: Int) {
        let kubectlPath = resolveKubectl()
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: kubectlPath)
        process.arguments = [
            "port-forward",
            "--context", context,
            "-n", namespace,
            target,
            "\(localPort):\(remotePort)"
        ]
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.environment = ProcessInfo.processInfo.environment

        // Monitor stdout for "Forwarding from" ready signal
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                if output.contains("Forwarding from") {
                    if let portRange = output.range(of: #"127\.0\.0\.1:(\d+)"#, options: .regularExpression) {
                        let portStr = output[portRange].split(separator: ":").last ?? ""
                        if let actualPort = Int(portStr) {
                            if let idx = self.forwards.firstIndex(where: { $0.id == id }) {
                                self.forwards[idx].localPort = actualPort
                            }
                        }
                    }
                    if let idx = self.forwards.firstIndex(where: { $0.id == id }) {
                        let wasReconnecting = self.forwards[idx].status == .reconnecting
                        self.forwards[idx].status = .active
                        self.forwards[idx].retryCount = 0
                        self.forwards[idx].error = nil

                        // Open exactly once per forward: not again for kubectl's
                        // second (IPv6) readiness line, and not on a reconnect,
                        // which would steal focus while the user is working.
                        if !wasReconnecting && !self.forwards[idx].hasOpenedBrowser {
                            self.forwards[idx].hasOpenedBrowser = true
                            self.openInBrowser(self.forwards[idx].localURL)
                        }
                    }
                }
            }
        }

        // Monitor stderr for errors
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                if output.contains("error") || output.contains("unable") {
                    if let idx = self.forwards.firstIndex(where: { $0.id == id }) {
                        self.forwards[idx].status = .failed
                        self.forwards[idx].error = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }

        // Handle process termination — auto-retry if it was active
        process.terminationHandler = { [weak self] _ in
            // Detach the readability handlers and close the descriptors. Without
            // this each restart leaks two file descriptors plus the closures that
            // retain them, so a long-lived flapping forward eventually exhausts the
            // process's fd limit.
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            try? outPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForReading.close()

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.processes.removeValue(forKey: id)

                guard let idx = self.forwards.firstIndex(where: { $0.id == id }) else { return }
                let fwd = self.forwards[idx]

                // Only retry if it was active (not manually stopped) and under retry limit
                if (fwd.status == .active || fwd.status == .reconnecting) && fwd.retryCount < PortForward.maxRetries {
                    self.forwards[idx].status = .reconnecting
                    self.forwards[idx].retryCount += 1
                    self.forwards[idx].error = nil

                    // Exponential backoff: 1s, 2s, 4s, 8s, 16s
                    let delay = UInt64(pow(2.0, Double(fwd.retryCount))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)

                    // Re-check it wasn't manually stopped during the delay
                    if let idx2 = self.forwards.firstIndex(where: { $0.id == id }),
                       self.forwards[idx2].status == .reconnecting {
                        // Claim a fresh local port: something else may well have
                        // taken the old one while we were backing off, and reusing
                        // it makes the retry fail for a reason unrelated to the
                        // original disconnect.
                        let retryPort = self.findFreePort()
                        self.forwards[idx2].localPort = retryPort
                        self.startProcess(for: id, context: fwd.context, namespace: fwd.namespace,
                                         target: fwd.target, localPort: retryPort, remotePort: fwd.remotePort)
                    }
                } else if fwd.status == .starting {
                    self.forwards[idx].status = .failed
                    self.forwards[idx].error = "Process terminated unexpectedly"
                } else if fwd.retryCount >= PortForward.maxRetries {
                    self.forwards[idx].status = .failed
                    self.forwards[idx].error = "Gave up after \(PortForward.maxRetries) retries"
                }
            }
        }

        do {
            try process.run()
            processes[id] = process
        } catch {
            if let idx = forwards.firstIndex(where: { $0.id == id }) {
                forwards[idx].status = .failed
                forwards[idx].error = error.localizedDescription
            }
        }
    }

    private func findFreePort() -> Int {
        // Bind to port 0 to let the OS assign a free port
        let socket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socket >= 0 else { return 9000 + Int.random(in: 0...999) }
        defer { close(socket) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0  // Let OS pick
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return 9000 + Int.random(in: 0...999) }

        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socket, $0, &addrLen)
            }
        }
        guard result == 0 else { return 9000 + Int.random(in: 0...999) }

        return Int(UInt16(bigEndian: boundAddr.sin_port))
    }

    private func resolveKubectl() -> String {
        let paths = [
            "/usr/local/bin/kubectl",
            "/opt/homebrew/bin/kubectl",
            "/usr/bin/kubectl",
        ]
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            ?? "kubectl"
    }
}
