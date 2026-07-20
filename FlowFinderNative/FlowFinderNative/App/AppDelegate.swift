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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
