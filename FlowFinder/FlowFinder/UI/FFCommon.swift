import AppKit
import Combine

// MARK: - FFOpaqueContainerView

/// 实体背景容器：背景色由 layer.backgroundColor 提供（各窗口控制器自行设置动态色）。
/// 注意：isOpaque 必须返回 false——isOpaque=true 会告知 AppKit「本视图内容不变，可缓存」，
/// 主题切换时系统会跳过该视图及子树的自动重绘，导致深色模式下窗口内容不跟随（视觉不变）。
/// 背景色跟随主题由各窗口在 .appearanceChanged 时重设 layer.backgroundColor 保证。
class FFOpaqueContainerView: NSView {
    override var isOpaque: Bool { return false }
}

// MARK: - 窗口拖动拦截（2026-10-20 #1）

/// 不参与窗口拖动的普通视图。
///
/// 根因：AppKit 的 `NSView.mouseDownCanMoveWindow` 默认实现是
/// **「视图不透明（isOpaque == true）就允许拖窗口」**。NSView.isOpaque 的默认值是 true，
/// 因此工具栏里的堆栈视图、占位视图、面包屑容器这些「纯排版容器」全部成了窗口拖动区——
/// 用户在操作面板上按住一拖，动的却是整个窗口。
///
/// 修法有两种：把 isOpaque 改成 false（副作用大——会关掉主题切换时的子树重绘），
/// 或显式覆写 mouseDownCanMoveWindow（无副作用）。这里用后者。
class FFNonDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

/// 不参与窗口拖动的堆栈视图（工具栏的两行、标签条里的标签栈都用它）
class FFNonDragStackView: NSStackView {
    override var mouseDownCanMoveWindow: Bool { false }
}

/// 卡片包裹视图：卡片四周的留白属于「边框空白处」，按住可拖动窗口。
/// 卡片本体命中的是里面的面板内容，不会走到这里。
class FFCardWrapperView: NSView, FFRegionAware {

    /// 卡片四周的 8pt 留白属于窗口区：按住可拖动窗口。
    /// 卡片本体命中的是里面的面板内容，不会走到这里。
    var ffRegion: FFRegion { .window }
}

// MARK: - 应用自管的窗口拖动（2026-10-20 #1）

/// 窗口拖动的唯一入口。
///
/// 为什么不用系统那套：窗口顶部 28pt 是系统标题栏的拖动区，正好压在操作面板工具栏
/// 的第一行上——「按住操作面板拖动」实际拖走的是整个窗口，这是用户抱怨的核心。
/// `NSWindow.isMovable = false` 可以关掉系统对标题栏/背景的拖动，
/// 但代价是窗口完全不能被系统拖动，于是只能自己按区域放行：
/// - 侧栏空白          → 拖窗口
/// - 面板卡片四周留白  → 拖窗口
/// - 操作面板本体      → 拖面板（不是拖窗口）
///
/// 官方文档也推荐这个组合：禁用服务端拖动后，在 NSWindow 子类里自行处理
/// mouseDown / mouseDragged / mouseUp。
enum FFWindowDrag {

    /// 从 mouseDown 开始跑一次跟踪循环，把鼠标位移换算成窗口位移
    static func begin(from view: NSView) {
        guard let window = view.window else { return }
        let startPoint = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let now = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: startOrigin.x + (now.x - startPoint.x),
                                         y: startOrigin.y + (now.y - startPoint.y)))
        }
    }
}


// MARK: - FFNotificationNames

/// 统一管理所有自定义 Notification.Name 常量
/// 消除散布在各文件中的字符串字面量
/// 注意：fileList* 系列通知定义在 FileListView.swift 的 extension 中，此处仅补充未定义的
extension Notification.Name {

    /// 标签缓存预热完成（2026-10-20 #4）——列表据此刷新标签色点
    static let ffTagCacheWarmed = Notification.Name("FFTagCacheWarmed")
    // 窗口/视图相关
    static let openSettings = Notification.Name("OpenSettings")
    /// 2026-10-19 #10：侧栏显隐（侧栏按钮或 ⌥⌘S 发出，窗口统一执行动画）
    static let sidebarDidToggleVisibility = Notification.Name("FFSidebarDidToggleVisibility")
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

    // Wave2 P0-4（多窗口）：FSEvents 文件系统变更广播。FSEvents watcher 是 CoreBridge
    // 进程级单例（重复 start 会先 stop 旧 watcher），故挂在 AppDelegate 生命周期上，
    // 变更经此通知广播，各 MainWindowController 自行判断影响并刷新本窗口面板。
    static let fileSystemDidChange = Notification.Name("FFFileSystemDidChange")

    // Wave4 Task 4: 列表密度 / 网格图标大小变更广播（设置页与手势双入口共用，
    // 所有 FileListView / FileGridView / 设置滑杆监听后同步刷新）
    static let listDensityChanged = Notification.Name("FFListDensityChanged")
    static let gridIconSizeChanged = Notification.Name("FFGridIconSizeChanged")
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

    // Wave2 P0-3：运行时键位设置键（暂无录制器 UI，由 ShortcutCenter 读取，缺省回退内置默认值）
    static let shortcutRename = "shortcut_rename"
    static let shortcutDelete = "shortcut_delete"
    static let shortcutGoUp = "shortcut_go_up"

    /// 全部快捷键设置键（设置页「恢复默认」统一清空）
    static let allShortcutKeys: [String] = [
        shortcutNewFolder, shortcutOpenFile, shortcutCloseWindow, shortcutCopy,
        shortcutCut, shortcutPaste, shortcutSelectAll, shortcutTrash,
        shortcutUndo, shortcutRedo, shortcutListView, shortcutGridView,
        shortcutRefresh, shortcutSearch, shortcutDuplicateScan, shortcutTaskPanel,
        shortcutQuicklook, shortcutDuplicate, shortcutConnectServer, shortcutPreferences,
        shortcutRename, shortcutDelete, shortcutGoUp,
    ]

    // 任务 T12: 删除确认"不再询问"开关（全入口统一读取；勾选后跳过确认弹窗直接执行）
    static let deleteConfirmDisabled = "delete_confirm_disabled"

