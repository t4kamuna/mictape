import Darwin
import Foundation

public struct Destination: Codable, Sendable, Equatable {
    /// The matched directory's own name, used for picking it.
    public let name: String
    /// The directory recordings are written to (match + subdirectory).
    public let path: String
}

public enum DestinationError: Error, CustomStringConvertible, Equatable {
    case none
    case noMatch(String)
    case ambiguous(String?, [String])

    public var description: String {
        switch self {
        case .none:
            return "No destination directories found. Check `destinations` in the config."
        case .noMatch(let query):
            return "No destination matches \"\(query)\". Run `mictape destinations` to list them."
        case .ambiguous(let query, let names):
            let head = query.map { "\"\($0)\" matches several destinations" } ?? "Several destinations are configured; pick one with --to"
            return head + ":\n" + names.map { "  \($0)" }.joined(separator: "\n")
        }
    }
}

public enum Destinations {
    /// Expands every rule. A rule without wildcards is used as-is even if the
    /// directory does not exist yet; globs only yield existing directories.
    public static func list(_ rules: [DestinationRule]) -> [Destination] {
        var seen = Set<String>()
        var result: [Destination] = []
        for rule in rules {
            let pattern = Paths.expandTilde(rule.path)
            let matches = hasWildcard(pattern) ? glob(pattern).filter(isDirectory) : [pattern]
            for match in matches {
                let base = (match as NSString).standardizingPath
                var path = base
                if let sub = rule.subdirectory, !sub.isEmpty {
                    path = (base as NSString).appendingPathComponent(sub)
                }
                guard seen.insert(path).inserted else { continue }
                result.append(Destination(name: (base as NSString).lastPathComponent, path: path))
            }
        }
        return result
    }

    /// Picks one destination by case-insensitive substring of its name.
    /// With no query, succeeds only when exactly one destination exists.
    public static func select(_ query: String?, from all: [Destination]) throws -> Destination {
        guard !all.isEmpty else { throw DestinationError.none }
        guard let query, !query.isEmpty else {
            guard all.count == 1 else { throw DestinationError.ambiguous(nil, all.map(\.name)) }
            return all[0]
        }
        if let exact = all.first(where: { $0.name.caseInsensitiveCompare(query) == .orderedSame }) {
            return exact
        }
        let matches = all.filter { $0.name.localizedCaseInsensitiveContains(query) }
        switch matches.count {
        case 0: throw DestinationError.noMatch(query)
        case 1: return matches[0]
        default: throw DestinationError.ambiguous(query, matches.map(\.name))
        }
    }

    static func hasWildcard(_ pattern: String) -> Bool {
        pattern.contains { "*?[{".contains($0) }
    }

    static func glob(_ pattern: String) -> [String] {
        var g = glob_t()
        defer { globfree(&g) }
        guard Darwin.glob(pattern, GLOB_BRACE | GLOB_TILDE, nil, &g) == 0 else { return [] }
        return (0..<Int(g.gl_pathc)).compactMap { g.gl_pathv[$0].map { String(cString: $0) } }.sorted()
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
