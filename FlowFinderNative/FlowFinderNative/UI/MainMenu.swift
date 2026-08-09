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
        let newWindow = fileMenu.addItem(withTitle: "新窗口", action: nil, keyEquivalent: "n")
        newWindow.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "打开", action: #selector(MainWindowController.menuOpen(_:)), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
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
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(MainWindowController.menuCut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(MainWindowController.menuCopy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(MainWindowController.menuPaste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(MainWindowController.menuSelectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "重命名", action: #selector(MainWindowController.menuRename(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "批量重命名...", action: #selector(MainWindowController.menuBatchRename(_:)), keyEquivalent: "")
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
        goMenu.addItem(withTitle: "上一级", action: #selector(MainWindowController.menuGoUp(_:)), keyEquivalent: "")
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
        toolsMenu.addItem(withTitle: "搜索...", action: #selector(MainWindowController.menuSearch(_:)), keyEquivalent: "f")
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
        helpMenu.addItem(withTitle: "FlowFinder 帮助", action: nil, keyEquivalent: "?")
        helpMenu.addItem(withTitle: "键盘快捷键", action: nil, keyEquivalent: "")

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

    /// shortcut_* UserDefaults key → 菜单项 action selector 映射。
    /// 无法映射的键（shortcut_quicklook / shortcut_duplicate）在设置页对应，但主菜单无对应菜单项，不在此映射。
    private static let shortcutMenuMap: [(key: String, action: Selector)] = [
        (FFUserDefaultsKeys.shortcutNewFolder, #selector(MainWindowController.menuNewFolder(_:))),
        (FFUserDefaultsKeys.shortcutOpenFile, #selector(MainWindowController.menuOpen(_:))),
        (FFUserDefaultsKeys.shortcutCloseWindow, #selector(NSWindow.performClose(_:))),
        (FFUserDefaultsKeys.shortcutCopy, #selector(MainWindowController.menuCopy(_:))),
        (FFUserDefaultsKeys.shortcutCut, #selector(MainWindowController.menuCut(_:))),
        (FFUserDefaultsKeys.shortcutPaste, #selector(MainWindowController.menuPaste(_:))),
        (FFUserDefaultsKeys.shortcutSelectAll, #selector(MainWindowController.menuSelectAll(_:))),
        (FFUserDefaultsKeys.shortcutTrash, #selector(MainWindowController.menuMoveToTrash(_:))),
        (FFUserDefaultsKeys.shortcutUndo, Selector("undo:")),
        (FFUserDefaultsKeys.shortcutRedo, Selector("redo:")),
        (FFUserDefaultsKeys.shortcutListView, #selector(MainWindowController.menuListView(_:))),
        (FFUserDefaultsKeys.shortcutGridView, #selector(MainWindowController.menuGridView(_:))),
        (FFUserDefaultsKeys.shortcutRefresh, #selector(MainWindowController.menuRefresh(_:))),
        (FFUserDefaultsKeys.shortcutSearch, #selector(MainWindowController.menuSearch(_:))),
        (FFUserDefaultsKeys.shortcutDuplicateScan, #selector(MainWindowController.menuDuplicateScan(_:))),
        (FFUserDefaultsKeys.shortcutTaskPanel, #selector(MainWindowController.menuTaskPanel(_:))),
        (FFUserDefaultsKeys.shortcutConnectServer, #selector(MainWindowController.menuConnectServer(_:))),
        (FFUserDefaultsKeys.shortcutPreferences, #selector(MainWindowController.menuSettings(_:))),
    ]

    /// 读取 UserDefaults 中已保存的快捷键并应用到对应菜单项。
    /// 未保存过（用户未改动）的键保持菜单构建时的默认值。
    private static func applyShortcutSettings(to menu: NSMenu?) {
        guard let menu = menu else { return }
        for entry in shortcutMenuMap {
            guard let saved = UserDefaults.standard.string(forKey: entry.key),
                  let parsed = parseShortcut(saved),
                  let item = findMenuItem(action: entry.action, in: menu) else { continue }
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
