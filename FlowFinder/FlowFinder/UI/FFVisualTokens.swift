import AppKit

/// 设置 > 外观 > 界面尺寸（2026-10-21 用户确认三档）。
enum FFSizeLevel: String, CaseIterable {
    case compact
    case comfortable
    case large

    var title: String {
        switch self {
        case .compact: return "紧凑"
        case .comfortable: return "舒适"
        case .large: return "大"
        }
    }

    var bodyFontSize: CGFloat {
        switch self {
        case .compact: return 12
        case .comfortable: return 13
        case .large: return 14
        }
    }

    var rowHeight: CGFloat {
        switch self {
        case .compact: return 28
        case .comfortable: return 30
        case .large: return 32
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .compact: return 16
        case .comfortable: return 18
        case .large: return 20
        }
    }
}

enum FFSizePreference {
    static let storageKey = "ff_ui_size_level"

    static var current: FFSizeLevel {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storageKey),
                  let level = FFSizeLevel(rawValue: raw) else { return .comfortable }
            return level
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: .ffSizePreferenceChanged, object: newValue)
        }
    }
}

extension Notification.Name {
    static let ffSizePreferenceChanged = Notification.Name("ffSizePreferenceChanged")
}

/// 顶栏 C2（2026-10-21 用户确认）：44pt 栏 / 38pt 标签 / 6pt 空条 / 22pt 共用中线。
enum FFTopBarMetrics {
    static let height: CGFloat = 36
    static let tabHeight: CGFloat = 30
    static let topStrip: CGFloat = 6
    static let centerline: CGFloat = 18
    static let tabFontSize: CGFloat = 13
    static let iconSize: CGFloat = 16
    static let fillet: CGFloat = 10
    static let horizontalMargin: CGFloat = 16
    /// 标签框中心距顶部 21，内容再上移 3pt 对齐 18pt 共用中线。
    static let tabContentOffset: CGFloat = 3
}

enum FFVisualTokens {
    /// 全应用唯一强调色来源（用户可在设置中改；默认系统强调色）。
    static var accent: NSColor { FFAccent.current }
    static var tabUnderlineColor: NSColor { accent }
    static let windowBackground = NSColor.windowBackgroundColor
    static let paneBackground = NSColor.controlBackgroundColor
    static let sidebarBackground = NSColor.underPageBackgroundColor
    static let separator = NSColor.separatorColor
    static let label = NSColor.labelColor
    static let secondaryLabel = NSColor.secondaryLabelColor
    static let tertiaryLabel = NSColor.tertiaryLabelColor

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 6
        static let card: CGFloat = 8
        static let details: CGFloat = 12
        static let panel: CGFloat = 12
        static let window: CGFloat = 12
    }

    static var rowHeight: CGFloat { FFSizePreference.current.rowHeight }
    static let rowHeightCompact: CGFloat = 24
    static let toolbarHeight: CGFloat = 34
    static let statusBarHeight: CGFloat = 28
    static let searchFieldHeight: CGFloat = 28
    static var iconSize: CGFloat { FFSizePreference.current.iconSize }
    static let activePaneEdge: CGFloat = 2

    enum Font {
        static let caption = NSFont.systemFont(ofSize: 11)
        static let captionMedium = NSFont.systemFont(ofSize: 11, weight: .medium)
        static var body: NSFont { NSFont.systemFont(ofSize: FFSizePreference.current.bodyFontSize) }
        static let sectionTitle = NSFont.systemFont(ofSize: 15, weight: .medium)
        static let emptyTitle = NSFont.systemFont(ofSize: 17, weight: .semibold)
    }

    enum Motion {
        static let micro: TimeInterval = 0.16
        static let paneMode: TimeInterval = 0.22
    }
}
