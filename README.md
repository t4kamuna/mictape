# mictape

Record your Mac's microphone to `.m4a` files from the command line — long sessions, no fuss.

- **Crash-safe.** Audio is written as fragmented MP4 and flushed every second. If the process is killed or the battery dies, everything up to the last second still plays.
- **Saves where you want, named how you want.** Pick a destination by name (`mictape start physics 3`) from directories you configure with globs, and name files with a template.
- **Runs in the background.** `start` / `stop` / `status` let launchers such as Raycast drive it.
- **Keeps the Mac awake** (idle sleep only) while recording.
- **Private by design.** No network access, no telemetry, no account. The only permission it asks for is the microphone.

Format: AAC, 48 kHz, mono, 128 kbps (about 86 MB for 90 minutes).

## Requirements

- macOS 14 or later
- Swift 6 (Xcode 16, or just the Command Line Tools: `xcode-select --install`)

## Install from source

```sh
git clone https://github.com/t4kamuna/mictape.git
cd mictape
swift build -c release
install -m 755 .build/release/mictape /usr/local/bin/mictape
```

The first recording asks for microphone access. The permission is granted to the app that runs `mictape` (your terminal, or Raycast).

## Usage

```sh
mictape test                    # record 10 seconds and check the input level
mictape record                  # record in the foreground; press q or Ctrl+C to stop
mictape start physics 3         # record in the background into "physics", label "3"
mictape status
mictape stop
mictape devices                 # list input devices
mictape destinations            # list configured destinations
```

`start`, `stop`, `status`, `devices`, `destinations`, and `test` accept `--json`.

Keep the lid open while recording: closing it sleeps the Mac, and the recording stops there (what was recorded so far is kept).

## Configuration

Optional. `~/.config/mictape/config.json` (or `$XDG_CONFIG_HOME/mictape/config.json`, or the path in `$MICTAPE_CONFIG`):

```json
{
  "destinations": [
    { "path": "~/Recordings" },
    { "path": "~/Documents/Classes/[0-9]*-?*", "subdirectory": "audio" }
  ],
  "filename": "{label}-{date:yyyyMMdd}.m4a",
  "device": "MacBook Air Microphone"
}
```

- `destinations`: directories or globs. Every directory a glob matches becomes a destination, picked by a case-insensitive part of its name. `subdirectory` is appended and created when recording starts. A path without wildcards is used even if it does not exist yet. Default: `~/Recordings`.
- `filename`: tokens are `{label}` and `{date:FORMAT}` ([date format patterns](https://unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table)). If the file exists, `-2`, `-3`, … is appended. Default: `{date:yyyyMMdd-HHmmss}.m4a`.
- `device`: input device name (or part of it) or ID from `mictape devices`. Default: the system input.

## Files

- Recordings: only in the destinations you configure.
- State: `~/Library/Application Support/mictape/` (the running recording and the background recorder's log).

## License

MIT
