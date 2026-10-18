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
}
