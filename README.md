<p align="center">
  <img src="icon.svg" width="320" alt="Tusk icon" />
</p>

# Tusk

* Minimal, native macOS PostgreSQL client
* Built in SwiftUI for macOS 14+

### Features

* Connection credentials stored in the system Keychain
* SSH tunnel support
* Schema browser — tables, columns, indexes, foreign keys
* Data browser — with filtering
* SQL query editor with syntax highlighting

### Non-Features

* No Electron
* No Telemetry
* No Subscription

---

**[Download Tusk-1.2.1.dmg](https://github.com/Shape-Machine/tusk-macos/releases/download/v1.2.1/Tusk-1.2.1.dmg)** — macOS 14+ · [All releases](https://github.com/Shape-Machine/tusk-macos/releases)

> Not notarized. On first launch right-click → **Open**, or run `xattr -d com.apple.quarantine /Applications/Tusk.app`.

---

## Screenshots

![Screenshot 01](screenshots/1.2.1-01.png)

![Screenshot 02](screenshots/1.2.1-02.png)

![Screenshot 03](screenshots/1.2.1-03.png)

![Screenshot 04](screenshots/1.2.1-04.png)

![Screenshot 05](screenshots/1.2.1-05.png)

![Screenshot 06](screenshots/1.2.1-06.png)

![Screenshot 07](screenshots/1.2.1-07.png)

![Screenshot 08](screenshots/1.2.1-08.png)

![Screenshot 09](screenshots/1.2.1-09.png)

---

## Development

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
