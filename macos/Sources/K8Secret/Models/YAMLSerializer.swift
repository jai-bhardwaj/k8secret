import Foundation

/// Converts a JSON dictionary to a YAML string representation.
enum YAMLSerializer {
    static func serialize(_ value: Any, indent: Int = 0) -> String {
        if let dict = value as? [String: Any] {
            return serializeMap(dict, indent: indent)
        } else if let arr = value as? [Any] {
            return serializeSequence(arr, indent: indent)
        } else if let str = value as? String {
            return serializeString(str, indent: indent)
        } else if let num = value as? NSNumber {
            // Check if it's a boolean
            if num === kCFBooleanTrue { return "true" }
            if num === kCFBooleanFalse { return "false" }
            return "\(num)"
        } else if value is NSNull {
            return "null"
        } else {
            return "\(value)"
        }
    }

    private static func serializeMap(_ dict: [String: Any], indent: Int) -> String {
        if dict.isEmpty { return "{}" }
        let pad = String(repeating: "  ", count: indent)
        var lines: [String] = []

        // Sort keys, but put common k8s fields first
        let priority = ["apiVersion", "kind", "metadata", "spec", "status", "data"]
        let sortedKeys = dict.keys.sorted { a, b in
            let ai = priority.firstIndex(of: a) ?? Int.max
            let bi = priority.firstIndex(of: b) ?? Int.max
            if ai != bi { return ai < bi }
            return a < b
        }

        for key in sortedKeys {
            guard let val = dict[key] else { continue }
            if let subDict = val as? [String: Any], !subDict.isEmpty {
                lines.append("\(pad)\(key):")
                lines.append(serializeMap(subDict, indent: indent + 1))
            } else if let arr = val as? [Any], !arr.isEmpty {
                lines.append("\(pad)\(key):")
                lines.append(serializeSequence(arr, indent: indent + 1))
            } else {
                lines.append("\(pad)\(key): \(serialize(val, indent: indent + 1))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func serializeSequence(_ arr: [Any], indent: Int) -> String {
        if arr.isEmpty { return "[]" }
        let pad = String(repeating: "  ", count: indent)
        var lines: [String] = []

        for item in arr {
            if let dict = item as? [String: Any] {
                let keys = dict.keys.sorted()
                if let firstKey = keys.first, let firstVal = dict[firstKey] {
                    let isSimple = !(firstVal is [String: Any]) && !(firstVal is [Any])
                    if isSimple {
                        lines.append("\(pad)- \(firstKey): \(serialize(firstVal))")
                    } else {
                        lines.append("\(pad)- \(firstKey):")
                        lines.append(serialize(firstVal, indent: indent + 2))
                    }
                    for key in keys.dropFirst() {
                        guard let val = dict[key] else { continue }
                        if let subDict = val as? [String: Any], !subDict.isEmpty {
                            lines.append("\(pad)  \(key):")
                            lines.append(serializeMap(subDict, indent: indent + 2))
                        } else if let subArr = val as? [Any], !subArr.isEmpty {
                            lines.append("\(pad)  \(key):")
                            lines.append(serializeSequence(subArr, indent: indent + 2))
                        } else {
                            lines.append("\(pad)  \(key): \(serialize(val))")
                        }
                    }
                }
            } else {
                lines.append("\(pad)- \(serialize(item))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func serializeString(_ str: String, indent: Int) -> String {
        if str.isEmpty { return "''" }

        if str.contains("\n") {
            // Block scalar. The body sits one level deeper than the key, and the
            // chomping indicator has to match whether the value ends in a newline —
            // plain `|` implies a trailing newline, so a value without one must use
            // `|-` or it grows a character every time it's edited and re-applied.
            let pad = String(repeating: "  ", count: indent)
            let endsWithNewline = str.hasSuffix("\n")
            let body = endsWithNewline ? String(str.dropLast()) : str
            let header = endsWithNewline ? "|" : "|-"

            let rendered = body
                .components(separatedBy: "\n")
                .map { $0.isEmpty ? "" : pad + $0 }
                .joined(separator: "\n")
            return "\(header)\n\(rendered)"
        }

        // Quote anything that would parse back as a non-string. The parser now types
        // scalars, so an unquoted "3" would return as the number 3 and an unquoted
        // "true" as a boolean — silently changing the resource on round-trip.
        let needsQuoting = str.contains(":") || str.contains("#") || str.contains("{") ||
            str.contains("}") || str.contains("[") || str.contains("]") || str.contains(",") ||
            str.contains("&") || str.contains("*") || str.contains("!") || str.contains("|") ||
            str.contains(">") || str.contains("'") || str.contains("\"") ||
            str.contains("\t") ||
            str.hasPrefix(" ") || str.hasSuffix(" ") ||
            str.hasPrefix("-") || str.hasPrefix("?") || str.hasPrefix("%") || str.hasPrefix("@") ||
            looksLikeNonString(str)

        if needsQuoting {
            let escaped = str
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return str
    }

    /// True when the plain text would be re-read as a bool, null or number.
    private static func looksLikeNonString(_ str: String) -> Bool {
        switch str {
        case "true", "True", "TRUE", "false", "False", "FALSE",
             "null", "Null", "NULL", "~", "yes", "no", "on", "off":
            return true
        default:
            break
        }

        var body = Substring(str)
        if body.hasPrefix("-") || body.hasPrefix("+") { body = body.dropFirst() }
        guard !body.isEmpty else { return false }

        // Integer or simple decimal, matching what the parser will accept back.
        let digitsAndOneDot = body.allSatisfy { ($0.isASCII && $0.isNumber) || $0 == "." }
        return digitsAndOneDot && body.filter { $0 == "." }.count <= 1 && body.contains(where: \.isNumber)
    }
}
