import Combine
import Foundation

/// 每面板的单一真值。视图只读，加载服务写入；选择/筛选/视图变化以粒度变更集发布。
enum PaneChange: Equatable {
    case initial
    case files
    case selection
    case filter
    case viewMode
    case all
}

final class PaneStore {
    private(set) var state: PaneState
    private(set) var selection: Set<FileEntry.ID> = []
    @Published private(set) var change: PaneChange = .initial
    /// 廉价签名：避免每次选中都对十万级 FileEntry 数组做深比较。
    private var filesSignature: String

    init(initial: PaneState) {
        self.state = initial
        self.filesSignature = FFPerformancePolicy.tagCountSignature(initial)
    }

    func apply(state newState: PaneState) {
        let signpost = FFPerf.begin("PaneStore.apply")
        defer { FFPerf.end("PaneStore.apply", signpost) }
        let signature = FFPerformancePolicy.tagCountSignature(newState)
        let filesChanged = newState.path != state.path || signature != filesSignature
        let filterChanged = newState.searchQuery != state.searchQuery || newState.tagFilter != state.tagFilter
        let viewChanged = newState.viewMode != state.viewMode
            || newState.sortField != state.sortField
            || newState.sortAscending != state.sortAscending
            || newState.groupBy != state.groupBy
        state = newState
        filesSignature = signature
        if filesChanged {
            change = .files
        } else if filterChanged {
            change = .filter
        } else if viewChanged {
            change = .viewMode
        }
    }

    func setSelection(_ ids: Set<FileEntry.ID>) {
        guard ids != selection else { return }
        selection = ids
        change = .selection
    }

    /// 迁移期：视图仍会写 `state.selectedFiles`，Store 静默跟随，不额外发变更。
    func syncSelection(from files: [FileEntry]) {
        selection = Set(files.map(\.path))
    }

    func setFilter(_ tag: Tag?) {
        state.tagFilter = tag
        change = .filter
    }

    func setViewMode(_ mode: ViewMode) {
        state.viewMode = mode
        change = .viewMode
    }
}
