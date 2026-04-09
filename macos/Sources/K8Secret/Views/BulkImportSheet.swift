import SwiftUI

struct BulkImportSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var format: ImportFormat = .env
    @State private var mode: ImportMode = .merge
    @State private var parsedPairs: [(String, String)] = []
    @State private var parseError: String?

    enum ImportFormat: String, CaseIterable {
        case env = ".env"
        case json = "JSON"
    }

    enum ImportMode: String, CaseIterable {
        case merge = "Merge"
        case replace = "Replace"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(.blue)
                Text("Bulk Import")
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                Spacer()
            }

            // Format + Mode pickers
            HStack(spacing: 16) {
                Picker("Format", selection: $format) {
                    ForEach(ImportFormat.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Picker("Mode", selection: $mode) {
                    ForEach(ImportMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()

                Text(mode == .merge ? "Add/overwrite existing keys" : "Replace all keys")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Input
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("PASTE DATA")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !input.isEmpty {
                        Text("\(input.components(separatedBy: "\n").count) lines")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                TextEditor(text: $input)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .padding(4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .scrollContentBackground(.hidden)
                    .onChange(of: input) { _, _ in parseInput() }
                    .onChange(of: format) { _, _ in parseInput() }
            }

            // Parse error
            if let error = parseError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
            }

            // Preview
            if !parsedPairs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PREVIEW (\(parsedPairs.count) keys)")
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(parsedPairs, id: \.0) { key, value in
                                HStack {
                                    Text(key)
                                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                                        .foregroundStyle(.blue)
                                        .frame(minWidth: 120, alignment: .leading)
                                    Text("=")
                                        .foregroundStyle(.tertiary)
                                    Text(value.prefix(80) + (value.count > 80 ? "..." : ""))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // Actions
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import \(parsedPairs.count) Keys") {
                    state.bulkImport(pairs: parsedPairs, replace: mode == .replace)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(parsedPairs.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 680)
    }

    private func parseInput() {
        parseError = nil
        parsedPairs = []
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }

        switch format {
        case .env:
            parsedPairs = parseEnv(trimmed)
        case .json:
            parsedPairs = parseJSON(trimmed)
        }
    }

    private func parseEnv(_ text: String) -> [(String, String)] {
        var result: [(String, String)] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if let eqIdx = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[trimmed.startIndex..<eqIdx]).trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
                // Strip surrounding quotes
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                if !key.isEmpty {
                    result.append((key, value))
                }
            }
        }
        if result.isEmpty && !text.isEmpty {
            parseError = "No valid KEY=VALUE pairs found"
        }
        return result
    }

    private func parseJSON(_ text: String) -> [(String, String)] {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            parseError = "Invalid JSON — expected { \"key\": \"value\" }"
            return []
        }
        return json.sorted(by: { $0.key < $1.key }).map { key, val in
            let strVal: String
            if let s = val as? String { strVal = s }
            else if let n = val as? NSNumber { strVal = "\(n)" }
            else { strVal = "\(val)" }
            return (key, strVal)
        }
    }
}

// MARK: - Export Sheet

struct ExportSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var format: ExportFormat = .env

    enum ExportFormat: String, CaseIterable {
        case env = ".env"
        case json = "JSON"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.green)
                Text("Export")
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                Spacer()
            }

            Picker("Format", selection: $format) {
                ForEach(ExportFormat.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            let content = format == .env ? state.exportAsEnv() : state.exportAsJSON()

            ScrollView {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 300)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                    state.showToast("Copied to clipboard")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 600)
    }
}
