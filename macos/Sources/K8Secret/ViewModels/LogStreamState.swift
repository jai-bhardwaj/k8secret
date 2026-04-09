import SwiftUI

/// Identifies a log stream window
struct LogStreamID: Codable, Hashable {
    let context: String
    let namespace: String
    let pod: String
    let container: String
}

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

    private var streamTask: Task<Void, Never>?
    private let client = K8sClient()
    private var lineCounter = 0

    struct LogLine: Identifiable {
        let id: Int
        let timestamp: String?
        let text: String
        let level: LogLevel
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

    var filteredLines: [LogLine] {
        var result = lines

        if let level = levelFilter {
            result = result.filter { $0.level == level }
        }

        if !search.isEmpty {
            result = result.filter { $0.text.localizedCaseInsensitiveContains(search) }
        }

        return result
    }

    var levelCounts: [LogLevel: Int] {
        var counts: [LogLevel: Int] = [:]
        for line in lines {
            counts[line.level, default: 0] += 1
        }
        return counts
    }

    init(id: LogStreamID) {
        self.id = id
    }

    func start() async {
        guard !isStreaming else { return }
        isStreaming = true
        error = nil

        // Connect the client using the same context as the parent window
        do {
            _ = try await client.connect(context: id.context)
        } catch {
            self.error = "Connection failed: \(error.localizedDescription)"
            isStreaming = false
            return
        }

        streamTask = Task { [weak self] in
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
                // Stream ended normally
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
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func clear() {
        lines.removeAll()
        lineCounter = 0
    }

    private func appendLine(_ raw: String) {
        lineCounter += 1
        let (ts, text) = parseTimestamp(raw)
        let level = detectLevel(text)
        lines.append(LogLine(id: lineCounter, timestamp: ts, text: text, level: level))

        // Cap at 10k lines to avoid memory issues
        if lines.count > 10_000 {
            lines.removeFirst(lines.count - 10_000)
        }
    }

    private func parseTimestamp(_ line: String) -> (String?, String) {
        // K8s timestamps look like: 2024-01-15T12:34:56.789Z message...
        guard line.count > 30,
              line[line.index(line.startIndex, offsetBy: 4)] == "-",
              line[line.index(line.startIndex, offsetBy: 10)] == "T" else {
            return (nil, line)
        }
        // Find the first space after the timestamp
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