    // Wave4 Task 4: 视图密度与缩放（列表密度三档 + 网格图标大小，跨会话记忆）
    static let listDensity = "list_density"
    static let gridIconSize = "grid_icon_size"
}

// MARK: - FFListDensity（Wave4 Task 4: 列表密度三档）

/// 列表密度三档：紧凑 22 / 标准 26 / 宽松 32（带标签行 42/48/56 联动）。
/// UserDefaults key `list_density`，默认标准；切换经 .listDensityChanged 广播刷新。
enum FFListDensity: String, CaseIterable {
    case compact = "compact"
    case standard = "standard"
    case relaxed = "relaxed"

    /// 基础行高（无标签文件行）。2026-10-19 #11：标准档 30pt 单行
    var baseRowHeight: CGFloat {
        switch self {
        case .compact: return 26
        case .standard: return 30
        case .relaxed: return 36
        }
    }

    /// 带标签行高（文件名行 + 标签药丸行，随档位联动）
    var taggedRowHeight: CGFloat {
        switch self {
        case .compact: return 44
        case .standard: return 48
        case .relaxed: return 56
        }
    }

    /// 设置页展示名
    var title: String {
        switch self {
        case .compact: return "紧凑"
        case .standard: return "标准"
        case .relaxed: return "宽松"
        }
    }

    /// 读取当前密度（无已保存设置时回退标准档）
    static var current: FFListDensity {
        guard let raw = UserDefaults.standard.string(forKey: FFUserDefaultsKeys.listDensity),
              let density = FFListDensity(rawValue: raw) else { return .standard }
        return density
    }
}

// MARK: - ShortcutCenter（Wave2 P0-3：运行时快捷键统一读取）

/// 运行时快捷键统一消费入口。
///
/// 背景：设置页 ShortcutRecorderView 将格式化字符串（如 "⌘N"、"空格键"、"⌘⇧Z"）写入
/// UserDefaults 的 shortcut_* 键，但此前仅菜单项键位展示（MainMenu.applyShortcutSettings）
/// 消费了其中一部分，keyDown / 全局 monitor 中的键位判定全部硬编码（审计 menu P0-3）。
///
/// 本枚举职责：
/// - 统一解析 shortcut_* 存储的字符串为 (keyCode, modifiers)，供运行时按键比对；
/// - 未保存过设置的键回退内置默认值（与 Wave2 之前的硬编码行为一致，未自定义的用户零感知）；
/// - 每次按键实时读取 UserDefaults，设置页改键后立即生效（无需重启、无需监听通知）。
enum ShortcutCenter {

    /// 键位绑定：键码 + 修饰键（仅 .command/.option/.control/.shift 的 rawValue 组合）
    typealias Binding = (keyCode: UInt, modifiers: UInt)

    /// 内置默认值（= Wave2 之前的硬编码键位）
    private static let defaultBindings: [String: Binding] = [
        FFUserDefaultsKeys.shortcutQuicklook: (49, 0),                        // 空格 → QuickLook
        FFUserDefaultsKeys.shortcutRename: (36, 0),                           // Return → 内联重命名
        FFUserDefaultsKeys.shortcutDelete: (51, 0),                           // Del → 移到废纸篓
        FFUserDefaultsKeys.shortcutOpenFile: (31, commandRaw),                // ⌘O → 打开
        FFUserDefaultsKeys.shortcutGoUp: (126, commandRaw),                   // ⌘↑ → 上一级
        FFUserDefaultsKeys.shortcutListView: (18, commandRaw),                // ⌘1 → 列表视图
        FFUserDefaultsKeys.shortcutGridView: (19, commandRaw),                // ⌘2 → 网格视图
        FFUserDefaultsKeys.shortcutDuplicate: (2, commandRaw),                // ⌘D → 复制选中项
    ]

    /// ⌘ 修饰键 rawValue（defaultBindings 字面量使用）
    private static let commandRaw = UInt(NSEvent.ModifierFlags.command.rawValue)

    /// 读取指定功能的当前键位（keyCode + 修饰键）。无已保存设置时返回内置默认值。
    static func current(_ key: String) -> Binding? {
        if let stored = UserDefaults.standard.string(forKey: key), let parsed = parse(stored) {
            return parsed
        }
        return defaultBindings[key]
    }

    /// 判定按键事件是否命中指定功能的键位设置。
    /// 修饰键仅比对四个真实修饰键（.command/.option/.control/.shift）——Enter 自带
    /// .numericPad、部分按键带 .function 标志，参与比对会误判不命中。
    /// 特例：shortcut_rename 配置为 Return(36) 时同时接受数字小键盘 Enter(76)，与历史行为一致。
    static func eventMatches(_ key: String, event: NSEvent) -> Bool {
        guard let binding = current(key) else { return false }
        var keyCodeMatch = event.keyCode == UInt16(binding.keyCode)
        if !keyCodeMatch, binding.keyCode == 36, event.keyCode == 76 {
            keyCodeMatch = true  // 数字小键盘 Enter 别名
        }
        guard keyCodeMatch else { return false }
        let realModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return realModifiers.rawValue == binding.modifiers
    }

    /// 解析设置页保存的快捷键字符串（ShortcutRecorderView.formatShortcut 的输出格式，
    /// 修饰键符号顺序不限）为键位绑定。无法解析时返回 nil（由调用方回退默认值）。
    private static func parse(_ shortcut: String) -> Binding? {
        var modifiers: UInt = 0
        var rest = Substring(shortcut)
        while let first = rest.first {
            switch first {
            case "⌘":
                modifiers |= commandRaw
                rest = rest.dropFirst()
            case "⇧":
                modifiers |= UInt(NSEvent.ModifierFlags.shift.rawValue)
                rest = rest.dropFirst()
            case "⌥":
                modifiers |= UInt(NSEvent.ModifierFlags.option.rawValue)
                rest = rest.dropFirst()
            case "⌃":
                modifiers |= UInt(NSEvent.ModifierFlags.control.rawValue)
                rest = rest.dropFirst()
            default:
                guard let keyCode = keyCode(for: String(rest)) else { return nil }
                return (keyCode, modifiers)
            }
        }
        return nil
    }

