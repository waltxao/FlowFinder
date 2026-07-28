import Foundation
import Combine

// MARK: - SortField

enum SortField: String, CaseIterable {
    case name = "名称"
    case modifiedAt = "修改日期"
    case type = "类型"
    case size = "大小"

    var key: String {
        switch self {
        case .name: return "name"
        case .modifiedAt: return "modifiedAt"
        case .type: return "extension"
        case .size: return "size"
        }
    }
}

// MARK: - ViewMode

enum ViewMode: String, CaseIterable {
    case list = "list"
    case grid = "grid"
}

// MARK: - PaneState

struct PaneState {
    var path: String = ""
    var history: [String] = []
    var historyIndex: Int = 0
    var files: [FileEntry] = []
    var selectedFiles: [FileEntry] = []  // 有序数组，支持 Shift/Cmd 选择
    var isLoading: Bool = false
    var error: String?
    var searchQuery: String = ""
    var sortField: SortField = .name
    var sortAscending: Bool = true
    var viewMode: ViewMode = .list
    var groupBy: String = "none"
}

// MARK: - PaneViewModel

public class PaneViewModel: ObservableObject {
    @Published var state: PaneState = PaneState()

    /// 由 MainWindowController 注入，用于注册撤销/重做（per-window UndoManager）
    weak var undoManager: UndoManager?

    /// 线程安全策略：所有 `state` 的读写原则上在主线程进行（@Published 触发 UI 刷新
    /// 也要求主线程）。后台异步任务（如 `loadDirectory`）必须在派发到后台队列前
    /// 捕获所需字段的不可变快照，避免与主线程并发写入造成数据竞争。
    /// 选中状态（selectedFiles）与排序过滤状态（sortField/sortAscending/searchQuery）
    /// 仅由 UI 在主线程修改，后台线程不直接访问，从而避免竞争。

    var currentPath: String { state.path }
    var files: [FileEntry] { state.files }
    var selectedFiles: [FileEntry] { state.selectedFiles }
    var isLoading: Bool { state.isLoading }
    var error: String? { state.error }

    /// 选中条目（计算属性，用于 DetailsBar）
    var selectedEntries: [FileEntry] { state.selectedFiles }

    /// 任务 F10-10: 当前目录的完整文件列表快照（已排序，未过滤）。
    /// 修复问题11辅助：applyFilter 此前基于 state.files 过滤，而 state.files 在搜索时
    /// 已被缩小为子集，导致用户删字回退搜索时无法恢复被过滤掉的项目。
    /// 引入 allFiles 保存原始列表，applyFilter 始终从 allFiles 过滤到 state.files。
    private var allFiles: [FileEntry] = []

    init() {}

    init(path: String) {
        state.path = path
        state.history = [path]
        state.historyIndex = 0
        loadDirectory()
    }

    // MARK: - Navigation

