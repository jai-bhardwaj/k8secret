import Foundation

/// Converts a JSON dictionary to a YAML string representation.
enum YAMLSerializer {
    static func serialize(_ value: Any, indent: Int = 0) -> String {
        if let dict = value as? [String: Any] {
            return serializeMap(dict, indent: indent)
        } else if let arr = value as? [Any] {
            return serializeSequence(arr, indent: indent)
        } else if let str = value as? String {
            return serializeString(str)
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

    private static func serializeString(_ str: String) -> String {
        if str.isEmpty { return "''" }
        if str.contains("\n") {
            // Multi-line string
            let lines = str.components(separatedBy: "\n")
            return "|\n" + lines.map { "  \($0)" }.joined(separator: "\n")
        }
        // Quote if contains special chars
        let needsQuoting = str.contains(":") || str.contains("#") || str.contains("{") ||
            str.contains("}") || str.contains("[") || str.contains("]") || str.contains(",") ||
            str.contains("&") || str.contains("*") || str.contains("!") || str.contains("|") ||
            str.contains(">") || str.contains("'") || str.contains("\"") ||
            str.hasPrefix(" ") || str.hasSuffix(" ") ||
            str == "true" || str == "false" || str == "null" || str == "yes" || str == "no"
        if needsQuoting {
            let escaped = str.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return str
    }
}
