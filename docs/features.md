# Tusk — Features

### Connections
PostgreSQL connections with name, host, port, credentials, SSL toggle, and color tagging. Passwords and SSH passphrases stored in macOS Keychain. SSH tunnel support with automatic port forwarding and key-based auth. Multiple connections can be open simultaneously. Test-connection validates config before saving, with friendly error messages for common failures (SSL mismatch, bad credentials, unsupported auth).

### Schema Browser
Full schema tree in the sidebar — schemas → tables. Public schema auto-expands; others collapsed by default. Click a table to open it. Manual schema refresh via ⌘R. Schemas auto-refresh on connect.

### Table Detail
Four views per table: Columns (types, nullability, defaults, PK indicators), Foreign Keys, Relations (incoming and outgoing relationships as a radial graph), and Data.

### Data Browser
Paginated grid (1000 rows/page) with previous/next navigation. Real-time text filter searches all columns via PostgreSQL ILIKE with 300ms debounce. Copy all visible rows as CSV, JSON, or INSERT statements. Export to CSV via save panel. Right-click any row for per-row copy actions (CSV, JSON, INSERT). Double-click any cell to view the full value in a modal.

### Query Editor
SQL editor with live syntax highlighting (keywords, strings, numbers, comments). ⌘↵ to run. Per-tab connection picker — switch databases without leaving the editor. SELECT/WITH queries are automatically capped at 1000 rows. Results show row count, execution time, and a capped indicator when the limit is hit. Results persist when switching tabs and back. Copy all results as CSV or JSON. Export to CSV. File-backed queries autosave to disk every 500ms with a visual confirmation indicator. Double-click or right-click any cell for copy and inspection options.

### File Explorer
Local filesystem browser in the sidebar. Navigate directories, create and rename SQL files and folders inline. Delete with confirmation (files moved to Trash). Open `.sql` files directly into a query editor tab. Last visited directory persisted across sessions.

### Tabs
Unlimited tabs — table browsers and query editors co-exist. Color-coded connection dots per tab. ⌘T new query tab, ⌘W close, ⌘[/] navigate between tabs. Tab titles reflect file names for file-backed queries.

### Appearance
Font size (11–17pt) and font design (sans-serif, monospaced) configurable separately for sidebar and content. Changes apply immediately and persist across sessions.

### Updates
Built-in update checker fetches the latest release from GitHub. Shows current status (up to date, update available with version, error) and links directly to the release when an update is found.
