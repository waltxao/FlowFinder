import Foundation
import os.log

/// 统一日志工具：基于 os_log 的封装
/// 所有模块使用统一的日志分类，便于在 Console.app 中筛选
enum FFLog {
    private static let subsystem = "com.flowfinder.native"

    static let ui = OSLog(subsystem: subsystem, category: "UI")
    static let bridge = OSLog(subsystem: subsystem, category: "Bridge")
    static let thumbnail = OSLog(subsystem: subsystem, category: "Thumbnail")
    static let theme = OSLog(subsystem: subsystem, category: "Theme")
    static let task = OSLog(subsystem: subsystem, category: "Task")
    static let glass = OSLog(subsystem: subsystem, category: "Glass")

    /// 调试日志（仅 Debug 构建输出）
    @inlinable
    static func debug(_ message: String, log: OSLog = .default) {
        #if DEBUG
        os_log("%{public}@", log: log, type: .debug, message)
        #endif
    }

    /// 信息日志
    @inlinable
    static func info(_ message: String, log: OSLog = .default) {
        os_log("%{public}@", log: log, type: .info, message)
    }

    /// 错误日志
    @inlinable
    static func error(_ message: String, log: OSLog = .default) {
        os_log("%{public}@", log: log, type: .error, message)
    }

    /// 警告日志
    @inlinable
    static func warning(_ message: String, log: OSLog = .default) {
        os_log("%{public}@", log: log, type: .default, message)
    }
}
