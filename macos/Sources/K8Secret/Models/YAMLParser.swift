import Foundation

/// Minimal YAML parser handling the subset used by kubeconfig files and by the
/// resource editor.
///
/// Supports: typed scalars (string / int / double / bool / null), maps, sequences
/// (including inline map entries with sibling keys at sequence-item indent + 2),
/// quoted strings, literal (`|`) and folded (`>`) block scalars with chomping
/// indicators, and `#` comments.
///
/// Not supported: anchors and aliases, flow collections (`{a: b}`, `[1, 2]`),
/// multiple documents, and tags. `YAMLParser.validate` reports those rather than
/// silently mis-parsing them.
enum YAMLValue {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case map([String: YAMLValue])
    case sequence([YAMLValue])
    case null

    /// Textual form of any scalar.
    ///
    /// Deliberately lenient: it returns the source text for numbers and booleans
    /// too, so callers that only ever want a string (a token that happens to be all
    /// digits, a cluster named `123`) keep working now that scalars carry types.
    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .map, .sequence, .null: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .string(let s):
            switch s.lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        default: return nil
        }
    }

    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    var mapValue: [String: YAMLValue]? {
        if case .map(let m) = self { return m }
        return nil
    }

    var sequenceValue: [YAMLValue]? {
        if case .sequence(let s) = self { return s }
        return nil
    }

    subscript(key: String) -> YAMLValue? {
        mapValue?[key]
    }

    /// Foundation representation, suitable for `JSONSerialization`.
    ///
    /// This is what makes the resource editor safe: `replicas: 3` reaches the API
    /// server as the number 3, not the string "3".
    var jsonObject: Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        case .map(let m): return m.mapValues(\.jsonObject)
        case .sequence(let s): return s.map(\.jsonObject)
        }
    }
}

struct YAMLParser {
    private struct Line {
        let indent: Int
        let content: String   // trimmed; empty for blank lines
        let raw: String

        /// Blank and comment-only lines carry no structure, but blank lines are
        /// still meaningful *inside* a block scalar, so they are kept in the list
        /// and skipped only during structural parsing.
        var isStructural: Bool { !content.isEmpty && !content.hasPrefix("#") }
    }

    private var lines: [Line]
    private var pos: Int = 0

    static func parse(_ text: String) -> YAMLValue {
        var parser = YAMLParser(text: text)
        return parser.parseValue(minIndent: -1)
    }

    /// Reasons this text can't be parsed faithfully. Empty means it round-trips.
    ///
    /// The editor writes straight to a live cluster, so a construct we'd quietly
    /// mangle has to be refused rather than applied.
    static func validate(_ text: String) -> [String] {
        var problems: [String] = []
        var sawDocumentStart = false

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line == "---" || line.hasPrefix("--- ") {
                if sawDocumentStart {
                    problems.append("Multiple YAML documents aren't supported — edit one resource at a time.")
                    break
                }
                sawDocumentStart = true
                continue
            }

            // Anchors/aliases and merge keys change meaning on expansion.
            if line.hasPrefix("&") || line.hasPrefix("*") || line.contains(": &") || line.contains(": *") {
                problems.append("Anchors and aliases (&, *) aren't supported.")
            }
            if line.hasPrefix("<<:") {
                problems.append("Merge keys (<<:) aren't supported.")
            }

            // Flow collections after a key, e.g. `args: [a, b]` or `meta: {x: 1}`.
            if let colon = line.firstIndex(of: ":") {
                let after = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if after.hasPrefix("[") || after.hasPrefix("{") {
                    problems.append("Inline flow collections ([...] / {...}) aren't supported — use block style.")
                }
            }
        }

