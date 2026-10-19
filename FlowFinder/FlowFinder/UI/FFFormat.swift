import Foundation

/// 共享格式化工具，避免在多个文件中重复创建 Formatter 实例
public enum FFFormat {
    /// 共享的 ByteCountFormatter（countStyle = .file）
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return f
    }()

    /// 共享的长日期格式：2026年8月2日 14:30
    private static let longDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f
    }()

    /// 共享的短日期格式：2026/8/2
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy/M/d"
        return f
    }()

    /// 共享的仅日期格式：2026年8月2日
    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    /// 格式化文件大小
    public static func fileSize(_ bytes: UInt64) -> String {
        return byteFormatter.string(fromByteCount: Int64(bytes))
    }

    /// 格式化日期（长格式：2026年8月2日 14:30）
    public static func date(_ date: Date) -> String {
        return longDateFormatter.string(from: date)
    }

    /// 格式化日期（短格式：2026/8/2）
    public static func dateShort(_ date: Date) -> String {
        return shortDateFormatter.string(from: date)
    }

    /// 格式化日期（仅日期：2026年8月2日）
    public static func dateOnly(_ date: Date) -> String {
        return dateOnlyFormatter.string(from: date)
    }

    /// 当年紧凑格式：10月18日 14:32
    private static let compactSameYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    /// 跨年紧凑格式：2025年10月18日
    private static let compactOtherYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    /// 格式化日期（紧凑：当年省略年份并保留时间，跨年保留年份省略时间）
    ///
    /// 用途：列表「大小 · 修改时间」元信息列（`docs/PLAN-2026-10-19.md` §3.7）。
    /// 该列宽度有限且面板变窄时不收缩，因此必须比 `date(_:)` 更短。
    public static func dateCompact(_ date: Date) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        return sameYear
            ? compactSameYearFormatter.string(from: date)
            : compactOtherYearFormatter.string(from: date)
    }
}