    func navigate(to path: String) {
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

    // MARK: - Selection (有序数组)

    func selectFile(_ file: FileEntry, multi: Bool = false, shiftKey: Bool = false) {
        if shiftKey, let lastSelected = state.selectedFiles.last {
            if let startIndex = state.files.firstIndex(where: { $0.path == lastSelected.path }),
               let endIndex = state.files.firstIndex(where: { $0.path == file.path }) {
                let range = min(startIndex, endIndex)...max(startIndex, endIndex)
                state.selectedFiles = Array(state.files[range])
            }
        } else if multi {
            if let idx = state.selectedFiles.firstIndex(where: { $0.path == file.path }) {
                state.selectedFiles.remove(at: idx)
            } else {
                state.selectedFiles.append(file)
            }
        } else {
            state.selectedFiles = [file]
        }
    }

    func clearSelection() {
        state.selectedFiles.removeAll()
    }

    func selectAll() {
        state.selectedFiles = state.files
    }

    /// 通过路径选择文件（用于 NSTableView 行选择回调）
    func selectByPath(_ path: String, multi: Bool = false, shiftKey: Bool = false) {
        guard let entry = state.files.first(where: { $0.path == path }) else { return }
        selectFile(entry, multi: multi, shiftKey: shiftKey)
    }

    // MARK: - Sorting & Filtering

    func setSortField(_ field: SortField, ascending: Bool? = nil) {
        state.sortField = field
        if let asc = ascending { state.sortAscending = asc }
        applySort()
    }

    func toggleSortDirection() {
        state.sortAscending.toggle()
        applySort()
    }

    func setGroupBy(_ groupBy: String) {
        state.groupBy = groupBy
        applySort()
    }

    // MARK: - 任务 F10-8: 分组聚合（v0.6.6 仿访达）

    /// 分组后的文件列表（按种类/日期/大小聚合）。
    /// - groupBy == "none" 时返回单个分组 "全部"，包含所有文件
    /// - 其余维度返回有序分组，组内顺序与 state.files 一致（state.files 已由 applySort 排序），
    ///   因此"排序在分组内生效"：先排序再分组的实现保证组内顺序正确，
    ///   但组的整体顺序由本方法决定（仿访达：种类/日期/大小各有固定顺序）
    ///
    /// 注意：返回值使用元组 (key, entries)，元组在 Swift 中无法直接作为 @Published
    /// 触发 UI 刷新，UI 层应通过监听 $state 变化后调用此计算属性获取最新分组。
    var groupedFiles: [(key: String, entries: [FileEntry])] {
        guard state.groupBy != "none" else {
            return [(key: "全部", entries: state.files)]
        }
        switch state.groupBy {
        case "kind": return groupByKind()
        case "date": return groupByDate()
        case "size": return groupBySize()
        default: return [(key: "全部", entries: state.files)]
        }
    }

    /// 按种类分组（仿访达）。
    /// 分组顺序：文件夹 → 图片 → 文档 → 视频 → 音频 → 其他
    /// 组内顺序保持 state.files 原序（已排序）。
    private func groupByKind() -> [(key: String, entries: [FileEntry])] {
        // 预定义分组顺序与键名
        let order: [(key: String, test: (FileEntry) -> Bool)] = [
            ("文件夹", { $0.isDirectory }),
            ("图片", { FileEntryKind.imageExtensions.contains($0.fileExtension) }),
            ("文档", { FileEntryKind.documentExtensions.contains($0.fileExtension) }),
            ("视频", { FileEntryKind.videoExtensions.contains($0.fileExtension) }),
            ("音频", { FileEntryKind.audioExtensions.contains($0.fileExtension) }),
            ("其他", { _ in true }),
        ]
        // 按 state.files 原序遍历，分桶到首个匹配组（保持组内已排序顺序）
        var buckets: [String: [FileEntry]] = [:]
        for entry in state.files {
            for (key, test) in order {
                if test(entry) {
                    buckets[key, default: []].append(entry)
                    break
                }
            }
        }
        // 按 order 顺序输出非空分组
        return order.compactMap { (key, _) in
            buckets[key].map { (key, $0) }
        }
    }

    /// 按修改日期分组（仿访达）。
    /// 分组顺序：今天 → 昨天 → 本周 → 本月 → 更早
    /// 本周/本月的起始按 Calendar.current 的自然周/月计算（本周从本周日开始或区域设置默认起始日）。
    private func groupByDate() -> [(key: String, entries: [FileEntry])] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        let monthInterval = calendar.dateInterval(of: .month, for: now)
        let startOfWeek = weekInterval?.start ?? startOfToday
        let startOfMonth = monthInterval?.start ?? startOfToday

        let order: [(key: String, test: (Date) -> Bool)] = [
            ("今天", { $0 >= startOfToday }),
            ("昨天", { $0 >= startOfYesterday && $0 < startOfToday }),
            ("本周", { $0 >= startOfWeek && $0 < startOfYesterday }),
            ("本月", { $0 >= startOfMonth && $0 < startOfWeek }),
            ("更早", { _ in true }),
        ]
        var buckets: [String: [FileEntry]] = [:]
        for entry in state.files {
            for (key, test) in order {
                if test(entry.modificationDate) {
                    buckets[key, default: []].append(entry)
                    break
                }
            }
        }
        return order.compactMap { (key, _) in
            buckets[key].map { (key, $0) }
        }
    }

    /// 按大小分组（仿访达，仅对文件分桶，文件夹归入"更小"）。
    /// 分组顺序：>1GB → >100MB → >10MB → >1MB → 更小
    /// ">100MB" 表示 100MB ~ 1GB 区间，依此类推（按顺序首个匹配）。
    private func groupBySize() -> [(key: String, entries: [FileEntry])] {
        let _1MB: UInt64 = 1_048_576
        let _10MB: UInt64 = 10 * _1MB
        let _100MB: UInt64 = 100 * _1MB
        let _1GB: UInt64 = 1024 * _1MB

        let order: [(key: String, test: (FileEntry) -> Bool)] = [
            (">1GB", { !$0.isDirectory && $0.size >= _1GB }),
            (">100MB", { !$0.isDirectory && $0.size >= _100MB }),
            (">10MB", { !$0.isDirectory && $0.size >= _10MB }),
            (">1MB", { !$0.isDirectory && $0.size >= _1MB }),
            ("更小", { _ in true }),
        ]
        var buckets: [String: [FileEntry]] = [:]
        for entry in state.files {
            for (key, test) in order {
                if test(entry) {
                    buckets[key, default: []].append(entry)
                    break
                }
            }
        }
        return order.compactMap { (key, _) in
            buckets[key].map { (key, $0) }
        }
    }

