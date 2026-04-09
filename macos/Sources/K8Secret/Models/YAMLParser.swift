import Foundation

/// Minimal YAML parser handling the subset used by kubeconfig files.
/// Supports: scalars, maps, sequences (including inline map entries with
/// sibling keys at sequence-item indent + 2), quoted strings, and
/// multi-line values on subsequent indented lines.
enum YAMLValue {
    case string(String)
    case map([String: YAMLValue])
    case sequence([YAMLValue])
    case null

    var stringValue: String? {
        if case .string(let s) = self { return s }
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
}

struct YAMLParser {
    private var lines: [(indent: Int, content: String)]
    private var pos: Int = 0

    static func parse(_ text: String) -> YAMLValue {
        var parser = YAMLParser(text: text)
        return parser.parseValue(minIndent: -1)
    }

    private init(text: String) {
        self.lines = text
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
                let indent = line.prefix(while: { $0 == " " }).count
                return (indent, trimmed)
            }
    }

    private var done: Bool { pos >= lines.count }

    private mutating func parseValue(minIndent: Int) -> YAMLValue {
        guard !done else { return .null }

        let (indent, content) = lines[pos]
        if indent < minIndent { return .null }

        // Sequence items may sit at the same indent as the parent map key.
        // e.g.  clusters:\n- cluster:\n    server: ...
        // Here "clusters:" is at indent 0 and "- cluster:" is also at indent 0.
        // When called from parseMap after consuming "clusters:", minIndent is 0,
        // and the sequence item is also at indent 0.  We must allow indent == minIndent
        // for sequence items specifically.
        if content.hasPrefix("- ") || content == "-" {
            if indent >= minIndent {
                return parseSequence(seqIndent: indent)
            }
            return .null
        }

        // For non-sequence values, require strictly greater indent.
        if indent <= minIndent { return .null }

        // Map entry
        if findColon(in: content) != nil {
            return parseMap(mapIndent: indent)
        }

        // Plain scalar
        pos += 1
        return .string(unquote(content))
    }

    private mutating func parseMap(mapIndent: Int) -> YAMLValue {
        var dict: [String: YAMLValue] = [:]

        while !done {
            let (indent, content) = lines[pos]
            if indent != mapIndent { break }
            // Stop if we hit a sequence item at this indent (belongs to parent)
            if content.hasPrefix("- ") || content == "-" { break }

            guard let colonIdx = findColon(in: content) else { break }

            let key = String(content[content.startIndex..<content.index(content.startIndex, offsetBy: colonIdx)])
                .trimmingCharacters(in: .whitespaces)
            let afterColon = String(content[content.index(content.startIndex, offsetBy: colonIdx + 1)...])
                .trimmingCharacters(in: .whitespaces)

            pos += 1

            if afterColon.isEmpty {
                // Value is on next lines (nested map, sequence, or block scalar)
                dict[key] = parseValue(minIndent: mapIndent)
            } else {
                dict[key] = .string(unquote(afterColon))
            }
        }

        return .map(dict)
    }

    private mutating func parseSequence(seqIndent: Int) -> YAMLValue {
        var items: [YAMLValue] = []

        while !done {
            let (indent, content) = lines[pos]
            if indent != seqIndent { break }
            guard content.hasPrefix("- ") || content == "-" else { break }

            let after = content == "-" ? "" : String(content.dropFirst(2)).trimmingCharacters(in: .whitespaces)

            if after.isEmpty {
                // Bare "- " with nested value on following lines
                pos += 1
                items.append(parseValue(minIndent: seqIndent))
            } else if findColon(in: after) != nil {
                // Inline map start: "- key: value" with possible sibling keys
                // on following lines at seqIndent + 2.
                let itemIndent = seqIndent + 2
                lines[pos] = (itemIndent, after)
                items.append(parseMap(mapIndent: itemIndent))
            } else {
                pos += 1
                items.append(.string(unquote(after)))
            }
        }

        return .sequence(items)
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

    private func unquote(_ s: String) -> String {
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}
