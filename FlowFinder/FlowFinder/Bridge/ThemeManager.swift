import Foundation
import AppKit
import Combine
import os.log

/// 外观模式枚举（任务 F11-3: 恢复三态 light/dark/system，修正 v0.6.5 T2 错误移除）
public enum AppearanceMode: Int, CaseIterable {
    case light = 1   // 浅色
    case dark = 2    // 深色
    case system = 3  // 自动跟随系统

    public var title: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        case .system: return "自动跟随系统"
        }
    }

    public var iconName: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }

    /// 任务 T2 遗留：在浅色/深色二态间切换。
    /// .system 视为“深色”，切换到 .light；其余按 light<->dark 互换。
    /// 侧边栏 toggleTheme 用此方法，保留原行为。
    public var toggled: AppearanceMode {
        switch self {
        case .light: return .dark
        case .dark: return .light
        case .system: return .light
        }
    }
}

/// 主题管理器：管理应用外观模式（浅色/深色/跟随系统）
public final class ThemeManager: ObservableObject {

    public static let shared = ThemeManager()

    /// 设置键名
    private let settingsKey = "appearance_mode"

    public private(set) var currentMode: AppearanceMode = .light

    /// 主题变更订阅者列表（多订阅者模式，避免单闭包互相覆盖）
    private var modeChangedHandlers: [(AppearanceMode) -> Void] = []

    /// 主题变更回调（已废弃，优先使用 NotificationCenter 监听 .appearanceChanged 通知）
    ///
    /// 历史问题：原实现为单闭包，多处赋值会互相覆盖（如 SidebarView 直接赋值
    /// 覆盖了 AppearanceSettingsView / MainWindowController 已注册的回调）。
    ///
    /// 现改为多订阅者：`set` 时追加到 `modeChangedHandlers` 数组（不再覆盖），
    /// `get` 始终返回 nil。同时通过 NotificationCenter 发送 `.appearanceChanged`
    /// 通知，新代码应监听该通知而非使用此属性。
    @available(*, deprecated, message: "使用 NotificationCenter 监听 .appearanceChanged 通知")
    public var onModeChanged: ((AppearanceMode) -> Void)? {
        get { nil }
        set {
            if let handler = newValue {
                modeChangedHandlers.append(handler)
            }
        }
    }

    private init() {
        loadSavedMode()
    }

    // MARK: - Public API

    /// 将当前模式解析为最终生效的 light/dark。
    /// .system 模式下根据系统当前外观决定 light/dark。
    /// 供 UI 层（FileListView/FileGridView/MainWindowController 等）判断深浅色用，
    /// 避免在 .system + 系统深色场景下 currentMode == .dark 误判为浅色。
    public var resolvedMode: AppearanceMode {
        switch currentMode {
        case .light, .dark:
            return currentMode
        case .system:
            return systemIsDark ? .dark : .light
        }
    }

    /// 当前是否为深色（已解析 .system）。供 UI 层快速判断使用。
    public var resolvedIsDark: Bool {
        return resolvedMode == .dark
    }

    /// 应用指定外观模式
    /// - Parameter mode: 外观模式
    public func applyMode(_ mode: AppearanceMode) {
        FFDebug.log("ThemeManager.applyMode: 收到 mode=\(mode.title)")
        currentMode = mode
        saveMode(mode)

        // 任务 F11-3: 恢复 .system 三态
        // .system: 不设置 NSApp.appearance（nil = 跟随系统），由系统自动切换 light/dark
        switch mode {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system:
            NSApp.appearance = nil
        }
        FFDebug.log("ThemeManager.applyMode: NSApp.appearance 已设为=\(String(describing: NSApp.appearance?.name))")

        // 通知所有窗口刷新
        // 背景玻璃架构：containerView（普通 NSView）作为 contentView，
        // glassView（NSGlassEffectView）和 mainContainer 是其子视图。
        // window.appearance = nil 以保持玻璃效果；
        // mainContainer 显式设置 appearance 确保子视图能解析选中高亮色。
        for window in NSApp.windows {
            if #available(macOS 26.0, *), hasGlassEffect(in: window) {
                window.appearance = nil
                let effectiveApp = NSApp.appearance ?? NSApp.effectiveAppearance
                if let mainContainer = findMainContainer(in: window) {
                    mainContainer.appearance = effectiveApp
                }
                continue
            }
            // NSVisualEffectView 架构：窗口和内容容器都跟随 NSApp.appearance
            window.appearance = NSApp.appearance
            if let mainContainer = findMainContainer(in: window) {
                mainContainer.appearance = NSApp.appearance
            }
        }

        // 刷新所有 FFGlassView 实例的玻璃令牌（噪声/高光/内阴影/tint）
        FFGlassView.refreshAllInstances()

