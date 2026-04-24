import SwiftUI

struct TableDetailView: View {
    let client: DatabaseClient
    let connectionID: UUID
    let schemaName: String
    let tableName: String
    var isView: Bool = false
    var isReadOnly: Bool = false

    @Environment(AppState.self) private var appState
    @AppStorage("tusk.content.fontSize")   private var contentFontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var contentFontDesign: TuskFontDesign = .sansSerif

    enum Tab { case columns, keys, relations, indexes, triggers, ddl, data }

    @State private var selectedTab: Tab = .columns
    @State private var selectedColumnIDs: Set<String> = []
    @State private var columns: [ColumnInfo] = []
    @State private var foreignKeys: [ForeignKeyInfo] = []
    @State private var isLoadingMeta = false
    @State private var dataState = DataBrowserState()
    @State private var indexes: [IndexInfo] = []
    @State private var indexesError: String? = nil
    @State private var isLoadingIndexes = false
    @State private var indexesLoadTask: Task<Void, Never>? = nil
    @State private var triggers: [TriggerInfo] = []
    @State private var triggersError: String? = nil
    @State private var isLoadingTriggers = false
    @State private var triggersLoadTask: Task<Void, Never>? = nil
    @State private var ddlText = ""
    @State private var ddlError: String? = nil
    @State private var isLoadingDDL = false
    @State private var ddlLoadTask: Task<Void, Never>? = nil
    @State private var showingAddConstraint = false
    @State private var showingCreateIndex = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabPicker
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: schemaName + "." + tableName) { await loadMeta() }
        .onChange(of: schemaName + "." + tableName) { _, _ in
            columns = []
            foreignKeys = []
            dataState.loadTask?.cancel()
            dataState.filterDebounceTask?.cancel()
            dataState.result = nil
            dataState.error = nil
            dataState.isLoading = false
            dataState.offset = 0
            dataState.filterText = ""
            indexesLoadTask?.cancel()
            indexesLoadTask = nil
            indexes = []
            indexesError = nil
            isLoadingIndexes = false
            triggersLoadTask?.cancel()
            triggersLoadTask = nil
            triggers = []
            triggersError = nil
            isLoadingTriggers = false
            ddlLoadTask?.cancel()
            ddlLoadTask = nil
            ddlText = ""
            ddlError = nil
            isLoadingDDL = false
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .indexes && indexes.isEmpty && !isLoadingIndexes {
                indexesLoadTask = Task { await loadIndexes() }
            }
            if newTab == .triggers && triggers.isEmpty && !isLoadingTriggers {
                triggersLoadTask = Task { await loadTriggers() }
            }
            if newTab == .ddl && ddlText.isEmpty && !isLoadingDDL {
                ddlLoadTask = Task { await loadDDL() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tablecells")
                .foregroundStyle(.blue)
            Text(tableName)
                .font(.system(size: contentFontSize + 8, weight: .semibold, design: contentFontDesign.design))
            Text(schemaName)
                .font(.system(.caption, design: contentFontDesign.design))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: 2) {
            tabSegment("Columns", for: .columns)
            tabSegment("Foreign Keys", for: .keys)
            tabSegment("Relations", for: .relations)
            tabSegment("Indexes", for: .indexes)
            tabSegment("Triggers", for: .triggers)
            tabSegment("DDL", for: .ddl)
            tabSegment("Data", for: .data)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private func tabSegment(_ title: String, for tab: Tab) -> some View {
        Button { selectedTab = tab } label: {
            Text(title)
                .font(.system(size: contentFontSize - 1, design: contentFontDesign.design))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    selectedTab == tab ? Color(nsColor: .selectedControlColor) : .clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .data:
            DataBrowserView(client: client, connectionID: connectionID, schemaName: schemaName, tableName: tableName, isView: isView, isReadOnly: isReadOnly, columns: columns, state: dataState)
        case .columns:
            columnsTab
        case .keys:
            keysTab
        case .relations:
            RelationsView(client: client, connectionID: connectionID, schemaName: schemaName, tableName: tableName)
        case .indexes:
            indexesTab
        case .triggers:
            triggersTab
        case .ddl:
            DDLTab(ddlText: ddlText, ddlError: ddlError, isLoading: isLoadingDDL, fontSize: contentFontSize, fontDesign: contentFontDesign)
        }
    }

    // MARK: - Columns tab

    private var columnsTab: some View {
        VStack(spacing: 0) {
            if !isView && !isReadOnly {
                HStack {
                    Spacer()
                    Button { addColumn() } label: {
                        Label("Add Column", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
                Divider()
            }
            Group {
                if isLoadingMeta {
                    ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(columns, selection: $selectedColumnIDs) {
                        TableColumn("Column") { col in
                            HStack(spacing: 4) {
                                if col.isPrimaryKey {
                                    Image(systemName: "key.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                Text(col.name)
                            }
                        }
                        TableColumn("Type") { col in
                            Text(col.dataType).foregroundStyle(.secondary)
                        }
                        TableColumn("Nullable") { col in
                            Text(col.isNullable ? "YES" : "NO")
                                .foregroundStyle(col.isNullable ? .secondary : .primary)
                        }
                        TableColumn("Default") { col in
                            Text(col.defaultValue ?? "—").foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu(forSelectionType: String.self) { ids in
                        if !isView && !isReadOnly, ids.count == 1, let id = ids.first,
                           let col = columns.first(where: { $0.id == id }) {
                            Button("Rename…")      { renameColumn(col) }
                            Button("Edit…")        { editColumn(col) }
                            Divider()
                            Button("Drop Column…") { dropColumn(col) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rename column

    private func renameColumn(_ col: ColumnInfo) {
        let alert = NSAlert()
        alert.messageText = "Rename Column \"\(col.name)\""
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = col.name
        field.selectText(nil)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != col.name else { return }

        Task {
            do {
                let sql = "ALTER TABLE \(quoteIdentifier(schemaName)).\(quoteIdentifier(tableName)) RENAME COLUMN \(quoteIdentifier(col.name)) TO \(quoteIdentifier(newName));"
                _ = try await client.query(sql)
                await loadMeta()
            } catch {
                let err = NSAlert()
                err.messageText = "Rename Failed"
                err.informativeText = error.localizedDescription
                err.alertStyle = .warning
                err.runModal()
            }
        }
    }

    // MARK: - Edit column

    private func editColumn(_ col: ColumnInfo) {
        let alert = NSAlert()
        alert.messageText = "Edit Column \"\(col.name)\""
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        // Accessory view: type field, default field, nullable checkbox
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 92))

        let typeLabel = NSTextField(labelWithString: "Type")
        typeLabel.frame = NSRect(x: 0, y: 68, width: 80, height: 17)
        typeLabel.alignment = .right

        let typeField = NSTextField(frame: NSRect(x: 88, y: 65, width: 212, height: 22))
        typeField.stringValue = col.dataType
        typeField.placeholderString = "e.g. text, integer, boolean"

        let defaultLabel = NSTextField(labelWithString: "Default")
        defaultLabel.frame = NSRect(x: 0, y: 38, width: 80, height: 17)
        defaultLabel.alignment = .right

        let defaultField = NSTextField(frame: NSRect(x: 88, y: 35, width: 212, height: 22))
        defaultField.stringValue = col.defaultValue ?? ""
        defaultField.placeholderString = "leave blank to drop default"

        let nullableCheck = NSButton(checkboxWithTitle: "Nullable", target: nil, action: nil)
        nullableCheck.frame = NSRect(x: 88, y: 6, width: 212, height: 18)
        nullableCheck.state = col.isNullable ? .on : .off

        container.addSubview(typeLabel)
        container.addSubview(typeField)
        container.addSubview(defaultLabel)
        container.addSubview(defaultField)
        container.addSubview(nullableCheck)

        alert.accessoryView = container
        alert.window.initialFirstResponder = typeField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let newType    = typeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDefault = defaultField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNullable = nullableCheck.state == .on

        let typeChanged    = !newType.isEmpty && newType != col.dataType
        let defaultChanged = newDefault != (col.defaultValue ?? "")
        let nullableChanged = newNullable != col.isNullable

        guard typeChanged || defaultChanged || nullableChanged else { return }

        Task {
            do {
                let t = "\(quoteIdentifier(schemaName)).\(quoteIdentifier(tableName))"
                let c = quoteIdentifier(col.name)

                _ = try await client.query("BEGIN;")
                do {
                    if typeChanged {
                        _ = try await client.query("ALTER TABLE \(t) ALTER COLUMN \(c) TYPE \(newType);")
                    }
                    if defaultChanged {
                        if newDefault.isEmpty {
                            _ = try await client.query("ALTER TABLE \(t) ALTER COLUMN \(c) DROP DEFAULT;")
                        } else {
                            _ = try await client.query("ALTER TABLE \(t) ALTER COLUMN \(c) SET DEFAULT \(newDefault);")
                        }
                    }
                    if nullableChanged {
                        if newNullable {
                            _ = try await client.query("ALTER TABLE \(t) ALTER COLUMN \(c) DROP NOT NULL;")
                        } else {
                            _ = try await client.query("ALTER TABLE \(t) ALTER COLUMN \(c) SET NOT NULL;")
                        }
                    }
                    _ = try await client.query("COMMIT;")
                } catch {
                    try? await client.query("ROLLBACK;")
                    throw error
                }
                await loadMeta()
            } catch {
                let err = NSAlert()
                err.messageText = "Edit Failed"
                err.informativeText = error.localizedDescription
                err.alertStyle = .warning
                err.runModal()
            }
        }
    }

    // MARK: - Add column

    private func addColumn() {
        let alert = NSAlert()
        alert.messageText = "Add Column to \"\(tableName)\""
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 122))

        let nameLabel = NSTextField(labelWithString: "Name")
        nameLabel.frame = NSRect(x: 0, y: 98, width: 80, height: 17)
        nameLabel.alignment = .right

        let nameField = NSTextField(frame: NSRect(x: 88, y: 95, width: 212, height: 22))
        nameField.placeholderString = "column_name"

        let typeLabel = NSTextField(labelWithString: "Type")
        typeLabel.frame = NSRect(x: 0, y: 68, width: 80, height: 17)
        typeLabel.alignment = .right

        let typeField = NSTextField(frame: NSRect(x: 88, y: 65, width: 212, height: 22))
        typeField.stringValue = "text"
        typeField.placeholderString = "e.g. text, integer, boolean"

        let defaultLabel = NSTextField(labelWithString: "Default")
        defaultLabel.frame = NSRect(x: 0, y: 38, width: 80, height: 17)
        defaultLabel.alignment = .right

        let defaultField = NSTextField(frame: NSRect(x: 88, y: 35, width: 212, height: 22))
        defaultField.placeholderString = "leave blank for no default"

        let nullableCheck = NSButton(checkboxWithTitle: "Nullable", target: nil, action: nil)
        nullableCheck.frame = NSRect(x: 88, y: 6, width: 212, height: 18)
        nullableCheck.state = .on

        container.addSubview(nameLabel)
        container.addSubview(nameField)
        container.addSubview(typeLabel)
        container.addSubview(typeField)
        container.addSubview(defaultLabel)
        container.addSubview(defaultField)
        container.addSubview(nullableCheck)

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name       = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let type       = typeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultVal = defaultField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let nullable   = nullableCheck.state == .on

        guard !name.isEmpty, !type.isEmpty else { return }

        let dangerousTokens = [";", "--", "/*", "*/"]
        for input in [type, defaultVal] where !input.isEmpty {
            if dangerousTokens.contains(where: { input.contains($0) }) {
                let err = NSAlert()
                err.messageText = "Invalid Input"
                err.informativeText = "Type and default value must not contain SQL metacharacters (;  --  /*  */)."
                err.alertStyle = .warning
                err.runModal()
                return
            }
        }

        Task {
            do {
                let t = "\(quoteIdentifier(schemaName)).\(quoteIdentifier(tableName))"
                let c = quoteIdentifier(name)
                var sql = "ALTER TABLE \(t) ADD COLUMN \(c) \(type)"
                if !defaultVal.isEmpty { sql += " DEFAULT \(defaultVal)" }
                if !nullable           { sql += " NOT NULL" }
                sql += ";"
                _ = try await client.query(sql)
                await loadMeta()
            } catch {
                let err = NSAlert()
                err.messageText = "Add Column Failed"
                err.informativeText = error.localizedDescription
                err.alertStyle = .warning
                err.runModal()
            }
        }
    }

    // MARK: - Drop column

    private func dropColumn(_ col: ColumnInfo) {
        let alert = NSAlert()
        alert.messageText = "Drop Column \"\(col.name)\"?"
        alert.informativeText = "This will permanently remove the column and all its data from \"\(tableName)\". This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Drop Column")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                let sql = "ALTER TABLE \(quoteIdentifier(schemaName)).\(quoteIdentifier(tableName)) DROP COLUMN \(quoteIdentifier(col.name));"
                _ = try await client.query(sql)
                await loadMeta()
            } catch {
                let err = NSAlert()
                err.messageText = "Drop Column Failed"
                err.informativeText = error.localizedDescription
                err.alertStyle = .warning
                err.runModal()
            }
        }
    }

    // MARK: - Keys tab

    private var keysTab: some View {
        VStack(spacing: 0) {
            if !isView && !isReadOnly {
                HStack {
                    Spacer()
                    Button {
                        showingAddConstraint = true
                    } label: {
                        Label("Add Constraint", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .sheet(isPresented: $showingAddConstraint) {
                        AddConstraintSheet(
                            schemaName: schemaName,
                            tableName: tableName,
                            tableColumns: columns,
                            client: client
                        ) {
                            await loadMeta()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
                Divider()
            }
            Group {
                if isLoadingMeta {
                    ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if foreignKeys.isEmpty {
                    ContentUnavailableView("No foreign keys", systemImage: "link")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(foreignKeys) {
                        TableColumn("Constraint", value: \.constraintName)
                        TableColumn("Column", value: \.fromColumn)
                        TableColumn("References") { fk in
                            Text("\(fk.toTable)(\(fk.toColumn))")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Indexes tab

    private var indexesTab: some View {
        VStack(spacing: 0) {
            if !isView && !isReadOnly {
                HStack {
                    Spacer()
                    Button {
                        showingCreateIndex = true
                    } label: {
                        Label("Add Index", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .sheet(isPresented: $showingCreateIndex) {
                        CreateIndexSheet(
                            schemaName: schemaName,
                            tableName: tableName,
                            tableColumns: columns,
                            client: client
                        ) {
                            indexesLoadTask?.cancel()
                            indexesLoadTask = Task { await loadIndexes() }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
                Divider()
            }
            Group {
                if isLoadingIndexes {
                    ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = indexesError {
                    ContentUnavailableView("Failed to load indexes", systemImage: "exclamationmark.triangle")
                        .help(error)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if indexes.isEmpty {
                    ContentUnavailableView("No indexes", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(indexes) {
                        TableColumn("Name", value: \.name)
                        TableColumn("Unique") { idx in
                            Text(idx.isUnique ? "YES" : "NO")
                                .foregroundStyle(idx.isUnique ? .primary : .secondary)
                        }
                        TableColumn("Primary") { idx in
                            Text(idx.isPrimary ? "YES" : "NO")
                                .foregroundStyle(idx.isPrimary ? .primary : .secondary)
                        }
                        TableColumn("Definition", value: \.definition)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Triggers tab

    private var triggersTab: some View {
        Group {
            if isLoadingTriggers {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = triggersError {
                ContentUnavailableView("Failed to load triggers", systemImage: "exclamationmark.triangle")
                    .help(error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if triggers.isEmpty {
                ContentUnavailableView("No triggers", systemImage: "bolt.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(triggers) {
                    TableColumn("Name", value: \.name)
                    TableColumn("Timing", value: \.timing)
                    TableColumn("Event", value: \.event)
                    TableColumn("Statement", value: \.statement)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load metadata

    private func loadMeta() async {
        isLoadingMeta = true
        // Use the AppState column cache so repeat opens are instant (#214)
        async let cols = try? await appState.cachedColumns(connectionID: connectionID, schema: schemaName, table: tableName, using: client)
        async let fks  = try? await client.foreignKeys(schema: schemaName, table: tableName)
        columns     = await cols ?? []
        foreignKeys = await fks  ?? []
        isLoadingMeta = false
    }

    private func loadIndexes() async {
        isLoadingIndexes = true
        do {
            let result = try await client.fetchIndexes(schema: schemaName, table: tableName)
            guard !Task.isCancelled else { isLoadingIndexes = false; return }
            indexes = result
            indexesError = nil
        } catch {
            guard !Task.isCancelled else { isLoadingIndexes = false; return }
            indexesError = error.localizedDescription
        }
        isLoadingIndexes = false
    }

    private func loadTriggers() async {
        isLoadingTriggers = true
        do {
            let result = try await client.fetchTriggers(schema: schemaName, table: tableName)
            guard !Task.isCancelled else { isLoadingTriggers = false; return }
            triggers = result
            triggersError = nil
        } catch {
            guard !Task.isCancelled else { isLoadingTriggers = false; return }
            triggersError = error.localizedDescription
        }
        isLoadingTriggers = false
    }

    private func loadDDL() async {
        isLoadingDDL = true
        do {
            let result = try await client.tableDDL(schema: schemaName, table: tableName)
            guard !Task.isCancelled else { isLoadingDDL = false; return }
            ddlText = result
            ddlError = nil
        } catch {
            guard !Task.isCancelled else { isLoadingDDL = false; return }
            ddlError = error.localizedDescription
        }
        isLoadingDDL = false
    }
}

// MARK: - DDL tab

private struct DDLTab: View {
    let ddlText: String
    let ddlError: String?
    let isLoading: Bool
    let fontSize: Double
    let fontDesign: TuskFontDesign

    var body: some View {
        if isLoading {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = ddlError {
            ContentUnavailableView("Failed to load DDL", systemImage: "exclamationmark.triangle")
                .help(error)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if ddlText.isEmpty {
            ContentUnavailableView("No DDL available", systemImage: "doc.text")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ddlText, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
                Divider()
                SQLTextEditor(text: .constant(ddlText), fontSize: fontSize, isEditable: false)
            }
        }
    }
}
