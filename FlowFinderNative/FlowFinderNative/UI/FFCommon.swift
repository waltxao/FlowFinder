import AppKit

// MARK: - FFOpaqueContainerView

/// 实体背景容器：背景色由 layer.backgroundColor 提供（各窗口控制器自行设置动态色）。
/// 注意：isOpaque 必须返回 false——isOpaque=true 会告知 AppKit「本视图内容不变，可缓存」，
/// 主题切换时系统会跳过该视图及子树的自动重绘，导致深色模式下窗口内容不跟随（视觉不变）。
/// 背景色跟随主题由各窗口在 .appearanceChanged 时重设 layer.backgroundColor 保证。
class FFOpaqueContainerView: NSView {
    override var isOpaque: Bool { return false }
}

// MARK: - FFNotificationNames

/// 统一管理所有自定义 Notification.Name 常量
/// 消除散布在各文件中的字符串字面量
/// 注意：fileList* 系列通知定义在 FileListView.swift 的 extension 中，此处仅补充未定义的
extension Notification.Name {
    // 窗口/视图相关
    static let openSettings = Notification.Name("OpenSettings")
    static let refreshHiddenFiles = Notification.Name("refreshHiddenFiles")
    static let appearanceChanged = Notification.Name("AppearanceChanged")
    // v0.6.9: 文件夹显示配置变更通知
    static let refreshFileTags = Notification.Name("refreshFileTags")
    static let refreshFileExtensions = Notification.Name("refreshFileExtensions")
    static let refreshSystemFiles = Notification.Name("refreshSystemFiles")

    // 任务相关
    static let taskProgressUpdated = Notification.Name("TaskProgressUpdated")
    static let taskCompleted = Notification.Name("TaskCompleted")

    // 标签相关
    static let fileListAddTag = Notification.Name("FileListAddTag")

    // SMB 网络卷断连重连
    static let smbVolumeDisconnected = Notification.Name("SMBVolumeDisconnected")
    static let smbVolumeReconnected = Notification.Name("SMBVolumeReconnected")
    static let smbVolumeReconnectFailed = Notification.Name("SMBVolumeReconnectFailed")
}

// MARK: - FFUserDefaultsKeys

/// 统一管理所有 UserDefaults key 常量
/// 消除散布在各文件中的字符串字面量
enum FFUserDefaultsKeys {
    static let showHiddenFiles = "show_hidden_files"
    static let themeMode = "appearance_mode"
    // v0.6.9: 文件夹显示配置
    static let showFileTags = "show_file_tags"
    static let showFileExtensions = "show_file_extensions"
    static let showSystemFiles = "show_system_files"
}

// MARK: - FFAccent（应用级强调色源）

/// 应用级强调色：替代 NSColor.controlAccentColor（系统色，AppKit 不允许应用层覆盖）。
/// 由设置页「强调色」写入 UserDefaults key "accent_color"（hex 字符串），FFAccent.current 读取并广播刷新。
/// 全应用所有「强调色」UI 引用统一改为 FFAccent.current，这样设置改动即可全应用即时生效。
/// 默认值 "#0a84ff"（系统强调色蓝），与 macOS 默认一致。
enum FFAccent {
    /// UserDefaults key（hex 字符串，如 "#bf5af2"）
    static let storageKey = "accent_color"
    /// 默认强调色（系统蓝）
    static let defaultHex = "#0a84ff"

    /// 当前强调色。每次读取都从 UserDefaults 取最新值，保证设置改动即时生效。
    static var current: NSColor {
        let hex = UserDefaults.standard.string(forKey: storageKey) ?? defaultHex
        return NSColor(hex: hex) ?? .controlAccentColor
    }

    /// 当前 hex 字符串（供 UI 颜色选择器高亮选中项）
    static var currentHex: String {
        UserDefaults.standard.string(forKey: storageKey) ?? defaultHex
    }

    /// 设置新强调色并广播刷新全应用。
    /// 由设置页「强调色」颜色选择器调用。
    static func set(hex: String) {
        UserDefaults.standard.set(hex, forKey: storageKey)
        NotificationCenter.default.post(name: .accentColorChanged, object: nil, userInfo: ["hex": hex])
    }
}

extension Notification.Name {
    /// 强调色变更通知（由 FFAccent.set 广播，监听者收到后刷新 UI）
    static let accentColorChanged = Notification.Name("FFAccentColorChanged")
}
