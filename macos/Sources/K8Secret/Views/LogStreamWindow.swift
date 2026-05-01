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
        .overlay {
            if let toast = copyToast {
                VStack {
                    Text(toast)
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .transition(.opacity)
                    Spacer()
                }
                .padding(.top, 50)
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { copyToast = nil }
                    }
                }
            }
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

            // Copy filtered logs
            Button {
                let text = state.filteredLines.map { line in
                    let ts = line.timestamp.map { "\($0) " } ?? ""
                    return "\(ts)\(line.text)"
                }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copyToast = "Copied \(state.filteredLines.count) lines"
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Copy all visible logs")

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
    @State private var copyToast: String?

    @State private var autoScroll = true

    private var logContent: some View {
        SelectableLogView(
            lines: state.filteredLines,
            search: state.search,
            wrapLines: state.wrapLines,
            autoScroll: $autoScroll
        )
        .background(Color.black.opacity(0.3))
        .onChange(of: state.filteredLines.count) { _, _ in
            autoScroll = true
        }
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

// MARK: - Native selectable log view backed by NSTextView

struct SelectableLogView: NSViewRepresentable {
    let lines: [LogStreamState.LogLine]
    let search: String
    let wrapLines: Bool
    @Binding var autoScroll: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 4)

        if wrapLines {
            textView.textContainer?.widthTracksTextView = true
            textView.isHorizontallyResizable = false
        } else {
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
        }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !wrapLines
        scrollView.drawsBackground = false

        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        // Update wrap mode
        if wrapLines {
            textView.textContainer?.widthTracksTextView = true
            textView.isHorizontallyResizable = false
            scrollView.hasHorizontalScroller = false
        } else {
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
            scrollView.hasHorizontalScroller = true
        }

        // Only rebuild text if lines changed
        let newCount = lines.count
        if newCount != context.coordinator.lastLineCount || search != context.coordinator.lastSearch {
            let attributed = buildAttributedString()
            textView.textStorage?.setAttributedString(attributed)
            context.coordinator.lastLineCount = newCount
            context.coordinator.lastSearch = search

            if autoScroll {
                DispatchQueue.main.async {
                    textView.scrollToEndOfDocument(nil)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var textView: NSTextView?
        var lastLineCount = 0
        var lastSearch = ""
    }

    private func buildAttributedString() -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let monoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let lineNumFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let tsFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: NSColor.textColor
        ]
        let lineNumAttrs: [NSAttributedString.Key: Any] = [
            .font: lineNumFont,
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let tsAttrs: [NSAttributedString.Key: Any] = [
            .font: tsFont,
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let errorAttrs: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: NSColor.systemRed
        ]
        let warnAttrs: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: NSColor.systemOrange
        ]
        let highlightAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.systemYellow,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        let podFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)

        for (i, line) in lines.enumerated() {
            let lineNum = NSAttributedString(string: String(format: "%4d  ", line.id), attributes: lineNumAttrs)
            result.append(lineNum)

            // Pod name prefix for multi-pod streams
            if let podName = line.podName {
                let shortName = shortenPodName(podName)
                let podAttrs: [NSAttributedString.Key: Any] = [
                    .font: podFont,
                    .foregroundColor: line.podColor ?? NSColor.secondaryLabelColor
                ]
                result.append(NSAttributedString(string: "[\(shortName)]  ", attributes: podAttrs))
            }

            if let ts = line.timestamp {
                let formatted = formatTimestamp(ts)
                result.append(NSAttributedString(string: "\(formatted)  ", attributes: tsAttrs))
            }

            let textAttrs: [NSAttributedString.Key: Any]
            switch line.level {
            case .error: textAttrs = errorAttrs
            case .warn: textAttrs = warnAttrs
            default: textAttrs = defaultAttrs
            }

            if !search.isEmpty {
                appendHighlighted(to: result, text: line.text, search: search, baseAttrs: textAttrs, highlightAttrs: highlightAttrs)
            } else {
                result.append(NSAttributedString(string: line.text, attributes: textAttrs))
            }

            if i < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
            }
        }

        return result
    }

    private func appendHighlighted(to result: NSMutableAttributedString, text: String, search: String, baseAttrs: [NSAttributedString.Key: Any], highlightAttrs: [NSAttributedString.Key: Any]) {
        var remaining = text[text.startIndex...]

        while let range = remaining.range(of: search, options: .caseInsensitive) {
            if range.lowerBound > remaining.startIndex {
                result.append(NSAttributedString(string: String(remaining[remaining.startIndex..<range.lowerBound]), attributes: baseAttrs))
            }
            result.append(NSAttributedString(string: String(remaining[range]), attributes: highlightAttrs))
            remaining = remaining[range.upperBound...]
        }

        if !remaining.isEmpty {
            result.append(NSAttributedString(string: String(remaining), attributes: baseAttrs))
        }
    }

    private func formatTimestamp(_ ts: String) -> String {
        guard ts.count >= 19,
              let tIdx = ts.firstIndex(of: "T") else { return ts }
        let timeStart = ts.index(after: tIdx)
        let timeEnd = ts.index(timeStart, offsetBy: 8, limitedBy: ts.endIndex) ?? ts.endIndex
        return String(ts[timeStart..<timeEnd])
    }

    /// Shorten pod name to just the unique suffix (e.g., "app-6f7b8c9d-x4k2p" → "x4k2p")
    private func shortenPodName(_ name: String) -> String {
        let parts = name.split(separator: "-")
        if parts.count >= 3 {
            return String(parts.suffix(1).joined())
        }
        return String(name.suffix(8))
    }
}

