# Tusk

<p align="center">
  <img src="icon.svg" width="160" alt="Tusk icon" />
</p>

A minimal, native macOS PostgreSQL client. No Electron, no telemetry, no subscription.

Built in SwiftUI for macOS 14+. Tusk is for developers who want a fast, no-nonsense way to explore databases and run queries — without handing their credentials or query history to a cloud service.

**Features**

- SQL query editor with syntax highlighting
- Schema browser — tables, columns, indexes, foreign keys
- Table data browser with filtering and CSV export
- SSH tunnel support
- Credentials stored in the system Keychain
- Multiple simultaneous connections

## Requirements

- macOS 14+
- Xcode 16+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Setup

```sh
git clone https://github.com/Shape-Machine/tusk-macos.git
cd tusk-macos
xcodegen generate
open Tusk.xcodeproj
```

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
