import Darwin
import Foundation

/// The running recording, persisted so `stop` and `status` can find it.
public struct RecordingState: Codable, Sendable, Equatable {
    public let pid: Int32
    public let path: String
    public let device: String
    public let startedAt: Date

    public init(pid: Int32, path: String, device: String, startedAt: Date) {
        self.pid = pid
        self.path = path
        self.device = device
        self.startedAt = startedAt
    }

    public var isAlive: Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}

public struct StateStore: Sendable {
    public let directory: URL

    public init(directory: URL = StateStore.defaultDirectory) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mictape", isDirectory: true)
    }

    var stateURL: URL { directory.appendingPathComponent("state.json") }
    public var logURL: URL { directory.appendingPathComponent("recorder.log") }

    public func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The current recording, or nil. A state left behind by a dead process is removed.
    public func current() -> RecordingState? {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? Self.decoder.decode(RecordingState.self, from: data) else { return nil }
        guard state.isAlive else {
            clear()
            return nil
        }
        return state
    }

    public func save(_ state: RecordingState) throws {
        try ensureDirectory()
        try Self.encoder.encode(state).write(to: stateURL, options: .atomic)
    }

    public func clear(ifPID pid: Int32? = nil) {
        if let pid {
            guard let data = try? Data(contentsOf: stateURL),
                  let state = try? Self.decoder.decode(RecordingState.self, from: data),
                  state.pid == pid else { return }
        }
        try? FileManager.default.removeItem(at: stateURL)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
