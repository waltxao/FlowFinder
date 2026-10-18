import Cocoa

// MARK: - MainMenu

/// 构建 macOS 标准菜单栏（File/Edit/View/Go/Window/Help）
class MainMenu {
    /// 设置应用程序菜单栏
    static func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (FlowFinder)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 FlowFinder", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 FlowFinder", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "偏好设置...", action: #selector(MainWindowController.menuSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 FlowFinder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "新建文件夹", action: #selector(MainWindowController.menuNewFolder(_:)), keyEquivalent: "n")
        // #7：应用内标签页（⌘T 新建 / ⌘W 关闭标签，最后一个标签时退回关窗）
        fileMenu.addItem(withTitle: "新建标签页", action: #selector(MainWindowController.menuNewTab(_:)), keyEquivalent: "t")
        // Wave2 P0-4：⌘⇧N 新窗口接通真多窗口实现（原 action: nil 永久禁用）
        let newWindow = fileMenu.addItem(withTitle: "新窗口", action: #selector(MainWindowController.menuNewWindow(_:)), keyEquivalent: "n")
        newWindow.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "打开", action: #selector(MainWindowController.menuOpen(_:)), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "关闭标签页", action: #selector(MainWindowController.menuCloseTab(_:)), keyEquivalent: "w")
        let closeWindow = fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeWindow.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "移动到废纸篓", action: #selector(MainWindowController.menuMoveToTrash(_:)), keyEquivalent: "\u{8}")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "添加标签...", action: #selector(MainWindowController.menuAddTag(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: "显示简介", action: #selector(MainWindowController.menuGetInfo(_:)), keyEquivalent: "i")

        // Edit menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        // Wave2 P0-2：剪切/复制/粘贴改用标准编辑 selector（copy:/cut:/paste:）——
        // 文本编辑中（field editor 在响应链前端）原生拦截为文本编辑；焦点在文件列表时
        // 沿响应链落到 MainWindowController 的 copy(_:) 等分流实现执行文件操作。
        // 全选保留 menuSelectAll:（NSTableView/NSCollectionView 原生实现 selectAll: 会拦截，
        // 文本编辑分流在该 action 内部完成——见 MainWindowController.menuSelectAll）。
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(MainWindowController.menuSelectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        // Wave2 P1：重命名改内联行为（与 Enter 一致），热键 F2（keyCode 120，无修饰键）。
        // 不绑 "\r"（Enter）：菜单键位无修饰键会全局拦截 Return，破坏文本框回车提交。
        let renameItem = editMenu.addItem(withTitle: "重命名", action: #selector(MainWindowController.menuRename(_:)), keyEquivalent: String(UnicodeScalar(0xF705)!))
        renameItem.keyEquivalentModifierMask = []
        editMenu.addItem(withTitle: "批量重命名...", action: #selector(MainWindowController.menuBatchRename(_:)), keyEquivalent: "")
        // Wave2 P1：⌘D 复制选中项菜单入口（键位展示跟随 shortcut_duplicate 设置）
        editMenu.addItem(withTitle: "复制选中项", action: #selector(MainWindowController.menuDuplicateSelected(_:)), keyEquivalent: "d")
        // Wave2 P1：⌥⌘C 拷贝路径（多选时每行一个路径）
        let copyPaths = editMenu.addItem(withTitle: "拷贝路径", action: #selector(MainWindowController.menuCopyPaths(_:)), keyEquivalent: "c")
        copyPaths.keyEquivalentModifierMask = [.command, .option]
        editMenu.addItem(.separator())
        let copyToOther = editMenu.addItem(withTitle: "复制到另一面板", action: #selector(MainWindowController.menuCopyToOther(_:)), keyEquivalent: "c")
        copyToOther.keyEquivalentModifierMask = [.command, .shift]
        let moveToOther = editMenu.addItem(withTitle: "移动到另一面板", action: #selector(MainWindowController.menuMoveToOther(_:)), keyEquivalent: "x")
        moveToOther.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(withTitle: "在对侧面板打开", action: #selector(MainWindowController.menuOpenInOther(_:)), keyEquivalent: "")

        // View menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "显示")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "列表视图", action: #selector(MainWindowController.menuListView(_:)), keyEquivalent: "1")
        viewMenu.addItem(withTitle: "图标视图", action: #selector(MainWindowController.menuGridView(_:)), keyEquivalent: "2")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "显示隐藏文件", action: #selector(MainWindowController.menuToggleHiddenFiles(_:)), keyEquivalent: "")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "刷新", action: #selector(MainWindowController.menuRefresh(_:)), keyEquivalent: "r")

        // Go menu (导航)
        let goMenuItem = NSMenuItem()
        mainMenu.addItem(goMenuItem)
        let goMenu = NSMenu(title: "前往")
        goMenuItem.submenu = goMenu
        goMenu.addItem(withTitle: "后退", action: #selector(MainWindowController.menuGoBack(_:)), keyEquivalent: "[")
        goMenu.addItem(withTitle: "前进", action: #selector(MainWindowController.menuGoForward(_:)), keyEquivalent: "]")
        // Wave2 P2：上一级补展示热键 ⌘↑（↑ = 0xF700，与 ⌘↑ 导航键位一致）
        let goUpItem = goMenu.addItem(withTitle: "上一级", action: #selector(MainWindowController.menuGoUp(_:)), keyEquivalent: String(UnicodeScalar(0xF700)!))
        goUpItem.keyEquivalentModifierMask = [.command]
        goMenu.addItem(.separator())
        goMenu.addItem(withTitle: "桌面", action: #selector(MainWindowController.menuGoDesktop(_:)), keyEquivalent: "")
        goMenu.addItem(withTitle: "文档", action: #selector(MainWindowController.menuGoDocuments(_:)), keyEquivalent: "")
        goMenu.addItem(withTitle: "下载", action: #selector(MainWindowController.menuGoDownloads(_:)), keyEquivalent: "")
        goMenu.addItem(withTitle: "主目录", action: #selector(MainWindowController.menuGoHome(_:)), keyEquivalent: "")
        goMenu.addItem(.separator())
        goMenu.addItem(withTitle: "连接服务器...", action: #selector(MainWindowController.menuConnectServer(_:)), keyEquivalent: "k")

        // Tools menu (工具)
        let toolsMenuItem = NSMenuItem()
        mainMenu.addItem(toolsMenuItem)
        let toolsMenu = NSMenu(title: "工具")
        toolsMenuItem.submenu = toolsMenu
        // Wave2 P1：⌘F 分流——聚焦活动面板内搜索框；全局搜索面板改绑 ⌘⇧F
        toolsMenu.addItem(withTitle: "搜索...", action: #selector(MainWindowController.menuSearch(_:)), keyEquivalent: "f")
        let globalSearchItem = toolsMenu.addItem(withTitle: "全局搜索...", action: #selector(MainWindowController.menuGlobalSearch(_:)), keyEquivalent: "f")
        globalSearchItem.keyEquivalentModifierMask = [.command, .shift]
        let dupScanItem = toolsMenu.addItem(withTitle: "重复文件扫描...", action: #selector(MainWindowController.menuDuplicateScan(_:)), keyEquivalent: "d")
        dupScanItem.keyEquivalentModifierMask = [.command, .shift]
        toolsMenu.addItem(.separator())
        toolsMenu.addItem(withTitle: "任务面板", action: #selector(MainWindowController.menuTaskPanel(_:)), keyEquivalent: "0")

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "将全部窗口前置", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        // Help menu
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "帮助")
        helpMenuItem.submenu = helpMenu
        // Wave2 P0-4：帮助菜单接通真实 action（原 action: nil 永久禁用）
        helpMenu.addItem(withTitle: "FlowFinder 帮助", action: #selector(MainWindowController.menuHelp(_:)), keyEquivalent: "?")
        helpMenu.addItem(withTitle: "键盘快捷键", action: #selector(MainWindowController.menuKeyboardShortcutsHelp(_:)), keyEquivalent: "")

        // Wave2 P0-3：记录映射菜单项的默认键位基线（供 applyShortcutSettings 回退/恢复默认）
        for entry in shortcutMenuMap {
            if let item = findMenuItem(action: entry.action, in: mainMenu) {
                defaultKeyEquivalents[entry.action] = (item.keyEquivalent, item.keyEquivalentModifierMask)
            }
        }

        // C3: 应用已保存的快捷键设置（shortcut_* → 菜单项 keyEquivalent）
        applyShortcutSettings(to: mainMenu)
        // C3: 注册快捷键变更监听：设置页录制保存后广播 .shortcutsChanged，刷新菜单
        if shortcutsObserverToken == nil {
            shortcutsObserverToken = NotificationCenter.default.addObserver(
                forName: .shortcutsChanged, object: nil, queue: .main
            ) { _ in
                applyShortcutSettings(to: NSApp.mainMenu)
            }
        }

        NSApp.mainMenu = mainMenu
    }

    // MARK: - 快捷键设置接入（C3）

    /// 快捷键变更监听 token（block 版 observer 需强引用，否则会被自动移除）
    private static var shortcutsObserverToken: NSObjectProtocol?

    /// Wave2 P0-3：菜单项默认键位基线（setupMainMenu 构建时记录）。
    /// applyShortcutSettings 先回退基线再应用已保存设置——否则「恢复默认」清空设置键后，
    /// 菜单项会残留上一次的自定义键位（旧键仍触发，违反改键红线）。
    private static var defaultKeyEquivalents: [Selector: (key: String, mask: NSEvent.ModifierFlags)] = [:]

    /// shortcut_* UserDefaults key → 菜单项 action selector 映射。
    /// 无法映射的键（shortcut_quicklook / shortcut_duplicate）在设置页对应，但主菜单无对应菜单项，不在此映射。
    private static let shortcutMenuMap: [(key: String, action: Selector)] = [
        (FFUserDefaultsKeys.shortcutNewFolder, #selector(MainWindowController.menuNewFolder(_:))),
        (FFUserDefaultsKeys.shortcutOpenFile, #selector(MainWindowController.menuOpen(_:))),
        (FFUserDefaultsKeys.shortcutCloseWindow, #selector(NSWindow.performClose(_:))),
        // Wave2 P0-2：剪切/复制/粘贴已改标准编辑 selector（与编辑菜单项一致），
        // 快捷键设置应用时按同一 selector 查找菜单项
        (FFUserDefaultsKeys.shortcutCopy, #selector(NSText.copy(_:))),
        (FFUserDefaultsKeys.shortcutCut, #selector(NSText.cut(_:))),
        (FFUserDefaultsKeys.shortcutPaste, #selector(NSText.paste(_:))),
        (FFUserDefaultsKeys.shortcutSelectAll, #selector(MainWindowController.menuSelectAll(_:))),
        (FFUserDefaultsKeys.shortcutTrash, #selector(MainWindowController.menuMoveToTrash(_:))),
        (FFUserDefaultsKeys.shortcutUndo, NSSelectorFromString("undo:")),
        (FFUserDefaultsKeys.shortcutRedo, NSSelectorFromString("redo:")),
        (FFUserDefaultsKeys.shortcutListView, #selector(MainWindowController.menuListView(_:))),
        (FFUserDefaultsKeys.shortcutGridView, #selector(MainWindowController.menuGridView(_:))),
        (FFUserDefaultsKeys.shortcutRefresh, #selector(MainWindowController.menuRefresh(_:))),
        (FFUserDefaultsKeys.shortcutSearch, #selector(MainWindowController.menuSearch(_:))),
        (FFUserDefaultsKeys.shortcutDuplicateScan, #selector(MainWindowController.menuDuplicateScan(_:))),
        (FFUserDefaultsKeys.shortcutTaskPanel, #selector(MainWindowController.menuTaskPanel(_:))),
        (FFUserDefaultsKeys.shortcutConnectServer, #selector(MainWindowController.menuConnectServer(_:))),
        (FFUserDefaultsKeys.shortcutPreferences, #selector(MainWindowController.menuSettings(_:))),
        // Wave2 P0-3/P1：⌘D 复制选中项有菜单入口了，键位展示跟随 shortcut_duplicate 设置
        (FFUserDefaultsKeys.shortcutDuplicate, #selector(MainWindowController.menuDuplicateSelected(_:))),
    ]

    /// 读取 UserDefaults 中已保存的快捷键并应用到对应菜单项。
    /// Wave2 P0-3：先回退到菜单构建时的默认键位（基线），再叠加已保存的自定义值——
    /// 改键后旧键位从菜单消失（旧键不再触发）；清空设置（恢复默认）后回退基线。
    private static func applyShortcutSettings(to menu: NSMenu?) {
        guard let menu = menu else { return }
        for entry in shortcutMenuMap {
            guard let item = findMenuItem(action: entry.action, in: menu) else { continue }
            // 回退默认键位基线（菜单重建时已记录；基线缺失则保持当前值）
            if let baseline = defaultKeyEquivalents[entry.action] {
                item.keyEquivalent = baseline.key
                item.keyEquivalentModifierMask = baseline.mask
            }
            // 叠加已保存的自定义键位
            guard let saved = UserDefaults.standard.string(forKey: entry.key),
                  let parsed = parseShortcut(saved) else { continue }
            var mask = parsed.mask
            // 原 map 约定：所有默认快捷键均含 ⌘（菜单项 keyEquivalentModifierMask 也均含 .command），
            // 故对普通字符键强制补上 command，避免无修饰键/仅 shift 的快捷键误触发。
            if !mask.contains(.command) {
                mask.insert(.command)
            }
            item.keyEquivalent = parsed.key
            item.keyEquivalentModifierMask = mask
        }
    }

    /// 递归查找指定 action 的菜单项（跨所有子菜单）
    private static func findMenuItem(action: Selector, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.action == action { return item }
            if let submenu = item.submenu, let found = findMenuItem(action: action, in: submenu) {
                return found
            }
        }
        return nil
    }

    /// 解析设置页保存的快捷键字符串（如 "⌘⇧Z"、"⌘N"、"⌘,"）为 keyEquivalent + modifierMask。
    /// 与 ShortcutRecorderView.formatShortcut 的输出格式对应；字母键统一转小写（大写由 ⇧ 修饰键表达）。
    /// 无法解析时返回 nil（保持菜单默认值）。
    private static func parseShortcut(_ shortcut: String) -> (key: String, mask: NSEvent.ModifierFlags)? {
        var mask: NSEvent.ModifierFlags = []
        var rest = shortcut
        while let first = rest.first {
            switch first {
            case "⌘": mask.insert(.command); rest.removeFirst()
            case "⇧": mask.insert(.shift); rest.removeFirst()
            case "⌥": mask.insert(.option); rest.removeFirst()
            case "⌃": mask.insert(.control); rest.removeFirst()
            default:
                let keyStr = rest
                switch keyStr {
                case "空格键": return (" ", mask)
                case "⌫": return ("\u{8}", mask)      // Backspace
                case "↩": return ("\r", mask)         // Return
                case "⇥": return ("\t", mask)         // Tab
                case "⎋": return ("\u{1B}", mask)     // Escape
                case "←": return ("\u{F702}", mask)   // Left arrow
                case "→": return ("\u{F703}", mask)   // Right arrow
                case "↑": return ("\u{F700}", mask)   // Up arrow
                case "↓": return ("\u{F701}", mask)   // Down arrow
                default:
                    if keyStr.hasPrefix("F"), let n = Int(keyStr.dropFirst()), n >= 1, n <= 19 {
                        return (String(UnicodeScalar(0xF703 + n)!), mask)  // F1 = 0xF704
                    }
                    guard keyStr.count == 1 else { return nil }
                    return (keyStr.lowercased(), mask)
                }
            }
        }
        return nil
    }
}
