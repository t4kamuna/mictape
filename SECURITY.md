# Security

## What mictape does and does not do

- It makes no network connections of any kind: no update checks, no telemetry, no analytics.
- The only permission it requests is microphone access.
- It writes only to the destinations you configure and to `~/Library/Application Support/mictape/`.
- It needs no administrator rights, helper tools, sudoers rules, or launch daemons.
- It has no third-party dependencies; it uses only Apple's system frameworks (Foundation, AVFoundation, IOKit).

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting ("Report a vulnerability" in the Security tab) rather than a public issue.
