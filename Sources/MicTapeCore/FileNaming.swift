import Foundation

public enum FileNamingError: Error, CustomStringConvertible, Equatable {
    case labelRequired
    case invalidLabel(String)
    case unknownToken(String)
    case invalidName(String)

    public var description: String {
        switch self {
        case .labelRequired:
            return "The file name template uses {label}; pass one with --label."
        case .invalidLabel(let label):
            return "Invalid label \"\(label)\": it must not contain \"/\" or start with \".\"."
        case .unknownToken(let token):
            return "Unknown token {\(token)} in the file name template."
        case .invalidName(let name):
            return "The file name template produced an invalid name \"\(name)\"."
        }
    }
}

public enum FileNaming {
    /// Renders a template such as `{label}-{date:yyyyMMdd}.m4a`.
    public static func render(_ template: String, label: String?, date: Date = Date(), timeZone: TimeZone = .current) throws -> String {
        if let label, label.contains("/") || label.hasPrefix(".") || label.isEmpty {
            throw FileNamingError.invalidLabel(label)
        }
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else {
                out += rest[open...]
                rest = ""
                break
            }
            let token = String(rest[rest.index(after: open)..<close])
            out += try expand(token, label: label, date: date, timeZone: timeZone)
            rest = rest[rest.index(after: close)...]
        }
        out += rest
        if !out.lowercased().hasSuffix(".m4a") { out += ".m4a" }
        guard !out.contains("/"), !out.hasPrefix("."), out != ".m4a" else { throw FileNamingError.invalidName(out) }
        return out
    }

    /// Returns `directory/name`, or `name-2`, `name-3`, … when it already exists.
    public static func uniqueURL(directory: URL, name: String, fileManager: FileManager = .default) -> URL {
        let first = directory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: first.path) else { return first }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var i = 2
        while true {
            let candidate = directory.appendingPathComponent("\(stem)-\(i).\(ext)")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    private static func expand(_ token: String, label: String?, date: Date, timeZone: TimeZone) throws -> String {
        if token == "label" {
            guard let label else { throw FileNamingError.labelRequired }
            return label
        }
        if token.hasPrefix("date:") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = String(token.dropFirst(5))
            return formatter.string(from: date)
        }
        throw FileNamingError.unknownToken(token)
    }
}