    func setSearchQuery(_ query: String) {
        state.searchQuery = query
        // 任务 F10-10: 始终走 applyFilter（基于 allFiles），避免搜索清空时重新读盘（修复问题11辅助）
        // applyFilter 在 query 为空时恢复 allFiles，非空时从 allFiles 过滤
        applyFilter()
    }

    func setViewMode(_ mode: ViewMode) {
        state.viewMode = mode
    }

    // MARK: - File Operations

    func deleteSelected() {
        let toDelete = state.selectedFiles
        guard !toDelete.isEmpty else { return }

        // 使用 FileManager.trashItem 移到废纸篓（与 macOS Finder 行为一致），
        // 并保留 trashURL 用于撤销时恢复。trashItem 必须在主线程调用，
        // deleteSelected 由菜单/右键菜单触发，已在主线程。
        var trashedItems: [(originalPath: String, trashURL: URL)] = []
        var failedCount = 0

        for entry in toDelete {
            let url = URL(fileURLWithPath: entry.path)
            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                if let trashURL = resultingURL as URL? {
                    trashedItems.append((originalPath: entry.path, trashURL: trashURL))
                }
            } catch {
                failedCount += 1
            }
        }

        if !trashedItems.isEmpty {
            // 失效缓存以反映删除（best-effort，缓存错误不阻塞 UI）
            let parentDir = (trashedItems[0].originalPath as NSString).deletingLastPathComponent
            try? CoreBridge.shared.invalidateCache(path: parentDir)

            // 注册撤销：从废纸篓恢复（moveItem 回原路径）
            let items = trashedItems
            let originalDir = items.first.map { ($0.originalPath as NSString).deletingLastPathComponent } ?? ""
            undoManager?.registerUndo(withTarget: self) { vm in
                var restoreFailed = 0
                for (originalPath, trashURL) in items {
                    do {
                        try FileManager.default.moveItem(at: trashURL, to: URL(fileURLWithPath: originalPath))
                    } catch {
                        // I3: 原路径已被占用等原因导致恢复失败，记录并反馈
                        restoreFailed += 1
                    }
                }
                // 失效缓存以反映恢复
                if let firstPath = items.first?.originalPath {
                    let dir = (firstPath as NSString).deletingLastPathComponent
                    try? CoreBridge.shared.invalidateCache(path: dir)
                }
                // 注册 redo：重新移入废纸篓
                vm.undoManager?.registerUndo(withTarget: vm) { vm2 in
                    for (originalPath, _) in items {
                        try? FileManager.default.trashItem(at: URL(fileURLWithPath: originalPath), resultingItemURL: nil)
                    }
                    vm2.loadDirectory()
                }
                vm.undoManager?.setActionName("删除 \(items.count) 个项目")
                if restoreFailed > 0 {
                    vm.state.error = "\(restoreFailed) 个项目无法恢复（原路径已被占用）"
                }
                // I4: 仅当 VM 仍在原目录时才刷新（用户可能已导航离开），
                // 文件已恢复到原位置，用户导航回去后自然可见。
                if vm.state.path == originalDir {
                    vm.loadDirectory()
                }
            }
            undoManager?.setActionName("删除 \(trashedItems.count) 个项目")

            state.selectedFiles.removeAll()
            loadDirectory()
        }