        return Array(Set(problems)).sorted()
    }

    private init(text: String) {
        self.lines = text
            .components(separatedBy: .newlines)
            .map { line in
                Line(
                    indent: line.prefix(while: { $0 == " " }).count,
                    content: line.trimmingCharacters(in: .whitespaces),
                    raw: line
                )
            }
    }

    private mutating func skipNonStructural() {
        while pos < lines.count && !lines[pos].isStructural { pos += 1 }
    }

    private var done: Bool { pos >= lines.count }

    private mutating func parseValue(minIndent: Int) -> YAMLValue {
        skipNonStructural()
        guard !done else { return .null }

        let line = lines[pos]
        if line.indent < minIndent { return .null }

        // Sequence items may sit at the same indent as the parent map key.
        // e.g.  clusters:\n- cluster:\n    server: ...
        // Here "clusters:" is at indent 0 and "- cluster:" is also at indent 0.
        if line.content.hasPrefix("- ") || line.content == "-" {
            if line.indent >= minIndent {
                return parseSequence(seqIndent: line.indent)
            }
            return .null
        }

        // For non-sequence values, require strictly greater indent.
        if line.indent <= minIndent { return .null }

        // Map entry
        if findColon(in: line.content) != nil {
            return parseMap(mapIndent: line.indent)
        }

        // Plain scalar
        pos += 1
        return scalar(from: stripComment(line.content))
    }

    private mutating func parseMap(mapIndent: Int) -> YAMLValue {
        var dict: [String: YAMLValue] = [:]

        while true {
            skipNonStructural()
            guard !done else { break }

            let line = lines[pos]
            if line.indent != mapIndent { break }
            // Stop if we hit a sequence item at this indent (belongs to parent)
            if line.content.hasPrefix("- ") || line.content == "-" { break }

            guard let colonIdx = findColon(in: line.content) else { break }

            let content = line.content
            let key = String(content[content.startIndex..<content.index(content.startIndex, offsetBy: colonIdx)])
                .trimmingCharacters(in: .whitespaces)
            let afterColon = String(content[content.index(content.startIndex, offsetBy: colonIdx + 1)...])
                .trimmingCharacters(in: .whitespaces)

            pos += 1

            if let header = blockScalarHeader(afterColon) {
                dict[unquote(key)] = parseBlockScalar(header: header, parentIndent: mapIndent)
                continue
            }

            let text = stripComment(afterColon)
            if text.isEmpty {
                // Value is on the following lines (nested map or sequence)
                dict[unquote(key)] = parseValue(minIndent: mapIndent)
            } else {
                dict[unquote(key)] = scalar(from: text)
            }
        }

        return .map(dict)
    }

    private mutating func parseSequence(seqIndent: Int) -> YAMLValue {
        var items: [YAMLValue] = []

        while true {
            skipNonStructural()
            guard !done else { break }

            let line = lines[pos]
            if line.indent != seqIndent { break }
            guard line.content.hasPrefix("- ") || line.content == "-" else { break }

            let after = line.content == "-"
                ? ""
                : String(line.content.dropFirst(2)).trimmingCharacters(in: .whitespaces)

            if after.isEmpty {
                // Bare "- " with nested value on following lines
                pos += 1
                items.append(parseValue(minIndent: seqIndent))
            } else if findColon(in: after) != nil {
                // Inline map start: "- key: value" with possible sibling keys
                // on following lines at seqIndent + 2.
                let itemIndent = seqIndent + 2
                lines[pos] = Line(
                    indent: itemIndent,
                    content: after,
                    raw: String(repeating: " ", count: itemIndent) + after
                )
                items.append(parseMap(mapIndent: itemIndent))
            } else {
                pos += 1
                items.append(scalar(from: stripComment(after)))
            }
        }

        return .sequence(items)
    }

    // MARK: - Block scalars

    /// Returns the header (`|`, `|-`, `>-`, …) if this value opens a block scalar.
    private func blockScalarHeader(_ s: String) -> String? {
        guard s.hasPrefix("|") || s.hasPrefix(">") else { return nil }
        // Reject things like ">>" or "| something" that aren't block headers.
        let indicators = s.dropFirst()
        guard indicators.allSatisfy({ $0 == "-" || $0 == "+" }) else { return nil }
        return s
    }

    /// Read an indented block into a single string.
    ///
    /// The serializer emits multi-line values (certificates, keys, embedded config)
    /// as `|` blocks, so without this the editor could write a resource it could
    /// not read back.
    private mutating func parseBlockScalar(header: String, parentIndent: Int) -> YAMLValue {
        let folded = header.hasPrefix(">")
        let strip = header.contains("-")
        let keep = header.contains("+")

        var collected: [String] = []
        var blockIndent: Int?

        while pos < lines.count {
            let line = lines[pos]

            if line.content.isEmpty {
                collected.append("")
                pos += 1
                continue
            }
            if line.indent <= parentIndent { break }

            if blockIndent == nil { blockIndent = line.indent }
            let dropCount = min(blockIndent ?? line.indent, line.indent)
            collected.append(String(line.raw.dropFirst(dropCount)))
            pos += 1
        }

        // Trailing blank lines belong to the document, not the block, unless the
        // `+` (keep) chomping indicator was given.
        if !keep {
            while collected.last?.isEmpty == true { collected.removeLast() }
        }

        var text = folded ? foldLines(collected) : collected.joined(separator: "\n")
        if !strip && !text.isEmpty { text += "\n" }

        return .string(text)
    }

    /// Folded (`>`) scalars join consecutive non-empty lines with a space; a blank
    /// line becomes a single newline.
    private func foldLines(_ lines: [String]) -> String {
        var result = ""
        var previousWasText = false

        for line in lines {
            if line.isEmpty {
                result += "\n"
                previousWasText = false
            } else {
                if previousWasText { result += " " }
                result += line
                previousWasText = true
            }
        }
        return result
    }

    // MARK: - Scalars

    /// Infer a scalar's type the way the Kubernetes API expects.
    ///
    /// Everything used to parse as `.string`, so the editor turned `replicas: 3`
    /// into `"3"` and `PUT` it — which the API server rejects, or worse coerces.
    /// Quoted text stays a string; only `true`/`false` are booleans (`yes`/`no` are
    /// deliberately not, to avoid the classic "Norway problem").
    private func scalar(from raw: String) -> YAMLValue {
        if isQuoted(raw) { return .string(unquote(raw)) }

        switch raw {
        case "true", "True", "TRUE":    return .bool(true)
        case "false", "False", "FALSE": return .bool(false)
        case "null", "Null", "NULL", "~", "": return .null
        default: break
        }

        if Self.isInteger(raw), let i = Int(raw) { return .int(i) }
        if Self.isDecimal(raw), let d = Double(raw) { return .double(d) }

        return .string(raw)
    }

    private static func isInteger(_ s: String) -> Bool {
        var body = Substring(s)
        if body.hasPrefix("-") || body.hasPrefix("+") { body = body.dropFirst() }
        // Reject "007"-style values: they're usually identifiers, not numbers.
        if body.count > 1 && body.hasPrefix("0") { return false }
        return !body.isEmpty && body.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func isDecimal(_ s: String) -> Bool {
        var body = Substring(s)
        if body.hasPrefix("-") || body.hasPrefix("+") { body = body.dropFirst() }

        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        return parts.allSatisfy { part in part.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    private func isQuoted(_ s: String) -> Bool {
        guard s.count >= 2 else { return false }
        return (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'"))
    }

    private func findColon(in s: String) -> Int? {
        // Find ':' that is followed by ' ' or end-of-string, indicating a map key.
        // Skip colons inside quoted strings.
        var inSingle = false
        var inDouble = false
        for (i, ch) in s.enumerated() {
            if ch == "'" && !inDouble { inSingle.toggle(); continue }
            if ch == "\"" && !inSingle { inDouble.toggle(); continue }
            if ch == ":" && !inSingle && !inDouble {
                let nextIdx = s.index(s.startIndex, offsetBy: i + 1)
                if nextIdx == s.endIndex || s[nextIdx] == " " {
                    return i
                }
            }
        }
        return nil
    }

    /// Strip a trailing `# comment` from a scalar.
    ///
    /// YAML only starts a comment at a `#` that follows whitespace (or begins the
    /// value) and sits outside quotes. Without this, a perfectly ordinary
    /// `server: https://prod.example.com  # production` parsed into a server URL
    /// with the comment glued on, and every request to that cluster failed with an
    /// error that pointed nowhere near the kubeconfig.
    private func stripComment(_ s: String) -> String {
        var inSingle = false
        var inDouble = false
        var previousWasSpace = true
        var index = s.startIndex

        while index < s.endIndex {
            let ch = s[index]
            if ch == "'" && !inDouble {
                inSingle.toggle()
            } else if ch == "\"" && !inSingle {
                inDouble.toggle()
            } else if ch == "#" && !inSingle && !inDouble && previousWasSpace {
                return String(s[s.startIndex..<index]).trimmingCharacters(in: .whitespaces)
            }
            previousWasSpace = (ch == " " || ch == "\t")
            index = s.index(after: index)
        }
        return s
    }

    private func unquote(_ s: String) -> String {
        guard isQuoted(s) else { return s }
        let inner = String(s.dropFirst().dropLast())

        // Single-quoted YAML only escapes '' → '. Double-quoted supports backslash escapes.
        if s.hasPrefix("'") {
            return inner.replacingOccurrences(of: "''", with: "'")
        }

        var result = ""
        var iterator = inner.makeIterator()
        while let ch = iterator.next() {
            guard ch == "\\" else { result.append(ch); continue }
            switch iterator.next() {
            case "n":  result.append("\n")
            case "t":  result.append("\t")
            case "r":  result.append("\r")
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            case "0":  result.append("\0")
            case let other?: result.append(other)
            case nil:  result.append("\\")
            }
        }
        return result
    }
}
