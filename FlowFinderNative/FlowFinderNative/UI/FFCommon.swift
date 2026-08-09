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
    // 文件内容变更（重命名等数量不变的操作）→ 列表/网格强制刷新
    static let fileListContentChanged = Notification.Name("FileListContentChanged")

    // SMB 网络卷断连重连
    static let smbVolumeDisconnected = Notification.Name("SMBVolumeDisconnected")
    static let smbVolumeReconnected = Notification.Name("SMBVolumeReconnected")
    static let smbVolumeReconnectFailed = Notification.Name("SMBVolumeReconnectFailed")

    // 快捷键设置变更（设置页录制保存后广播；MainMenu 监听后刷新菜单快捷键）
    static let shortcutsChanged = Notification.Name("FFShortcutsChanged")
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

    // 设置页：通用
    static let startupLocation = "startup_location"
    static let checkUpdateOnStartup = "check_update_on_startup"
    static let defaultViewMode = "default_view_mode"
    static let confirmFileOperations = "confirm_file_operations"
    static let defaultFileBehavior = "default_file_behavior"
    // 设置页：文件管理
    static let folderFirstSort = "folder_first_sort"
    static let keepSelectionPosition = "keep_selection_position"
    // 设置页：SMB
    static let smbDefaultDomain = "smb_default_domain"
    static let smbAutoReconnect = "smb_auto_reconnect"
    // 设置页：快捷键（MainMenu 读取并应用到菜单项）
    static let shortcutNewFolder = "shortcut_new_folder"
    static let shortcutOpenFile = "shortcut_open_file"
    static let shortcutCloseWindow = "shortcut_close_window"
    static let shortcutCopy = "shortcut_copy"
    static let shortcutCut = "shortcut_cut"
    static let shortcutPaste = "shortcut_paste"
    static let shortcutSelectAll = "shortcut_select_all"
    static let shortcutTrash = "shortcut_trash"
    static let shortcutUndo = "shortcut_undo"
    static let shortcutRedo = "shortcut_redo"
    static let shortcutListView = "shortcut_list_view"
    static let shortcutGridView = "shortcut_grid_view"
    static let shortcutRefresh = "shortcut_refresh"
    static let shortcutSearch = "shortcut_search"
    static let shortcutDuplicateScan = "shortcut_duplicate_scan"
    static let shortcutTaskPanel = "shortcut_task_panel"
    static let shortcutQuicklook = "shortcut_quicklook"
    static let shortcutDuplicate = "shortcut_duplicate"
    static let shortcutConnectServer = "shortcut_connect_server"
    static let shortcutPreferences = "shortcut_preferences"
    // 标签（侧边栏/设置页/标签弹窗共享存储）
    static let sidebarTags = "SidebarTags"
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

// MARK: - FFPaneMenuBuilder（列表/网格视图共享右键菜单）

/// 统一构建文件面板右键菜单：FileListView 与 FileGridView 共用同一套菜单结构与 action
/// （架构统一：两种视图只是排列方式不同，右键操作完全一致）。
/// 所有 item 的 action 用 Selector 字符串引用——两个视图都实现了同名 @objc 方法，
/// target 传入实际视图，运行时按 selector 分派到对应视图的实现。
enum FFPaneMenuBuilder {

