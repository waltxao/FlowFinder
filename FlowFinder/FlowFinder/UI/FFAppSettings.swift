import Foundation

// MARK: - 设置读取（批次 1）

/// 拖拽默认行为三档（B1-06）。
enum FFDragBehavior: String {
    case finder
    case alwaysCopy
    case alwaysMove
}

/// 所有设置读取集中在这里；默认参数可注入，测试不污染真实偏好。
enum FFAppSettings {

    static func dragBehavior(defaults: UserDefaults = .standard) -> FFDragBehavior {
        guard let raw = defaults.string(forKey: FFUserDefaultsKeys.defaultFileBehavior),
              let value = FFDragBehavior(rawValue: raw) else { return .finder }
        return value
    }

    static func folderFirstSort(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: FFUserDefaultsKeys.folderFirstSort) != nil else { return true }
        return defaults.bool(forKey: FFUserDefaultsKeys.folderFirstSort)
    }

    static func keepSelectionPosition(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: FFUserDefaultsKeys.keepSelectionPosition)
    }

    /// 键名沿用 `confirm_file_operations`，语义收窄为「移动前确认」（B1-05）。
    static func confirmMove(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: FFUserDefaultsKeys.confirmFileOperations)
    }

    static func checkUpdateOnStartup(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: FFUserDefaultsKeys.checkUpdateOnStartup) != nil else { return true }
        return defaults.bool(forKey: FFUserDefaultsKeys.checkUpdateOnStartup)
    }

    static func smbDomain(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: FFUserDefaultsKeys.smbDefaultDomain) ?? ""
    }

    static func smbAutoReconnect(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: FFUserDefaultsKeys.smbAutoReconnect)
    }
}

// MARK: - 拖拽语义

enum FFDragBehaviorPolicy {

    /// - finder：同盘移动 / 跨盘复制，⌘ 反转
    /// - alwaysCopy：默认复制，⌘ 反转成移动
    /// - alwaysMove：默认移动，⌘ 反转成复制
    static func shouldMove(behavior: FFDragBehavior,
                           commandPressed: Bool,
                           sameVolume: Bool) -> Bool {
        switch behavior {
        case .finder:
            return commandPressed ? !sameVolume : sameVolume
        case .alwaysCopy:
            return commandPressed
        case .alwaysMove:
            return !commandPressed
        }
    }
}

// MARK: - 排序

enum FFSortPolicy {

    static func isOrderedBefore(_ a: FileEntry,
                                _ b: FileEntry,
                                field: SortField,
                                ascending: Bool,
                                folderFirst: Bool) -> Bool {
        if folderFirst, a.isDirectory != b.isDirectory {
            return a.isDirectory
        }
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

// MARK: - 刷新保持选中

enum FFSelectionRestore {

    /// 只保留仍然存在的路径，并沿用刷新前的选中顺序。
    static func pathsToRestore(previous: [String], available: [String]) -> [String] {
        let availableSet = Set(available)
        return previous.filter { availableSet.contains($0) }
    }
}
