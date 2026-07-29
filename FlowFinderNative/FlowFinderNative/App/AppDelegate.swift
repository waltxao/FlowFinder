import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FFDebug.clear()
        FFDebug.log("AppDelegate: applicationDidFinishLaunching")

        // 任务 F11-3: 全局 ErrorBoundary（v0.6.7）
        // 捕获未处理异常，弹窗提示而非崩溃。轻量进程重启依赖 terminate 后由
        // launch agent / 用户再次打开；此处“重启”按钮通过 relaunch 触发再终止。
        NSSetUncaughtExceptionHandler { exception in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "应用遇到错误"
                alert.informativeText = "错误：\(exception.name.rawValue)\n\n\(exception.reason ?? "未知错误")\n\n请重启应用。"
                alert.addButton(withTitle: "重启")
                alert.addButton(withTitle: "退出")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    AppDelegate.relaunchAndTerminate()
                } else {
                    NSApp.terminate(nil)
                }
            }
        }

        // 任务 S1: 滚动条样式已改为自定义 FFScroller 子类，不再依赖 UserDefaults
        // 激活应用，确保窗口显示在前台
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

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
            // macOS 14+: 使用新的 activate() API（旧的 ignoringOtherApps 已废弃且在 macOS 27 上不可靠）
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
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

    // MARK: - ErrorBoundary 辅助

    /// 任务 F11-3: 异常恢复后重新启动应用并终止当前进程。
    /// 通过 `open` 命令重新打开主 bundle（会启动一个新实例），
    /// 再调用 NSApp.terminate 让当前崩溃实例干净退出。
    /// 若重启动失败则仅终止，避免卡死。
    static func relaunchAndTerminate() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundleURL.path]
        do {
            try task.run()
        } catch {
            NSLog("[FlowFinder] ErrorBoundary relaunch failed: \(error)")
        }
        // 给 open 一点时间派生新进程后再终止当前实例
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }
}
