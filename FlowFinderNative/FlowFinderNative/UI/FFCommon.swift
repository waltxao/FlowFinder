import AppKit

// MARK: - FFOpaqueContainerView

/// 重写 isOpaque 返回 true 的 NSView 子类。
/// 任务 F11-2: 窗口级实体背景（v0.6.7），移除透明玻璃架构。
/// 让窗口服务器捕获鼠标事件，背景色由 layer.backgroundColor 提供。
/// 统一替换各窗口控制器中重复定义的 *OpaqueContainerView 子类。
class FFOpaqueContainerView: NSView {
    override var isOpaque: Bool { return true }
}

// MARK: - FFKeyCodes

/// 键码常量：消除全项目的魔法数字
/// 参考 Carbon/HIToolbox/Events.h 中的 kVK_* 常量
enum FFKeyCodes {
    static let space: UInt16 = 49         // 空格
    static let returnKey: UInt16 = 36      // 回车
    static let enter: UInt16 = 76          // 小键盘回车
    static let escape: UInt16 = 53         // Escape
    static let delete: UInt16 = 51         // Delete (Backspace)
    static let forwardDelete: UInt16 = 117 // Forward Delete
    static let upArrow: UInt16 = 126       // 上箭头
    static let downArrow: UInt16 = 125     // 下箭头
    static let leftArrow: UInt16 = 123     // 左箭头
    static let rightArrow: UInt16 = 124    // 右箭头
    static let home: UInt16 = 115          // Home
    static let end: UInt16 = 119           // End
    static let pageUp: UInt16 = 116        // Page Up
    static let pageDown: UInt16 = 121      // Page Down
    static let tab: UInt16 = 48            // Tab
    static let o: UInt16 = 31              // O 键
    static let c: UInt16 = 8               // C 键
    static let one: UInt16 = 18            // 数字 1
    static let two: UInt16 = 19            // 数字 2
}

// MARK: - FFNotificationNames

/// 统一管理所有自定义 Notification.Name 常量
/// 消除散布在各文件中的字符串字面量
/// 注意：fileList* 系列通知定义在 FileListView.swift 的 extension 中，此处仅补充未定义的
extension Notification.Name {
    // 窗口/视图相关
    static let openSettings = Notification.Name("OpenSettings")
    static let refreshHiddenFiles = Notification.Name("refreshHiddenFiles")
    static let toggleDualPane = Notification.Name("ToggleDualPane")
    static let appearanceChanged = Notification.Name("AppearanceChanged")

    // 任务相关
    static let taskProgressUpdated = Notification.Name("TaskProgressUpdated")
    static let taskCompleted = Notification.Name("TaskCompleted")

    // 侧边栏相关
    static let sidebarSelectionChanged = Notification.Name("SidebarSelectionChanged")
    static let sidebarFavoritesChanged = Notification.Name("SidebarFavoritesChanged")

    // 标签相关
    static let tagsUpdated = Notification.Name("TagsUpdated")
    static let fileListAddTag = Notification.Name("FileListAddTag")
}

// MARK: - FFUserDefaultsKeys

/// 统一管理所有 UserDefaults key 常量
/// 消除散布在各文件中的字符串字面量
enum FFUserDefaultsKeys {
    static let deleteConfirmDisabled = "delete_confirm_disabled"
    static let defaultViewMode = "default_view_mode"
    static let showHiddenFiles = "show_hidden_files"
    static let defaultDualPane = "default_dual_pane"
    static let sidebarTags = "SidebarTags"
    static let sidebarFavorites = "SidebarFavorites"
    static let themeMode = "theme_mode"
}
