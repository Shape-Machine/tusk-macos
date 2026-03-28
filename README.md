<p align="center">
  <img src="icon.svg" width="320" alt="Tusk icon" />
</p>

# Tusk

* Minimal, native macOS PostgreSQL client
* Built in SwiftUI for macOS 14+

---

<h3 align=center><a href="https://github.com/Shape-Machine/tusk-macos/releases/download/v2026.03.28-00/Tusk-2026.03.28-00.dmg">Download Tusk-2026.03.28-00.dmg</a><small> — macOS 14+</small></h3>
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

## Sponsor

Tusk is free and open source.
If it's useful to you, consider sponsoring its development.

One-time: [Coffee €5](https://buy.stripe.com/14A28saQ95kI9q93qNes003) · [Supporter €15](https://buy.stripe.com/4gMeVebUddRefOx7H3es004) · [Sponsor €49](https://buy.stripe.com/00w6oI2jD7sQeKt7H3es005)

Monthly: [Hero Coffee €5](https://buy.stripe.com/8x29AU7DXdReeKtaTfes000) · [Hero Supporter €15](https://buy.stripe.com/9B6bJ2f6p5kI59T2mJes001) · [Hero Sponsor €49](https://buy.stripe.com/bJe5kEgat8wUfOx3qNes002)

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

## Sponsor

Tusk is free and open source.
If it's useful to you, consider sponsoring its development.

One-time: [Coffee €5](https://buy.stripe.com/14A28saQ95kI9q93qNes003) · [Supporter €15](https://buy.stripe.com/4gMeVebUddRefOx7H3es004) · [Sponsor €49](https://buy.stripe.com/00w6oI2jD7sQeKt7H3es005)

Monthly: [Hero Coffee €5](https://buy.stripe.com/8x29AU7DXdReeKtaTfes000) · [Hero Supporter €15](https://buy.stripe.com/9B6bJ2f6p5kI59T2mJes001) · [Hero Sponsor €49](https://buy.stripe.com/bJe5kEgat8wUfOx3qNes002)

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
