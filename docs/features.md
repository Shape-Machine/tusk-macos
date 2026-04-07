# Tusk — Features
_Generated from source: v2026.04.07-00_

## Connections

- Named connection profiles with optional color tag (blue, green, orange, red, purple, gray) and notes field
- Passwords and SSH passphrases stored in macOS Keychain (never in config files)
- SSL/TLS toggle per connection
- Read-only mode — prevents any write queries from executing for that connection
- SSH tunnel: host, port, user, private key file (file picker), optional passphrase stored in Keychain
- Import a connection from a PostgreSQL URI (`postgres://` scheme) to auto-fill all fields
- Test connection before saving (validates SSL and SSH tunnel end-to-end)
- Multiple connections open simultaneously; one active database client per connection
- Duplicate connection (copies Keychain credentials)
- Right-click a connection: connect, disconnect, refresh schema, edit, duplicate, or delete
- Database switcher per connection
- Superuser role badge shown on the connection row

## Schema Browser

- Schemas → tables tree in the sidebar with connection color indicator
- Tables, Views, Enums, Sequences, and Functions listed per schema
- Database switcher per connection
- Optional table size overlay: total size, row estimate, and index size per table (toggle in Settings)
- Click a table or view to open it in a detail tab
- Right-click a table: Rename, Truncate, or Drop (with CASCADE option)
- Right-click a schema: New Table wizard with column builder, type picker, nullable/default/PK fields, and live DDL preview
- Live filter bar for schema items
- ⌘R or right-click to refresh schema; auto-refreshes on connect
- Role browser: view and open role detail tabs

## Table Inspector

- Seven tabs per table: Columns, Keys, Relations, Indexes, Triggers, DDL, Data
- **Columns** — name, type, nullability, default value, primary key indicator; add column toolbar button; right-click to Rename, Edit (type/default/nullability), or Drop with confirmation
- **Keys** — foreign key constraints with column, referenced table and column; add constraint button
- **Relations** — radial graph of outgoing and incoming FK relationships with column-level labels; pinch-to-zoom (0.3×–3.0×), drag-to-pan, double-click to reset
- **Indexes** — index definitions with uniqueness and primary key indicators; create index button
- **Triggers** — trigger names, timing (BEFORE/AFTER/INSTEAD OF), event types (INSERT/UPDATE/DELETE), and statement text
- **DDL** — generated `CREATE TABLE` statement in a read-only syntax-highlighted editor with one-click copy
- **Data** — full paginated data browser (see Data Browser section)

## Data Browser

- Paginated data grid with configurable page size (50 / 100 / 500 / 1 000 / 5 000 rows); Previous / Next navigation
- Real-time text filter (`ILIKE` across all columns, 300 ms debounce)
- Sortable columns — click header for ascending; click again for descending; third click clears sort
- Resizable columns with widths persisted per connection, schema, and table
- Pinned/frozen columns persisted per connection and table
- Inline row editing via primary key (tables only)
- Insert new rows via modal form with per-column NULL toggles and type badges (tables with primary key only)
- Delete rows with confirmation (tables with primary key only)
- Copy selected rows or all visible rows as CSV, JSON, or INSERT SQL
- Export full table to CSV via system save panel

## SQL Editor

- Live SQL syntax highlighting
- ⌘↵ runs all statements; ⌘⇧↵ runs the selection or statement at cursor
- ⌘⌥↵ runs EXPLAIN ANALYZE on the current statement; result shown as an indented cost tree with slow nodes highlighted
- ⌘/ toggles line comments
- Multi-statement execution: statements run sequentially, stops on first error; one Result tab per SELECT
- Log tab shows per-statement outcome: row count, duration, OK, or error
- SELECT results capped at 1 000 rows; indicator shown when result is truncated
- Per-tab connection picker — switch connections without leaving the editor
- File-backed queries auto-save to disk every 500 ms with a brief "Saved" indicator
- Cancel running query
- Copy results as CSV or JSON

## File Explorer

- Sidebar browser for local `.sql` files and folders
- Remembers last visited directory across sessions; up button and home navigation
- Create `.sql` files and folders inline; rename inline; delete with confirmation (moved to Trash)
- Open `.sql` files into a new query editor tab; open files marked with an accent dot

## Activity Monitor

- Live view of active backend sessions for the selected connection
- Displays PID, application name, state, wait event type/name, duration, and current query per session
- Auto-refreshes every 5 seconds; manual refresh button
- Sessions running longer than 30 seconds highlighted in orange
- Right-click a session: cancel its query or terminate the backend, both with confirmation dialogs
- Passwords redacted in query display

## Appearance

- Font family picker (sans-serif / serif / monospace) — separate settings for sidebar and content
- Font size slider (11–17 pt in 1 pt steps) — separate settings for sidebar and content
- Table size display toggle for schema sidebar
- Data browser page size setting (50 / 100 / 500 / 1 000 / 5 000)

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
| Toggle Line Comment | ⌘/ |
| Settings | ⌘, |
| Help | ⌘? |
