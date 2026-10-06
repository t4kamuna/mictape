import Darwin
import Foundation
import MicTapeCore

let usage = """
mictape \(MicTape.version) - record the microphone to .m4a files

Usage:
  mictape record [<destination>] [<label>] [options]   Record in the foreground; stop with q or Ctrl+C
  mictape start  [<destination>] [<label>] [options]   Record in the background
  mictape stop                                         Stop the background recording
  mictape status                                       Show the current recording
  mictape test [--seconds N]                           Record a few seconds and check the input level
  mictape devices                                      List input devices
  mictape destinations                                 List configured destinations
  mictape config                                       Show the effective configuration
  mictape config add-destination <path> [--subdirectory <dir>]
  mictape config remove-destination <path> [--subdirectory <dir>]
  mictape config set-filename <template>
  mictape config preview-filename <template> [--label <label>]

Options:
  -t, --to <name>        Destination to save into (case-insensitive substring)
  -l, --label <label>    Value for {label} in the file name template
  -d, --device <device>  Input device name or ID (default: system default)
      --json             Print machine-readable JSON
  -h, --help             Show this help

Config: \(Config.fileURL().path)
"""

struct Options {
    var command = ""
    var positionals: [String] = []
    var to: String?
    var label: String?
    var device: String?
    var output: String?
    var subdirectory: String?
    var seconds = 10.0
    var json = false
    var background = false
}

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case message(String)

    var description: String {
        switch self {
        case .usage(let m), .message(let m): return m
        }
    }
}

func parse(_ args: [String]) throws -> Options {
    var o = Options()
    var it = args.makeIterator()
    func value(_ flag: String) throws -> String {
        guard let v = it.next() else { throw CLIError.usage("\(flag) needs a value") }
        return v
    }
    while let arg = it.next() {
        switch arg {
        case "-t", "--to": o.to = try value(arg)
        case "-l", "--label": o.label = try value(arg)
        case "-d", "--device": o.device = try value(arg)
        case "--output": o.output = try value(arg)
        case "--subdirectory": o.subdirectory = try value(arg)
        case "--seconds":
            guard let s = Double(try value(arg)), s > 0 else { throw CLIError.usage("--seconds must be a positive number") }
            o.seconds = s
        case "--json": o.json = true
        case "--background": o.background = true
        case "-h", "--help": o.command = "help"
        case "--version": o.command = "version"
        default:
            if arg.hasPrefix("-") && arg != "-" { throw CLIError.usage("Unknown option \(arg)") }
            if o.command.isEmpty { o.command = arg } else { o.positionals.append(arg) }
        }
    }
    // For config, positionals are a subcommand and its argument, not a destination and label.
    if o.command != "config" {
        if o.to == nil, o.positionals.count > 0 { o.to = o.positionals[0] }
        if o.label == nil, o.positionals.count > 1 { o.label = o.positionals[1] }
    }
    if o.positionals.count > 2 { throw CLIError.usage("Too many arguments") }
    return o
}

// MARK: - Output

