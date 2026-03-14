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
    @AppStorage("tusk.sidebar.fontSize")    private var sidebarFontSize   = 13.0
    @AppStorage("tusk.sidebar.fontDesign") private var sidebarFontDesign: TuskFontDesign = .sansSerif

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
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @FocusState private var isFolderNameFocused: Bool
    @State private var renamingItem: FileItem? = nil
    @State private var renameText = ""
    @FocusState private var isRenameFocused: Bool
    @State private var itemPendingDelete: FileItem? = nil
    @State private var deleteErrorMessage: String? = nil

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
        .alert("Could Not Delete", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { deleteErrorMessage = nil }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                currentDirectory = currentDirectory.deletingLastPathComponent()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: sidebarFontSize - 2, design: sidebarFontDesign.design))
            }
            .disabled(isAtHome)
            .buttonStyle(.borderless)
            .foregroundStyle(isAtHome ? .tertiary : .secondary)

            Image(systemName: "folder.fill")
                .font(.system(size: sidebarFontSize - 2, design: sidebarFontDesign.design))
                .foregroundStyle(.secondary)

            Text(isAtHome ? "Home" : currentDirectory.lastPathComponent)
                .font(.system(size: sidebarFontSize - 2, weight: .medium, design: sidebarFontDesign.design))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Menu {
                Button {
                    isCreatingFolder = false
                    newFileName = ""
                    isCreatingFile = true
                    isFileNameFocused = true
                } label: {
                    Label("New SQL File", systemImage: "doc.badge.plus")
                }
                Button {
                    isCreatingFile = false
                    newFolderName = ""
                    isCreatingFolder = true
                    isFolderNameFocused = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: sidebarFontSize - 2, design: sidebarFontDesign.design))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .fixedSize()
            .help("New item")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - File list

    @ViewBuilder
    private var fileList: some View {
        if items.isEmpty && !isCreatingFile && !isCreatingFolder {
            Text("Empty folder")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if isCreatingFolder {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        TextField("folder name", text: $newFolderName)
                            .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                            .focused($isFolderNameFocused)
                            .onSubmit { commitNewFolder() }
                            .onExitCommand { isCreatingFolder = false }
                    }
                    .padding(.vertical, 1)
                }
                if isCreatingFile {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        TextField("filename.sql", text: $newFileName)
                            .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                            .focused($isFileNameFocused)
                            .onSubmit { commitNewFile() }
                            .onExitCommand { isCreatingFile = false }
                    }
                    .padding(.vertical, 1)
                }
                ForEach(items) { item in
                    if renamingItem?.id == item.id {
                        HStack(spacing: 6) {
                            Image(systemName: item.icon)
                                .foregroundStyle(.secondary)
                            TextField(item.isDirectory ? "folder name" : "filename.sql", text: $renameText)
                                .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                                .focused($isRenameFocused)
                                .onSubmit { commitRename() }
                                .onExitCommand { renamingItem = nil }
                        }
                        .padding(.vertical, 1)
                    } else {
                        Button {
                            if item.isDirectory {
                                currentDirectory = item.url
                            } else if item.isSql {
                                Task { await appState.openFileInEditor(url: item.url) }
                            }
                        } label: {
                            Label {
                                Text(item.name)
                                    .font(.system(size: sidebarFontSize, design: sidebarFontDesign.design))
                                    .foregroundStyle(item.isInteractable ? .primary : .tertiary)
                                    .lineLimit(1)
                            } icon: {
                                Image(systemName: item.icon)
                                    .foregroundStyle(item.isInteractable ? .secondary : .quaternary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!item.isInteractable)
                        .contextMenu {
                            if item.isSql || item.isDirectory {
                                Button("Rename") {
                                    renameText = item.isDirectory
                                        ? item.name
                                        : item.url.deletingPathExtension().lastPathComponent
                                    renamingItem = item
                                    isRenameFocused = true
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    itemPendingDelete = item
                                }
                            }
                        }
                    }
                }
                .confirmationDialog(
                    "Delete \"\(itemPendingDelete?.name ?? "")\"?",
                    isPresented: Binding(
                        get: { itemPendingDelete != nil },
                        set: { if !$0 { itemPendingDelete = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        if let item = itemPendingDelete { commitDelete(item) }
                    }
                } message: {
                    Text(itemPendingDelete?.isDirectory == true
                         ? "This folder will be moved to the Trash."
                         : "This file will be moved to the Trash.")
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Create new file

    private func commitNewFile() {
        var name = newFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { isCreatingFile = false; return }
        name = URL(fileURLWithPath: name).lastPathComponent
        guard !name.isEmpty, !name.hasPrefix(".") else { isCreatingFile = false; return }
        if !name.lowercased().hasSuffix(".sql") { name += ".sql" }
        let fileURL = currentDirectory.appendingPathComponent(name)
        guard fileURL.deletingLastPathComponent().standardized == currentDirectory.standardized else {
            isCreatingFile = false
            return
        }
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            isCreatingFile = false
            Task { await appState.openFileInEditor(url: fileURL) }
            return
        }
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

    // MARK: - Create new folder

    private func commitNewFolder() {
        var name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { isCreatingFolder = false; return }
        name = URL(fileURLWithPath: name).lastPathComponent
        guard !name.isEmpty, !name.hasPrefix(".") else { isCreatingFolder = false; return }
        let folderURL = currentDirectory.appendingPathComponent(name)
        guard folderURL.deletingLastPathComponent().standardized == currentDirectory.standardized else {
            isCreatingFolder = false
            return
        }
        guard !FileManager.default.fileExists(atPath: folderURL.path) else {
            isCreatingFolder = false
            return
        }
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        } catch {
            isCreatingFolder = false
            return
        }
        isCreatingFolder = false
        Task { await loadItems() }
    }

    // MARK: - Rename

    private func commitRename() {
        guard let item = renamingItem else { return }
        var name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        name = URL(fileURLWithPath: name).lastPathComponent
        guard !name.isEmpty, !name.hasPrefix(".") else { renamingItem = nil; return }
        if item.isSql, !name.lowercased().hasSuffix(".sql") { name += ".sql" }
        let newURL = currentDirectory.appendingPathComponent(name)
        guard newURL.deletingLastPathComponent().standardized == currentDirectory.standardized else {
            renamingItem = nil; return
        }
        guard newURL != item.url else { renamingItem = nil; return }
        guard !FileManager.default.fileExists(atPath: newURL.path) else { renamingItem = nil; return }
        do {
            try FileManager.default.moveItem(at: item.url, to: newURL)
        } catch {
            renamingItem = nil; return
        }
        if item.isSql {
            appState.renameFileTab(from: item.url, to: newURL)
        } else if item.isDirectory {
            appState.renameFolderTabs(from: item.url, to: newURL)
        }
        renamingItem = nil
        Task { await loadItems() }
    }

    // MARK: - Delete

    private func commitDelete(_ item: FileItem) {
        if item.isDirectory {
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: item.url,
                    includingPropertiesForKeys: nil,
                    options: .skipsHiddenFiles
                )
                guard contents.isEmpty else {
                    deleteErrorMessage = "\"\(item.name)\" is not empty. Remove its contents before deleting it."
                    itemPendingDelete = nil
                    return
                }
            } catch {
                deleteErrorMessage = "Could not verify the contents of \"\(item.name)\"."
                itemPendingDelete = nil
                return
            }
        }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            if item.isSql { appState.closeTabForFile(url: item.url) }
            itemPendingDelete = nil
            Task { await loadItems() }
        } catch {
            deleteErrorMessage = error.localizedDescription
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
