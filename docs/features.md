# Tusk — Features

_Generated from source: v2026.03.27-00_

## Connections

- Named connection profiles: name, host, port, database, username, password
- Passwords and SSH passphrases stored in macOS Keychain (never in config files)
- Color tag per connection: blue, green, orange, red, purple, gray
- SSL/TLS toggle per connection
- SSH tunnel: host, port, user, private key file (file picker), optional passphrase
- Test connection before saving (validates SSL and SSH tunnel end-to-end)
- Multiple connections open simultaneously; one active database client per connection
- Right-click a connection to connect, disconnect, refresh schema, edit, or delete
- Schema refresh error badge shown on the connection header when schema load fails

## Schema Browser

- Schemas → tables tree in the sidebar; public schema auto-expanded, others collapsed
- Tables, Views, Enums, Sequences, and Functions listed per schema
- Optional table size overlay: total size, row estimate, and index size per table (toggle in Settings)
- Click a table or view to open it in a detail tab
- Right-click a table: Rename (`ALTER TABLE … RENAME TO`), Truncate (with optional RESTART IDENTITY), or Drop (warns of FK dependents; CASCADE option)
- Right-click a schema or the Tables group: New Table wizard — column builder with type picker, nullable/default/PK fields, and a live DDL preview pane
- `⌘R` or right-click to refresh schema; auto-refreshes on connect

## Table Inspector

- Seven tabs per table: Columns, Keys, Relations, Indexes, Triggers, DDL, Data
- **Columns** — name, type, nullability, default value, primary key indicator; toolbar `+` to add a column; right-click to Rename, Edit (type/default/nullability, wrapped in a transaction), or Drop with confirmation
- **Keys** — primary key and unique constraints with column lists
- **Relations** — radial graph of outgoing and incoming foreign key relationships with column-level labels; pinch-to-zoom (0.3×–3.0×), drag-to-pan, double-click to reset view
- **Indexes** — index definitions with uniqueness and primary key indicators
- **Triggers** — trigger names, timing (BEFORE/AFTER), event types (INSERT/UPDATE/DELETE), and statement text
- **DDL** — generated `CREATE TABLE` statement in a read-only syntax-highlighted editor; one-click copy
- **Data** — full paginated data browser (see Data Browser section below)
- All tabs lazy-load on first access; tab state survives sub-tab switches within the same table

## Data Browser

- 1,000 rows per page with Previous / Next navigation
- Real-time text filter (PostgreSQL `ILIKE`, 300 ms debounce)
- Sortable columns — click header to sort ascending; click again for descending; third click clears sort (tables only; not available for views)
- Resizable columns — drag column divider; widths persisted per connection, schema, and table
- Inline cell editing via double-click; generates `UPDATE` via primary key (tables only)
- Insert new rows via modal form with per-column NULL toggles and type badges (tables with a primary key only)
- Delete rows via context menu with confirmation (tables with a primary key only)
- Copy all visible rows as CSV, JSON, or INSERT SQL
- Export to CSV via system save panel
- Empty-table state shown when the table has no rows

## SQL Editor

- Live syntax highlighting (keywords, strings, numbers, comments)
- `⌘↵` runs all statements; `⌘⇧↵` runs the selection or statement at cursor
- `⌘⌥↵` runs EXPLAIN ANALYZE on the current statement; results shown in a Plan tab as an indented cost tree with seq scans and hash joins highlighted
- Multi-statement execution: statements run sequentially, stops on first error; one Result tab per SELECT
- Log tab shows per-statement outcome: row count, duration, OK, or error
- SELECT/WITH results capped at 1,000 rows
- Per-tab connection picker — switch databases without leaving the editor
- File-backed queries auto-save to disk every 500 ms with a brief "Saved" indicator
- Copy results as CSV or JSON; export to CSV via save panel
- Unlimited query tabs per connection; tab title shows file name for file-backed queries

## File Explorer

- Sidebar browser for local `.sql` files and folders
- Navigate from home directory; last visited directory persisted across sessions
- Up button (disabled at home) and Home button for quick navigation
- Create `.sql` files and folders inline; rename inline; delete with confirmation
- Open `.sql` files into a new query editor tab with auto-save wired to disk
- Open files indicated with a dot in the file list

## Activity Monitor

- Live view of active backend sessions for the selected connection
- Displays PID, application name, state, wait event type and name, duration, and current query per session
- Auto-refreshes every 5 seconds; manual refresh button available
- Sessions running longer than 30 seconds highlighted in orange
- Right-click a session to cancel its query or terminate the backend, both with confirmation dialogs

## Appearance

- Font settings for sidebar and content areas, configurable independently
- Font design: sans-serif, monospaced, or serif (each option shown in its own typeface)
- Font size: 11–17 pt in 1 pt increments
- Show table sizes toggle for the schema sidebar
- All settings applied immediately and persisted across sessions via `@AppStorage`

## Keyboard Shortcuts

- `⌘,` — Settings
- `⇧⌘N` — New Connection
- `⌘W` — Close Tab
- `⌘T` — New Query Tab
- `⌘R` — Refresh Schema
- `⌘]` / `⌘[` — Next / Previous Tab
- `⌘↵` — Run All (query editor)
- `⌘⇧↵` — Run Current (query editor)
- `⌘⌥↵` — EXPLAIN ANALYZE (query editor)
- `⌘?` — Help
