import Foundation

/// 快捷键设置的真值桥：默认键位来自 FFKeyboardContract，冲突检测覆盖所有可自定义项。
enum FFShortcutSettings {

    /// 设置页存储键 → 键盘契约动作（仅映射契约中存在的动作）。
    static let contractActions: [String: FFShortcutAction] = [
        FFUserDefaultsKeys.shortcutNewFolder: .newFolder,
        FFUserDefaultsKeys.shortcutCloseWindow: .closeWindow,
        FFUserDefaultsKeys.shortcutTrash: .moveToTrash,
        FFUserDefaultsKeys.shortcutRename: .rename,
        FFUserDefaultsKeys.shortcutQuicklook: .quickLook,
        FFUserDefaultsKeys.shortcutDuplicate: .duplicate,
        FFUserDefaultsKeys.shortcutSearch: .search,
        FFUserDefaultsKeys.shortcutDuplicateScan: .duplicateScan,
        FFUserDefaultsKeys.shortcutPreferences: .settings,
        FFUserDefaultsKeys.shortcutGoUp: .up,
    ]

    /// 契约之外的默认展示（与 MainMenu 的默认键位一致）。
    static let fallbackDefaults: [String: String] = [
        FFUserDefaultsKeys.shortcutOpenFile: "⌘O",
        FFUserDefaultsKeys.shortcutCopy: "⌘C",
        FFUserDefaultsKeys.shortcutCut: "⌘X",
        FFUserDefaultsKeys.shortcutPaste: "⌘V",
        FFUserDefaultsKeys.shortcutSelectAll: "⌘A",
        FFUserDefaultsKeys.shortcutUndo: "⌘Z",
        FFUserDefaultsKeys.shortcutRedo: "⌘⇧Z",
        FFUserDefaultsKeys.shortcutListView: "⌥⌘1",
        FFUserDefaultsKeys.shortcutGridView: "⌥⌘2",
        FFUserDefaultsKeys.shortcutRefresh: "⌘R",
        FFUserDefaultsKeys.shortcutTaskPanel: "⌘0",
        FFUserDefaultsKeys.shortcutConnectServer: "⌘K",
        FFUserDefaultsKeys.shortcutDelete: "⌘⌫",
    ]

    static let titles: [String: String] = [
        FFUserDefaultsKeys.shortcutNewFolder: "新建文件夹",
        FFUserDefaultsKeys.shortcutOpenFile: "打开文件",
        FFUserDefaultsKeys.shortcutCloseWindow: "关闭窗口",
        FFUserDefaultsKeys.shortcutCopy: "复制",
        FFUserDefaultsKeys.shortcutCut: "剪切",
        FFUserDefaultsKeys.shortcutPaste: "粘贴",
        FFUserDefaultsKeys.shortcutSelectAll: "全选",
        FFUserDefaultsKeys.shortcutTrash: "移到废纸篓",
        FFUserDefaultsKeys.shortcutUndo: "撤销",
        FFUserDefaultsKeys.shortcutRedo: "重做",
        FFUserDefaultsKeys.shortcutListView: "列表视图",
        FFUserDefaultsKeys.shortcutGridView: "图标视图",
        FFUserDefaultsKeys.shortcutRefresh: "刷新",
        FFUserDefaultsKeys.shortcutSearch: "搜索",
        FFUserDefaultsKeys.shortcutDuplicateScan: "重复文件扫描",
        FFUserDefaultsKeys.shortcutTaskPanel: "任务面板",
        FFUserDefaultsKeys.shortcutQuicklook: "Quick Look 预览",
        FFUserDefaultsKeys.shortcutDuplicate: "复制选中项",
        FFUserDefaultsKeys.shortcutConnectServer: "连接服务器",
        FFUserDefaultsKeys.shortcutPreferences: "偏好设置",
        FFUserDefaultsKeys.shortcutRename: "重命名",
        FFUserDefaultsKeys.shortcutDelete: "删除",
        FFUserDefaultsKeys.shortcutGoUp: "上一级",
    ]

    static func defaultDisplay(for storageKey: String) -> String? {
        if let action = contractActions[storageKey] {
            return FFKeyboardContract.shortcut(for: action).display
        }
        return fallbackDefaults[storageKey]
    }

    static func effectiveDisplay(for storageKey: String,
                                 stored: [String: String]) -> String? {
        stored[storageKey] ?? defaultDisplay(for: storageKey)
    }

    /// 返回与 display 冲突的另一项存储键；无冲突返回 nil。
    static func conflict(for display: String,
                         storageKey: String,
                         stored: [String: String]) -> String? {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return FFUserDefaultsKeys.allShortcutKeys.first { key in
            key != storageKey && effectiveDisplay(for: key, stored: stored) == trimmed
        }
    }

    static func title(for storageKey: String) -> String {
        titles[storageKey] ?? storageKey
    }

    static func storedShortcuts(_ defaults: UserDefaults = .standard) -> [String: String] {
        var result: [String: String] = [:]
        for key in FFUserDefaultsKeys.allShortcutKeys {
            if let value = defaults.string(forKey: key) {
                result[key] = value
            }
        }
        return result
    }
}
