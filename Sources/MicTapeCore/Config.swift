import Foundation

/// User configuration, read from `$MICTAPE_CONFIG` or
/// `$XDG_CONFIG_HOME/mictape/config.json` (default `~/.config/mictape/config.json`).
public struct Config: Codable, Sendable, Equatable {
    /// Where recordings may be saved. Each entry is a glob; every matching
    /// directory becomes a destination you can pick by name.
    public var destinations: [DestinationRule]
    /// File name template. Tokens: `{label}`, `{date:FORMAT}` (ICU date format).
    public var filename: String
    /// Input device name or unique ID. Omit for the system default.
    public var device: String?

    public static let defaultFilename = "{date:yyyyMMdd-HHmmss}.m4a"

    public init(destinations: [DestinationRule] = [DestinationRule(path: "~/Recordings")],
                filename: String = Config.defaultFilename,
                device: String? = nil) {
        self.destinations = destinations
        self.filename = filename
        self.device = device
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Config()
        destinations = try c.decodeIfPresent([DestinationRule].self, forKey: .destinations) ?? defaults.destinations
        filename = try c.decodeIfPresent(String.self, forKey: .filename) ?? defaults.filename
        device = try c.decodeIfPresent(String.self, forKey: .device)
    }

    public static func fileURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["MICTAPE_CONFIG"], !path.isEmpty {
            return URL(fileURLWithPath: Paths.expandTilde(path))
        }
        let base = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? Paths.expandTilde("~/.config")
        return URL(fileURLWithPath: base).appendingPathComponent("mictape/config.json")
    }

    /// Loads the config file, or the defaults when it does not exist.
    public static func load(from url: URL = Config.fileURL()) throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        } catch {
            throw ConfigError.invalid(url.path, error)
        }
    }
}

public struct DestinationRule: Codable, Sendable, Equatable {
    /// A directory path or glob, e.g. `~/Notes/*/recordings` or `~/Classes/[0-9]*-?*`.
    public var path: String
    /// Appended to every match, e.g. `assets/audio`. Created when recording starts.
    public var subdirectory: String?

    public init(path: String, subdirectory: String? = nil) {
        self.path = path
        self.subdirectory = subdirectory
    }
}

public enum ConfigError: Error, CustomStringConvertible {
    case invalid(String, Error)

    public var description: String {
        switch self {
        case .invalid(let path, let error):
            return "Could not read \(path): \(error)"
        }
    }
}

enum Paths {
    static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
