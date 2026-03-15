<p align="center">
  <img src="icon.svg" width="320" alt="Tusk icon" />
</p>

# Tusk

* Minimal, native macOS PostgreSQL client
* Built in SwiftUI for macOS 14+

---

<h3 align=center><a href="https://github.com/Shape-Machine/tusk-macos/releases/download/v1.3.0/Tusk-1.3.0.dmg">Download Tusk-1.3.0.dmg</a><small> — macOS 14+</small></h3>
<p align=center>
<em>
Not notarized.<br/>
On first launch right-click → <strong>Open</strong>, or<br/>
run <code>xattr -d com.apple.quarantine /Applications/Tusk.app</code>
</em>
</p>

---

## Features

See [docs/features.md](docs/features.md) for a full breakdown.

---

## Non Features

No Electron. No telemetry. No subscription.

---

## Screenshots

![Screenshot 01](docs/screenshots/1.3.0-01.png)

![Screenshot 02](docs/screenshots/1.3.0-02.png)

![Screenshot 03](docs/screenshots/1.3.0-03.png)

![Screenshot 04](docs/screenshots/1.3.0-04.png)

![Screenshot 05](docs/screenshots/1.3.0-05.png)

![Screenshot 06](docs/screenshots/1.3.0-06.png)

![Screenshot 07](docs/screenshots/1.3.0-07.png)

![Screenshot 08](docs/screenshots/1.3.0-08.png)

![Screenshot 09](docs/screenshots/1.3.0-09.png)

![Screenshot 10](docs/screenshots/1.3.0-10.png)

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
