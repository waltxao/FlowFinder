import Foundation
import Combine
import AppKit  // v0.7.4 项 6: createFolderFromSelection 使用 NSWindow 弹冲突框

// MARK: - 任务 T10 通知

extension Notification.Name {
    /// 任务 T10: 删除/撤销/重做文件系统操作状态变更通知。
    /// 后台 I/O 完成回主线程更新 state 后发出，供 Wave4 T12 的 UI 订阅
    /// （展示删除进度/失败详情）。本任务只保证状态机与通知正确，不改 UI 外观。
    ///
    /// userInfo 键（均可选，按操作类型填充）:
    /// - "path": String，操作发生的目录路径
    /// - "deletedCount": Int，成功移入废纸篓/删除的条目数
    /// - "restoredCount": Int，成功恢复的条目数
    /// - "failedPaths": [String]，失败的路径列表（typed）
    static let paneFileOperationChanged = Notification.Name("PaneFileOperationChanged")
}

// MARK: - SortField

enum SortField: String, CaseIterable, Equatable {
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

enum ViewMode: String, CaseIterable, Equatable {
    case list = "list"
    case grid = "grid"
}

/// 面板内搜索的硬上限（与 performRecursiveSearch 共用）。
enum FFSearchPolicy {
    static let maxDepth = 3
    static let maxResults = 500
}

/// J2-07 搜索范围。
enum FFSearchScope: String, CaseIterable, Equatable {
    case current = "本栏"
    case recursive = "含子目录"
    case bothPanes = "双栏"

    var title: String { rawValue }
    var searchesSubdirectories: Bool { self == .recursive }
    var searchesBothPanes: Bool { self == .bothPanes }
}

// MARK: - PaneState

struct PaneState: Equatable {
    var path: String = ""
    var history: [String] = []
    var historyIndex: Int = 0
    var files: [FileEntry] = []
    var selectedFiles: [FileEntry] = []  // 有序数组，支持 Shift/Cmd 选择
    var isLoading: Bool = false
    var error: String?
    var searchQuery: String = ""
    var searchScope: FFSearchScope = .current
    var sortField: SortField = .name
    var sortAscending: Bool = true
    var viewMode: ViewMode = .list
    var groupBy: String = "none"
    /// 2026-10-21 Phase 5：多标签 AND 筛选（⌘ 点选累加）。
    var tagFilters: [Tag] = []
    /// 兼容旧调用：单标签读写映射到数组首项。
    var tagFilter: Tag? {
        get { tagFilters.first }
        set { tagFilters = newValue.map { [$0] } ?? [] }
    }
    /// 任务 T10: 删除/撤销/重做文件系统操作进行中标志。
    /// 后台 I/O 执行期间为 true，完成回主线程后置 false。供 Wave4 T12 UI 展示进度/禁用重复操作。
    var isDeleting: Bool = false
    /// 任务 T10: 最近一次删除/恢复失败的路径列表（typed 结构化失败文件名列表）。
    /// 空数组表示无失败。供 Wave4 T12 UI 统一展示失败详情。
    var deleteFailedPaths: [String] = []
}

// MARK: - PaneViewModel

public class PaneViewModel: ObservableObject {
    @Published var state: PaneState = PaneState()

    /// 由 MainWindowController 注入，用于注册撤销/重做（per-window UndoManager）
    weak var undoManager: UndoManager?

    /// Wave1 P0-2：底部任务进度条（弱引用，由 MainWindowController 注入，
    /// 与 undoManager 注入模式一致）。「用所选项目新建文件夹」等批量移动操作
    /// 经直连进度模式（startDirectProgress/updateDirectProgress/completeDirectProgress）
    /// 反馈进度；仅在主线程调用其 API。
    weak var taskProgressBar: TaskProgressBar?

    /// Wave1 P0-2：底部进度栏容器展开/收起钩子（由 MainWindowController 注入）。
    /// TaskProgressBar 直连 API 只控制视图自身 isHidden，容器高度约束归窗口层
    /// 管理（showProgressBar/hideProgressBar 为窗口层私有实现）；未注入时操作
    /// 照常执行，仅无进度栏展开/收起表现。
    var progressBarsExpanded: (() -> Void)?
    var progressBarsCollapsed: (() -> Void)?

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

    /// 任务 F10-10: 当前目录的完整文件列表快照（已排序，未过滤）。
    /// 修复问题11辅助：applyFilter 此前基于 state.files 过滤，而 state.files 在搜索时
    /// 已被缩小为子集，导致用户删字回退搜索时无法恢复被过滤掉的项目。
    /// 引入 allFiles 保存原始列表，applyFilter 始终从 allFiles 过滤到 state.files。
    private var allFiles: [FileEntry] = []

    /// 当前目录原始列表的只读视图（未经过搜索/标签/显示过滤）。
    /// 标签计数需要这个基数：用 `state.files` 会让「筛选中某标签」时
    /// 该标签自己的计数塌缩为筛后条数，失去参考意义。
    var unfilteredFiles: [FileEntry] { allFiles }

    /// 任务 F11-11: 大目录分页加载状态（C5）。
    /// 为避免 10 万+ 文件一次性渲染卡顿，loadDirectory 后首批 pageSize 条立即显示，
    /// 其余按 pageSize 分批异步追加（DispatchQueue.main.asyncAfter）。
    /// 任何会重置列表的操作（loadDirectory/applySort/applyFilter 由搜索/标签触发）
    /// 都须先 cancelPagination() 取消挂起的追加任务，避免竞态覆盖。
    private var paginationWorkItems: [DispatchWorkItem] = []
    /// 分页每批大小（首批与追加批均为 500 条）
    private let paginationPageSize: Int = 500
    /// 任务 F10-10: 搜索防抖任务。快速输入时取消上一次挂起的递归搜索，300ms 后只触发一次。
    private var searchDebounceWorkItem: DispatchWorkItem?
    /// 任务 F11-11: loadDirectory 的加载代次（C5）。
    /// 每次发起新 loadDirectory 时自增，后台完成回主线程时校验代次一致才应用结果，
    /// 避免快速导航时旧后台加载覆盖新加载（竞态导致显示错误目录内容）。
    private var loadGeneration: Int = 0
    /// 搜索双击定位：加载完成后自动选中的目标路径。
    private var pendingSelectionPath: String?
    /// 一次性钩子：本轮加载完成（选中项已落地、视图已 reload）后执行一次（R4-18 新建文件夹）。
    private var afterLoadReady: (() -> Void)?
    /// 刷新同目录时按设置保留的选中路径（批次 1 B1-02）。
    private var pendingRestoredSelectionPaths: [String]?
    /// 任务 T10: 删除/撤销/重做文件系统操作代次。
    /// 每次发起新的删除/撤销/重做时自增；后台完成回主线程时校验代次一致才应用结果，
    /// 避免快速连续操作（删除→删除、删除→撤销→重做）的后台完成回调互相覆盖 UI 状态。
    private var deleteOperationGeneration: Int = 0
    /// 重命名后待发的内容变更通知标志（加载完成后发出，确保视图读到新数据）
    private var pendingContentChangeNotification = false

    init() {}

    init(path: String) {
        state.path = path
        state.history = [path]
        state.historyIndex = 0
        loadDirectory()
    }

    // MARK: - Navigation

    func navigate(to path: String, selecting itemPath: String? = nil) {
        // 防重复：导航到当前路径时不产生新历史条目
        if path == state.path {
            state.searchQuery = ""
            state.tagFilter = nil  // 任务 F11-8: 导航时清除标签筛选（与 searchQuery 一致）
            state.error = nil
            if let itemPath {
                if let entry = state.files.first(where: { $0.path == itemPath }) {
                    state.selectedFiles = [entry]
                } else {
                    // 目标不在当前列表里（列表还没到、或对象是列表之后才出现的）：
                    // 先失效目录缓存再重读，落地后选中。此前直接清空选择，
                    // 「定位到该任务对象」点了等于没点（R4-24）。
                    pendingSelectionPath = itemPath
                    state.selectedFiles.removeAll()
                    try? CoreBridge.shared.invalidateCache(path: state.path)
                    loadDirectory()
                }
            } else {
                state.selectedFiles.removeAll()
            }
            return
        }
        pendingSelectionPath = itemPath
        if state.historyIndex < state.history.count - 1 {
            state.history = Array(state.history.prefix(state.historyIndex + 1))
        }
        state.history.append(path)
        // 历史上限：超出时裁掉最旧条目，防止无限增长
        if state.history.count > 500 {
            state.history.removeFirst(state.history.count - 500)
        }
        state.historyIndex = state.history.count - 1
        state.path = path
        state.selectedFiles.removeAll()
        state.searchQuery = ""
        state.tagFilter = nil  // 任务 F11-8: 导航时清除标签筛选（与 searchQuery 一致）
        state.error = nil
        loadDirectory()
    }

