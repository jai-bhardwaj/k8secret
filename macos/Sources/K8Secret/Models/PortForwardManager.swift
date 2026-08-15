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

    enum Status {
        case starting
        case active
        case reconnecting
        case failed
    }

    static let maxRetries = 5

    var localURL: String {
        "http://localhost:\(localPort)"
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

    /// Start a port forward to a service
    func forwardService(context: String, namespace: String, serviceName: String, remotePort: Int) {
        let localPort = findFreePort()
        let pf = PortForward(
            context: context,
            namespace: namespace,
            target: "svc/\(serviceName)",
            displayName: serviceName,
            remotePort: remotePort,
            localPort: localPort
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
            localPort: localPort
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
                        // Only auto-open on first connect, not on reconnect
                        if !wasReconnecting {
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
