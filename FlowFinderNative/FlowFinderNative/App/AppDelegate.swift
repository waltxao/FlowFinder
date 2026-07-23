import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 激活应用，确保窗口显示在前台
        NSApp.activate(ignoringOtherApps: true)

        // 应用保存的主题
        ThemeManager.shared.startObservingSystemChanges()
        ThemeManager.shared.applyMode(ThemeManager.shared.currentMode)

        // 设置菜单栏
        MainMenu.setupMainMenu()

        // 初始化 L2 持久化目录缓存（SQLite）。db 路径位于
        // ~/Library/Application Support/FlowFinder/dir_cache.db。
        // 失败时仅记录日志，不阻断启动 —— L1 内存缓存仍然可用。
        initPersistentDirectoryCache()

        // 创建主窗口
        let controller = MainWindowController()
        controller.showWindow(nil)
        self.mainWindowController = controller

        // 确保窗口可见并置前
        if let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 初始化 L2 持久化目录缓存。
    ///
    /// 在 `~/Library/Application Support/FlowFinder/` 下创建（如不存在）
    /// `dir_cache.db` 文件，并调用 `CoreBridge.shared.initCache(dbPath:)`
    /// 让 FFI 层启用 L1+L2 两级缓存。失败仅打印日志，不抛错。
    private func initPersistentDirectoryCache() {
        let fm = FileManager.default
        let appSupportURL: URL
        do {
            appSupportURL = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            NSLog("[FlowFinder] Failed to locate Application Support directory: \(error)")
            return
        }

        let appDir = appSupportURL.appendingPathComponent("FlowFinder", isDirectory: true)
        let dbURL = appDir.appendingPathComponent("dir_cache.db", isDirectory: false)

        do {
            try fm.createDirectory(
                at: appDir,
                withIntermediateDirectories: true
            )
        } catch {
            NSLog("[FlowFinder] Failed to create cache directory at \(appDir.path): \(error)")
            return
        }

        do {
            try CoreBridge.shared.initCache(dbPath: dbURL.path)
            NSLog("[FlowFinder] L2 directory cache initialized at \(dbURL.path)")
        } catch {
            NSLog("[FlowFinder] Failed to initialize L2 directory cache at \(dbURL.path): \(error)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
