import Foundation
import AppKit
import Combine

/// 外观模式枚举（任务 T2: 移除 system 自动跟随，仅 light/dark 二态）
public enum AppearanceMode: Int, CaseIterable {
    case light = 1   // 浅色
    case dark = 2    // 深色

    public var title: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    public var iconName: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// 切换到另一态
    public var toggled: AppearanceMode {
        return self == .light ? .dark : .light
    }
}

/// 主题管理器：管理应用外观模式（浅色/深色/跟随系统）
public final class ThemeManager: ObservableObject {

    public static let shared = ThemeManager()

    /// 设置键名
    private let settingsKey = "appearance_mode"

    public private(set) var currentMode: AppearanceMode = .light

    /// 主题变更回调
    public var onModeChanged: ((AppearanceMode) -> Void)?

    private init() {
        loadSavedMode()
    }

    // MARK: - Public API

    /// 应用指定外观模式
    /// - Parameter mode: 外观模式
    public func applyMode(_ mode: AppearanceMode) {
        currentMode = mode
        saveMode(mode)

        // 任务 T2: 仅 light/dark 二态，无 system 自动跟随
        switch mode {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

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
            window.appearance = NSApp.appearance
        }

        // 刷新所有 FFGlassView 实例的玻璃令牌（噪声/高光/内阴影/tint）
        FFGlassView.refreshAllInstances()

        onModeChanged?(mode)
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

    /// 开始监听系统主题变更（任务 T2: 仅用于刷新玻璃效果，不再自动切换模式）
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

    /// 获取当前系统外观（任务 T2: 用于决定首次启动时的初始模式）
    public var systemIsDark: Bool {
        let effective = NSApp.appearance ?? NSApp.effectiveAppearance
        return effective.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: - Private

    @objc private func systemAppearanceChanged() {
        // 任务 T2: 不再自动跟随系统，仅刷新玻璃效果令牌
        // 用户必须手动点击切换按钮才会改变 light/dark 模式
        for window in NSApp.windows {
            window.appearance = NSApp.appearance
            if let mainContainer = findMainContainer(in: window) {
                mainContainer.appearance = NSApp.appearance ?? NSApp.effectiveAppearance
            }
        }
        FFGlassView.refreshAllInstances()
        onModeChanged?(currentMode)
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
            // 任务 T2: 首次启动根据系统当前外观决定初始模式
            currentMode = systemIsDark ? .dark : .light
        }
    }

    private func saveMode(_ mode: AppearanceMode) {
        // 保存到两处：CoreBridge（Rust 端）和 UserDefaults（快速读取）
        UserDefaults.standard.set(mode.rawValue, forKey: settingsKey)

        do {
            try CoreBridge.shared.setSetting(key: settingsKey, value: String(mode.rawValue))
        } catch {
            print("ThemeManager: 保存主题到 Rust 失败: \(error.localizedDescription)")
        }
    }
}
