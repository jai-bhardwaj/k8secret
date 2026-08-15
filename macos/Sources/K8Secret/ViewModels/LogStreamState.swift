import SwiftUI

/// Identifies a log stream window
struct LogStreamID: Codable, Hashable {
    let context: String
    let namespace: String
    let pod: String
    let container: String

    /// For deployment-level streaming: comma-separated pod names
    var isMultiPod: Bool { pod.contains(",") }
    var podNames: [String] { pod.split(separator: ",").map(String.init) }
}

// Pod color palette for multi-pod streaming
private let podColors: [NSColor] = [
    .systemCyan, .systemMint, .systemPink, .systemPurple,
    .systemYellow, .systemTeal, .systemIndigo, .systemOrange,
    .systemGreen, .systemBlue
]

@MainActor
@Observable
final class LogStreamState {
    let id: LogStreamID
    private(set) var lines: [LogLine] = []
    var search: String = ""
    var levelFilter: LogLevel? = nil
    var isStreaming = false
    var wrapLines = true
    var error: String?

    private var streamTasks: [Task<Void, Never>] = []
    private let client = K8sClient()
    private var lineCounter = 0
    private var podColorMap: [String: NSColor] = [:]

    /// How many lines scrolled out of the buffer — surfaced so the window can say
    /// the history is truncated instead of quietly pretending it's complete.
    private(set) var droppedLines = 0

    private static let maxLines = 10_000
    private static let trimBatch = 1_000

    struct LogLine: Identifiable {
        let id: Int
        let timestamp: String?
        let text: String
        let level: LogLevel
        let podName: String?
        let podColor: NSColor?
    }

    enum LogLevel: String, CaseIterable, Identifiable {
        case error = "ERROR"
        case warn = "WARN"
        case info = "INFO"
        case debug = "DEBUG"
        case trace = "TRACE"
        case other = "OTHER"

        var id: String { rawValue }

        var color: Color {
            switch self {
            case .error: return .red
            case .warn: return .orange
            case .info: return .blue
            case .debug: return .green
            case .trace: return .gray
            case .other: return .secondary
            }
        }
    }

    /// Counts and pod names are maintained incrementally rather than recomputed.
    ///
    /// These were computed properties scanning the whole buffer, and every appended
    /// line invalidated the view — so a busy pod made SwiftUI walk up to 10,000
    /// lines three times per line received.
    private(set) var levelCounts: [LogLevel: Int] = [:]
    private var podNames: Set<String> = []
    private(set) var activePods: [String] = []

    var filteredLines: [LogLine] {
        // Still a scan, but only when a filter is actually engaged — and the common
        // case (no filter, no search) now returns the buffer untouched.
        guard levelFilter != nil || !search.isEmpty else { return lines }

        return lines.filter { line in
            if let level = levelFilter, line.level != level { return false }
            if !search.isEmpty, !line.text.localizedCaseInsensitiveContains(search) { return false }
            return true
        }
    }

    init(id: LogStreamID) {
        self.id = id
    }

    func start() async {
        guard !isStreaming else { return }
        isStreaming = true
        error = nil

        do {
            _ = try await client.connect(context: id.context)
        } catch {
            self.error = "Connection failed: \(error.localizedDescription)"
            isStreaming = false
            return
        }

        if id.isMultiPod {
            // Multi-pod streaming (deployment-level)
            let pods = id.podNames
            for (i, podName) in pods.enumerated() {
                podColorMap[podName] = podColors[i % podColors.count]
                let task = Task { [weak self] in
                    guard let self else { return }
                    do {
                        let container = self.id.container.isEmpty ? nil : self.id.container
                        try await self.client.streamPodLogs(
                            namespace: self.id.namespace,
                            name: podName,
                            container: container,
                            tailLines: 50
                        ) { line in
                            Task { @MainActor [weak self] in
                                self?.appendLine(line, podName: podName)
                            }
                        }
                    } catch {
                        if !Task.isCancelled {
                            await MainActor.run {
                                self.appendLine("[stream ended: \(error.localizedDescription)]", podName: podName)
                            }
                        }
                    }
                }
                streamTasks.append(task)
            }
        } else {
            // Single pod streaming
            let task = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.client.streamPodLogs(
                        namespace: self.id.namespace,
                        name: self.id.pod,
                        container: self.id.container,
                        tailLines: 200
                    ) { line in
                        Task { @MainActor [weak self] in
                            self?.appendLine(line)
                        }
                    }
                    await MainActor.run {
                        self.isStreaming = false
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.error = error.localizedDescription
                            self.isStreaming = false
                        }
                    }
                }
            }
            streamTasks.append(task)
        }
    }

    func stop() {
        for task in streamTasks { task.cancel() }
        streamTasks.removeAll()
        isStreaming = false
    }

    func clear() {
        lines.removeAll()
        levelCounts.removeAll()
        podNames.removeAll()
        activePods.removeAll()
        lineCounter = 0
        droppedLines = 0
    }

    /// Non-private so buffer accounting can be tested without a live stream.
    func appendLine(_ raw: String, podName: String? = nil) {
        lineCounter += 1
        let (ts, text) = parseTimestamp(raw)
        let level = detectLevel(text)
        let color = podName.flatMap { podColorMap[$0] }

        lines.append(LogLine(id: lineCounter, timestamp: ts, text: text, level: level, podName: podName, podColor: color))
        levelCounts[level, default: 0] += 1

        if let podName, podNames.insert(podName).inserted {
            activePods = podNames.sorted()
        }

        // Trim in batches. Dropping one line at a time made every append past the
        // cap an O(n) memmove of the whole buffer.
        if lines.count > Self.maxLines + Self.trimBatch {
            let excess = lines.count - Self.maxLines
            for dropped in lines.prefix(excess) {
                if let count = levelCounts[dropped.level] {
                    levelCounts[dropped.level] = count > 1 ? count - 1 : nil
                }
            }
            lines.removeFirst(excess)
            droppedLines += excess
        }
    }

    private func parseTimestamp(_ line: String) -> (String?, String) {
        guard line.count > 30,
              line[line.index(line.startIndex, offsetBy: 4)] == "-",
              line[line.index(line.startIndex, offsetBy: 10)] == "T" else {
            return (nil, line)
        }
        if let spaceIdx = line.firstIndex(of: " ") {
            let ts = String(line[line.startIndex..<spaceIdx])
            let rest = String(line[line.index(after: spaceIdx)...])
            return (ts, rest)
        }
        return (nil, line)
    }

    private func detectLevel(_ text: String) -> LogLevel {
        let upper = text.uppercased()
        let prefix = String(upper.prefix(80))

        if prefix.contains("ERROR") || prefix.contains("FATAL") || prefix.contains("PANIC") { return .error }
        if prefix.contains("WARN") { return .warn }
        if prefix.contains("DEBUG") { return .debug }
        if prefix.contains("TRACE") { return .trace }
        if prefix.contains("INFO") { return .info }
        return .other
    }
}