    func goBack() -> Bool {
        guard state.historyIndex > 0 else { return false }
        state.historyIndex -= 1
        state.path = state.history[state.historyIndex]
        state.selectedFiles.removeAll()
        state.searchQuery = ""
        state.tagFilter = nil  // 任务 F11-8: 导航时清除标签筛选
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
        state.tagFilter = nil  // 任务 F11-8: 导航时清除标签筛选
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
        // 批次 1 B1-02：刷新保持选中（默认关）。关闭时刷新即清空选中；
        // 打开时先记下路径，加载完成后只恢复仍然存在的项。
        if FFAppSettings.keepSelectionPosition() {
            pendingRestoredSelectionPaths = state.selectedFiles.map(\.path)
        } else {
            pendingRestoredSelectionPaths = nil
            state.selectedFiles = []
        }
        // 刷新前先失效缓存；FFI 放后台，完成后回主线程再重新加载，
        // 既保证顺序又不在主线程等待信号量。
        let path = state.path
        CoreBridge.shared.invalidateCacheAsync(path: path) { [weak self] in
            self?.loadDirectory()
        }
    }

    // MARK: - 标签页会话（2026-10-18 #7）

    /// 捕获当前完整浏览状态（路径 / 前进后退历史 / 排序 / 视图模式 / 分组 / 标签筛选）
    func captureSession() -> PaneState { state }

    /// 恢复一个标签的浏览状态：整体替换 state 后重新列举当前路径。
    /// 不清空 history——标签页切换要保留各自的返回栈。
    func restoreSession(_ session: PaneState) {
        state = session
        refresh()
    }

    // MARK: - Selection (有序数组)

