import SwiftUI

// MARK: - Function Detail Tab

struct FunctionDetailView: View {
    let oid: UInt32
    let client: DatabaseClient
    let connection: Connection

    @Environment(AppState.self) private var appState
    @AppStorage("tusk.content.fontSize")   private var contentFontSize   = 13.0
    @AppStorage("tusk.content.fontDesign") private var contentFontDesign: TuskFontDesign = .sansSerif

    @State private var detail: FunctionDetail? = nil
    @State private var isLoading = true
    @State private var isExecutorVisible = false

    private var isReadOnly: Bool { connection.isReadOnly }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                if isExecutorVisible {
                    VSplitView {
                        sourcePane(detail: detail)
                            .frame(minHeight: 120)
                        ExecutorPane(detail: detail, client: client, isReadOnly: isReadOnly)
                            .frame(minHeight: 120)
                    }
                } else {
                    sourcePane(detail: detail)
                }
            } else {
                ContentUnavailableView {
                    Label("Failed to Load Function", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Could not retrieve details for this function.")
                } actions: {
                    Button("Retry") { Task { await reload() } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await reload() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "function")
                .foregroundStyle(.secondary)
            Text(detail.map { "\($0.schema).\($0.name)" } ?? "…")
                .font(.system(size: contentFontSize, weight: .semibold, design: contentFontDesign.design))
            Spacer()
            if let detail, !isLoading {
                metadataBadges(detail: detail)
                if !isReadOnly || detail.volatility == "IMMUTABLE" {
                    Toggle(isOn: $isExecutorVisible) {
                        Label("Run", systemImage: "play.fill")
                            .font(.callout)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if !isReadOnly {
                    Button("Drop…") { dropFunction(detail) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func metadataBadges(detail: FunctionDetail) -> some View {
        HStack(spacing: 6) {
            badge(detail.language.uppercased(), color: .blue)
            badge(detail.volatility, color: volatilityColor(detail.volatility))
            if detail.isSecurityDefiner {
                badge("SECURITY DEFINER", color: .orange)
            }
            if !detail.returnType.isEmpty && detail.returnType != "NULL" {
                Text("→ \(detail.returnType)")
                    .font(.system(size: contentFontSize - 1, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: contentFontSize - 2, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }

    private func volatilityColor(_ v: String) -> Color {
        switch v {
        case "IMMUTABLE": return .green
        case "STABLE":    return .teal
        default:          return .secondary
        }
    }

    // MARK: - Source pane

    private func sourcePane(detail: FunctionDetail) -> some View {
        SQLTextEditor(
            text: .constant(detail.source),
            fontSize: contentFontSize,
            isEditable: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func reload() async {
        isLoading = true
        detail = try? await client.functionDetail(oid: oid)
        isLoading = false
    }

    private func dropFunction(_ detail: FunctionDetail) {
        let isProcedure = detail.returnType.isEmpty
        let kind = isProcedure ? "Procedure" : "Function"
        let alert = NSAlert()
        alert.messageText = "Drop \(kind) \"\(detail.name)\"?"
        alert.informativeText = "This permanently removes the \(kind.lowercased()): \(detail.schema).\(detail.name)(\(detail.arguments.map { $0.typeName }.joined(separator: ", ")))"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Drop \(kind)")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                let argTypes = detail.arguments.map { $0.typeName }.joined(separator: ", ")
                let dropSQL = isProcedure
                    ? "DROP PROCEDURE \(quoteIdentifier(detail.schema)).\(quoteIdentifier(detail.name))(\(argTypes));"
                    : "DROP FUNCTION \(quoteIdentifier(detail.schema)).\(quoteIdentifier(detail.name))(\(argTypes));"
                _ = try await client.query(dropSQL)
                try? await appState.refreshSchema(for: connection)
                if let tab = appState.openTabs.first(where: {
                    if case .function(let cid, let s, let n, _) = $0.kind {
                        return cid == connection.id && s == detail.schema && n == detail.name
                    }
                    return false
                }) { appState.closeDetailTab(tab.id) }
            } catch {
                let err = NSAlert()
                err.messageText = "Drop Function Failed"
                err.informativeText = error.localizedDescription
                err.alertStyle = .warning
                err.runModal()
            }
        }
    }
}

// MARK: - Executor pane

private struct ExecutorPane: View {
    let detail: FunctionDetail
    let client: DatabaseClient
    let isReadOnly: Bool

    @AppStorage("tusk.content.fontSize") private var contentFontSize = 13.0

    @State private var argValues: [String] = []
    @State private var result: QueryResult? = nil
    @State private var errorMessage: String? = nil
    @State private var isRunning = false

    private var inArgs: [FunctionArg] { detail.arguments }

    var body: some View {
        VStack(spacing: 0) {
            executorToolbar
            Divider()
            if let result {
                ResultsGrid(result: result)
            } else if let errorMessage {
                ScrollView {
                    Text(errorMessage)
                        .font(.system(size: contentFontSize - 1, design: .monospaced))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                Color(nsColor: .textBackgroundColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            argValues = Array(repeating: "", count: inArgs.count)
        }
    }

    private var executorToolbar: some View {
        HStack(spacing: 10) {
            if inArgs.isEmpty {
                Text("No parameters")
                    .font(.system(size: contentFontSize - 1))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(inArgs) { arg in
                            argField(arg)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Spacer()
            if isRunning {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await execute() }
            } label: {
                Label("Execute", systemImage: "play.fill")
                    .font(.callout)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isRunning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func argField(_ arg: FunctionArg) -> some View {
        let label = arg.name.map { "\($0): \(arg.typeName)" } ?? arg.typeName
        let binding = Binding<String>(
            get: { arg.index < argValues.count ? argValues[arg.index] : "" },
            set: { if arg.index < argValues.count { argValues[arg.index] = $0 } }
        )

        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: contentFontSize - 2))
                .foregroundStyle(.secondary)
            if isBoolType(arg.typeName) {
                Toggle("", isOn: Binding(
                    get: { binding.wrappedValue.lowercased() == "true" },
                    set: { binding.wrappedValue = $0 ? "true" : "false" }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            } else {
                TextField(arg.typeName, text: binding)
                    .font(.system(size: contentFontSize, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 80, maxWidth: 200)
                    .controlSize(.small)
            }
        }
    }

    private func isBoolType(_ typeName: String) -> Bool {
        let t = typeName.lowercased()
        return t == "boolean" || t == "bool"
    }

    private func execute() async {
        isRunning = true
        errorMessage = nil
        result = nil

        let schema = detail.schema
        let name   = detail.name
        let isProcedure = detail.returnType.isEmpty

        // Build argument list: cast each value to its declared type
        let argList: String
        if inArgs.isEmpty {
            argList = ""
        } else {
            argList = inArgs.enumerated().map { idx, arg in
                let val = idx < argValues.count ? argValues[idx] : ""
                return val.isEmpty ? "NULL" : "\(quoteLiteral(val))::\(arg.typeName)"
            }.joined(separator: ", ")
        }

        let sql: String
        if isProcedure {
            sql = "CALL \(quoteIdentifier(schema)).\(quoteIdentifier(name))(\(argList));"
        } else {
            sql = "SELECT * FROM \(quoteIdentifier(schema)).\(quoteIdentifier(name))(\(argList));"
        }

        do {
            let r = try await client.query(sql)
            result = r
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }
}
