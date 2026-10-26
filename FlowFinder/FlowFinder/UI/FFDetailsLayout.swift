import CoreGraphics
import Foundation

/// 详情检查器的尺寸策略：宽度决定列数，面板高度决定展开上限，设置滑块决定图标大小。
/// 压缩包信息（只读文件尾，不调用外部命令）。
enum FFArchiveInfo {
    /// 读取 ZIP End of Central Directory 的总条目数。
    static func zipEntryCount(path: String) -> Int? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 22 else { return nil }
        let tailLength = min(UInt64(65_557), size)
        guard (try? handle.seek(toOffset: size - tailLength)) != nil,
              let tail = try? handle.read(upToCount: Int(tailLength)),
              tail.count >= 22 else { return nil }

        let signature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        var matchIndex: Int?
        var index = tail.count - 22
        while index >= 0 {
            if tail[index] == signature[0], tail[index + 1] == signature[1],
               tail[index + 2] == signature[2], tail[index + 3] == signature[3] {
                matchIndex = index
                break
            }
            index -= 1
        }
        guard let eocd = matchIndex else { return nil }
        // EOCD.TotalNumberOfEntries 是 16 位（offset 10）；ZIP64 的超大条目数此处不展开。
        let count = Int(UInt16(tail[eocd + 10]) | (UInt16(tail[eocd + 11]) << 8))
        return count > 0 ? count : nil
    }
}

/// 详情栏三档高度（2026-10-23 重做）。
enum FFDetailsTier: Double, Equatable {
    case collapsed = 54
    case standard = 132
    case large = 240

    var height: CGFloat { CGFloat(rawValue) }
}

/// 三档状态机：点击在「折叠 ↔ 上次展开档」之间切换；拖动松手按中点吸附。
struct FFDetailsBarTierState {
    private(set) var tier: FFDetailsTier
    private(set) var lastExpanded: FFDetailsTier

    init(tier: FFDetailsTier = .collapsed, lastExpanded: FFDetailsTier = .standard) {
        self.tier = tier
        self.lastExpanded = lastExpanded == .collapsed ? .standard : lastExpanded
    }

    /// 点击小白条：折叠 → 上次展开档；已展开 → 记住当前档并折叠。
    @discardableResult
    mutating func click() -> FFDetailsTier {
        if tier == .collapsed {
            tier = lastExpanded
        } else {
            lastExpanded = tier
            tier = .collapsed
        }
        return tier
    }

    /// 拖动松手：按中点吸附，并更新上次展开档。
    @discardableResult
    mutating func snap(to height: CGFloat, paneHeight: CGFloat) -> FFDetailsTier {
        let next = FFDetailsLayoutPolicy.snapTier(forHeight: height, paneHeight: paneHeight)
        tier = next
        if next != .collapsed { lastExpanded = next }
        return next
    }
}

enum FFDetailsLayoutPolicy {
    static let defaultIconSize: CGFloat = 64
    static let minimumIconSize: CGFloat = 48
    /// 2026-10-23 重做：图标上限 96 → 200（D-04a）。
    static let maximumIconSize: CGFloat = 200
    /// 2026-10-21 Phase 4：展开高度 132–300，默认 132。
    static let defaultExpandedHeight: CGFloat = 132
    static let minimumExpandedHeight: CGFloat = 132
    static let maximumExpandedHeight: CGFloat = 300
    /// 三档高度（2026-10-23 D-02）。
    static let standardExpandedHeight: CGFloat = 132
    static let largeExpandedHeight: CGFloat = 240
    /// 中点吸附阈值（D-08）：<93 收起；93–186 标准；≥186 大档。
    static let collapseSnapThreshold: CGFloat = 93
    static let largeSnapThreshold: CGFloat = 186
    /// 上次展开档记忆 key（跨会话）。
    static let lastExpandedTierKey = "FFDetailsBarLastExpandedTier"
    /// 左侧预览列宽 96–232，默认 132（上限 200 → 232，D-04a）。
    static let defaultPreviewColumnWidth: CGFloat = 132
    static let minimumPreviewColumnWidth: CGFloat = 96
    static let maximumPreviewColumnWidth: CGFloat = 232
    /// 图标区内边距：图标区宽 = 图标边长 + 32。
    static let iconColumnPadding: CGFloat = 32
    /// 图标上下留白（内容高 − 8 = 图标最大边长；上下各 4pt）。
    static let iconVerticalPadding: CGFloat = 8
    /// 信息区单列/双列分界（按信息区实际宽度，D-05）。
    static let infoSingleColumnWidth: CGFloat = 340

