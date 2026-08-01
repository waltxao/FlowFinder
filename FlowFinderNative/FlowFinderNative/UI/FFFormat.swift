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

    /// 共享的 DateFormatter（dateStyle = .medium, timeStyle = .short）
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// 格式化文件大小
    public static func fileSize(_ bytes: UInt64) -> String {
        return byteFormatter.string(fromByteCount: Int64(bytes))
    }

    /// 格式化日期
    public static func date(_ date: Date) -> String {
        return dateFormatter.string(from: date)
    }
}