func eprint(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

func printJSON<T: Encodable>(_ value: T) {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    e.dateEncodingStrategy = .iso8601
    print(String(data: try! e.encode(value), encoding: .utf8)!)
}

func clock(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
}

struct SavedRecording: Encodable {
    let path: String
    let duration: TimeInterval
}

struct StatusReport: Encodable {
    let recording: Bool
    let path: String?
    let device: String?
    let startedAt: Date?
    let elapsed: TimeInterval?
    let pid: Int32?
}

// MARK: - Commands

let store = StateStore()

/// Resolves where the next recording goes, from options and config.
func plannedOutput(_ o: Options, config: Config) throws -> URL {
    if let output = o.output { return URL(fileURLWithPath: output) }
    let destination = try Destinations.select(o.to, from: Destinations.list(config.destinations))
    let name = try FileNaming.render(config.filename, label: o.label)
    let dir = URL(fileURLWithPath: destination.path, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return FileNaming.uniqueURL(directory: dir, name: name)
}

func ensureIdle() throws {
    if let state = store.current() {
        throw CLIError.message("Already recording to \(state.path) (pid \(state.pid)). Stop it with `mictape stop`.")
    }
}

var savedTermios: termios?

func restoreTerminal() {
    if var t = savedTermios { tcsetattr(STDIN_FILENO, TCSANOW, &t) }
}

/// Reads single keys from a terminal without waiting for Enter.
func watchForQuit(_ onQuit: @escaping () -> Void) -> DispatchSourceRead? {
    guard isatty(STDIN_FILENO) == 1 else { return nil }
    var t = termios()
    tcgetattr(STDIN_FILENO, &t)
    savedTermios = t
    t.c_lflag &= ~tcflag_t(ICANON | ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &t)
    let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
    source.setEventHandler {
        var byte: UInt8 = 0
        if read(STDIN_FILENO, &byte, 1) == 1, byte == UInt8(ascii: "q") || byte == UInt8(ascii: "Q") { onQuit() }
    }
    source.resume()
    return source
}

var keepAlive: [AnyObject] = []

func record(_ o: Options) async throws {
    let config = try Config.load()
    try ensureIdle()
    let url = try plannedOutput(o, config: config)
    try await Devices.requestAccess()
    let device = try Devices.resolve(o.device ?? config.device)
    let recorder = try Recorder(url: url, device: device)
    let sleep = SleepAssertion(reason: "mictape is recording \(url.lastPathComponent)")
    let pid = getpid()
    try store.save(RecordingState(pid: pid, path: url.path, device: device.localizedName, startedAt: Date()))
    recorder.start()

    let interactive = !o.background && isatty(STDERR_FILENO) == 1
    if !o.background {
        eprint("Recording \(device.localizedName) -> \(url.path)")
        eprint("Press q or Ctrl+C to stop. Keep the lid open: closing it sleeps the Mac and stops the recording.")
    } else {
        eprint("\(Date()) recording \(url.path) pid \(pid)")
    }

    var finishing = false
    func finish() {
        guard !finishing else { return }
        finishing = true
        restoreTerminal()
        Task {
            var failure: Error?
            do { try await recorder.stop() } catch { failure = error }
            sleep.release()
            store.clear(ifPID: pid)
            if interactive { FileHandle.standardError.write("\n".data(using: .utf8)!) }
            let duration = LevelCheck.duration(url)
            if let failure {
                eprint("\(failure)")
                exit(1)
            }
            guard let duration, duration > 0 else {
                try? FileManager.default.removeItem(at: url)
                eprint("Nothing was recorded. Run `mictape test` to check the microphone.")
                exit(1)
            }
            if o.json {
                printJSON(SavedRecording(path: url.path, duration: duration))
            } else {
                print("Saved \(url.path) (\(clock(duration)))")
            }
            exit(0)
        }
    }

    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler { finish() }
        source.resume()
        keepAlive.append(source)
    }
    if !o.background, let keys = watchForQuit({ finish() }) { keepAlive.append(keys) }
    if interactive {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler {
            guard !finishing else { return }
            FileHandle.standardError.write("\r\u{1B}[KREC \(clock(recorder.duration))".data(using: .utf8)!)
        }
        timer.resume()
        keepAlive.append(timer)
    }
}

func start(_ o: Options) async throws {
    let config = try Config.load()
    try ensureIdle()
    let url = try plannedOutput(o, config: config)
    // Ask for microphone access here, while attached to the caller,
    // so the prompt is not raised by a detached process.
    try await Devices.requestAccess()
    let device = try Devices.resolve(o.device ?? config.device)
    try store.ensureDirectory()

    guard let exe = Bundle.main.executablePath else { throw CLIError.message("Cannot locate the mictape executable.") }
    let args = [exe, "record", "--background", "--output", url.path, "--device", device.uniqueID]
    var attr = posix_spawnattr_t(nil as OpaquePointer?)
    posix_spawnattr_init(&attr)
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
    var actions = posix_spawn_file_actions_t(nil as OpaquePointer?)
    posix_spawn_file_actions_init(&actions)
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, store.logURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO)
    defer {
        posix_spawnattr_destroy(&attr)
        posix_spawn_file_actions_destroy(&actions)
    }
    var child: pid_t = 0
    let cargs = args.map { strdup($0) } + [nil]
    defer { cargs.forEach { free($0) } }
    let rc = posix_spawn(&child, exe, &actions, &attr, cargs, environ)
    guard rc == 0 else { throw CLIError.message("Could not start the recorder: \(String(cString: strerror(rc)))") }

    for _ in 0..<100 {
        if let state = store.current(), state.pid == child {
            if o.json {
                printJSON(StatusReport(recording: true, path: state.path, device: state.device,
                                       startedAt: state.startedAt, elapsed: 0, pid: state.pid))
            } else {
                print("Recording \(state.device) -> \(state.path)")
            }
            return
        }
        var status: Int32 = 0
        if waitpid(child, &status, WNOHANG) == child { break }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    let log = (try? String(contentsOf: store.logURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    throw CLIError.message(log.flatMap { $0.isEmpty ? nil : $0 } ?? "The recorder did not start.")
}

func stop(_ o: Options) async throws {
    guard let state = store.current() else { throw CLIError.message("Not recording.") }
    kill(state.pid, SIGINT)
    for _ in 0..<400 where state.isAlive {
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    if state.isAlive { throw CLIError.message("The recorder (pid \(state.pid)) did not stop.") }
    let url = URL(fileURLWithPath: state.path)
    guard let duration = LevelCheck.duration(url), duration > 0 else {
        throw CLIError.message("Nothing was recorded. Run `mictape test` to check the microphone.")
    }
    if o.json {
        printJSON(SavedRecording(path: state.path, duration: duration))
    } else {
        print("Saved \(state.path) (\(clock(duration)))")
    }
}

func status(_ o: Options) {
    let state = store.current()
    if o.json {
        printJSON(StatusReport(recording: state != nil, path: state?.path, device: state?.device,
                               startedAt: state?.startedAt,
                               elapsed: state.map { Date().timeIntervalSince($0.startedAt) }, pid: state?.pid))
    } else if let state {
        print("Recording \(state.device) -> \(state.path) (\(clock(Date().timeIntervalSince(state.startedAt))))")
    } else {
        print("Not recording.")
    }
}

func test(_ o: Options) async throws {
    let config = try Config.load()
    try await Devices.requestAccess()
    let device = try Devices.resolve(o.device ?? config.device)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mictape-test-\(getpid()).m4a")
    defer { try? FileManager.default.removeItem(at: url) }
    let recorder = try Recorder(url: url, device: device)
    if !o.json { eprint("Recording \(Int(o.seconds)) seconds from \(device.localizedName). Talk at a normal volume, or let it pick up the room.") }
    recorder.start()
    try await Task.sleep(nanoseconds: UInt64(o.seconds * 1_000_000_000))
    try await recorder.stop()
    let report = try LevelCheck.analyze(url)
    if o.json {
        printJSON(report)
        return
    }
    print(String(format: "Mean %.1f dB / max %.1f dB", report.meanDB, report.maxDB))
    switch report.verdict {
    case .silent: print("Too quiet. Check microphone access, the input device, and the input volume (System Settings > Sound > Input).")
    case .quiet: print("A bit quiet. It will work, but sit closer or raise the input volume if you can.")
    case .ok: print("OK")
    }
}

func devices(_ o: Options) {
    let list = Devices.list()
    if o.json { printJSON(list); return }
    for d in list { print("\(d.isDefault ? "*" : " ") \(d.name)  [\(d.id)]") }
}

func destinations(_ o: Options) throws {
    let list = Destinations.list(try Config.load().destinations)
    if o.json { printJSON(list); return }
    if list.isEmpty { print("No destinations. Edit \(Config.fileURL().path).") }
    for d in list { print("\(d.name)\t\(d.path)") }
}

struct ConfigReport: Encodable {
    let path: String
    let exists: Bool
    let filename: String
    let needsLabel: Bool
    let device: String?
    let destinations: [DestinationRule]
}

struct FilenamePreview: Encodable {
    let template: String
    let example: String?
    let needsLabel: Bool
    let error: String?
}

func configCommand(_ o: Options) throws {
    let url = Config.fileURL()
    var config = try Config.load(from: url)
    let sub = o.positionals.first
    let arg = o.positionals.count > 1 ? o.positionals[1] : nil
    func need(_ what: String) throws -> String {
        guard let arg, !arg.isEmpty else { throw CLIError.usage("config \(sub ?? "") needs \(what)") }
        return arg
    }
    switch sub {
    case nil:
        break
    case "add-destination":
        let path = try need("a path")
        let subdirectory = o.subdirectory.flatMap { $0.isEmpty ? nil : $0 }
        if !config.addDestination(DestinationRule(path: path, subdirectory: subdirectory)) {
            throw CLIError.message("That destination is already configured.")
        }
        try config.save(to: url)
    case "remove-destination":
        let path = try need("a path")
        if config.removeDestination(path: path, subdirectory: o.subdirectory) == 0 {
            throw CLIError.message("No configured destination has the path \(path).")
        }
        try config.save(to: url)
    case "set-filename":
        try config.setFilename(try need("a template"))
        try config.save(to: url)
    case "preview-filename":
        let template = try need("a template")
        let needsLabel = template.contains("{label}")
        let preview: FilenamePreview
        do {
            let example = try FileNaming.render(template, label: needsLabel ? (o.label ?? "3") : nil)
            preview = FilenamePreview(template: template, example: example, needsLabel: needsLabel, error: nil)
        } catch {
            preview = FilenamePreview(template: template, example: nil, needsLabel: needsLabel, error: "\(error)")
        }
        if o.json { printJSON(preview) } else { print(preview.example ?? preview.error ?? "") }
        return
    default:
        throw CLIError.usage("Unknown config subcommand \(sub!)\n\n\(usage)")
    }
    try showConfig(o, url: url, config: config)
}

func showConfig(_ o: Options, url: URL, config: Config) throws {
    let report = ConfigReport(path: url.path, exists: FileManager.default.fileExists(atPath: url.path),
                              filename: config.filename, needsLabel: config.filename.contains("{label}"),
                              device: config.device, destinations: config.destinations)
    if o.json { printJSON(report); return }
    print("Config:   \(report.path)\(report.exists ? "" : " (not found, using defaults)")")
    print("Filename: \(report.filename)")
    print("Device:   \(report.device ?? "system default")")
    for rule in report.destinations {
        print("Destination: \(rule.path)" + (rule.subdirectory.map { " + \($0)" } ?? ""))
    }
}

// MARK: - Main

func run() async -> Int32 {
    do {
        let o = try parse(Array(CommandLine.arguments.dropFirst()))
        switch o.command {
        case "record": try await record(o); return -1
        case "start": try await start(o)
        case "stop": try await stop(o)
        case "status": status(o)
        case "test": try await test(o)
        case "devices": devices(o)
        case "destinations": try destinations(o)
        case "config": try configCommand(o)
        case "version": print(MicTape.version)
        case "help", "": print(usage)
        default: throw CLIError.usage("Unknown command \(o.command)\n\n\(usage)")
        }
        return 0
    } catch let error as CLIError {
        eprint(error.description)
        if case .usage = error { return 2 }
        return 1
    } catch {
        eprint("\(error)")
        return 1
    }
}

Task {
    let code = await run()
    // record keeps running until it is stopped; everything else exits here.
    if code >= 0 { exit(code) }
}
dispatchMain()
