import Foundation

/// 纯策略：把「状态发射」与「昂贵副作用」解耦，避免选中/加载标志变化触发
/// 标签 xattr 扫描、任务面板重建。
enum FFPerformancePolicy {

    /// 标签计数只关心目录与文件集合。用 path + 数量 + 首尾路径做廉价签名，
    /// 避免每次状态发射都对十万级数组做全量比较。
    static func tagCountSignature(_ state: PaneState) -> String {
        let first = state.files.first?.path ?? ""
        let last = state.files.last?.path ?? ""
        return "\(state.path)|\(state.files.count)|\(first)|\(last)"
    }

    static func shouldRefreshTagCounts(previous: PaneState, current: PaneState) -> Bool {
        tagCountSignature(previous) != tagCountSignature(current)
    }

    static func shouldPublishTasks(previous: [TaskInfo], next: [TaskInfo]) -> Bool {
        previous != next
    }
}