    static func clampedPreviewColumnWidth(_ value: CGFloat) -> CGFloat {
        min(maximumPreviewColumnWidth, max(minimumPreviewColumnWidth, value))
    }

    static func storedPreviewColumnWidth(defaults: UserDefaults = .standard) -> CGFloat {
        guard let raw = defaults.object(forKey: "FFDetailsBarIconWidth") as? Double,
              raw >= Double(minimumPreviewColumnWidth) else {
            return defaultPreviewColumnWidth
        }
        return clampedPreviewColumnWidth(CGFloat(raw))
    }

    static func columns(forWidth width: CGFloat) -> Int {
        width < 480 ? 1 : 2
    }

    static func maxExpandedHeight(forPaneHeight height: CGFloat) -> CGFloat {
        min(maximumExpandedHeight, max(minimumExpandedHeight, height * 0.45))
    }

    /// 大档实际高度：240，但不超过面板高 45%，且不低于标准档。
    static func largeTierHeight(forPaneHeight height: CGFloat) -> CGFloat {
        min(largeExpandedHeight, max(standardExpandedHeight, height * 0.45))
    }

    /// 三档中点吸附（D-08 A）。
    static func snapTier(forHeight height: CGFloat, paneHeight: CGFloat) -> FFDetailsTier {
        if height < collapseSnapThreshold { return .collapsed }
        let large = largeTierHeight(forPaneHeight: paneHeight)
        if height >= largeSnapThreshold, large > standardExpandedHeight + 0.5 {
            return .large
        }
        return .standard
    }

    /// 图标实际边长：设定值 / 列宽上限 / 当前内容高上限三者取小（D-04a）。
    static func iconEdge(setting: CGFloat,
                         columnWidth: CGFloat,
                         contentHeight: CGFloat) -> CGFloat {
        let bySetting = clampedIconSize(setting)
        let byWidth = max(minimumIconSize, columnWidth - iconColumnPadding)
        let byHeight = max(minimumIconSize, contentHeight - iconVerticalPadding)
        return max(minimumIconSize, min(bySetting, byWidth, byHeight))
    }

    /// 图标区宽度 = max(默认 132, 图标边长 + 32)，上限 232。
    /// 保留默认 132 的呼吸感；图标变大时自动加宽，不会反过来卡住图标。
    static func iconColumnWidth(forEdge edge: CGFloat) -> CGFloat {
        min(maximumPreviewColumnWidth,
            max(defaultPreviewColumnWidth, edge + iconColumnPadding))
    }

    /// 信息区列数（滚动模式）：< 340pt 单列；≥ 340pt 起双列，最多 4 列。
    static func scrollColumnCount(forWidth width: CGFloat) -> Int {
        if width < infoSingleColumnWidth { return 1 }
        let estimated = Int(floor((width + FFDetailsFlowLayout.columnGap) /
                                  (FFDetailsFlowLayout.minColumnWidth + FFDetailsFlowLayout.columnGap)))
        return max(2, min(FFDetailsFlowLayout.maxColumnCount, estimated))
    }

    static func clampedIconSize(_ value: CGFloat) -> CGFloat {
        min(maximumIconSize, max(minimumIconSize, value))
    }

    static func storedIconSize(defaults: UserDefaults = .standard) -> CGFloat {
        let raw = defaults.object(forKey: FFUserDefaultsKeys.detailsPreviewSize) as? Double
        let value = raw.map { CGFloat($0) } ?? defaultIconSize
        return clampedIconSize(value)
    }

    /// 跨会话读取「上次展开档」：≥ 200 视为大档，否则标准档。
    static func storedLastExpandedTier(defaults: UserDefaults = .standard) -> FFDetailsTier {
        defaults.double(forKey: lastExpandedTierKey) >= 200 ? .large : .standard
    }
}