        if failedCount > 0 {
            state.error = "\(failedCount) 个项目删除失败"
        }
    }

    func renameFile(_ oldPath: String, to newName: String) {
        let dir = (oldPath as NSString).deletingLastPathComponent
        let newPath = (dir as NSString).appendingPathComponent(newName)
        do {
            try CoreBridge.shared.renameFile(src: oldPath, dst: newPath)
            // 注册撤销：undo 闭包内调用 renameFile 反向重命名，
            // NSUndoManager 在 undo 模式下会将 registerUndo 加入 redo 栈，
            // 因此 redo 自动支持，且不会无限递归。
            let oldName = (oldPath as NSString).lastPathComponent
            undoManager?.registerUndo(withTarget: self) { vm in
                vm.renameFile(newPath, to: oldName)
            }
            undoManager?.setActionName("重命名")
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

        // 在派发到后台队列前捕获 state 的不可变快照，避免后台线程读取 `state`
        // 与主线程并发写入（如用户在加载过程中导航/排序）造成数据竞争。
        let path = state.path
        let sortField = state.sortField
        let sortAscending = state.sortAscending

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let entries = try CoreBridge.shared.listDirectory(path: path)
                // 在后台线程完成排序，避免阻塞 UI；使用捕获的快照而非读取 self.state
                let sortedEntries = self.sortEntries(entries, field: sortField, ascending: sortAscending)
                DispatchQueue.main.async {
                    // 任务 F10-10: 保存原始列表到 allFiles，applyFilter 始终基于 allFiles 过滤（修复问题11辅助）
                    self.allFiles = sortedEntries
                    // 若当前有搜索查询，过滤后赋值；否则直接赋值完整列表
                    if self.state.searchQuery.isEmpty {
                        self.state.files = sortedEntries
                    } else {
                        let query = self.state.searchQuery.lowercased()
                        self.state.files = sortedEntries.filter { $0.name.lowercased().contains(query) }
                    }
                    self.state.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.state.error = error.localizedDescription
                    self.state.isLoading = false
                }
            }
        }
    }

    /// 在后台线程排序（不触发 @Published 变更）。
    /// 排序字段与方向通过参数传入（快照），避免读取 `state` 造成数据竞争。
    private func sortEntries(_ entries: [FileEntry], field: SortField, ascending: Bool) -> [FileEntry] {
        return entries.sorted { a, b in
            let comparison: Bool
            switch field {
            case .name:
                comparison = a.sortName.localizedCaseInsensitiveCompare(b.sortName) == .orderedAscending
            case .modifiedAt:
                comparison = a.modificationDate < b.modificationDate
            case .type:
                comparison = a.fileExtension.localizedCaseInsensitiveCompare(b.fileExtension) == .orderedAscending
            case .size:
                comparison = a.size < b.size
            }
            return ascending ? comparison : !comparison
        }
    }

    private func applySort() {
        // 任务 F10-10: 排序基于 allFiles（原始列表），避免在已过滤子集上排序导致丢失项目（修复问题11辅助）
        let sorted = sortEntries(allFiles, field: state.sortField, ascending: state.sortAscending)
        // 同步更新 allFiles 为排序后顺序
        allFiles = sorted
        // 若当前有搜索查询，过滤后赋值；否则直接赋值完整列表
        if state.searchQuery.isEmpty {
            // 仅在顺序实际变化时才更新（减少不必要的 reloadData）
            if sorted.map(\.path) != state.files.map(\.path) {
                state.files = sorted
            }
        } else {
            let query = state.searchQuery.lowercased()
            state.files = sorted.filter { $0.name.lowercased().contains(query) }
        }
    }

    private func applyFilter() {
        guard !state.searchQuery.isEmpty else {
            // 搜索清空：恢复完整列表（基于 allFiles，确保退格回退时项目全部恢复）
            state.files = allFiles
            return
        }
        // 任务 F10-10: 始终从 allFiles 过滤，而非从已缩小的 state.files 过滤（修复问题11辅助）
        // 此前从 state.files 过滤，导致用户删字回退搜索时无法恢复被过滤掉的项目
        let query = state.searchQuery.lowercased()
        state.files = allFiles.filter { $0.name.lowercased().contains(query) }
    }
}

// MARK: - FileEntryKind（任务 F10-8 分组辅助）

/// 文件种类分组用的扩展名集合（小写）。
/// 与 FileEntry.kindDescription 的分类保持视觉一致，但聚合到分组维度。
enum FileEntryKind {
    /// 图片扩展名
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp",
        "heic", "heif", "svg", "raw", "cr2", "nef", "arw", "psd", "ico",
    ]
    /// 文档扩展名（文本/办公文档/PDF/代码等可读文档）
    static let documentExtensions: Set<String> = [
        "pdf", "txt", "md", "rtf", "doc", "docx", "xls", "xlsx",
        "ppt", "pptx", "pages", "numbers", "key", "html", "htm",
        "css", "js", "ts", "json", "xml", "yaml", "yml", "csv",
        "py", "rb", "go", "rs", "java", "c", "cpp", "h", "hpp",
        "swift", "sh", "sql", "log", "epub",
    ]
    /// 视频扩展名
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv", "webm",
        "mpeg", "mpg", "3gp", "mts", "m2ts", "vob",
    ]
    /// 音频扩展名
    static let audioExtensions: Set<String> = [
        "mp3", "wav", "aac", "m4a", "flac", "ogg", "wma", "aiff",
        "aif", "alac", "opus", "amr",
    ]
}
