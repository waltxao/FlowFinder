import AppKit

// MARK: - FFOpaqueContainerView

/// 重写 isOpaque 返回 true 的 NSView 子类。
/// 任务 F11-2: 窗口级实体背景（v0.6.7），移除透明玻璃架构。
/// 让窗口服务器捕获鼠标事件，背景色由 layer.backgroundColor 提供。
/// 统一替换各窗口控制器中重复定义的 *OpaqueContainerView 子类。
class FFOpaqueContainerView: NSView {
    override var isOpaque: Bool { return true }
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
