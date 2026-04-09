import SwiftUI

struct LogStreamWindow: View {
    let logID: LogStreamID
    @State private var state: LogStreamState

    init(logID: LogStreamID) {
        self.logID = logID
        self._state = State(initialValue: LogStreamState(id: logID))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logContent
            Divider()
            statusBar
        }
        .frame(minWidth: 700, minHeight: 400)
        .navigationTitle("\(logID.pod) — \(logID.container)")
        .task {
            await state.start()
        }
        .onDisappear {
            state.stop()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search logs...", text: Binding(
                    get: { state.search },
                    set: { state.search = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))

                if !state.search.isEmpty {
                    Button {
                        state.search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 300)

            // Level filter pills
            levelFilters

            Spacer()

            // Wrap toggle
            Button {
                state.wrapLines.toggle()
            } label: {
                Image(systemName: "text.word.spacing")
                    .font(.system(size: 12))
                    .foregroundStyle(state.wrapLines ? .primary : .tertiary)
            }
            .buttonStyle(.plain)
            .help(state.wrapLines ? "Disable line wrap" : "Enable line wrap")

            // Jump to bottom
            if let lastID = state.filteredLines.last?.id, !visibleIDs.contains(lastID) {
                Button {
                    scrollProxy?.scrollTo(lastID, anchor: .bottomLeading)
                } label: {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Jump to bottom")
            }

            Divider().frame(height: 16)

            // Clear
            Button {
                state.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Clear logs")

            // Stream toggle
            Button {
                if state.isStreaming {
                    state.stop()
                } else {
                    Task { await state.start() }
                }
            } label: {
                Image(systemName: state.isStreaming ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(state.isStreaming ? .orange : .green)
            }
            .buttonStyle(.plain)
            .help(state.isStreaming ? "Pause stream" : "Resume stream")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Level filters

    private var levelFilters: some View {
        HStack(spacing: 4) {
            ForEach(LogStreamState.LogLevel.allCases.filter { $0 != .other }) { level in
                let count = state.levelCounts[level] ?? 0
                let isActive = state.levelFilter == level

                Button {
                    state.levelFilter = isActive ? nil : level
                } label: {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(level.color)
                            .frame(width: 6, height: 6)
                        Text(level.rawValue)
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .foregroundStyle(level.color)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        isActive ? level.color.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isActive ? level.color.opacity(0.3) : Color.clear, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? .primary : .secondary)
            }
        }
    }

    // MARK: - Log content

    @State private var scrollProxy: ScrollViewProxy?

    @State private var visibleIDs: Set<Int> = []

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(state.filteredLines) { line in
                        logLineView(line)
                            .id(line.id)
                            .onAppear { visibleIDs.insert(line.id) }
                            .onDisappear { visibleIDs.remove(line.id) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .background(Color.black.opacity(0.3))
            .onAppear { scrollProxy = proxy }
            .onChange(of: state.filteredLines.count) { oldCount, newCount in
                // Check if the previous last line is currently visible
                let prevLastID = newCount > oldCount
                    ? state.filteredLines[max(0, oldCount - 1)].id
                    : state.filteredLines.last?.id ?? 0

                let userIsAtBottom = oldCount == 0 || visibleIDs.contains(prevLastID)

                if userIsAtBottom, let id = state.filteredLines.last?.id {
                    proxy.scrollTo(id, anchor: .bottomLeading)
                }
            }
        }
    }

    private func logLineView(_ line: LogStreamState.LogLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Line number
            Text("\(line.id)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 8)

            // Level indicator
            Rectangle()
                .fill(line.level.color)
                .frame(width: 3)
                .padding(.vertical, 1)

            // Timestamp
            if let ts = line.timestamp {
                Text(formatTimestamp(ts))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
            }

            // Log text with search highlighting
            if state.search.isEmpty {
                Text(line.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(line.level == .error ? .red : line.level == .warn ? .orange : .primary)
                    .textSelection(.enabled)
                    .lineLimit(state.wrapLines ? nil : 1)
            } else {
                highlightedText(line.text, search: state.search)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(state.wrapLines ? nil : 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(
            line.level == .error ? Color.red.opacity(0.06) :
            line.level == .warn ? Color.orange.opacity(0.04) : Color.clear
        )
    }

    private func highlightedText(_ text: String, search: String) -> Text {
        guard !search.isEmpty else { return Text(text) }

        var result = Text("")
        var remaining = text[text.startIndex...]

        while let range = remaining.range(of: search, options: .caseInsensitive) {
            // Text before match
            if range.lowerBound > remaining.startIndex {
                result = result + Text(remaining[remaining.startIndex..<range.lowerBound])
                    .foregroundStyle(.primary)
            }
            // Highlighted match — bold yellow since .background isn't available on Text concatenation
            result = result + Text(remaining[range])
                .foregroundStyle(.yellow)
                .bold()
                .underline()

            remaining = remaining[range.upperBound...]
        }

        // Remaining text
        if !remaining.isEmpty {
            result = result + Text(remaining).foregroundStyle(.primary)
        }

        return result
    }

    private func formatTimestamp(_ ts: String) -> String {
        // Extract just HH:MM:SS from ISO timestamp
        guard ts.count >= 19,
              let tIdx = ts.firstIndex(of: "T") else { return ts }
        let timeStart = ts.index(after: tIdx)
        let timeEnd = ts.index(timeStart, offsetBy: 8, limitedBy: ts.endIndex) ?? ts.endIndex
        return String(ts[timeStart..<timeEnd])
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            // Stream status
            HStack(spacing: 5) {
                Circle()
                    .fill(state.isStreaming ? .green : .red)
                    .frame(width: 6, height: 6)
                Text(state.isStreaming ? "Streaming" : "Paused")
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
            }

            Rectangle().fill(.quaternary).frame(width: 1, height: 12)

            // Line count
            Text("\(state.filteredLines.count) lines")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)

            if state.filteredLines.count != state.lines.count {
                Text("(\(state.lines.count) total)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Error
            if let err = state.error {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            // Pod info
            Text("\(logID.namespace)/\(logID.pod)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)

            Text(logID.container)
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
    }
}

