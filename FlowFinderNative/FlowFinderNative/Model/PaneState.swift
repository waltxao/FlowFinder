import Foundation
import Combine

// MARK: - PaneState

struct PaneState {
    var path: String = ""
    var history: [String] = []
    var historyIndex: Int = 0
    var files: [FileEntry] = []
    var selectedFiles: Set<String> = []
    var isLoading: Bool = false
    var error: String?
    var searchQuery: String = ""
    var sortField: String = "name"
    var sortAscending: Bool = true
    var viewMode: String = "list"
    var groupBy: String = "none"
}

// MARK: - PaneViewModel

public class PaneViewModel: ObservableObject {
    @Published var state: PaneState = PaneState()
    private var cancellables = Set<AnyCancellable>()

    var currentPath: String { state.path }
    var files: [FileEntry] { state.files }
    var selectedFiles: Set<String> { state.selectedFiles }
    var isLoading: Bool { state.isLoading }
    var error: String? { state.error }

    init() {}

    init(path: String) {
        state.path = path
        state.history = [path]
        state.historyIndex = 0
    }

    // MARK: - Navigation

    func navigate(to path: String) {
        // Trim current history if we're not at the end
        if state.historyIndex < state.history.count - 1 {
            state.history = Array(state.history.prefix(state.historyIndex + 1))
        }

        state.history.append(path)
        state.historyIndex = state.history.count - 1
        state.path = path
        state.selectedFiles.removeAll()
        state.searchQuery = ""
        state.error = nil

        loadDirectory()
    }

    func goBack() -> Bool {
        guard state.historyIndex > 0 else { return false }
        state.historyIndex -= 1
        state.path = state.history[state.historyIndex]
        state.selectedFiles.removeAll()
        state.searchQuery = ""
        state.error = nil
        loadDirectory()
        return true
    }

    func goForward() -> Bool {
        guard state.historyIndex < state.history.count - 1 else { return false }
        state.historyIndex += 1
        state.path = state.history[state.historyIndex]
        state.selectedFiles.removeAll()
        state.searchQuery = ""
        state.error = nil
        loadDirectory()
        return true
    }

    func goUp() {
        guard !state.path.isEmpty else { return }
        let parentPath = (state.path as NSString).deletingLastPathComponent
        guard parentPath != state.path else { return }
        navigate(to: parentPath)
    }

    func refresh() {
        loadDirectory()
    }

    // MARK: - Selection

    func selectFile(_ file: FileEntry, multi: Bool = false, shiftKey: Bool = false) {
        if shiftKey, let lastSelected = state.selectedFiles.first {
            // Range selection (simplified)
            if let startIndex = state.files.firstIndex(where: { $0.path == lastSelected }),
               let endIndex = state.files.firstIndex(where: { $0.path == file.path }) {
                let range = min(startIndex, endIndex)...max(startIndex, endIndex)
                let rangePaths = state.files[range].map(\.path)
                state.selectedFiles = Set(rangePaths)
            }
        } else if multi {
            if state.selectedFiles.contains(file.path) {
                state.selectedFiles.remove(file.path)
            } else {
                state.selectedFiles.insert(file.path)
            }
        } else {
            state.selectedFiles = [file.path]
        }
    }

    func clearSelection() {
        state.selectedFiles.removeAll()
    }

    func selectAll() {
        state.selectedFiles = Set(state.files.map(\.path))
    }

    // MARK: - Sorting & Filtering

    func setSortField(_ field: String, ascending: Bool = true) {
        state.sortField = field
        state.sortAscending = ascending
        applySort()
    }

    func setGroupBy(_ groupBy: String) {
        state.groupBy = groupBy
        applySort()
    }

    func setSearchQuery(_ query: String) {
        state.searchQuery = query
        if query.isEmpty {
            loadDirectory()
        } else {
            applyFilter()
        }
    }

    func setViewMode(_ mode: String) {
        state.viewMode = mode
    }

    // MARK: - File Operations

    func deleteSelected() {
        // TODO: Implement delete with confirmation
        let pathsToDelete = Array(state.selectedFiles)
        guard !pathsToDelete.isEmpty else { return }

        do {
            for path in pathsToDelete {
                try CoreBridge.shared.deleteFile(path: path)
            }
            state.selectedFiles.removeAll()
            loadDirectory()
        } catch {
            state.error = error.localizedDescription
        }
    }

    func renameFile(_ oldPath: String, to newName: String) {
        let dir = (oldPath as NSString).deletingLastPathComponent
        let newPath = (dir as NSString).appendingPathComponent(newName)

        do {
            try CoreBridge.shared.renameFile(src: oldPath, dst: newPath)
            loadDirectory()
        } catch {
            state.error = error.localizedDescription
        }
    }

    func createDirectory() {
        let newDirName = "未命名文件夹"
        let newDirPath = (state.path as NSString).appendingPathComponent(newDirName)

        do {
            try CoreBridge.shared.createDirectory(path: newDirPath)
            loadDirectory()
        } catch {
            state.error = error.localizedDescription
        }
    }

    // MARK: - Private

    private func loadDirectory() {
        guard !state.path.isEmpty else { return }

        state.isLoading = true
        state.error = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let entries = try CoreBridge.shared.listDirectory(path: self.state.path)
                DispatchQueue.main.async {
                    self.state.files = entries
                    self.state.isLoading = false
                    self.applySort()
                }
            } catch {
                DispatchQueue.main.async {
                    self.state.error = error.localizedDescription
                    self.state.isLoading = false
                }
            }
        }
    }

    private func applySort() {
        let field = state.sortField
        let ascending = state.sortAscending

        state.files.sort(by: { a, b in
            let comparison: Bool
            switch field {
            case "name":
                comparison = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case "modifiedAt":
                comparison = a.modificationDate < b.modificationDate
            case "size":
                comparison = a.size < b.size
            case "extension":
                comparison = a.fileExtension.localizedCaseInsensitiveCompare(b.fileExtension) == .orderedAscending
            default:
                comparison = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return ascending ? comparison : !comparison
        })
    }

    private func applyFilter() {
        guard !state.searchQuery.isEmpty else {
            loadDirectory()
            return
        }

        let query = state.searchQuery.lowercased()
        state.files = state.files.filter { file in
            file.name.lowercased().contains(query)
        }
    }
}
