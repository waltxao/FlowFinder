import Foundation

/// 启动目录解析（核心旅程 J1：装上就能用，不出现空窗口）。
///
/// 背景：`loadInitialDirectories` 此前把 `~/Desktop` / `~/Documents` 硬编码交给面板，
/// 不校验存在性；设置项「上次打开的位置」也没有实现（注释写着「暂回退到桌面」）。
/// 若 `~/Desktop` 不存在（新机器、被删除、被重定向），首开就是一屏
/// 「无法加载此文件夹」——正是 J1 要避免的。
///
/// 这里做成纯函数，路径存在性由调用方注入，便于单测。
enum FFStartupPath {

    /// 「启动时打开」设置取值
    enum Choice: Int {
        case lastLocation = 0
        case home = 1
        case desktop = 2
    }

    /// 左面板：按设置选项决定候选序列，取第一个真实存在的目录，全不存在则回主目录。
    static func resolve(
        choice: Int,
        lastLocation: String?,
        home: String,
        isDirectory: (String) -> Bool
    ) -> String {
        let desktop = (home as NSString).appendingPathComponent("Desktop")
        let candidates: [String]
        switch Choice(rawValue: choice) ?? .lastLocation {
        case .home:
            candidates = [home]
        case .desktop:
            candidates = [desktop]
        case .lastLocation:
            candidates = [lastLocation, desktop].compactMap { $0 }
        }
        if let hit = candidates.first(where: isDirectory) { return hit }
        return home
    }

    /// 右面板：上次位置 → 指定子目录（默认「文稿」）→ 主目录。
    static func resolveSecondary(
        lastLocation: String?,
        home: String,
        subdirectory: String,
        isDirectory: (String) -> Bool
    ) -> String {
        let preferred = (home as NSString).appendingPathComponent(subdirectory)
        let candidates = [lastLocation, preferred].compactMap { $0 }
        if let hit = candidates.first(where: isDirectory) { return hit }
        return home
    }

    // MARK: - 持久化

    static let lastLeftKey = "last_left_path"
    static let lastRightKey = "last_right_path"
    static let lastActivePaneKey = "last_active_pane"

    /// 完整会话恢复：只接受 left/right；单栏模式不恢复右栏活动态。
    static func activePane(from raw: String?, singlePane: Bool) -> PaneSide? {
        guard !singlePane, let raw else { return nil }
        switch raw {
        case "right": return .right
        case "left": return .left
        default: return nil
        }
    }

    /// 真实文件系统判定
    static func isDirectoryOnDisk(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
