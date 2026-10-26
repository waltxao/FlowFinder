import Foundation

/// 破坏性操作的默认值集中在这里，UI 与测试共用同一真值。
enum FFConflictPolicy {
    /// 复制/移动遇到同名文件时默认不覆盖；替换必须由用户显式选择。
    static let defaultDecision: ConflictResolution = .skip

    /// 冲突弹窗按钮顺序：跳过（默认）/ 保留两者 / 替换（危险，置末）。
    static let buttonOrder: [ConflictResolution] = [.skip, .keepBoth, .replace]
}

enum FFDuplicateSelectionPolicy {
    /// 查重结果默认不勾选任何待删除项。
    static func initialSelection(groups: [Any]) -> Set<String> {
        []
    }

    /// 每组至少保留一个文件：仅当标记后仍有未标记项时才允许加入删除集合。
    static func canMarkForDeletion(filePath: String,
                                   allPaths: [String],
                                   currentlyMarked: Set<String>) -> Bool {
        guard allPaths.contains(filePath) else { return false }
        return allPaths.contains { $0 != filePath && !currentlyMarked.contains($0) }
    }
}

enum FFDeleteCopy {
    /// 永久删除不能暗示可撤销（与废纸篓语义区分）。
    static let permanentDeleteMentionsUndo = false
    static let permanentDeleteWarning = "此操作无法撤销"
}
