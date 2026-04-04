# Tusk — Features
_Generated from source: v2026.03.28-00_

## Connections

- Named connection profiles: name, host, port, database, username, password, optional notes
- Passwords and SSH passphrases stored in macOS Keychain (never in config files)
- Color tag per connection: blue, green, orange, red, purple, gray
- SSL/TLS toggle per connection
- Read-only mode — prevents any write queries from executing for that connection
- SSH tunnel: host, port, user, private key file (file picker), optional passphrase stored in Keychain
- Import a connection from a PostgreSQL URI (`postgres://` scheme) to auto-fill all fields
- Test connection before saving (validates SSL and SSH tunnel end-to-end)
- Multiple connections open simultaneously; one active database client per connection
- Right-click a connection: connect, disconnect, refresh schema, edit, duplicate, or delete
- Schema refresh error badge shown on the connection header when schema load fails

## Schema Browser

- Schemas → tables tree in the sidebar; public schema auto-expanded, others collapsed
- Tables, Views, Enums, Sequences, and Functions listed per schema
- Database switcher per connection
- Optional table size overlay: total size, row estimate, and index size per table (toggle in Settings)
- Click a table or view to open it in a detail tab
- Right-click a table: Rename, Truncate (with optional RESTART IDENTITY), or Drop (warns of FK dependents; CASCADE option)
- Right-click a schema or the Tables group: New Table wizard — column builder with type picker, nullable/default/PK fields, and a live DDL preview pane
- `⌘R` or right-click to refresh schema; auto-refreshes on connect

## Table Inspector

- Seven tabs per table: Columns, Keys, Relations, Indexes, Triggers, DDL, Data
- **Columns** — name, type, nullability, default value, primary key indicator; toolbar `+` to add a column; right-click to Rename, Edit (type/default/nullability), or Drop with confirmation
- **Keys** — primary key and unique constraints with column lists
- **Relations** — radial graph of outgoing and incoming foreign key relationships with column-level labels; pinch-to-zoom (0.3×–3.0×), drag-to-pan, double-click to reset view
- **Indexes** — index definitions with uniqueness and primary key indicators; create index
- **Triggers** — trigger names, timing (BEFORE/AFTER/INSTEAD OF), event types (INSERT/UPDATE/DELETE), and statement text
- **DDL** — generated `CREATE TABLE` statement in a read-only syntax-highlighted editor; one-click copy
- **Data** — full paginated data browser (see Data Browser section)
- All tabs lazy-load on first access; tab state survives sub-tab switches within the same table

## Data Browser

- 1,000 rows per page with Previous / Next navigation and row range indicator
- Real-time text filter (`ILIKE` across all columns, 300 ms debounce)
- Sortable columns — click header to sort ascending; click again for descending; third click clears sort (tables only; disabled for views and read-only connections)
- Resizable columns — drag column divider; widths persisted per connection, schema, and table
- Inline cell editing via double-click; generates `UPDATE` via primary key (tables only)
- Insert new rows via modal form with per-column NULL toggles and type badges (tables with a primary key only)
- Delete rows via context menu with confirmation (tables with a primary key only)
- Multi-row selection: Shift+Click, ⌘+Click; arrow keys navigate rows
- Copy selected rows as CSV, JSON, or INSERT SQL; copy all visible rows
- Export full table to CSV via system save panel
- JSON/JSONB tree view — toggle to expand/collapse nested JSON structures with syntax colouring

## SQL Editor

- Live syntax highlighting: keywords, strings, numbers, comments
- Configurable font family (sans-serif, monospaced, serif) and size
- `⌘↵` runs all statements; `⌘⇧↵` runs the selection or statement at cursor
- `⌘⌥↵` runs EXPLAIN ANALYZE on the current statement; results shown in a Plan tab as an indented cost tree; nodes exceeding 50% of total cost highlighted
- Multi-statement execution: statements run sequentially, stops on first error; one Result tab per SELECT
- Log tab shows per-statement outcome: row count, duration, OK, or error
- SELECT results capped at 1,000 rows; indicator shown when result is truncated
- Per-tab connection picker — switch databases without leaving the editor
- File-backed queries auto-save to disk every 500 ms with a brief "Saved" indicator
- Unlimited query tabs per connection; tab title shows file name for file-backed queries
- Copy results as CSV or JSON; export to CSV via save panel

## File Explorer

- Sidebar browser for local `.sql` files and folders
- Navigate from home directory; last visited directory persisted across sessions
- Up button (disabled at home) and Home button for quick navigation
- Create `.sql` files and folders inline; rename inline; delete with confirmation
- Open `.sql` files into a new query editor tab with auto-save wired to disk
- Currently open files marked with a dot in the file list
- Hidden files (dot-prefixed) not shown

## Activity Monitor

- Live view of active backend sessions for the selected connection
- Displays PID, application name, state, wait event type and name, duration, and current query per session
- Auto-refreshes every 5 seconds; manual refresh button available
- Sessions running longer than 30 seconds highlighted in orange; idle-in-transaction (aborted) sessions highlighted in red
- Right-click a session: cancel its query or terminate the backend, both with confirmation dialogs

## Appearance

- Font family and size configured independently for sidebar and content/editor areas
- Font design options: sans-serif, monospaced, serif (each option shown in its own typeface)
- Font size: 11–17 pt in 1 pt increments
- Show/hide table sizes toggle for the schema sidebar
- All settings applied immediately and persisted across sessions

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| New Connection | ⇧⌘N |
| New Query Tab | ⌘T |
| Close Tab | ⌘W |
| Next Tab | ⌘] |
| Previous Tab | ⌘[ |
| Refresh Schema | ⌘R |
| Run All | ⌘↵ |
| Run Current Statement | ⇧⌘↵ |
| EXPLAIN ANALYZE | ⌥⌘↵ |
| Settings | ⌘, |
| Help | ⌘? |