    /// 可读按键符号 → 键码。功能键/特殊键显式映射；字母/数字/符号反查 ANSI 键码表
    /// （与 ShortcutRecorderView.translateKeyCode 的正向映射一一对应）。
    private static func keyCode(for symbol: String) -> UInt? {
        switch symbol {
        case "空格键": return 49
        case "↩": return 36
        case "⌫": return 51
        case "⎋": return 53
        case "⇥": return 48
        case "←": return 123
        case "→": return 124
        case "↑": return 126
        case "↓": return 125
        default:
            break
        }
        if symbol.hasPrefix("F"), symbol.count > 1, let fn = Int(symbol.dropFirst()), fn >= 1, fn <= 19 {
            // 与 ShortcutRecorderView.formatShortcut 的 F 键编号规则一致（F1=122）
            return UInt(122 + fn - 1)
        }
        return reverseKeyMap[symbol]
            ?? reverseKeyMap[symbol.uppercased()]
            ?? reverseKeyMap[symbol.lowercased()]
    }

    /// ANSI 美式键盘布局的字符 → 键码反查表（正向来源：ShortcutRecorderView.translateKeyCode）
    private static let reverseKeyMap: [String: UInt] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7,
        "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15,
        "Y": 16, "T": 17, "1": 18, "2": 19, "3": 20, "4": 21, "5": 22,
        "6": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35,
        "L": 37, "J": 38, "'": 39, "K": 40, ";": 41,
        "\\": 42, ",": 43, "/": 44, "N": 45, "M": 46, ".": 47, "`": 50,
    ]
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
    /// 详情栏布局尺寸（高度/图标区宽/列宽）变更广播：左右两个面板的详情栏互相同步
    static let FFDetailsBarLayoutChanged = Notification.Name("FFDetailsBarLayoutChanged")
}

// MARK: - FFSwipeThrottler（两指轻扫节流）

/// Wave3 Task 5: 两指轻扫节流器——前进/后退动画进行中忽略重复轻扫（500ms 节流窗口）。
/// FileListView 与 FileGridView 共用同一套轻扫判定逻辑（两个面板各自独立实例）。
/// 主线程专用（仅在 swipeWithEvent 中调用）。
final class FFSwipeThrottler {
    /// 节流窗口（秒）
    private let interval: TimeInterval
    /// 上次接受轻扫的时间戳
    private var lastAcceptedAt: TimeInterval = 0

    init(interval: TimeInterval = 0.5) {
        self.interval = interval
    }

    /// 距上次有效轻扫超过节流窗口时返回 true，并记录本次时间戳
    func shouldAccept() -> Bool {
        let now = Date().timeIntervalSince1970
        guard now - lastAcceptedAt >= interval else { return false }
        lastAcceptedAt = now
        return true
    }
}

// MARK: - FFPaneMenuBuilder（列表/网格视图共享右键菜单）

/// 统一构建文件面板右键菜单：FileListView 与 FileGridView 共用同一套菜单结构与 action
/// （架构统一：两种视图只是排列方式不同，右键操作完全一致）。
/// 所有 item 的 action 用 #selector 静态引用 FFPaneActionsController 的方法，
/// target 传入 actionsController（v0.7.3 起两个视图的操作统一委托给控制器）。
/// 用 #selector 而非 Selector("字符串")：方法改名/删除时编译期即报错，
/// 避免菜单静默失效（旧写法曾导致 20 个 selector 失去静态检查）。
enum FFPaneMenuBuilder {

