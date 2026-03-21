# Tusk — Features

_Last updated: 2026-03-21_

### Connections
Manage multiple PostgreSQL connections with full SSH tunnel and SSL support.
- Name, host, port, database, username, password, SSL toggle, color tag (6 colors)
- Passwords and SSH passphrases stored in macOS Keychain
- SSH tunnel: host, port, user, key file (browse picker), passphrase
- Test connection validates full config (including SSL/SSH) before saving
- Multiple connections open simultaneously
- Right-click to connect, disconnect, refresh schema, edit, or delete

### Schema Browser
Navigate schemas and tables directly from the sidebar.
- Schemas → tables tree; public schema auto-expands, others collapsed
- Views, Enums, Sequences, and Functions listed under collapsible groups per schema
- Optional table size overlay: total size, row estimate, and index size per table (toggle in Settings)
- Click a table to open its detail tab
- `⌘R` or right-click to refresh schema
- Auto-refreshes on connect
- Schema refresh error badge on connection header

### Table Detail
Seven tabs per table for complete introspection.
- **Columns** — name, type, nullability, default value, primary key indicator
- **Foreign Keys** — foreign key constraints with referenced table and column
- **Relations** — radial graph of incoming and outgoing foreign key relationships with column labels; pinch-to-zoom, drag-to-pan, and auto-scale
- **Indexes** — index definitions with uniqueness and primary key indicators
- **Triggers** — trigger names, timing, and event types
- **DDL** — generated `CREATE TABLE` statement in a read-only syntax-highlighted editor; one-click copy
- **Data** — full paginated data browser (see below)

### Data Browser
Paginated, filterable grid for browsing, editing, and exporting table data.
- 1000 rows/page with previous/next navigation
- Real-time text filter across all columns (PostgreSQL ILIKE, 300ms debounce)
- Inline cell editing — double-click to edit with NULL toggle; generates UPDATE via primary key
- Insert new rows via modal form with per-column NULL toggles and type badges
- Delete rows from context menu; both require a primary key to be present
- Double-click any cell to view the full value in a modal
- JSON/JSONB cells show an interactive expandable tree alongside raw text
- Right-click rows: copy as CSV, JSON, or INSERT (single or multi-row)
- Copy all visible rows as CSV, JSON, or INSERT; export to CSV via save panel

### Query Editor
Full SQL editor with multi-statement execution and per-statement results.
- Live syntax highlighting (keywords, strings, numbers, comments)
- `⌘↵` runs all statements; `⌘⇧↵` runs the selection or statement at cursor
- `⌘⌥↵` runs EXPLAIN ANALYZE on the current statement; results shown in a **Plan N** tab as an indented cost tree with seq scans and hash joins highlighted orange
- Quote-aware statement splitter handles `''`, `$tag$`, `--`, and `/* */`
- Statements execute sequentially; stops on first error
- **Log tab** — live per-statement outcome (row count · duration, OK, or error in red)
- **Result N tabs** — one interactive grid per SELECT result; clickable from the log
- **Plan N tabs** — EXPLAIN ANALYZE plan tree with cost, rows, and actual timing per node
- Single SELECT auto-switches to Result 1 for a clean single-query feel
- SELECT/WITH results capped at 1000 rows with indicator
- Per-tab connection picker — switch databases without leaving the editor
- File-backed queries autosave every 500ms with a brief visual confirmation
- Copy results as CSV or JSON; export to CSV via save panel

### Activity Monitor
Live view of active backend sessions per connection.
- Opens as a tab from the connection context menu
- Displays PID, application, state, wait event, duration, and current query per session
- Auto-refreshes every 5 seconds; manual refresh available
- Right-click a session to cancel its query or terminate the backend (with confirmation)
- Sessions running >30 seconds highlighted orange

### File Explorer
Local filesystem browser for opening and managing SQL files.
- Navigate directories from home; last visited directory persisted
- Create SQL files and folders inline; rename inline; delete with confirmation
- Open `.sql` files directly into a query editor tab with auto-save wired to disk
- Open files indicated with a dot in the file list

### Tabs
Unlimited tabs mixing table browsers, query editors, and activity monitors.
- `⌘T` new query tab · `⌘W` close · `⌘[` / `⌘]` navigate
- Color-coded connection dot per tab
- Tab title shows file name for file-backed queries

### Appearance
Font settings for sidebar and content areas, configurable independently.
- Font design: sans-serif, monospaced, or serif
- Font size: 11–17pt in 1pt increments
- Table size display toggle for sidebar
- Changes apply immediately and persist across sessions

### Updates
Built-in update checker against the GitHub releases feed.
- Shows: up to date, update available (with version), or error
- Links directly to the GitHub release when an update is found
