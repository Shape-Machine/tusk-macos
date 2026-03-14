import SwiftUI

// MARK: - File item model

struct FileItem: Identifiable {
    let url: URL
    var id: URL { url }
    let isDirectory: Bool

    var name: String { url.lastPathComponent }
    var isSql: Bool { !isDirectory && url.pathExtension.lowercased() == "sql" }
    var isInteractable: Bool { isDirectory || isSql }
    var icon: String {
        if isDirectory { return "folder" }
        if isSql { return "doc.text" }
        return "doc"
    }
}

// MARK: - File explorer view

struct FileExplorerView: View {
    @Environment(AppState.self) private var appState

    @State private var currentDirectory: URL = {
        if let path = UserDefaults.standard.string(forKey: "fileExplorerDirectory") {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: path)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()
    @State private var items: [FileItem] = []
    @State private var isCreatingFile = false
    @State private var newFileName = ""
    @FocusState private var isFileNameFocused: Bool

    private var homeDirectory: URL { FileManager.default.homeDirectoryForCurrentUser }
    private var isAtHome: Bool { currentDirectory.standardized == homeDirectory.standardized }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            fileList
        }
        .task(id: currentDirectory) { await loadItems() }
        .onChange(of: currentDirectory) { _, newValue in
            UserDefaults.standard.set(newValue.path, forKey: "fileExplorerDirectory")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                currentDirectory = currentDirectory.deletingLastPathComponent()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption)
            }
            .disabled(isAtHome)
            .buttonStyle(.borderless)
            .foregroundStyle(isAtHome ? .tertiary : .secondary)

            Image(systemName: "folder.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(isAtHome ? "Home" : currentDirectory.lastPathComponent)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                newFileName = ""
                isCreatingFile = true
                isFileNameFocused = true
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("New SQL file")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - File list

    @ViewBuilder
    private var fileList: some View {
        if items.isEmpty && !isCreatingFile {
            Text("Empty folder")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if isCreatingFile {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        TextField("filename.sql", text: $newFileName)
                            .font(.system(size: 12))
                            .focused($isFileNameFocused)
                            .onSubmit { commitNewFile() }
                            .onExitCommand { isCreatingFile = false }
                    }
                    .padding(.vertical, 1)
                }
                ForEach(items) { item in
                    Button {
                        if item.isDirectory {
                            currentDirectory = item.url
                        } else if item.isSql {
                            Task { await appState.openFileInEditor(url: item.url) }
                        }
                    } label: {
                        Label {
                            Text(item.name)
                                .font(.system(size: 12))
                                .foregroundStyle(item.isInteractable ? .primary : .tertiary)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: item.icon)
                                .foregroundStyle(item.isInteractable ? .secondary : .quaternary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!item.isInteractable)
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Create new file

    private func commitNewFile() {
        var name = newFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { isCreatingFile = false; return }
        if !name.lowercased().hasSuffix(".sql") { name += ".sql" }
        let fileURL = currentDirectory.appendingPathComponent(name)
        do {
            try "".write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            isCreatingFile = false
            return
        }
        isCreatingFile = false
        Task {
            await loadItems()
            await appState.openFileInEditor(url: fileURL)
        }
    }

    // MARK: - Load directory contents

    private func loadItems() async {
        let directory = currentDirectory
        let loaded = await Task.detached(priority: .userInitiated) {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            ) else { return [FileItem]() }

            return contents
                .compactMap { url -> FileItem? in
                    guard let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
                    else { return nil }
                    return FileItem(url: url, isDirectory: isDir ?? false)
                }
                .sorted {
                    // Folders first, then alphabetical within each group
                    if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
        }.value
        guard !Task.isCancelled else { return }
        items = loaded
    }
}
