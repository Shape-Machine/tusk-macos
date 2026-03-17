# Tusk — Features

### Connections
PostgreSQL connections with name, host, port, credentials, SSL toggle, and color tagging (six colors). Passwords and SSH passphrases stored in macOS Keychain. SSH tunnel support with automatic port forwarding, key-based auth, and configurable passphrase. Multiple connections can be open simultaneously. Test-connection validates the full config — including SSL and SSH — before saving, with descriptive error messages for common failures.

### Schema Browser
Full schema tree in the sidebar — schemas → tables. Public schema auto-expands; others collapsed by default. Click a table to open it in a detail tab. Manual schema refresh via ⌘R or the right-click context menu. Schemas auto-refresh on connect.

### Table Detail
Five tabs per table. **Columns** shows types, nullability, defaults, and primary key indicators. **Keys** lists all foreign key constraints with their referenced columns. **Relations** renders incoming and outgoing foreign key relationships as a radial graph with directional arrows and column labels. **DDL** shows the generated `CREATE TABLE` statement in a read-only syntax-highlighted editor with a one-click Copy button. **Data** opens the full data browser.

### Data Browser
Paginated grid (1000 rows/page) with previous/next navigation. Real-time text filter searches all columns via PostgreSQL ILIKE with 300ms debounce. Copy all visible rows as CSV, JSON, or INSERT statements. Export to CSV via save panel. Right-click any row for per-row copy actions (CSV, JSON, INSERT). Double-click any cell to view the full value in a modal; JSON and JSONB cells show an interactive tree view with expandable nodes alongside the raw text.

### Query Editor
SQL editor with live syntax highlighting. Two run modes: **Run All** (`⌘↵`) executes the entire buffer; **Run Current** (`⌘⇧↵`) executes the selection (which may span multiple statements) or the single statement the cursor is inside, detected by a quote-aware splitter that correctly handles single-quoted strings, dollar-quoted blocks, and SQL comments. Both modes execute statements sequentially and stop on the first error. Results appear in a tabbed panel: a live **Log** tab showing every statement's index, truncated SQL, outcome (row count and duration, OK, or error in red), and clickable links to result tabs; plus a **Result N** tab per SELECT with the full interactive grid. Running a single SELECT auto-switches to Result 1, preserving the single-query feel. SELECT/WITH queries are automatically capped at 1000 rows. Per-tab connection picker lets you switch databases without leaving the editor. File-backed queries autosave to disk every 500ms with a brief visual confirmation. Copy results as CSV or JSON; export to CSV via save panel.

### File Explorer
Local filesystem browser in the sidebar. Navigate directories, create and rename SQL files and folders inline, and delete with confirmation. Open `.sql` files directly into a query editor tab with auto-save wired to disk. Last visited directory persisted across sessions.

### Tabs
Unlimited tabs — table browsers and query editors co-exist in the same tab bar. Color-coded connection dots per tab. `⌘T` opens a new query tab, `⌘W` closes, `⌘[` / `⌘]` navigate. Tab titles reflect file names for file-backed queries.

### Appearance
Font size (11–17pt) and font design (sans-serif, monospaced, serif) configurable independently for sidebar and content. Changes apply immediately and persist across sessions.

### Updates
Built-in update checker fetches the latest release from GitHub. Shows current status — up to date, update available with version number, or error — and links directly to the GitHub release when an update is found.