    func selectFile(_ file: FileEntry, multi: Bool = false, shiftKey: Bool = false) {
        if shiftKey, let lastSelected = state.selectedFiles.last {
            if let startIndex = state.files.firstIndex(where: { $0.path == lastSelected.path }),
               let endIndex = state.files.firstIndex(where: { $0.path == file.path }) {
                let range = min(startIndex, endIndex)...max(startIndex, endIndex)
                state.selectedFiles = Array(state.files[range])
            } else {
                // lastSelected 不在当前过滤列表（如筛选后）时，退化为单选，避免 shift 静默失效
                state.selectedFiles = [file]
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
    /// v0.7.4 根因修复：移除签名缓存！原缓存用 groupBy+count+首尾路径做 key，
    /// 改名中间位置文件时 key 不变 -> 返回旧数据（含旧名字的 FileEntry）->
    /// rebuildDisplayRows 用旧路径查新索引失败 -> 文件从列表消失/显示旧名字。
    /// 运行时证据 [RENDER-DIAG]：groupedFiles=[logo12.png] vs state.files=[133.png] 不一致。
    /// 移除缓存后每次都从 state.files 实时计算，确保数据一致。
    /// 性能影响可忽略：分组遍历是 O(n)，与 rebuildDisplayRows 本身的 O(n) 同级，
    /// 且只在 reloadData 时调用（非滚动时高频调用）。
    var groupedFiles: [(key: String, entries: [FileEntry])] {
        return computeGroupedFiles()
    }

    private func computeGroupedFiles() -> [(key: String, entries: [FileEntry])] {
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
        // J2-07：只有「含子目录」才调度递归；本栏/双栏只过滤当前目录。
        if query.isEmpty {
            searchDebounceWorkItem?.cancel()
            searchDebounceWorkItem = nil
            applyFilter()
        } else {
            applyFilter()
            searchDebounceWorkItem?.cancel()
            searchDebounceWorkItem = nil
            guard state.searchScope.searchesSubdirectories else { return }
            let workItem = DispatchWorkItem { [weak self] in
                self?.performRecursiveSearch(query: query)
            }
            searchDebounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }
    }

    /// J2-07：切换搜索范围后立即重算当前过滤；离开「含子目录」会取消挂起的递归任务。
    func setSearchScope(_ scope: FFSearchScope) {
        guard state.searchScope != scope else { return }
        state.searchScope = scope
        searchDebounceWorkItem?.cancel()
        searchDebounceWorkItem = nil
        guard !state.searchQuery.isEmpty else {
            applyFilter()
            return
        }
        setSearchQuery(state.searchQuery)
    }

    /// 任务 F11-8: 设置标签筛选（点击侧边栏标签触发）。
    /// - 传入 tag 非空：仅显示含该标签的文件（在当前目录直接子项基础上过滤）
    /// - 传入 tag 为 nil：取消标签筛选，恢复完整列表
    /// - 再次点击当前已筛选的同一标签：自动取消（tagFilter 置 nil）
    func setTagFilter(_ tag: Tag?) {
        if let tag = tag, state.tagFilter?.id == tag.id {
            // 再次点击同一标签 -> 取消筛选
            state.tagFilter = nil
        } else {
            state.tagFilter = tag
        }
        applyFilter()
    }

    /// ⌘ 点选：累加/移除一个标签；普通点选：只保留该标签（再点一次取消）。
    func toggleTagFilter(_ tag: Tag, additive: Bool) {
        let key = TagIndexStore.normalize(tag.name)
        if additive {
            if let index = state.tagFilters.firstIndex(where: {
                TagIndexStore.normalize($0.name) == key
            }) {
                state.tagFilters.remove(at: index)
            } else {
                state.tagFilters.append(tag)
            }
        } else if state.tagFilters.count == 1,
                  TagIndexStore.normalize(state.tagFilters[0].name) == key {
            state.tagFilters = []
        } else {
            state.tagFilters = [tag]
        }
        applyFilter()
    }

    func setViewMode(_ mode: ViewMode) {
        state.viewMode = mode
    }

    // MARK: - File Operations

    func deleteSelected() {
        let toDelete = state.selectedFiles
        guard !toDelete.isEmpty else { return }

        // 任务 T10: 代次自增标记本次删除操作，后台完成回调按代次校验避免快速连续操作互相覆盖。
        let generation = { self.deleteOperationGeneration += 1; return self.deleteOperationGeneration }()
        state.isDeleting = true
        state.deleteFailedPaths = []
        state.error = nil

        // 任务 T10: 文件系统 I/O（trashItem）移到后台队列，避免大量文件/慢盘/SMB 阻塞主线程。
        // 主线程只负责 UndoManager 注册与 UI 更新（在后台完成回调 finishDelete 内进行）。
        FFDebug.log("[DELETE-DIAG] deleteSelected 派发后台 count=\(toDelete.count) generation=\(generation) isMainThread=\(Thread.isMainThread)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            FFDebug.log("[DELETE-DIAG] deleteSelected 后台开始 count=\(toDelete.count) isMainThread=\(Thread.isMainThread)")
            var trashedItems: [(originalPath: String, trashURL: URL)] = []
            var failedPaths: [String] = []
            for entry in toDelete {
                let url = URL(fileURLWithPath: entry.path)
                do {
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                    if let trashURL = resultingURL as URL? {
                        trashedItems.append((originalPath: entry.path, trashURL: trashURL))
                    }
                } catch {
                    failedPaths.append(entry.path)
                }
            }
            FFDebug.log("[DELETE-DIAG] deleteSelected 后台完成 成功=\(trashedItems.count) 失败=\(failedPaths.count)")
            DispatchQueue.main.async {
                guard self.deleteOperationGeneration == generation else {
                    FFDebug.log("[DELETE-DIAG] deleteSelected 丢弃过期完成 generation=\(generation) 当前=\(self.deleteOperationGeneration)")
                    return
                }
                self.finishDelete(toDelete: toDelete, trashedItems: trashedItems, failedPaths: failedPaths)
            }
        }
    }

    /// 任务 T10: 后台删除完成后的主线程收尾。
    /// 负责：注册撤销（必须主线程）、多目录缓存失效、失败项保留选中集、更新错误状态、发通知、刷新列表。
    private func finishDelete(toDelete: [FileEntry],
                              trashedItems: [(originalPath: String, trashURL: URL)],
                              failedPaths: [String]) {
        state.isDeleting = false
        state.deleteFailedPaths = failedPaths

        if !trashedItems.isEmpty {
            // 失效所有涉及目录的父缓存（多目录选择时逐目录失效，而非只失效第一个）
            let parentDirs = Self.parentDirectories(of: trashedItems.map { $0.originalPath })
            for dir in parentDirs {
                try? CoreBridge.shared.invalidateCache(path: dir)
            }

            // 注册撤销：从废纸篓恢复（moveItem 回原路径）。undoTrashRestore 会同步注册 redo（redoTrashRestore），
            // 而 redoTrashRestore 处理器内又会注册反向 undo（= undoTrashRestore），从而形成无限撤销/重做闭环。
            let items = trashedItems
            let originalDir = items.first.map { ($0.originalPath as NSString).deletingLastPathComponent } ?? ""
            let actionName = "删除 \(items.count) 个项目"
            undoManager?.registerUndo(withTarget: self) { vm in
                vm.undoTrashRestore(items: items, originalDir: originalDir, actionName: actionName)
            }
            undoManager?.setActionName(actionName)
        }

        // 失败项保留在选中集（便于用户重试），成功项已移除
        if !failedPaths.isEmpty {
            let remaining = toDelete.filter { failedPaths.contains($0.path) }
            state.selectedFiles = remaining
            state.error = "\(failedPaths.count) 个项目删除失败：\(failedPaths.joined(separator: ", "))"
        } else {
            state.selectedFiles.removeAll()
        }

        if !trashedItems.isEmpty || !failedPaths.isEmpty {
            loadDirectory()
        }

        // 任务 T10: 状态变更通知（供 Wave4 T12 UI 订阅）
        NotificationCenter.default.post(
            name: .paneFileOperationChanged,
            object: nil,
            userInfo: [
                "path": state.path,
                "deletedCount": trashedItems.count,
                "failedPaths": failedPaths,
            ]
        )
    }

    // MARK: - 删除撤销辅助（无限撤销/重做闭环）

    /// 撤销"删除"：从废纸篓恢复文件（moveItem 回原路径），并同步注册 redo（redoTrashRestore）。
    /// redoTrashRestore 处理器内又会注册反向 undo（= undoTrashRestore），从而形成无限撤销/重做闭环：
    /// 撤销→重做→撤销→重做…可无限进行。
    func undoTrashRestore(items: [(originalPath: String, trashURL: URL)], originalDir: String, actionName: String) {
        // 必须先注册 redo 再执行恢复：registerUndo 在撤销会话内（isUndoing）会路由到 redo 栈，
        // 否则重做栈可能为空，撤销后无法重做。registerUndo 必须在主线程（此处即主线程）。
        undoManager?.registerUndo(withTarget: self) { vm in
            vm.redoTrashRestore(items: items, actionName: actionName)
        }

        // 任务 T10: moveItem I/O 移到后台队列，避免阻塞主线程。
        let generation = { self.deleteOperationGeneration += 1; return self.deleteOperationGeneration }()
        state.isDeleting = true
        state.deleteFailedPaths = []
        state.error = nil

        FFDebug.log("[DELETE-DIAG] undoTrashRestore 派发后台 count=\(items.count) generation=\(generation) isMainThread=\(Thread.isMainThread)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var restoreFailed = 0
            var failedPaths: [String] = []
            for (originalPath, trashURL) in items {
                do {
                    try FileManager.default.moveItem(at: trashURL, to: URL(fileURLWithPath: originalPath))
                } catch {
                    // I3: 原路径已被占用等原因导致恢复失败，记录并反馈
                    restoreFailed += 1
                    failedPaths.append(originalPath)
                }
            }
            DispatchQueue.main.async {
                guard self.deleteOperationGeneration == generation else { return }
                self.state.isDeleting = false
                self.state.deleteFailedPaths = failedPaths
                // 失效缓存以反映恢复（多目录逐目录失效，与 deleteSelected 一致）
                let parentDirs = Self.parentDirectories(of: items.map { $0.originalPath })
                for dir in parentDirs {
                    try? CoreBridge.shared.invalidateCache(path: dir)
                }
                if restoreFailed > 0 {
                    self.state.error = "\(restoreFailed) 个项目无法恢复（原路径已被占用）"
                }
                // I4: 仅当 VM 仍在原目录时才刷新（用户可能已导航离开），
                // 文件已恢复到原位置，用户导航回去后自然可见。
                if self.state.path == originalDir {
                    self.loadDirectory()
                }
                NotificationCenter.default.post(
                    name: .paneFileOperationChanged,
                    object: nil,
                    userInfo: [
                        "path": self.state.path,
                        "restoredCount": items.count - restoreFailed,
                        "failedPaths": failedPaths,
                    ]
                )
            }
        }
    }

    /// 重做"删除"：把文件重新移入废纸篓（与初始删除相同）。
    /// 处理器内同步注册反向 undo（undoTrashRestore，路由到 undo 栈，isRedoing == true），
    /// 从而形成无限撤销/重做闭环。
    func redoTrashRestore(items: [(originalPath: String, trashURL: URL)], actionName: String) {
        // 先注册反向 undo 再执行移入废纸篓：registerUndo 在重做会话内（isRedoing）路由到 undo 栈。
        // registerUndo 必须在主线程（此处即主线程）。
        undoManager?.registerUndo(withTarget: self) { vm in
            let originalDir = items.first.map { ($0.originalPath as NSString).deletingLastPathComponent } ?? ""
            vm.undoTrashRestore(items: items, originalDir: originalDir, actionName: actionName)
        }

        // 任务 T10: trashItem I/O 移到后台队列，避免阻塞主线程。
        let generation = { self.deleteOperationGeneration += 1; return self.deleteOperationGeneration }()
        state.isDeleting = true
        state.deleteFailedPaths = []
        state.error = nil

        FFDebug.log("[DELETE-DIAG] redoTrashRestore 派发后台 count=\(items.count) generation=\(generation) isMainThread=\(Thread.isMainThread)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var failedPaths: [String] = []
            for (originalPath, _) in items {
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: originalPath), resultingItemURL: nil)
                } catch {
                    failedPaths.append(originalPath)
                }
            }
            DispatchQueue.main.async {
                guard self.deleteOperationGeneration == generation else { return }
                self.state.isDeleting = false
                self.state.deleteFailedPaths = failedPaths
                let parentDirs = Self.parentDirectories(of: items.map { $0.originalPath })
                for dir in parentDirs {
                    try? CoreBridge.shared.invalidateCache(path: dir)
                }
                if !failedPaths.isEmpty {
                    self.state.error = "\(failedPaths.count) 个项目无法重新删除"
                }
                self.loadDirectory()
                NotificationCenter.default.post(
                    name: .paneFileOperationChanged,
                    object: nil,
                    userInfo: [
                        "path": self.state.path,
                        "deletedCount": items.count - failedPaths.count,
                        "failedPaths": failedPaths,
                    ]
                )
            }
        }
    }

    // MARK: - J3-10 批量整理（预览后执行 + 整批一次撤销/重做）

    private var organizeOperationGeneration = 0

    /// 执行整理计划：后台逐项移动（永不覆盖已存在目标），完成后注册整批一次撤销。
    func performOrganize(plan: FFOrganizePlan, directory: String) {
        let moves = plan.moves
        let actionName = "批量整理"
        let generation = { self.organizeOperationGeneration += 1; return self.organizeOperationGeneration }()
        state.isDeleting = true
        state.error = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var movedPairs: [(source: String, target: String)] = []
            var failedPaths: [String] = []
            for move in moves {
                do {
                    try FileManager.default.createDirectory(atPath: move.targetDirectory,
                                                            withIntermediateDirectories: true)
                    try FileManager.default.moveItem(atPath: move.sourcePath, toPath: move.targetPath)
                    movedPairs.append((move.sourcePath, move.targetPath))
                } catch {
                    failedPaths.append(move.sourcePath)
                }
            }
            DispatchQueue.main.async {
                guard self.organizeOperationGeneration == generation else { return }
                self.finishOrganize(movedPairs: movedPairs, failedPaths: failedPaths,
                                    directory: directory, actionName: actionName)
            }
        }
    }

