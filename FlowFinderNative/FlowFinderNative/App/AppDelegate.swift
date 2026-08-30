import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController?

    /// Wave2 P0-4（多窗口）：⌘⇧N 新开的窗口控制器强引用数组。
    /// NSWindow 不持有其 windowController，新窗口若无外部强引用会在创建后立即释放；
    /// 窗口关闭时（windowWillClose）由 MainWindowController 通知移除，避免数组无界增长。
    private var extraWindowControllers: [MainWindowController] = []

    /// Wave2 P0-4（多窗口）：注册新窗口控制器（强引用，防释放）
    func registerWindowController(_ controller: MainWindowController) {
        extraWindowControllers.append(controller)
    }

    /// Wave2 P0-4（多窗口）：窗口关闭后移除对应控制器引用
    func unregisterWindowController(_ controller: MainWindowController) {
        extraWindowControllers.removeAll { $0 === controller }
    }

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

        // 初始化独立内容索引（FTS5）。db 路径位于
        // ~/Library/Application Support/FlowFinder/content_index.sqlite。
        // 失败时仅记录日志，不阻断启动 —— 搜索面板会显示对应状态并提供重建入口。
        initContentIndex()

        // 测试宿主（XCTest）模式跳过主窗口创建：单元测试自建所需窗口。宿主应用的
        // 真实主窗口在测试进程里与用例的窗口/主队列异步块竞态，曾引发窗口释放后
        // AppKit 延迟簿记块悬空访问（NSZombie 实证 _endLiveResize SIGSEGV，运行器崩溃）。
        // 注意用启动环境变量判定：XCTestBundle 在宿主 app 启动后才注入，
        // NSClassFromString("XCTestCase") 在本时刻尚不可靠
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil

        // 创建主窗口
        if !isRunningTests {
            let controller = MainWindowController()
            controller.showWindow(nil)
            self.mainWindowController = controller

            // Wave2 P0-4（多窗口）：FSEvents watcher 是 CoreBridge 进程级单例（重复 start
            // 会先 stop 旧 watcher 再启动新的），不能挂在单个 MainWindowController 上——
            // 第二窗口启动会顶掉首窗口的 watcher，窗口关闭后无人重启导致自动刷新失效。
            // 改挂 AppDelegate 生命周期，变更经 .fileSystemDidChange 广播给所有窗口。
            startGlobalFileSystemWatcher()

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
    }

    /// Wave2 P0-4（多窗口）：进程级 FSEvents 监控（监控用户主目录）。
    /// 变更经 .fileSystemDidChange 主线程广播，各 MainWindowController 自行判断
    /// 变更是否影响本窗口面板并刷新（原逻辑在 MainWindowController 内，随多窗口上移）。
    private func startGlobalFileSystemWatcher() {
        let homeDir = NSHomeDirectory()
        CoreBridge.shared.startFSEventsWatcher(path: homeDir) { changedPath in
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .fileSystemDidChange, object: nil,
                    userInfo: ["path": changedPath]
                )
            }
        } completion: { result in
            switch result {
            case .success:
                FFDebug.log("FSEvents 文件系统监控已启动，监控路径: \(homeDir)")
            case .failure(let error):
                // 失败保持可观察：与旧实现的错误日志链路一致（状态机 failed）
                FFLog.error("FSEvents 监控启动失败: \(error.localizedDescription)", log: FFLog.bridge)
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

    /// 初始化独立内容索引（FTS5）。
    ///
    /// 在 `~/Library/Application Support/FlowFinder/` 下解析 `content_index.sqlite`
    /// 路径并调用 `ContentIndexBridge.shared.initialize(dbPath:)`。目录创建复用
    /// `initPersistentDirectoryCache` 已有的 appDir 逻辑。失败仅打印日志，不抛错、
    /// 不阻断主界面 —— 搜索面板会通过状态机展示 error/empty 并提供重建入口。
    private func initContentIndex() {
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
        let dbURL = appDir.appendingPathComponent("content_index.sqlite", isDirectory: false)

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
            try ContentIndexBridge.shared.initialize(dbPath: dbURL.path)
            NSLog("[FlowFinder] Content index initialized at \(dbURL.path)")
        } catch {
            NSLog("[FlowFinder] Failed to initialize content index at \(dbURL.path): \(error)")
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
