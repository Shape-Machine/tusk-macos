# Tusk — Features

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
- Click a table to open its detail tab
- `⌘R` or right-click to refresh schema
- Auto-refreshes on connect

### Table Detail
Five tabs per table for complete introspection.
- **Columns** — name, type, nullability, default value, primary key indicator
- **Keys** — foreign key constraints with referenced table and column
- **Relations** — radial graph of incoming and outgoing foreign key relationships with column labels
- **DDL** — generated `CREATE TABLE` statement in a read-only syntax-highlighted editor; one-click copy
- **Data** — full paginated data browser (see below)

### Data Browser
Paginated, filterable grid for browsing and exporting table data.
- 1000 rows/page with previous/next navigation
- Real-time text filter across all columns (PostgreSQL ILIKE, 300ms debounce)
- Double-click any cell to view the full value in a modal
- JSON/JSONB cells show an interactive expandable tree alongside raw text
- Right-click rows: copy as CSV, JSON, or INSERT (single or multi-row)
- Copy all visible rows as CSV, JSON, or INSERT; export to CSV via save panel

### Query Editor
Full SQL editor with multi-statement execution and per-statement results.
- Live syntax highlighting (keywords, strings, numbers, comments)
- `⌘↵` runs all statements; `⌘⇧↵` runs the selection or statement at cursor
- Quote-aware statement splitter handles `''`, `$tag$`, `--`, and `/* */`
- Statements execute sequentially; stops on first error
- **Log tab** — live per-statement outcome (row count · duration, OK, or error in red)
- **Result N tabs** — one interactive grid per SELECT result; clickable from the log
- Single SELECT auto-switches to Result 1 for a clean single-query feel
- SELECT/WITH results capped at 1000 rows with indicator
- Per-tab connection picker — switch databases without leaving the editor
- File-backed queries autosave every 500ms with a brief visual confirmation
- Copy results as CSV or JSON; export to CSV via save panel

### File Explorer
Local filesystem browser for opening and managing SQL files.
- Navigate directories from home; last visited directory persisted
- Create SQL files and folders inline; rename inline; delete with confirmation
- Open `.sql` files directly into a query editor tab with auto-save wired to disk

### Tabs
Unlimited tabs mixing table browsers and query editors.
- `⌘T` new query tab · `⌘W` close · `⌘[` / `⌘]` navigate
- Color-coded connection dot per tab
- Tab title shows file name for file-backed queries

### Appearance
Font settings for sidebar and content areas, configurable independently.
- Font design: sans-serif, monospaced, or serif
- Font size: 11–17pt in 1pt increments
- Changes apply immediately and persist across sessions

### Updates
Built-in update checker against the GitHub releases feed.
- Shows: up to date, update available (with version), or error
- Links directly to the GitHub release when an update is found