    private func finishOrganize(movedPairs: [(source: String, target: String)],
                                failedPaths: [String],
                                directory: String,
                                actionName: String) {
        state.isDeleting = false

        var dirs = Set<String>([directory])
        for pair in movedPairs {
            dirs.insert((pair.target as NSString).deletingLastPathComponent)
        }
        for dir in dirs {
            try? CoreBridge.shared.invalidateCache(path: dir)
        }

        let movedSources = Set(movedPairs.map { $0.source })
        state.selectedFiles.removeAll { movedSources.contains($0.path) }

        if !failedPaths.isEmpty {
            state.error = "\(failedPaths.count) 个项目整理失败：\(failedPaths.joined(separator: ", "))"
        }

        if !movedPairs.isEmpty {
            registerUndoOrganize(movedPairs: movedPairs, directory: directory, actionName: actionName)
        }

        if state.path == directory {
            loadDirectory()
        }
        NotificationCenter.default.post(
            name: .paneFileOperationChanged,
            object: nil,
            userInfo: [
                "path": state.path,
                "movedCount": movedPairs.count,
                "failedPaths": failedPaths,
            ]
        )
    }

    /// 注册整批撤销（主线程调用）。undoOrganize 内会同步注册 redo，形成闭环。
    private func registerUndoOrganize(movedPairs: [(source: String, target: String)],
                                      directory: String,
                                      actionName: String) {
        undoManager?.registerUndo(withTarget: self) { vm in
            vm.undoOrganize(movedPairs: movedPairs, directory: directory, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    /// 撤销整理：全部文件移回原位置，并同步注册 redo（registerUndo 在撤销会话内路由到 redo 栈）。
    func undoOrganize(movedPairs: [(source: String, target: String)],
                      directory: String,
                      actionName: String) {
        undoManager?.registerUndo(withTarget: self) { vm in
            vm.redoOrganize(movedPairs: movedPairs, directory: directory, actionName: actionName)
        }

        let generation = { self.organizeOperationGeneration += 1; return self.organizeOperationGeneration }()
        state.isDeleting = true
        state.error = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var failedPaths: [String] = []
            for pair in movedPairs {
                do {
                    try FileManager.default.moveItem(atPath: pair.target, toPath: pair.source)
                } catch {
                    failedPaths.append(pair.source)
                }
            }
            DispatchQueue.main.async {
                guard self.organizeOperationGeneration == generation else { return }
                self.state.isDeleting = false
                var dirs = Set<String>([directory])
                for pair in movedPairs {
                    dirs.insert((pair.target as NSString).deletingLastPathComponent)
                }
                for dir in dirs {
                    try? CoreBridge.shared.invalidateCache(path: dir)
                }
                if !failedPaths.isEmpty {
                    self.state.error = "\(failedPaths.count) 个项目无法撤销（目标被占用）"
                }
                if self.state.path == directory {
                    self.loadDirectory()
                }
                NotificationCenter.default.post(
                    name: .paneFileOperationChanged,
                    object: nil,
                    userInfo: [
                        "path": self.state.path,
                        "restoredCount": movedPairs.count - failedPaths.count,
                        "failedPaths": failedPaths,
                    ]
                )
            }
        }
    }

    /// 重做整理：重新执行移动（处理器内注册反向 undo，形成无限撤销/重做闭环）。
    func redoOrganize(movedPairs: [(source: String, target: String)],
                      directory: String,
                      actionName: String) {
        undoManager?.registerUndo(withTarget: self) { vm in
            vm.undoOrganize(movedPairs: movedPairs, directory: directory, actionName: actionName)
        }

        let generation = { self.organizeOperationGeneration += 1; return self.organizeOperationGeneration }()
        state.isDeleting = true
        state.error = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var failedPaths: [String] = []
            for pair in movedPairs {
                do {
                    try FileManager.default.moveItem(atPath: pair.source, toPath: pair.target)
                } catch {
                    failedPaths.append(pair.source)
                }
            }
            DispatchQueue.main.async {
                guard self.organizeOperationGeneration == generation else { return }
                self.state.isDeleting = false
                var dirs = Set<String>([directory])
                for pair in movedPairs {
                    dirs.insert((pair.target as NSString).deletingLastPathComponent)
                }
                for dir in dirs {
                    try? CoreBridge.shared.invalidateCache(path: dir)
                }
                if !failedPaths.isEmpty {
                    self.state.error = "\(failedPaths.count) 个项目无法重做"
                }
                if self.state.path == directory {
                    self.loadDirectory()
                }
                NotificationCenter.default.post(
                    name: .paneFileOperationChanged,
                    object: nil,
                    userInfo: [
                        "path": self.state.path,
                        "movedCount": movedPairs.count - failedPaths.count,
                        "failedPaths": failedPaths,
                    ]
                )
            }
        }
    }

    func renameFile(_ oldPath: String, to newName: String) {
        let dir = (oldPath as NSString).deletingLastPathComponent
        let newPath = (dir as NSString).appendingPathComponent(newName)
        FFDebug.log("[RENAME-DIAG] PaneState.renameFile: oldPath=\(oldPath) newName=\(newName) newPath=\(newPath)")
        // 安全检查：newName 不应包含路径分隔符（否则会跨目录移动文件导致"消失"）
        if newName.contains("/") {
            state.error = "文件名不能包含 \"/\""
            return
        }
        if newPath != oldPath,
           FileManager.default.fileExists(atPath: newPath),
           !isSameFile(oldPath, newPath) {
            state.error = "已存在同名文件，请换一个名称"
            return
        }
        do {
            try CoreBridge.shared.renameFile(src: oldPath, dst: newPath)
            FFDebug.log("[RENAME-DIAG] PaneState.renameFile: Rust ff_rename 成功")
            // 根因修复（v0.7.4）：改名成功后必须先失效目录缓存再刷新！
            // listDirectory 优先读 Rust 侧 dir_cache（LRU 缓存），缓存命中就直接用
            // 缓存数据、不访问真实文件系统。改名成功后若不失效缓存，loadDirectory
            // 会读到旧缓存（还显示旧文件名）→ 用户看到"名字变回旧值/文件消失"。
            // deleteSelected/undoTrashRestore/refresh 都先 invalidateCache 再 loadDirectory，
            // 唯独 renameFile 漏了这一步（历史多轮修复均聚焦读取环节，未发现此遗漏）。
            try? CoreBridge.shared.invalidateCache(path: dir)
            // v0.7.4 根因修复：groupedFiles 签名缓存已彻底移除（见 groupedFiles 属性注释），
            // 不再需要手动清空。缓存移除后每次都从 state.files 实时计算，数据始终一致。
            // 修复 2：更新 state.selectedFiles 中旧路径条目为新路径/新名字，
            // 否则详情栏/右键菜单/QuickLook 等仍读到旧名字。
            state.selectedFiles = state.selectedFiles.map { entry in
                if entry.path == oldPath {
                    return FileEntry(
                        path: newPath, name: newName, isDirectory: entry.isDirectory,
                        isFile: entry.isFile, isSymlink: entry.isSymlink,
                        isHidden: entry.isHidden, isSystemProtected: entry.isSystemProtected,
                        size: entry.size, modificationDate: entry.modificationDate,
                        creationDate: entry.creationDate, tags: entry.tags
                    )
                }
                return entry
            }
            // 注册撤销：undo 闭包内调用 renameFile 反向重命名，
            // NSUndoManager 在 undo 模式下会将 registerUndo 加入 redo 栈，
            // 因此 redo 自动支持，且不会无限递归。
            let oldName = (oldPath as NSString).lastPathComponent
            undoManager?.registerUndo(withTarget: self) { vm in
                vm.renameFile(newPath, to: oldName)
            }
            undoManager?.setActionName("重命名")
            // 重命名是"数量不变"操作：加载完成后需通知视图强制刷新（sink 只比较数量不刷新）。
            // 通知延迟到 loadDirectory 异步完成、state.files 已更新后发出（否则 reload 读到旧数据）。
            pendingContentChangeNotification = true
            loadDirectory()
        } catch {
            state.error = error.localizedDescription
            FFDebug.log("[RENAME-DIAG] PaneState.renameFile: Rust ff_rename 失败 \(error.localizedDescription)")
        }
    }

    private func isSameFile(_ firstPath: String, _ secondPath: String) -> Bool {
        let first = URL(fileURLWithPath: firstPath)
        let second = URL(fileURLWithPath: secondPath)
        guard let firstValues = try? first.resourceValues(forKeys: [.fileResourceIdentifierKey]),
              let secondValues = try? second.resourceValues(forKeys: [.fileResourceIdentifierKey]),
              let firstID = firstValues.fileResourceIdentifier,
              let secondID = secondValues.fileResourceIdentifier else {
            return false
        }
        return (firstID as AnyObject).isEqual(secondID)
    }

    /// 目录内不重名的「未命名文件夹」：已存在时依次追加序号（R4-18）。
    /// 此前写死同名，第二次新建会撞车。
    static func untitledFolderName(in directory: String) -> String {
        let base = FFNaming.untitledFolderBase
        let fm = FileManager.default
        var candidate = base
        var counter = 2
        while fm.fileExists(atPath: (directory as NSString).appendingPathComponent(candidate)) {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        return candidate
    }

    /// ⇧⌘N 新建文件夹：创建 → 刷新并选中新项 → 列表就绪后回调（R4-18）。
    ///
    /// 旧行为只创建+刷新：焦点回不到列表、新项也没选中，用户还得自己再按一次 F2
    /// 才能改名。回调在视图完成 reload 之后派发到主线程，视图层据此滚到新行并进入内联重命名。
    func createDirectoryThenRenaming(_ readyForRename: @escaping (String) -> Void) {
        let newPath = (state.path as NSString)
            .appendingPathComponent(Self.untitledFolderName(in: state.path))
        do {
            try CoreBridge.shared.createDirectory(path: newPath)
        } catch {
            state.error = error.localizedDescription
            return
        }
        registerUndoCreateFolder(folderPath: newPath)
        // 与 deleteSelected/refresh 一致：先失效目录缓存再加载，否则 L2 缓存回吐旧列表，
        // 新建的文件夹根本不在 state.files 里，选中与重命名都无从谈起。
        try? CoreBridge.shared.invalidateCache(path: state.path)
        pendingSelectionPath = newPath
        afterLoadReady = { readyForRename(newPath) }
        loadDirectory()
    }

    /// v0.7.4 修订 2：注册"新建文件夹"的撤销（删除该文件夹）与重做（重新创建）
    private func registerUndoCreateFolder(folderPath: String) {
        undoManager?.registerUndo(withTarget: self) { vm in
            // 撤销：删除该文件夹（先删除其中的内容，再删文件夹本身）
            try? FileManager.default.removeItem(atPath: folderPath)
            try? CoreBridge.shared.invalidateCache(path: vm.state.path)
            vm.loadDirectory()
            // 注册重做：重新创建
            vm.undoManager?.registerUndo(withTarget: vm) { vm2 in
                vm2.redoCreateFolder(folderPath: folderPath)
            }
            vm.undoManager?.setActionName("新建文件夹")
        }
        undoManager?.setActionName("新建文件夹")
    }

    /// 重做"新建文件夹"：重新创建该文件夹
    private func redoCreateFolder(folderPath: String) {
        try? CoreBridge.shared.createDirectory(path: folderPath)
        try? CoreBridge.shared.invalidateCache(path: state.path)
        loadDirectory()
        // 注册反向撤销
        undoManager?.registerUndo(withTarget: self) { vm in
            try? FileManager.default.removeItem(atPath: folderPath)
            try? CoreBridge.shared.invalidateCache(path: vm.state.path)
            vm.loadDirectory()
            vm.undoManager?.registerUndo(withTarget: vm) { vm2 in
                vm2.redoCreateFolder(folderPath: folderPath)
            }
            vm.undoManager?.setActionName("新建文件夹")
        }
        undoManager?.setActionName("新建文件夹")
    }

    // MARK: - v0.7.4 项 6：用所选项目新建文件夹

    /// 用当前选中的项目新建文件夹：创建"新建文件夹"（重名自动加序号），
    /// 把选中的项目移动进去。冲突（目标已有同名项目）时弹窗询问。
    /// Wave1 P0-2：createDirectory + parallelMove + 逐项 moveFile 整体移入
    /// DispatchQueue.global 后台执行（旧实现同步阻塞主线程，大文件/跨卷移动
    /// 分钟级冻结且无进度）；parallelMove 接 progress 回调，经直连进度模式驱动
    /// 底部 TaskProgressBar（参考粘贴路径 MenuActions.swift 模式）；完成后主线程
    /// 清空选中 + 刷新 + 注册撤销；失败经 state.error 既有错误呈现链路展示。
    /// - Parameter window: 宿主窗口（用于冲突弹窗）
    /// - Returns: 是否启动了操作（无选中项返回 false；I/O 已后台化，完成经主线程回调）
    @discardableResult
    func createFolderFromSelection(window: NSWindow?) -> Bool {
        let items = state.selectedFiles
        guard !items.isEmpty else { return false }

        let dir = state.path
        // 生成不重复的文件夹名："新建文件夹"、"新建文件夹 2"、"新建文件夹 3"...
        // （主线程轻量 stat：此刻新文件夹尚未创建，保证后台 I/O 使用唯一路径）
        var folderName = "新建文件夹"
        var counter = 2
        while FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent(folderName)) {
            folderName = "新建文件夹 \(counter)"
            counter += 1
        }
        let folderPath = (dir as NSString).appendingPathComponent(folderName)

        // 冲突解决必须在主线程（runModal 同步模态弹窗）。新文件夹此刻尚未创建，
        // 目标目录内不会存在同名项——正常情况下全部进入 normalSrcs，与旧实现
        // 「先建目录、再查冲突」在结果上等价；并发竞态下出现的同名冲突仍按
        // 替换/保留两者/跳过处理，行为不回退。
        let srcPaths = items.map { $0.path }
        let conflictPlan = ConflictResolver.resolveConflicts(srcPaths: srcPaths, destDir: folderPath, window: window)

        // 进度条（直连模式，参考粘贴路径）：plan 为空（仅并发竞态冲突全跳过的
        // 极端情形）时不展示进度，后台仍会创建空文件夹，与旧行为一致
        let progressBar = taskProgressBar
        if !conflictPlan.isEmpty {
            progressBar?.startDirectProgress(operation: "移动",
                                             totalCount: conflictPlan.count,
                                             destinationPath: folderPath)
            progressBarsExpanded?()
        }

        // 后台仅捕获不可变快照（线程安全策略：后台线程不读写 state）
        let normalSrcs = conflictPlan.normalSrcs
        let keepBoth = conflictPlan.keepBoth

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // 1. 创建目标文件夹
            do {
                try CoreBridge.shared.createDirectory(path: folderPath)
            } catch {
                // 失败回主线程呈现（复用 state.error 既有链路）并收起进度栏
                DispatchQueue.main.async { [weak self] in
                    self?.state.error = "创建文件夹失败：\(error.localizedDescription)"
                    if !conflictPlan.isEmpty {
                        progressBar?.hide()
                        self?.progressBarsCollapsed?()
                    }
                }
                return
            }

            // 记录实际移动的 (源路径, 目标路径) 对，用于撤销
            var movedPairs: [(src: String, dst: String)] = []
            var failedCount = 0
            // 2. 普通源：批量移动（progress 回调从 ffi 线程切主线程更新进度条）
            if !normalSrcs.isEmpty {
                do {
                    _ = try CoreBridge.shared.parallelMove(srcs: normalSrcs, dstDir: folderPath) { completed, total in
                        DispatchQueue.main.async {
                            progressBar?.updateDirectProgress(
                                operation: "移动",
                                currentFileName: nil,
                                completed: completed,
                                total: total
                            )
                        }
                    }
                    movedPairs.append(contentsOf: normalSrcs.map {
                        (src: $0, dst: (folderPath as NSString).appendingPathComponent(($0 as NSString).lastPathComponent))
                    })
                } catch {
                    failedCount += normalSrcs.count
                }
            }
            // 3. keepBoth 源：逐项移动（目标名已是唯一名）
            for pair in keepBoth {
                let dst = (folderPath as NSString).appendingPathComponent(pair.dstName)
                do {
                    try CoreBridge.shared.moveFile(src: pair.src, dst: dst)
                    movedPairs.append((src: pair.src, dst: dst))
                } catch {
                    failedCount += 1
                }
            }

            // 4. 失效缓存（后台完成后再回主线程刷新，与粘贴路径的收尾顺序一致）
            try? CoreBridge.shared.invalidateCache(path: dir)

            // 5. 主线程收尾：选择恢复、刷新、撤销注册（必须主线程，语义不变）
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if failedCount > 0 {
                    self.state.error = "\(failedCount) 个项目移动失败"
                }
                self.state.selectedFiles.removeAll()
                self.loadDirectory()
                // v0.7.4 修订 2：注册撤销（把项目移回原位 + 删除文件夹），
                // 仍在主线程 UI 层注册，I/O 后台化不改变 undoManager 时序语义
                if !movedPairs.isEmpty {
                    self.registerUndoCreateFolderFromSelection(folderPath: folderPath, movedPairs: movedPairs)
                }
                // 进度收尾：标记完成 + 2.2 秒后收起容器（与粘贴路径一致）
                if !conflictPlan.isEmpty {
                    progressBar?.completeDirectProgress(operation: "移动", count: movedPairs.count)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                        self?.progressBarsCollapsed?()
                    }
                }
            }
        }
        return true
    }

    /// v0.7.4 修订 2：注册"用所选新建文件夹"的撤销（移回项目 + 删除文件夹）与重做
    private func registerUndoCreateFolderFromSelection(folderPath: String, movedPairs: [(src: String, dst: String)]) {
        let dir = state.path
        undoManager?.registerUndo(withTarget: self) { vm in
            // 撤销：把项目移回原处，再删除文件夹
            for pair in movedPairs {
                try? CoreBridge.shared.moveFile(src: pair.dst, dst: pair.src)
            }
            try? FileManager.default.removeItem(atPath: folderPath)
            try? CoreBridge.shared.invalidateCache(path: dir)
            vm.loadDirectory()
            // 注册重做
            vm.undoManager?.registerUndo(withTarget: vm) { vm2 in
                vm2.redoCreateFolderFromSelection(folderPath: folderPath, movedPairs: movedPairs)
            }
            vm.undoManager?.setActionName("新建文件夹")
        }
        undoManager?.setActionName("新建文件夹")
    }

    /// 重做"用所选新建文件夹"：重建文件夹并把项目移回
    private func redoCreateFolderFromSelection(folderPath: String, movedPairs: [(src: String, dst: String)]) {
        try? CoreBridge.shared.createDirectory(path: folderPath)
        for pair in movedPairs {
            try? CoreBridge.shared.moveFile(src: pair.src, dst: pair.dst)
        }
        try? CoreBridge.shared.invalidateCache(path: state.path)
        loadDirectory()
        // 注册反向撤销
        undoManager?.registerUndo(withTarget: self) { vm in
            for pair in movedPairs {
                try? CoreBridge.shared.moveFile(src: pair.dst, dst: pair.src)
            }
            try? FileManager.default.removeItem(atPath: folderPath)
            try? CoreBridge.shared.invalidateCache(path: vm.state.path)
            vm.loadDirectory()
            vm.undoManager?.registerUndo(withTarget: vm) { vm2 in
                vm2.redoCreateFolderFromSelection(folderPath: folderPath, movedPairs: movedPairs)
            }
            vm.undoManager?.setActionName("新建文件夹")
        }
        undoManager?.setActionName("新建文件夹")
    }

    // MARK: - v0.7.4 修订 2：标签操作撤销

    /// 注册"添加标签到文件"的撤销（移除该标签）。
    /// 供右键菜单/详情栏标签操作调用，实现 ⌘Z 撤销标签变更。
    func registerUndoAddTag(tag: Tag, path: String) {
        undoManager?.registerUndo(withTarget: self) { vm in
            _ = TagBridge.shared.removeTagByName(tag.name, path: path)
            vm.refresh()
            // 注册重做：重新添加
            vm.undoManager?.registerUndo(withTarget: vm) { vm2 in
                _ = TagBridge.shared.addTag(tag, path: path)
                vm2.refresh()
            }
            vm.undoManager?.setActionName("添加标签")
        }
        undoManager?.setActionName("添加标签")
    }

    /// 注册"从文件移除标签"的撤销（重新添加该标签）。
    /// 供右键菜单/详情栏标签操作调用，实现 ⌘Z 撤销标签变更。
    func registerUndoRemoveTag(tag: Tag, path: String) {
        undoManager?.registerUndo(withTarget: self) { vm in
            _ = TagBridge.shared.addTag(tag, path: path)
            vm.refresh()
            // 注册重做：再次移除
            vm.undoManager?.registerUndo(withTarget: vm) { vm2 in
                _ = TagBridge.shared.removeTagByName(tag.name, path: path)
                vm2.refresh()
            }
            vm.undoManager?.setActionName("移除标签")
        }
        undoManager?.setActionName("移除标签")
    }

    // MARK: - 任务 T10: 组合过滤纯函数

    /// 综合应用标签筛选 + 搜索查询过滤（取交集）的纯函数。
    /// 抽为静态纯函数以便单元测试（无 FFI/dylib/文件 I/O 依赖）。
    /// - 标签筛选：仅保留 tags 含该标签的条目（按 id 或 name 匹配）
    /// - 搜索过滤：name 包含匹配（大小写不敏感）
    /// - 两者同时激活时取交集（先标签后查询、先查询后标签结果一致）
    /// 不含显示配置过滤（隐藏/系统文件），由调用方 `applyDisplayFilter` 单独处理。
    static func filterEntries(_ entries: [FileEntry], tagFilter: Tag?, searchQuery: String) -> [FileEntry] {
        filterEntries(entries,
                      tagFilters: tagFilter.map { [$0] } ?? [],
                      searchQuery: searchQuery)
    }

    /// 多标签 AND：每个筛选标签都必须出现在文件上（按 id 或名称匹配）。
    static func filterEntries(_ entries: [FileEntry], tagFilters: [Tag], searchQuery: String) -> [FileEntry] {
        var result = entries
        if !tagFilters.isEmpty {
            result = result.filter { entry in
                tagFilters.allSatisfy { filter in
                    entry.tags.contains { $0.id == filter.id || $0.name == filter.name }
                }
            }
        }
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter { $0.name.lowercased().contains(query) }
        }
        return result
    }

    /// 任务 T10: 从路径列表提取父目录集合（用于多目录缓存失效）。
    /// 抽为静态纯函数以便单元测试（无 I/O 依赖）。
    static func parentDirectories(of paths: [String]) -> Set<String> {
        var dirs = Set<String>()
        for path in paths {
            dirs.insert((path as NSString).deletingLastPathComponent)
        }
        return dirs
    }

    // MARK: - Private

    private func loadDirectory() {
        guard !state.path.isEmpty else {
            // 空路径不会有任何加载完成回调，钩子留着会在下一次真实加载时误触发
            afterLoadReady = nil
            return
        }
        // 任务 F11-11: 取消上一轮挂起的分页追加任务，并自增加载代次（C5）
        // 代次校验用于丢弃快速导航时旧后台加载的过时完成结果
        cancelPagination()
        let generation = { self.loadGeneration += 1; return self.loadGeneration }()
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
                // 活体死锁热修：等待 FFI 结果的信号量在 CoreBridge.listDirectory 内，
                // 已加 10 秒超时兜底；超时由此处 catch 捕获并回主线程走错误浮层
                // （清 isLoading + 显示"目录响应超时"），迟到结果被结构性丢弃。
                let entries = try CoreBridge.shared.listDirectory(path: path)
                // 在后台线程完成排序，避免阻塞 UI；使用捕获的快照而非读取 self.state
                let sortedEntries = self.sortEntries(entries, field: sortField, ascending: sortAscending)
                DispatchQueue.main.async {
                    // 任务 F11-11: 代次校验 - 若期间又发起新 loadDirectory 则丢弃本次结果（C5）
                    guard self.loadGeneration == generation else { return }
                    // 任务 F10-10: 保存原始列表到 allFiles，applyFilter 始终基于 allFiles 过滤（修复问题11辅助）
                    self.allFiles = sortedEntries
                    // Wave3 Task 7: 后台批量预热标签缓存（前 500 条，async P1-4）。
                    // 主线程只做路径快照映射（500 次字符串拷贝，微秒级），xattr I/O 全部
                    // 在后台 utility 队列执行——渲染/滚动路径随后直接读缓存，不再逐条 getxattr。
                    // 2026-10-20 #4：预热完成后广播，列表据此刷新标签（渲染不再等标签）
                    let warmPaths = Array(sortedEntries.prefix(500).map { $0.path })
                    TagBridge.shared.warmCache(paths: warmPaths) {
                        NotificationCenter.default.post(
                            name: .ffTagCacheWarmed,
                            object: nil,
                            userInfo: ["paths": warmPaths])
                    }
                    // 任务 F11-8: 统一走 applyFilter（综合标签+搜索过滤），保持单一过滤入口
                    // 任务 F11-11: 大目录分页加载（C5）- 首批 pageSize 条立即显示，其余异步追加
                    // B7: 有标签筛选时走 applyFilter 的异步批量读标签路径（xattr I/O 不进主线程）
                    if self.state.tagFilter != nil {
                        self.applyFilter()
                    } else {
                        self.applyFilterPaginated()
                    }
                    if let target = self.pendingSelectionPath {
                        self.pendingSelectionPath = nil
                        self.pendingRestoredSelectionPaths = nil
                        if let entry = self.state.files.first(where: { $0.path == target }) {
                            self.state.selectedFiles = [entry]
                        }
                    } else if let restore = self.pendingRestoredSelectionPaths {
                        self.pendingRestoredSelectionPaths = nil
                        let byPath = Dictionary(self.state.files.map { ($0.path, $0) },
                                                uniquingKeysWith: { first, _ in first })
                        self.state.selectedFiles = FFSelectionRestore
                            .pathsToRestore(previous: restore,
                                            available: self.state.files.map(\.path))
                            .compactMap { byPath[$0] }
                    }
                    // 一次性就绪回调（R4-18）：视图的 reload 由上面的 state 变更经
                    // receive(on: main) 排队触发，这个 async 块排在它们之后，此时新行已在列表里。
                    if let ready = self.afterLoadReady {
                        self.afterLoadReady = nil
                        DispatchQueue.main.async(execute: ready)
                    }
                    // 诊断：记录加载完成后 state.files 是否包含预期文件名（验证数据层是否读到新名字）
                    // 小目录打印完整列表；大目录只打印前 8 个
                    if self.state.files.count <= 30 {
                        let allNames = self.state.files.map { $0.name }
                        FFDebug.log("[CACHE-DIAG] loadDirectory 完成 path=\(path) files=\(self.state.files.count) 全部=\(allNames)")
                    } else {
                        let previewNames = self.state.files.prefix(8).map { $0.name }
                        FFDebug.log("[CACHE-DIAG] loadDirectory 完成 path=\(path) files=\(self.state.files.count) 前8个=\(previewNames)")
                    }
                    // 重命名等"数量不变"操作：加载完成、state.files 已更新后发通知强制视图刷新
                    // v0.7.4 修复 3：通知携带目录路径，对侧面板（显示同一目录时）也刷新数据，
                    // 避免右面板仍渲染旧名字（底层审查 FINDING 2）。
                    if self.pendingContentChangeNotification {
                        self.pendingContentChangeNotification = false
                        NotificationCenter.default.post(name: .fileListContentChanged, object: nil,
                                                        userInfo: ["path": path])
                    }
                    // 若当前有非空搜索查询，触发子目录递归搜索（追加深层匹配项）
                    if !self.state.searchQuery.isEmpty && self.state.tagFilter == nil {
                        self.performRecursiveSearch(query: self.state.searchQuery)
                    }
                    self.state.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    // 任务 F11-11: 代次校验 - 错误回退也需丢弃过时结果（C5）
                    guard self.loadGeneration == generation else { return }
                    self.state.error = error.localizedDescription
                    self.state.isLoading = false
                }
            }
        }
    }

    /// 在后台线程排序（不触发 @Published 变更）。
    /// 排序字段与方向通过参数传入（快照），避免读取 `state` 造成数据竞争。
    private func sortEntries(_ entries: [FileEntry], field: SortField, ascending: Bool) -> [FileEntry] {
        let folderFirst = FFAppSettings.folderFirstSort()
        return entries.sorted {
            FFSortPolicy.isOrderedBefore($0, $1, field: field,
                                         ascending: ascending, folderFirst: folderFirst)
        }
    }

    private func applySort() {
        // 任务 F11-11: 排序变化为完整重载，取消挂起的分页追加任务（C5）
        cancelPagination()
        // 任务 F10-10: 排序基于 allFiles（原始列表），避免在已过滤子集上排序导致丢失项目（修复问题11辅助）
        let sorted = sortEntries(allFiles, field: state.sortField, ascending: state.sortAscending)
        // 同步更新 allFiles 为排序后顺序
        allFiles = sorted
        // 任务 F11-8: 统一走 applyFilter（综合标签+搜索过滤），保持单一过滤入口一致
        applyFilter()
    }

    // MARK: - v0.6.9: 显示配置过滤（隐藏文件 / 系统文件）

    /// 根据 UserDefaults 中的显示配置过滤文件列表。
    /// - showHiddenFiles == false → 过滤掉 isHidden 的文件
    /// - showSystemFiles == false → 过滤掉 isSystemProtected 的文件
    private func applyDisplayFilter(_ entries: [FileEntry]) -> [FileEntry] {
        let showHidden = UserDefaults.standard.bool(forKey: FFUserDefaultsKeys.showHiddenFiles)
        let showSystem = UserDefaults.standard.object(forKey: FFUserDefaultsKeys.showSystemFiles) as? Bool ?? false
        return entries.filter { entry in
            if !showHidden && entry.isHidden { return false }
            if !showSystem && entry.isSystemProtected { return false }
            return true
        }
    }

    private func applyFilter() {
        // 任务 F11-11: 搜索/标签筛选变化为完整重载，取消挂起的分页追加任务（C5）
        // （loadDirectory 的初始分页走 applyFilterPaginated，不经过此处）
        cancelPagination()
        // 任务 F11-8: 综合应用标签筛选 + 搜索过滤，结果均基于 allFiles（原始列表）
        let tagFilters = state.tagFilters
        let searchQuery = state.searchQuery
        // v0.6.9: 显示配置过滤（隐藏文件 / 系统文件）
        let displayFiltered = applyDisplayFilter(allFiles)

        // 无标签筛选：直接走纯函数过滤（搜索 + 标签交集），同步完成
        guard !tagFilters.isEmpty else {
            state.files = Self.filterEntries(displayFiltered, tagFilters: [], searchQuery: searchQuery)
            return
        }

        // 标签筛选：已缓存标签的条目直接过滤；未缓存的标签后台读取（xattr I/O）后补全再过滤。
        // 任务 T10 修复：tagFilter 与 searchQuery 同时激活时取交集（此前提前 return 漏掉搜索过滤）。
        let uncached = displayFiltered.filter { $0.tags.isEmpty }
        let cached = displayFiltered.filter { !$0.tags.isEmpty }

        if uncached.isEmpty {
            // 全部已缓存，主线程直接过滤（纯内存操作）
            state.files = Self.filterEntries(cached, tagFilters: tagFilters, searchQuery: searchQuery)
            return
        }

        // 快照当前筛选条件，后台读取完成后校验未变才应用
        let pathsToRead = uncached.map { $0.path }
        let generation = loadGeneration
        let capturedQuery = searchQuery
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var tagMap: [String: [Tag]] = [:]
            for path in pathsToRead {
                tagMap[path] = TagBridge.shared.getTags(path: path)
            }
            DispatchQueue.main.async {
                guard self.loadGeneration == generation else { return }
                guard self.state.tagFilters.map(\.name) == tagFilters.map(\.name) else { return }
                guard self.state.searchQuery == capturedQuery else { return }
                // 用后台读取的标签补齐 entry.tags，再做标签+搜索交集过滤
                let completed = displayFiltered.map { entry -> FileEntry in
                    guard entry.tags.isEmpty, let tags = tagMap[entry.path] else { return entry }
                    var updated = entry
                    updated.tags = tags
                    return updated
                }
                self.state.files = Self.filterEntries(completed, tagFilters: tagFilters, searchQuery: searchQuery)
            }
        }
    }

    // MARK: - 任务 F11-11: 大目录分页加载（C5）

    /// 取消所有挂起的分页追加任务。
    /// 在任何重置列表的操作（loadDirectory/applySort/applyFilter）前调用，
    /// 避免旧的追加任务在新列表已建立后覆盖 state.files（竞态）。
    private func cancelPagination() {
        for item in paginationWorkItems {
            item.cancel()
        }
        paginationWorkItems.removeAll()
    }

    /// 任务 F11-11: 分页应用过滤结果（C5）。
    /// 仅 loadDirectory 初始加载时调用：首批 pageSize 条立即显示（state.files 立即更新触发 UI），
    /// 其余按 pageSize 分批通过 DispatchQueue.main.asyncAfter 异步追加到 state.files。
    /// 搜索/排序/标签筛选变化走 applyFilter（完整重载），不经过此分页路径。
    ///
    /// 实现说明（简化方案，非增量插入）：
    /// - 首批直接赋值 state.files，触发 @Published -> FileListView reloadData
    /// - 后续每批用 asyncAfter 追加，每批到达时校验 loadGeneration 与 searchQuery/tagFilter
    ///   未变才应用，否则丢弃（用户可能在追加期间导航/搜索，需避免覆盖）
    private func applyFilterPaginated() {
        cancelPagination()

        // B7: 有标签筛选时统一走 applyFilter 的异步批量读标签路径
        //（applyFilterPaginated 的分页是同步过滤，无法承载 xattr I/O）
        if state.tagFilter != nil {
            applyFilter()
            return
        }

        // 综合标签 + 搜索过滤（与 applyFilter 相同逻辑，结果为完整过滤列表）。
        // 此处 tagFilter 必为 nil（上方已对非 nil 情况 early return 到 applyFilter），
        // 故仅需应用显示配置 + 搜索过滤。
        let filtered = Self.filterEntries(applyDisplayFilter(allFiles), tagFilter: nil, searchQuery: state.searchQuery)

        // 捕获快照，供追加批次校验（避免闭包内读取 self.state 造成竞态）
        let generation = loadGeneration
        let capturedQuery = state.searchQuery
        let capturedTagFilterId = state.tagFilter?.id

        // 首批：立即显示前 pageSize 条
        let firstBatchEnd = min(paginationPageSize, filtered.count)
        state.files = Array(filtered.prefix(firstBatchEnd))

        // 其余分批异步追加
        var offset = firstBatchEnd
        while offset < filtered.count {
            let batchStart = offset
            let batchEnd = min(batchStart + paginationPageSize, filtered.count)
            let batch = Array(filtered[batchStart..<batchEnd])
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                // 校验：加载代次未变 + 搜索查询未变 + 标签筛选未变，否则丢弃此批
                guard self.loadGeneration == generation else { return }
                guard self.state.searchQuery == capturedQuery else { return }
                guard self.state.tagFilter?.id == capturedTagFilterId else { return }
                // 追加批次（非增量插入，直接 append 后 @Published 触发 FileListView reloadData）
                self.state.files.append(contentsOf: batch)
            }
            paginationWorkItems.append(workItem)
            // 每批间隔 16ms（约一帧），让首批渲染先完成，避免阻塞主线程
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16 * (offset / paginationPageSize)), execute: workItem)
            offset = batchEnd
        }
    }

    /// 任务 F11-8: 异步递归搜索子目录，将匹配项追加到当前结果。
    /// 修复问题11：此前搜索仅匹配当前目录直接子项，搜索深层文件时一片空白。
    /// 性能策略：限制递归深度为 3 层，限制最大结果数为 500，避免大目录卡顿。
    /// 数值同时暴露给测试，避免文档与实现漂移。
    /// 仅当 searchQuery 非空且未设置标签筛选时执行（标签筛选为精确集合，不递归）。
    private func performRecursiveSearch(query: String) {
        guard !query.isEmpty, state.tagFilter == nil, state.searchScope.searchesSubdirectories else { return }
        // 在派发到后台前捕获不可变快照，避免数据竞争
        let basePath = state.path
        let loweredQuery = query.lowercased()
        let maxDepth = FFSearchPolicy.maxDepth
        let maxResults = FFSearchPolicy.maxResults
        // 已在当前目录过滤中存在的路径集合（避免重复）
        let existingPaths = Set(allFiles.map { $0.path })

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var results: [FileEntry] = []
            let fm = FileManager.default
            // 遍历子目录递归收集匹配项（深度优先）
            func walk(_ dir: String, depth: Int) {
                guard depth <= maxDepth, results.count < maxResults else { return }
                guard let children = try? fm.contentsOfDirectory(atPath: dir) else { return }
                for child in children {
                    if results.count >= maxResults { return }
                    let childPath = (dir as NSString).appendingPathComponent(child)
                    // 跳过隐藏文件（与 listDirectory 行为一致，避免 .Trash 等噪音）
                    if child.hasPrefix(".") { continue }
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: childPath, isDirectory: &isDir) else { continue }
                    if isDir.boolValue {
                        // 递归进入子目录
                        walk(childPath, depth: depth + 1)
                    } else {
                        // 当前目录直接子项已由 applyFilter 处理，跳过避免重复
                        if existingPaths.contains(childPath) { continue }
                        if child.lowercased().contains(loweredQuery) {
                            // 构造 FileEntry（modificationDate 用文件属性填充，tags 留空）
                            let entry = self.makeFileEntry(path: childPath, name: child, isDirectory: false)
                            results.append(entry)
                        }
                    }
                }
            }
            walk(basePath, depth: 1)

            DispatchQueue.main.async {
                // 外层已强引用解包 self，此处直接使用（注意：仍需校验查询未变）
                // 仅当用户搜索查询未变时才应用结果（避免异步竞态：用户已清空或改字）
                guard self.state.searchQuery == query else { return }
                // 仅当未启用标签筛选且范围仍为「含子目录」时才合并
                guard self.state.tagFilter == nil, self.state.searchScope.searchesSubdirectories else { return }
                // 合并：当前已显示的（当前目录直接匹配项）+ 递归匹配项
                let currentPaths = Set(self.state.files.map { $0.path })
                let newResults = results.filter { !currentPaths.contains($0.path) }
                if !newResults.isEmpty {
                    self.state.files.append(contentsOf: newResults)
                }
            }
        }
    }

    /// 任务 F11-8: 通过 FileManager.attributes 构造 FileEntry（供递归搜索结果使用）。
    /// tags 字段读取 xattr（标签筛选时可命中）
    private func makeFileEntry(path: String, name: String, isDirectory: Bool) -> FileEntry {
        let fm = FileManager.default
        var size: UInt64 = 0
        var modDate = Date()
        var createDate = Date()
        if let attrs = try? fm.attributesOfItem(atPath: path) {
            if let s = attrs[.size] as? UInt64 { size = s }
            if let m = attrs[.modificationDate] as? Date { modDate = m }
            if let c = attrs[.creationDate] as? Date { createDate = c }
        }
        let tags = TagBridge.shared.getTags(path: path)
        return FileEntry(
            path: path, name: name, isDirectory: isDirectory,
            isFile: !isDirectory, isSymlink: false,
            isHidden: false, isSystemProtected: false,
            size: size, modificationDate: modDate, creationDate: createDate,
            tags: tags
        )
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