        FFDebug.log("ThemeManager.applyMode: 即将发送 appearanceChanged 通知")
        notifyModeChanged(mode)
        FFDebug.log("ThemeManager.applyMode: 通知已发送完成")
    }

    /// 通知所有订阅者主题已变更（闭包订阅者 + NotificationCenter）
    /// - Parameter mode: 新的外观模式
    private func notifyModeChanged(_ mode: AppearanceMode) {
        // 遍历调用所有闭包订阅者（多订阅者，避免单闭包覆盖）
        for handler in modeChangedHandlers {
            handler(mode)
        }
        // 发送外观变更通知（推荐新代码使用 NotificationCenter 监听）
        NotificationCenter.default.post(
            name: .appearanceChanged,
            object: nil,
            userInfo: ["mode": mode]
        )
    }

    /// 检查窗口是否使用了 NSGlassEffectView（兼容新旧两种架构）
    private func hasGlassEffect(in window: NSWindow) -> Bool {
        guard #available(macOS 26.0, *) else { return false }
        guard let contentView = window.contentView else { return false }
        // 新架构：containerView 包含 NSGlassEffectView 子视图
        if contentView.subviews.contains(where: { $0 is NSGlassEffectView }) {
            return true
        }
        // 旧架构：contentView 本身就是 NSGlassEffectView
        return contentView is NSGlassEffectView
    }

    /// 查找窗口中的 mainContainer（兼容新旧两种玻璃架构）
    private func findMainContainer(in window: NSWindow) -> NSView? {
        guard let contentView = window.contentView else { return nil }
        if #available(macOS 26.0, *) {
            // 新架构：containerView → [glassView, mainContainer]
            if contentView.subviews.contains(where: { $0 is NSGlassEffectView }) {
                return contentView.subviews.first(where: { !($0 is NSGlassEffectView) })
            }
            // 旧架构：glassView 是 contentView，mainContainer 是其子视图
            if contentView is NSGlassEffectView {
                return contentView.subviews.first
            }
        }
        // NSVisualEffectView 回退
        if contentView is NSVisualEffectView {
            return contentView.subviews.first
        }
        return nil
    }

    /// 开始监听系统主题变更（任务 F11-3: .system 模式下系统切换时实际刷新窗口外观）
    public func startObservingSystemChanges() {
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    /// 停止监听
    public func stopObservingSystemChanges() {
        DistributedNotificationCenter.default.removeObserver(self)
    }

    /// 获取当前系统外观（任务 F11-3: .system 模式下决定 light/dark 解析）
    public var systemIsDark: Bool {
        let effective = NSApp.appearance ?? NSApp.effectiveAppearance
        return effective.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: - Private

    @objc private func systemAppearanceChanged() {
        // 任务 F11-3: .system 模式下，系统切换浅/深色时需实际刷新窗口外观；
        // light/dark 模式下用户已显式锁定，仅刷新玻璃效果令牌。
        if currentMode == .system {
            for window in NSApp.windows {
                window.appearance = nil  // 跟随系统
                if let mainContainer = findMainContainer(in: window) {
                    mainContainer.appearance = NSApp.effectiveAppearance
                }
            }
        } else {
            for window in NSApp.windows {
                window.appearance = NSApp.appearance
                if let mainContainer = findMainContainer(in: window) {
                    mainContainer.appearance = NSApp.appearance ?? NSApp.effectiveAppearance
                }
            }
        }
        FFGlassView.refreshAllInstances()
        notifyModeChanged(currentMode)
    }

    private func loadSavedMode() {
        // 优先从 CoreBridge 读取，回退到 UserDefaults
        let rustValue = CoreBridge.shared.getSetting(key: settingsKey)

        if !rustValue.isEmpty, let intValue = Int(rustValue), let mode = AppearanceMode(rawValue: intValue) {
            currentMode = mode
        } else if let savedValue = UserDefaults.standard.object(forKey: settingsKey) as? Int,
                  let mode = AppearanceMode(rawValue: savedValue) {
            currentMode = mode
        } else {
            // 任务 F11-3: 首次启动默认 .system（自动跟随系统）
            currentMode = .system
        }
    }

    private func saveMode(_ mode: AppearanceMode) {
        // 保存到两处：CoreBridge（Rust 端）和 UserDefaults（快速读取）
        UserDefaults.standard.set(mode.rawValue, forKey: settingsKey)

        do {
            try CoreBridge.shared.setSetting(key: settingsKey, value: String(mode.rawValue))
        } catch {
            FFLog.error("ThemeManager: 保存主题到 Rust 失败: \(error.localizedDescription)", log: FFLog.theme)
        }
    }
}
