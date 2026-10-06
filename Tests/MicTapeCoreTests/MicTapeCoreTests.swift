import Foundation
import Testing
@testable import MicTapeCore

@Suite struct FileNamingTests {
    let date = ISO8601DateFormatter().date(from: "2026-10-05T09:30:00Z")!
    let utc = TimeZone(identifier: "UTC")!

    @Test func rendersLabelAndDate() throws {
        #expect(try FileNaming.render("{label}-{date:yyyyMMdd}.m4a", label: "3", date: date, timeZone: utc) == "3-20261005.m4a")
    }

    @Test func defaultTemplateNeedsNoLabel() throws {
        #expect(try FileNaming.render(Config.defaultFilename, label: nil, date: date, timeZone: utc) == "20261005-093000.m4a")
    }

    @Test func appendsExtension() throws {
        #expect(try FileNaming.render("memo", label: nil) == "memo.m4a")
    }

    @Test func rejectsMissingOrUnsafeLabels() {
        #expect(throws: FileNamingError.labelRequired) { try FileNaming.render("{label}.m4a", label: nil) }
        #expect(throws: FileNamingError.invalidLabel("../x")) { try FileNaming.render("{label}.m4a", label: "../x") }
        #expect(throws: FileNamingError.invalidLabel("a/b")) { try FileNaming.render("{label}.m4a", label: "a/b") }
        #expect(throws: FileNamingError.unknownToken("nope")) { try FileNaming.render("{nope}.m4a", label: nil) }
    }

    @Test func numbersDuplicates() throws {
        let dir = try TempDir()
        let first = FileNaming.uniqueURL(directory: dir.url, name: "2-20261005.m4a")
        #expect(first.lastPathComponent == "2-20261005.m4a")
        try Data().write(to: first)
        let second = FileNaming.uniqueURL(directory: dir.url, name: "2-20261005.m4a")
        #expect(second.lastPathComponent == "2-20261005-2.m4a")
        try Data().write(to: second)
        #expect(FileNaming.uniqueURL(directory: dir.url, name: "2-20261005.m4a").lastPathComponent == "2-20261005-3.m4a")
    }
}

@Suite struct DestinationTests {
    @Test func expandsGlobAndAppendsSubdirectory() throws {
        let dir = try TempDir()
        for name in ["1-Phonetics", "2-Physics", "3-", "notes"] {
            try FileManager.default.createDirectory(at: dir.url.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let list = Destinations.list([DestinationRule(path: dir.url.path + "/[0-9]*-?*", subdirectory: "assets/audio")])
        #expect(list.map(\.name) == ["1-Phonetics", "2-Physics"])
        #expect(list[0].path.hasSuffix("/1-Phonetics/assets/audio"))
    }

    @Test func literalPathIsKeptEvenIfMissing() {
        let list = Destinations.list([DestinationRule(path: "/nonexistent/mictape/Recordings")])
        #expect(list == [Destination(name: "Recordings", path: "/nonexistent/mictape/Recordings")])
    }

    @Test func selectsBySubstring() throws {
        let all = [Destination(name: "1-Phonetics", path: "/a"), Destination(name: "2-Physics", path: "/b")]
        #expect(try Destinations.select("phon", from: all).path == "/a")
        #expect(throws: DestinationError.ambiguous("ph", ["1-Phonetics", "2-Physics"])) { try Destinations.select("ph", from: all) }
        #expect(throws: DestinationError.noMatch("math")) { try Destinations.select("math", from: all) }
        #expect(throws: DestinationError.ambiguous(nil, ["1-Phonetics", "2-Physics"])) { try Destinations.select(nil, from: all) }
        #expect(try Destinations.select(nil, from: [all[1]]).path == "/b")
    }

    @Test func exactNameWinsOverSubstring() throws {
        let all = [Destination(name: "Math", path: "/a"), Destination(name: "Math II", path: "/b")]
        #expect(try Destinations.select("math", from: all).path == "/a")
    }
}

@Suite struct ConfigTests {
    @Test func missingFileGivesDefaults() throws {
        let config = try Config.load(from: URL(fileURLWithPath: "/nonexistent/mictape/config.json"))
        #expect(config == Config())
    }

    @Test func partialFileKeepsDefaults() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("config.json")
        try #"{"filename": "{label}-{date:yyyyMMdd}.m4a"}"#.write(to: url, atomically: true, encoding: .utf8)
        let config = try Config.load(from: url)
        #expect(config.filename == "{label}-{date:yyyyMMdd}.m4a")
        #expect(config.destinations == Config().destinations)
    }

    @Test func addRemoveAndSetFilename() throws {
        var config = Config()
        let added = config.addDestination(DestinationRule(path: "~/Classes/*", subdirectory: "audio"))
        let addedAgain = config.addDestination(DestinationRule(path: "~/Classes/*", subdirectory: "audio"))
        #expect(added && !addedAgain)
        #expect(config.destinations.count == 2)
        let removed = config.removeDestination(path: "~/Recordings")
        #expect(removed == 1)
        #expect(config.destinations == [DestinationRule(path: "~/Classes/*", subdirectory: "audio")])
        try config.setFilename("{label}-{date:yyyyMMdd}")
        #expect(config.filename == "{label}-{date:yyyyMMdd}")
        var rejected: Error?
        do { try config.setFilename("{oops}") } catch { rejected = error }
        #expect(rejected as? FileNamingError == .unknownToken("oops"))
        #expect(config.filename == "{label}-{date:yyyyMMdd}")
    }

    @Test func saveRoundTripsAndFollowsSymlinks() throws {
        let dir = try TempDir()
        let real = dir.url.appendingPathComponent("dotfiles/config.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".write(to: real, atomically: true, encoding: .utf8)
        let link = dir.url.appendingPathComponent("config.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        var config = Config()
        config.addDestination(DestinationRule(path: "~/Meetings"))
        try config.save(to: link)

        let attrs = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect(attrs[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(try Config.load(from: real) == config)
    }

    @Test func environmentOverridesLocation() {
        #expect(Config.fileURL(environment: ["MICTAPE_CONFIG": "/x/c.json"]).path == "/x/c.json")
        #expect(Config.fileURL(environment: ["XDG_CONFIG_HOME": "/xdg"]).path == "/xdg/mictape/config.json")
    }
}

@Suite struct LevelTests {
    @Test func verdictThresholds() {
        #expect(LevelReport(meanDB: -23, maxDB: -3).verdict == .ok)
        #expect(LevelReport(meanDB: -35, maxDB: -10).verdict == .quiet)
        #expect(LevelReport(meanDB: -45, maxDB: -30).verdict == .silent)
    }
}

struct TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("mictape-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
