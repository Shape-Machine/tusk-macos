# Tusk

<p align="center">
  <img src="icon.svg" width="160" alt="Tusk icon" />
</p>

A minimal macOS PostgreSQL client built with SwiftUI.

## Requirements

- macOS 14+
- Xcode 16+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Setup

```sh
git clone <repo>
cd Tusk
xcodegen generate   # regenerate Tusk.xcodeproj from project.yml
make build          # build via xcodebuild
```

Open `Tusk.xcodeproj` in Xcode to run and develop.

## Project structure

```
Tusk/
├── AppState.swift          # central @Observable state
├── Database/               # PostgresNIO client, keychain, persistence
├── Models/                 # Connection, QueryResult, and schema types
└── Views/
    ├── ContentView.swift   # root NavigationSplitView
    ├── Sidebar/            # connection list, add/edit sheet
    └── Main/               # schema browser, table detail, query editor
```

## Dependencies

Managed via Swift Package Manager (defined in `Tusk.xcodeproj`):

- [PostgresNIO](https://github.com/vapor/postgres-nio) — async PostgreSQL driver