    /// 构建右键菜单
    /// - Parameters:
    ///   - target: 接收 action 的对象（通常为 FFPaneActionsController，需实现全部 selector）
    ///   - isLeft: 当前面板是否为左侧（决定"移动到/复制到另一面板"箭头方向）
    ///   - tagsSubmenu: 标签二级菜单（nil 则不添加标签项）
    static func buildMenu(for target: AnyObject, isLeft: Bool, tagsSubmenu: NSMenu?) -> NSMenu {
        let menu = NSMenu()

        // v0.7.4 修订 2：撤销/重做项（默认隐藏，有可撤销/重做操作时由 menuNeedsUpdate 显示）
        // 标题动态更新为"撤销 X"/"重做 X"，如"撤销删除"、"重做删除"
        // tag 100=撤销, 101=重做（用 tag 识别避免标题变化后匹配失败）
        let undoItem = menu.addItem(withTitle: "撤销", action: #selector(FFPaneActionsController.undoFromMenu(_:)), keyEquivalent: "z")
        undoItem.image = FFIcon.template(.undo2, size: FFIcon.Metrics.menu)
        undoItem.isHidden = true
        undoItem.tag = 100
        let redoItem = menu.addItem(withTitle: "重做", action: #selector(FFPaneActionsController.redoFromMenu(_:)), keyEquivalent: "Z")
        redoItem.image = FFIcon.template(.redo2, size: FFIcon.Metrics.menu)
        redoItem.isHidden = true
        redoItem.tag = 101
        menu.addItem(.separator())

        // 1. 打开
        menu.addItem(withTitle: "打开", action: #selector(FFPaneActionsController.openSelected(_:)), keyEquivalent: "")
        // B7 #4：在新标签页中打开（仅单个文件夹时显示，由 menuNeedsUpdate 控制）
        let newTabItem = menu.addItem(withTitle: "在新标签页中打开",
                                      action: #selector(FFPaneActionsController.openInNewTab(_:)),
                                      keyEquivalent: "")
        newTabItem.image = FFIcon.template(.externalLink, size: FFIcon.Metrics.menu)
        newTabItem.isHidden = true
        // 2. 分隔线
        menu.addItem(.separator())
        // 3. 复制
        let copyItem = menu.addItem(withTitle: "复制", action: #selector(FFPaneActionsController.copySelected(_:)), keyEquivalent: "c")
        copyItem.image = FFIcon.template(.copy, size: FFIcon.Metrics.menu)
        // 4. 剪切
        let cutItem = menu.addItem(withTitle: "剪切", action: #selector(FFPaneActionsController.cutSelected(_:)), keyEquivalent: "x")
        cutItem.image = FFIcon.template(.scissors, size: FFIcon.Metrics.menu)
        // 5. 粘贴
        let pasteItem = menu.addItem(withTitle: "粘贴", action: #selector(FFPaneActionsController.pasteSelected(_:)), keyEquivalent: "v")
        pasteItem.image = FFIcon.template(.clipboardPaste, size: FFIcon.Metrics.menu)
        // Wave2 P1：拷贝路径（多选时每行一个路径，写入系统剪贴板）
        let copyPathItem = menu.addItem(withTitle: "拷贝路径", action: #selector(FFPaneActionsController.copyPathsSelected(_:)), keyEquivalent: "")
        copyPathItem.image = FFIcon.template(.link, size: FFIcon.Metrics.menu)
        // 6. 分隔线
        menu.addItem(.separator())
        // 7. 移动到另一面板（箭头方向随面板）
        let moveItem = menu.addItem(withTitle: "移动到另一面板", action: #selector(FFPaneActionsController.moveToOtherPane(_:)), keyEquivalent: "")
        moveItem.image = FFIcon.template(isLeft ? .arrowRight : .arrowLeft, size: FFIcon.Metrics.menu)
        // 8. 复制到另一面板
        let copyOtherItem = menu.addItem(withTitle: "复制到另一面板", action: #selector(FFPaneActionsController.copyToOtherPane(_:)), keyEquivalent: "")
        copyOtherItem.image = FFIcon.template(.copy, size: FFIcon.Metrics.menu)
        // 9. 在对侧面板打开（仅文件夹，由 menuNeedsUpdate 动态显示）
        let openOtherItem = menu.addItem(withTitle: "在对侧面板打开", action: #selector(FFPaneActionsController.openInOtherPane(_:)), keyEquivalent: "")
        openOtherItem.image = FFIcon.template(.columns2, size: FFIcon.Metrics.menu)
        openOtherItem.isHidden = true
        // 10. 分隔线
        menu.addItem(.separator())
        // 11. 重命名
        let renameItem = menu.addItem(withTitle: "重命名", action: #selector(FFPaneActionsController.renameSelected(_:)), keyEquivalent: "")
        renameItem.image = FFIcon.template(.pencil, size: FFIcon.Metrics.menu)
        // 12. 移到废纸篓（红色文字）
        let deleteItem = menu.addItem(withTitle: "移到废纸篓", action: #selector(FFPaneActionsController.deleteSelected(_:)), keyEquivalent: "\u{7F}")
        deleteItem.image = FFIcon.template(.trash2, size: FFIcon.Metrics.menu)
        let redAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
        deleteItem.attributedTitle = NSAttributedString(string: "移到废纸篓", attributes: redAttrs)
        // 13. 分隔线
        menu.addItem(.separator())
        // 14. 新建文件夹
        let newFolderItem = menu.addItem(withTitle: "新建文件夹", action: #selector(FFPaneActionsController.createDirectory(_:)), keyEquivalent: "n")
        newFolderItem.image = FFIcon.template(.folderPlus, size: FFIcon.Metrics.menu)
        // 15. 用所选项目新建文件夹（选中数量在 menuNeedsUpdate 中动态更新标题）
        // v0.7.4 项 6：标题 "用所选 X 个项目新建文件夹"，X 由 updateMainMenu 填充
        let folderFromSelectionItem = menu.addItem(
            withTitle: "用所选项目新建文件夹",
            action: #selector(FFPaneActionsController.createFolderFromSelection(_:)),
            keyEquivalent: ""
        )
        folderFromSelectionItem.image = FFIcon.template(.folderPlus, size: FFIcon.Metrics.menu)
        folderFromSelectionItem.isHidden = true  // 无选中时隐藏，由 updateMainMenu 控制
        // 16. 分隔线
        menu.addItem(.separator())
        // 17. 添加到我的收藏
        let favItem = menu.addItem(withTitle: "添加到我的收藏", action: #selector(FFPaneActionsController.addToFavorites(_:)), keyEquivalent: "")
        favItem.image = FFIcon.template(.star, size: FFIcon.Metrics.menu)
        // 18. 标签（二级菜单）
        if let tagsSubmenu = tagsSubmenu {
            let tagsItem = menu.addItem(withTitle: "标签", action: nil, keyEquivalent: "")
            tagsItem.image = FFIcon.template(.tag, size: FFIcon.Metrics.menu)
            tagsItem.submenu = tagsSubmenu
        }
        // 19. AI 自动打标签
        let aiTagItem = menu.addItem(withTitle: "AI 自动打标签", action: #selector(FFPaneActionsController.generateAITags(_:)), keyEquivalent: "")
        aiTagItem.image = FFIcon.template(.sparkles, size: FFIcon.Metrics.menu)
        // 20. 查重扫描
        let dupItem = menu.addItem(withTitle: "查重扫描", action: #selector(FFPaneActionsController.duplicateScan(_:)), keyEquivalent: "")
        dupItem.image = FFIcon.template(.scanSearch, size: FFIcon.Metrics.menu)
        // 21. 分隔线
        menu.addItem(.separator())
        // 22. 显示简介
        let infoItem = menu.addItem(withTitle: "显示简介", action: #selector(FFPaneActionsController.showInfoMenu(_:)), keyEquivalent: "i")
        infoItem.image = FFIcon.template(.info, size: FFIcon.Metrics.menu)

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

// MARK: - FFPaneStateOverlayView（任务 T12：统一加载/空/错误/操作状态视图）

/// 面板状态呈现模式。
enum FFPaneOverlayMode: Equatable {
    case content        // 正常内容，overlay 隐藏
    case loading        // 加载中（列表为空时全屏）
    case empty          // 空状态（全屏）
    case error          // 错误（列表为空时全屏，否则顶部横幅）
    case operation      // 删除/撤销/重做进行中（顶部横幅，不遮挡列表）
}

/// 错误/空状态下的"重试"语义。
enum FFPaneRetryKind: Equatable {
    case none           // 无重试
    case reload         // 重新加载目录（refresh）
    case deleteRetry    // 重试删除失败项（deleteSelected，失败项仍保留在选中集）
}

/// 面板状态 → 呈现描述（纯函数，由 PaneState 真值驱动，不复制业务状态）。
// B7 #4：文件夹右键「在新标签页中打开」
extension Notification.Name {
    static let fileListDidOpenInNewTab = Notification.Name("fileListDidOpenInNewTab")
}

struct FFPaneStateDescriptor: Equatable {
    let mode: FFPaneOverlayMode
    let isFullScreen: Bool
    let icon: FFIconName?
    let title: String
    let subtitle: String
    let showsSpinner: Bool
    let showsRetry: Bool
    let retryKind: FFPaneRetryKind
    /// 权限类错误：显示「打开系统设置」直达「隐私与安全性 › 文件和文件夹」
    var showsOpenSettings: Bool = false

    /// 由 PaneState 计算呈现描述。优先级：删除中 > 错误 > 加载 > 空 > 内容。
    /// - 删除中：顶部横幅进度（不遮挡列表）
    /// - 错误 + 列表为空：全屏错误 + 重试
    /// - 错误 + 列表非空（删除部分失败）：顶部横幅 + 重试删除失败项
    /// - 加载 + 列表为空：全屏加载
    /// - 列表为空：区分首次无路径 / 搜索无结果 / 标签筛选 / 文件夹为空
    static func make(from state: PaneState) -> FFPaneStateDescriptor {
        if state.isDeleting {
            let count = state.selectedFiles.count
            return FFPaneStateDescriptor(
                mode: .operation, isFullScreen: false,
                icon: .refreshCw,
                title: count > 0 ? "正在删除 \(count) 个项目…" : "正在处理文件操作…",
                subtitle: "操作在后台执行，完成后列表自动更新",
                showsSpinner: true, showsRetry: false, retryKind: .none
            )
        }

        if let error = state.error {
            // J5：错误正文不得是系统英文原文，统一经 FFErrorText 转成中文 + 下一步
            let msg = FFErrorText.humanize(error)
            if state.files.isEmpty {
                let retryKind: FFPaneRetryKind = state.deleteFailedPaths.isEmpty ? .reload : .deleteRetry
                return FFPaneStateDescriptor(
                    mode: .error, isFullScreen: true, icon: .triangleAlert,
                    title: msg.title,
                    subtitle: msg.detail.isEmpty ? "点「重试」再试一次。" : msg.detail,
                    showsSpinner: false, showsRetry: true, retryKind: retryKind,
                    showsOpenSettings: msg.isPermission
                )
            }
            let failedCount = state.deleteFailedPaths.count
            return FFPaneStateDescriptor(
                mode: .error, isFullScreen: false, icon: .triangleAlert,
                title: failedCount > 0 ? "\(failedCount) 个项目删除失败" : msg.title,
                subtitle: msg.detail.isEmpty ? "点「重试」再试一次。" : msg.detail,
                showsSpinner: false, showsRetry: true,
                retryKind: failedCount > 0 ? .deleteRetry : .reload,
                showsOpenSettings: msg.isPermission
            )
        }

        if state.isLoading && state.files.isEmpty {
            return FFPaneStateDescriptor(
                mode: .loading, isFullScreen: true, icon: nil,
                title: "正在加载…", subtitle: "",
                showsSpinner: true, showsRetry: false, retryKind: .none
            )
        }

        if state.files.isEmpty {
            if state.path.isEmpty {
                return FFPaneStateDescriptor(
                    mode: .empty, isFullScreen: true, icon: .panelLeft,
                    title: "打开一个文件夹",
                    subtitle: "在侧边栏选择一个文件夹开始浏览",
                    showsSpinner: false, showsRetry: false, retryKind: .none
                )
            }
            if !state.searchQuery.isEmpty {
                return FFPaneStateDescriptor(
                    mode: .empty, isFullScreen: true, icon: .search,
                    title: "未找到匹配项",
                    subtitle: "没有名称与「\(state.searchQuery)」匹配的项目",
                    showsSpinner: false, showsRetry: false, retryKind: .none
                )
            }
            if state.tagFilter != nil {
                return FFPaneStateDescriptor(
                    mode: .empty, isFullScreen: true, icon: .tag,
                    title: "没有符合所选标签的项目",
                    subtitle: "移除标签筛选或选择其他标签",
                    showsSpinner: false, showsRetry: false, retryKind: .none
                )
            }
            return FFPaneStateDescriptor(
                mode: .empty, isFullScreen: true, icon: .folder,
                title: "此文件夹为空",
                subtitle: "将文件拖到这里开始整理",
                showsSpinner: false, showsRetry: false, retryKind: .none
            )
        }

        return FFPaneStateDescriptor(
            mode: .content, isFullScreen: false, icon: nil,
            title: "", subtitle: "",
            showsSpinner: false, showsRetry: false, retryKind: .none
        )
    }
}

/// 面板状态浮层视图：全屏（loading/empty/error）+ 顶部横幅（operation/删除部分失败）。
/// 由 PaneState 真值驱动：自行订阅 viewModel.$state（主线程），状态回 content 时隐藏。
/// 不遮挡列表布局——浮层是独立叠加层，列表布局与约束不受任何状态切换影响。
final class FFPaneStateOverlayView: NSView {

    weak var viewModel: PaneViewModel? {
        didSet {
            cancellable?.cancel()
            guard let viewModel = viewModel else {
                apply(FFPaneStateDescriptor.make(from: PaneState()))
                return
            }
            cancellable = viewModel.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.apply(FFPaneStateDescriptor.make(from: state))
                }
            apply(FFPaneStateDescriptor.make(from: viewModel.state))
        }
    }

    private var cancellable: AnyCancellable?
    private let fullStack = NSStackView()
    private let fullSpinner = NSProgressIndicator()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    /// 权限类错误时的定向引导（J5：无权限不能只告诉用户「失败了」）
    private let settingsButton = NSButton(title: "打开系统设置", target: nil, action: nil)
    private let bannerView = NSView()
    private let bannerSpinner = NSProgressIndicator()
    private let bannerIcon = NSImageView()
    private let bannerLabel = NSTextField(labelWithString: "")
    private let bannerSubtitle = NSTextField(labelWithString: "")
    private let bannerRetryButton = NSButton(title: "重试", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        apply(FFPaneStateDescriptor.make(from: PaneState()))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        apply(FFPaneStateDescriptor.make(from: PaneState()))
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        fullSpinner.style = .spinning
        fullSpinner.controlSize = .regular
        fullSpinner.isDisplayedWhenStopped = false
        fullSpinner.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = NSColor.secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = NSColor.secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 3
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        retryButton.bezelStyle = .rounded
        retryButton.controlSize = .small
        retryButton.font = NSFont.systemFont(ofSize: 11)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.target = self
        retryButton.action = #selector(retryTapped)

        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .small
        settingsButton.font = NSFont.systemFont(ofSize: 11)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.target = self
        settingsButton.action = #selector(openPrivacySettings)
        settingsButton.isHidden = true

        fullStack.orientation = .vertical
        fullStack.alignment = .centerX
        fullStack.spacing = 8
        fullStack.translatesAutoresizingMaskIntoConstraints = false
        fullStack.addArrangedSubview(fullSpinner)
        fullStack.addArrangedSubview(iconView)
        fullStack.addArrangedSubview(titleLabel)
        fullStack.addArrangedSubview(subtitleLabel)
        fullStack.addArrangedSubview(retryButton)
        fullStack.addArrangedSubview(settingsButton)

        bannerView.wantsLayer = true
        bannerView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.98).cgColor
        bannerView.translatesAutoresizingMaskIntoConstraints = false

        bannerSpinner.style = .spinning
        bannerSpinner.controlSize = .small
        bannerSpinner.isDisplayedWhenStopped = false
        bannerSpinner.translatesAutoresizingMaskIntoConstraints = false

        bannerIcon.imageScaling = .scaleProportionallyDown
        bannerIcon.contentTintColor = NSColor.systemYellow
        bannerIcon.translatesAutoresizingMaskIntoConstraints = false

        bannerLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        bannerLabel.textColor = NSColor.labelColor
        bannerLabel.lineBreakMode = .byTruncatingTail
        bannerLabel.translatesAutoresizingMaskIntoConstraints = false

        bannerSubtitle.font = NSFont.systemFont(ofSize: 10)
        bannerSubtitle.textColor = NSColor.secondaryLabelColor
        bannerSubtitle.lineBreakMode = .byTruncatingMiddle
        bannerSubtitle.translatesAutoresizingMaskIntoConstraints = false

        bannerRetryButton.bezelStyle = .rounded
        bannerRetryButton.controlSize = .small
        bannerRetryButton.font = NSFont.systemFont(ofSize: 10)
        bannerRetryButton.translatesAutoresizingMaskIntoConstraints = false
        bannerRetryButton.target = self
        bannerRetryButton.action = #selector(retryTapped)

        bannerView.addSubview(bannerSpinner)
        bannerView.addSubview(bannerIcon)
        bannerView.addSubview(bannerLabel)
        bannerView.addSubview(bannerSubtitle)
        bannerView.addSubview(bannerRetryButton)

        addSubview(fullStack)
        addSubview(bannerView)

        NSLayoutConstraint.activate([
            fullStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            fullStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            fullStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            fullStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            fullSpinner.widthAnchor.constraint(equalToConstant: 24),
            fullSpinner.heightAnchor.constraint(equalToConstant: 24),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            bannerView.topAnchor.constraint(equalTo: topAnchor),
            bannerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            bannerSpinner.leadingAnchor.constraint(equalTo: bannerView.leadingAnchor, constant: 12),
            bannerSpinner.centerYAnchor.constraint(equalTo: bannerView.centerYAnchor, constant: -8),
            bannerIcon.leadingAnchor.constraint(equalTo: bannerView.leadingAnchor, constant: 12),
            bannerIcon.centerYAnchor.constraint(equalTo: bannerView.centerYAnchor, constant: -8),
            bannerIcon.widthAnchor.constraint(equalToConstant: 14),
            bannerIcon.heightAnchor.constraint(equalToConstant: 14),

            bannerLabel.leadingAnchor.constraint(equalTo: bannerSpinner.trailingAnchor, constant: 8),
            bannerLabel.trailingAnchor.constraint(lessThanOrEqualTo: bannerRetryButton.leadingAnchor, constant: -8),
            bannerLabel.topAnchor.constraint(equalTo: bannerView.topAnchor, constant: 6),

            bannerSubtitle.leadingAnchor.constraint(equalTo: bannerLabel.leadingAnchor),
            bannerSubtitle.trailingAnchor.constraint(lessThanOrEqualTo: bannerRetryButton.leadingAnchor, constant: -8),
            bannerSubtitle.topAnchor.constraint(equalTo: bannerLabel.bottomAnchor, constant: 1),
            bannerSubtitle.bottomAnchor.constraint(equalTo: bannerView.bottomAnchor, constant: -6),

            bannerRetryButton.trailingAnchor.constraint(equalTo: bannerView.trailingAnchor, constant: -12),
            bannerRetryButton.centerYAnchor.constraint(equalTo: bannerView.centerYAnchor),
        ])
    }

    /// 应用状态描述：全屏/横幅二选一，content 时整体隐藏。
    private func apply(_ descriptor: FFPaneStateDescriptor) {
        FFDebug.log("[STATE-OVERLAY] mode=\(descriptor.mode) title=\(descriptor.title) showsRetry=\(descriptor.showsRetry) isMainThread=\(Thread.isMainThread)")
        let showsFull = descriptor.mode != .content && descriptor.mode != .operation && descriptor.isFullScreen
        let showsBanner = descriptor.mode != .content && !showsFull

        isHidden = descriptor.mode == .content
        fullStack.isHidden = !showsFull
        bannerView.isHidden = !showsBanner

        if showsFull {
            if descriptor.mode == .loading {
                fullSpinner.isHidden = false
                fullSpinner.startAnimation(nil)
                iconView.isHidden = true
                subtitleLabel.isHidden = true
                retryButton.isHidden = true
            } else {
                fullSpinner.isHidden = true
                fullSpinner.stopAnimation(nil)
                iconView.isHidden = false
                iconView.image = descriptor.icon.map {
                    FFIcon.image($0, size: 44, color: .secondaryLabelColor)
                }
                subtitleLabel.isHidden = descriptor.subtitle.isEmpty
                subtitleLabel.stringValue = descriptor.subtitle
                retryButton.isHidden = !descriptor.showsRetry
                settingsButton.isHidden = !descriptor.showsOpenSettings
            }
            titleLabel.stringValue = descriptor.title
        } else {
            fullSpinner.stopAnimation(nil)
            fullSpinner.isHidden = true
        }

        if showsBanner {
            bannerLabel.stringValue = descriptor.title
            bannerSubtitle.stringValue = descriptor.subtitle
            bannerSubtitle.isHidden = descriptor.subtitle.isEmpty
            bannerRetryButton.isHidden = !descriptor.showsRetry
            if descriptor.showsSpinner {
                bannerSpinner.isHidden = false
                bannerSpinner.startAnimation(nil)
                bannerIcon.isHidden = true
            } else {
                bannerSpinner.isHidden = true
                bannerSpinner.stopAnimation(nil)
                bannerIcon.isHidden = false
                bannerIcon.image = descriptor.icon.map {
                    FFIcon.image($0, size: 14, color: .secondaryLabelColor)
                }
            }
        } else {
            bannerSpinner.stopAnimation(nil)
            bannerSpinner.isHidden = true
        }
    }

    /// 命中穿透：仅保留"重试"按钮与顶部横幅的交互，其余区域穿透到下层列表。
    /// 全屏空/加载/错误状态下列表为空，穿透可保留空白区右键菜单（新建文件夹等）。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let hit = super.hitTest(point) else { return nil }
        if hit === retryButton || hit === bannerRetryButton || hit === settingsButton { return hit }
        if hit === bannerView || hit.isDescendant(of: bannerView) { return hit }
        return nil
    }

    /// 打开「系统设置 › 隐私与安全性 › 文件和文件夹」，让用户就地授权。
    @objc private func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
        if let url = url {
            NSWorkspace.shared.open(url)
        }
    }

    /// 重试：按描述符的重试语义分派（reload → refresh；deleteRetry → 重删失败项）。
    @objc private func retryTapped() {
        guard let viewModel = viewModel else { return }
        switch FFPaneStateDescriptor.make(from: viewModel.state).retryKind {
        case .reload:
            viewModel.refresh()
        case .deleteRetry:
            viewModel.deleteSelected()
        case .none:
            break
        }
    }
}

// MARK: - T13: 文件条目无障碍标签（VoiceOver）

/// 文件条目无障碍标签组合纯函数（T13）。
/// 供 FileListView/FileGridView/SearchPanel 复用，保证朗读文本一致。
enum FileEntryAccessibility {
    /// 组合"文件名 + 类型 + 大小"的可读标签。
    static func label(for entry: FileEntry) -> String {
        var parts: [String] = [entry.name]
        parts.append(entry.kindDescription)
        if !entry.isDirectory {
            parts.append(entry.formattedSize)
        }
        return parts.joined(separator: "，")
    }

    /// 目录条目（侧边栏）标签：名称 + 选中状态后缀。
    static func sidebarLabel(name: String, isSelected: Bool) -> String {
        isSelected ? "\(name)，已选中" : name
    }

    /// 搜索结果的详情文本（选中搜索结果时展示）。
    static func searchResultLabel(_ result: FFSearchResult) -> String {
        var parts: [String] = [result.name]
        if result.size > 0 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
            formatter.countStyle = .file
            parts.append(formatter.string(fromByteCount: Int64(result.size)))
        }
        return parts.joined(separator: "，")
    }
}

// MARK: - T13: reduced-motion 动画时长

/// 系统"减弱动态效果"开启时动画时长为 0（禁用动画）。
enum FFMotion {
    /// 返回系统 reduced-motion 感知的动画时长。
    static func animationDuration(_ proposed: TimeInterval) -> TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : proposed
    }
}

/// 分隔线手柄光效纯计算（v0.7.6 发布后修复轮）。
/// 设计文档：docs/superpowers/specs/2026-08-28-divider-handle-glow-follow-design.md
/// FFSplitView 负责视觉接线，本枚举只做可单元测试的数学核心。
enum FFDividerGlowMath {
    /// 渐隐半径（pt）：亮点上下各 120pt 渐隐至透明（总高约 240pt）。
    /// 2026-08-29 用户验收反馈由 60 调大：原范围偏小。
    static let fadeRadius: CGFloat = 120
    /// 拖拽热区半径（pt）：分隔线 X ±6pt 内按下/悬停生效
    static let hotZoneRadius: CGFloat = 6
    /// 每侧面板最小宽度（pt）：与 MainWindowController 的 NSSplitViewDelegate 约束一致
    static let minPaneWidth: CGFloat = 450

    /// 鼠标 Y（视图坐标系）→ 渐变轴中心比例（0~1）。
    /// AppKit 对 layer-backed 视图保持 layer 与 view 翻转一致，
    /// 因此 f = mouseY / height 恒成立，无需感知 isFlipped/isGeometryFlipped。
    static func glowCenter(mouseY: CGFloat, boundsHeight: CGFloat) -> CGFloat {
        guard boundsHeight > 0 else { return 0.5 }
        return min(max(mouseY / boundsHeight, 0), 1)
    }

    /// 渐变 locations：最亮点在 center，向上下渐隐 r 比例。
    /// 输出恒有序且 clamp 在 [0,1]（亮点贴窗口顶/底时自然截断）。
    static func gradientLocations(center: CGFloat, radiusFraction: CGFloat) -> [CGFloat] {
        let c = min(max(center, 0), 1)
        let r = min(max(radiusFraction, 0), 1)
        return [max(0, c - r), c, min(1, c + r)]
    }

    /// 鼠标 X → 分隔线目标位置（绝对跟随模型）：clamp 到每侧最小宽约束内。
    /// - leadingMin: 左侧子视图最小宽（双操作区 450；侧栏分隔 160，见 DESIGN-SPEC B-01）
    /// - trailingMin: 右侧子视图最小宽
    static func clampedDividerPosition(
        mouseX: CGFloat,
        boundsWidth: CGFloat,
        leadingMin: CGFloat = minPaneWidth,
        trailingMin: CGFloat = minPaneWidth
    ) -> CGFloat {
        let maxPosition = max(leadingMin, boundsWidth - trailingMin)
        return min(max(mouseX, leadingMin), maxPosition)
    }
}

/// 详情栏流动填充分配纯计算（v0.7.6 发布后详情栏重设计）。
/// 设计文档：docs/superpowers/specs/2026-08-29-details-bar-redesign-design.md
/// ExpandableDetailsBar 负责视觉接线，本枚举只做可单元测试的数学核心。
enum FFDetailsFlowLayout {
    /// 信息行之间的垂直间距（与列 NSStackView spacing 一致）
    static let rowSpacing: CGFloat = 4

    /// 列1 应装项数：按顺序累计高度（首项不计间距，其后每项 +rowSpacing），
    /// 超出 availableHeight 前的项数；项非空时至少返回 1（名称行始终可见）。
    static func flowSplit(itemHeights: [CGFloat], availableHeight: CGFloat) -> Int {
        var cumulative: CGFloat = 0
        for (index, height) in itemHeights.enumerated() {
            cumulative += (index == 0 ? 0 : rowSpacing) + height
            if cumulative > availableHeight {
                return max(index, 1)
            }
        }
        return itemHeights.count
    }

    /// 两列合计可见项数：列1 取 flowSplit，剩余项再按同一可用高度分配给列2，
    /// 列2 也装不下的项隐藏（返回值不含）。
    static func visibleItemCount(itemHeights: [CGFloat], availableHeight: CGFloat) -> Int {
        guard !itemHeights.isEmpty else { return 0 }
        let first = flowSplit(itemHeights: itemHeights, availableHeight: availableHeight)
        let rest = Array(itemHeights[first...])
        let second = flowSplit(itemHeights: rest, availableHeight: availableHeight)
        return first + second
    }

    // MARK: - 多列自适应（DESIGN-SPEC D-05 / D-06，v0.8.0）

    /// 列间距（列与列之间，取代原列1/列2 分界线的 8pt）
    static let columnGap: CGFloat = 8
    /// 单列最小宽度：低于此值信息行会频繁换行，不如减少列数
    static let minColumnWidth: CGFloat = 170
    /// 列数上限。4 列之后单列宽度必然低于 minColumnWidth（常规窗口下），
    /// 且更多列会让阅读顺序变跳跃
    static let maxColumnCount: Int = 4

    /// 一组行装进某一列后的总高（含行间距）
    static func columnHeight(of indexes: [Int], itemHeights: [CGFloat]) -> CGFloat {
        guard !indexes.isEmpty else { return 0 }
        var total: CGFloat = 0
        for (position, index) in indexes.enumerated() {
            guard index < itemHeights.count else { continue }
            total += (position == 0 ? 0 : rowSpacing) + itemHeights[index]
        }
        return total
    }

    /// 把行按顺序均衡分到 `columnCount` 列：目标是每列高度接近 `总高 / 列数`。
    /// 顺序保持（不重排行序），只在越过目标高度时换列；最后一列接收剩余全部行。
    static func distribute(itemHeights: [CGFloat], columnCount: Int) -> [[Int]] {
        guard !itemHeights.isEmpty else { return [] }
        let count = max(1, columnCount)
        if count == 1 { return [Array(itemHeights.indices)] }

        let all = Array(itemHeights.indices)
        let target = columnHeight(of: all, itemHeights: itemHeights) / CGFloat(count)

        var columns: [[Int]] = []
        var current: [Int] = []
        var currentHeight: CGFloat = 0

        for (index, height) in itemHeights.enumerated() {
            let addition = current.isEmpty ? height : height + rowSpacing
            let exceedsTarget = currentHeight + addition > target + rowSpacing
            // 只允许在「还没到最后一列」时换列，保证最后一列兜住所有剩余行
            if !current.isEmpty, columns.count < count - 1, exceedsTarget {
                columns.append(current)
                current = [index]
                currentHeight = height
            } else {
                current.append(index)
                currentHeight += addition
            }
        }
        if !current.isEmpty { columns.append(current) }
        return columns
    }

    /// 可行列数：使每列高度都不超过 `availableHeight` 的最小列数，受宽度与上限约束。
    /// 返回 1 表示单列已够；都装不下时返回上限值（由调用方截断）。
    static func columnCount(itemHeights: [CGFloat],
                            availableHeight: CGFloat,
                            availableWidth: CGFloat) -> Int {
        guard !itemHeights.isEmpty else { return 1 }
        let upper = maxColumnLimit(forWidth: availableWidth)
        for count in 1...upper {
            let columns = distribute(itemHeights: itemHeights, columnCount: count)
            if columns.allSatisfy({ columnHeight(of: $0, itemHeights: itemHeights) <= availableHeight }) {
                return count
            }
        }
        return upper
    }

    /// 宽度允许的最大列数：单列宽不得低于 `minColumnWidth`
    static func maxColumnLimit(forWidth availableWidth: CGFloat) -> Int {
        let estimated = Int(floor((availableWidth + columnGap) / (minColumnWidth + columnGap)))
        return max(1, min(maxColumnCount, estimated))
    }

    /// 每列应显示的行索引（未包含的行隐藏）。
    /// 优先找「不超高」的最小列数；都超高时用最大列数并逐列截断到装得下为止。
    static func columnLayout(itemHeights: [CGFloat],
                             availableHeight: CGFloat,
                             availableWidth: CGFloat) -> [[Int]] {
        guard !itemHeights.isEmpty else { return [] }
        let count = columnCount(itemHeights: itemHeights,
                                availableHeight: availableHeight,
                                availableWidth: availableWidth)
        let columns = distribute(itemHeights: itemHeights, columnCount: count)
        return columns.map { trim($0, itemHeights: itemHeights, availableHeight: availableHeight) }
    }

    /// 按可用高度截断一列（保序，装不下即停）
    private static func trim(_ indexes: [Int],
                             itemHeights: [CGFloat],
                             availableHeight: CGFloat) -> [Int] {
        var result: [Int] = []
        var total: CGFloat = 0
        for index in indexes {
            guard index < itemHeights.count else { continue }
            let addition = result.isEmpty ? itemHeights[index] : itemHeights[index] + rowSpacing
            if total + addition > availableHeight { break }
            result.append(index)
            total += addition
        }
        return result
    }
}
