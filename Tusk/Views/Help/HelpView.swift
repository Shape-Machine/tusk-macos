import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                shortcutsSection
                tipsSection
            }
            .padding(28)
        }
        .frame(width: 460)
    }

    // MARK: - Keyboard Shortcuts

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts")
                .font(.headline)

            VStack(spacing: 0) {
                shortcutRow("⌘T",       "New query tab")
                shortcutRow("⌘W",       "Close tab")
                shortcutRow("⌘[ / ⌘]", "Previous / next tab")
                shortcutRow("⇧⌘N",     "New connection")
                shortcutRow("⌘,",       "Settings")
                shortcutRow("⌘↵",       "Run all statements")
                shortcutRow("⇧⌘↵",     "Run current statement")
                shortcutRow("⌘⌥↵",     "EXPLAIN ANALYZE current statement")
                shortcutRow("⌘R",       "Refresh schema")
            }
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func shortcutRow(_ key: String, _ label: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.background, in: RoundedRectangle(cornerRadius: 4))
                .frame(width: 110, alignment: .center)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Feature Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Feature Tips")
                .font(.headline)

            tipGroup("Query Editor") {
                tipLine("Run all statements in the editor with ⌘↵, or only the statement at the cursor with ⇧⌘↵.")
                tipLine("Visualise a query's execution plan with ⌘⌥↵ — results render as a collapsible plan tree.")
                tipLine("Each query tab is independent; open as many as you need with ⌘T.")
            }

            tipGroup("Data Browser") {
                tipLine("Double-click any cell to edit it inline; press Return to save or Escape to cancel.")
                tipLine("Insert rows with the + button; delete selected rows with the − button.")
                tipLine("Copy selected rows as CSV, JSON, or INSERT statements from the toolbar.")
            }

            tipGroup("Schema Browser") {
                tipLine("Collapse or expand schema groups by clicking the group header.")
                tipLine("Table size (row count and disk usage) is shown as an overlay when available.")
                tipLine("After running DDL in the query editor, press ⌘R to refresh the schema tree.")
            }
        }
    }

    private func tipGroup(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            content()
        }
    }

    private func tipLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("·")
                .foregroundStyle(.tertiary)
                .font(.callout)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