    /// 构建右键菜单
    /// - Parameters:
    ///   - target: 接收 action 的视图（FileListView / FileGridView，需实现全部 selector）
    ///   - isLeft: 当前面板是否为左侧（决定"移动到/复制到另一面板"箭头方向）
    ///   - tagsSubmenu: 标签二级菜单（nil 则不添加标签项）
    static func buildMenu(for target: AnyObject, isLeft: Bool, tagsSubmenu: NSMenu?) -> NSMenu {
        let menu = NSMenu()

        // v0.7.4 修订 2：撤销/重做项（默认隐藏，有可撤销/重做操作时由 menuNeedsUpdate 显示）
        // 标题动态更新为"撤销 X"/"重做 X"，如"撤销删除"、"重做删除"
        // tag 100=撤销, 101=重做（用 tag 识别避免标题变化后匹配失败）
        let undoItem = menu.addItem(withTitle: "撤销", action: Selector("undoFromMenu:"), keyEquivalent: "z")
        undoItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "撤销")
        undoItem.isHidden = true
        undoItem.tag = 100
        let redoItem = menu.addItem(withTitle: "重做", action: Selector("redoFromMenu:"), keyEquivalent: "Z")
        redoItem.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "重做")
        redoItem.isHidden = true
        redoItem.tag = 101
        menu.addItem(.separator())

        // 1. 打开
        menu.addItem(withTitle: "打开", action: Selector("openSelected:"), keyEquivalent: "")
        // 2. 分隔线
        menu.addItem(.separator())
        // 3. 复制
        let copyItem = menu.addItem(withTitle: "复制", action: Selector("copySelected:"), keyEquivalent: "c")
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制")
        // 4. 剪切
        let cutItem = menu.addItem(withTitle: "剪切", action: Selector("cutSelected:"), keyEquivalent: "x")
        cutItem.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "剪切")
        // 5. 粘贴
        let pasteItem = menu.addItem(withTitle: "粘贴", action: Selector("pasteSelected:"), keyEquivalent: "v")
        pasteItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "粘贴")
        // 6. 分隔线
        menu.addItem(.separator())
        // 7. 移动到另一面板（箭头方向随面板）
        let moveItem = menu.addItem(withTitle: "移动到另一面板", action: Selector("moveToOtherPane:"), keyEquivalent: "")
        moveItem.image = NSImage(systemSymbolName: isLeft ? "arrow.right" : "arrow.left",
                                 accessibilityDescription: "移动到另一面板")
        // 8. 复制到另一面板
        let copyOtherItem = menu.addItem(withTitle: "复制到另一面板", action: Selector("copyToOtherPane:"), keyEquivalent: "")
        copyOtherItem.image = NSImage(systemSymbolName: isLeft ? "arrow.right.square" : "arrow.left.square",
                                      accessibilityDescription: "复制到另一面板")
        // 9. 在对侧面板打开（仅文件夹，由 menuNeedsUpdate 动态显示）
        let openOtherItem = menu.addItem(withTitle: "在对侧面板打开", action: Selector("openInOtherPane:"), keyEquivalent: "")
        openOtherItem.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "在对侧面板打开")
        openOtherItem.isHidden = true
        // 10. 分隔线
        menu.addItem(.separator())
        // 11. 重命名
        let renameItem = menu.addItem(withTitle: "重命名", action: Selector("renameSelected:"), keyEquivalent: "")
        renameItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "重命名")
        // 12. 移到废纸篓（红色文字）
        let deleteItem = menu.addItem(withTitle: "移到废纸篓", action: Selector("deleteSelected:"), keyEquivalent: "\u{7F}")
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "移到废纸篓")
        let redAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
        deleteItem.attributedTitle = NSAttributedString(string: "移到废纸篓", attributes: redAttrs)
        // 13. 分隔线
        menu.addItem(.separator())
        // 14. 新建文件夹
        let newFolderItem = menu.addItem(withTitle: "新建文件夹", action: Selector("createDirectory:"), keyEquivalent: "n")
        newFolderItem.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "新建文件夹")
        // 15. 用所选项目新建文件夹（选中数量在 menuNeedsUpdate 中动态更新标题）
        // v0.7.4 项 6：标题 "用所选 X 个项目新建文件夹"，X 由 updateMainMenu 填充
        let folderFromSelectionItem = menu.addItem(
            withTitle: "用所选项目新建文件夹",
            action: Selector("createFolderFromSelection:"),
            keyEquivalent: ""
        )
        folderFromSelectionItem.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "用所选项目新建文件夹")
        folderFromSelectionItem.isHidden = true  // 无选中时隐藏，由 updateMainMenu 控制
        // 16. 分隔线
        menu.addItem(.separator())
        // 17. 添加到我的收藏
        let favItem = menu.addItem(withTitle: "添加到我的收藏", action: Selector("addToFavorites:"), keyEquivalent: "")
        favItem.image = NSImage(systemSymbolName: "star", accessibilityDescription: "添加到我的收藏")
        // 18. 标签（二级菜单）
        if let tagsSubmenu = tagsSubmenu {
            let tagsItem = menu.addItem(withTitle: "标签", action: nil, keyEquivalent: "")
            tagsItem.image = NSImage(systemSymbolName: "tag", accessibilityDescription: "标签")
            tagsItem.submenu = tagsSubmenu
        }
        // 19. AI 自动打标签
        let aiTagItem = menu.addItem(withTitle: "AI 自动打标签", action: Selector("generateAITags:"), keyEquivalent: "")
        aiTagItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI 自动打标签")
        // 20. 查重扫描
        let dupItem = menu.addItem(withTitle: "查重扫描", action: Selector("duplicateScan:"), keyEquivalent: "")
        dupItem.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "查重扫描")
        // 21. 分隔线
        menu.addItem(.separator())
        // 22. 显示简介
        let infoItem = menu.addItem(withTitle: "显示简介", action: Selector("showInfoMenu:"), keyEquivalent: "i")
        infoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "显示简介")

        // 设置 target 与快捷键修饰键（与访达一致：⌘N 新建文件夹用 ⇧⌘N）
        for item in menu.items where item.action != nil {
            item.target = target
            if item.keyEquivalent == "n" {
                item.keyEquivalentModifierMask = [.command, .shift]
            } else if !item.keyEquivalent.isEmpty {
                item.keyEquivalentModifierMask = .command
            }
        }
        return menu
    }
}
