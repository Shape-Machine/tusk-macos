# Tusk

<p align="center">
  <img src="icon.svg" width="480" alt="Tusk icon" />
</p>

* Minimal, native macOS PostgreSQL client.
* No Electron
* No telemetry
* No subscription.
* Built in SwiftUI for macOS 14+.

**[Download Tusk-1.0.0.dmg](https://github.com/Shape-Machine/tusk-macos/releases/download/v1.0.0/Tusk-1.0.0.dmg)** — macOS 14+ · [All releases](https://github.com/Shape-Machine/tusk-macos/releases)

> Not notarized. On first launch right-click → **Open**, or run `xattr -d com.apple.quarantine /Applications/Tusk.app`.

### Features

* SQL query editor with syntax highlighting
* Schema browser — tables, columns, indexes, foreign keys
* Table data browser with filtering and CSV export
* SSH tunnel support
* Credentials stored in the system Keychain
* Multiple simultaneous connections

---

## Developers

### Requirements

* macOS 14+
* Xcode 16+
* [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

### Setup

```sh
git clone https://github.com/Shape-Machine/tusk-macos.git
cd tusk-macos
xcodegen generate
open Tusk.xcodeproj
```

```sh
make clean build run
```
