import Foundation

/// 批次 4：崩溃日志落盘（~/Library/Logs/FlowFinder/crash.log）。
enum FFCrashLog {

    static func directoryURL(base: URL? = nil) -> URL {
        let root = base ?? FileManager.default.homeDirectoryForCurrentUser
        return root.appendingPathComponent("Library/Logs/FlowFinder", isDirectory: true)
    }

    static func fileURL(base: URL? = nil) -> URL {
        directoryURL(base: base).appendingPathComponent("crash.log")
    }

    static func format(name: String, reason: String?, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "[\(formatter.string(from: date))] \(name)\n\(reason ?? "未知原因")\n\n"
    }

    /// 返回写入的文件 URL；失败返回 nil。
    @discardableResult
    static func append(name: String, reason: String?, base: URL? = nil) -> URL? {
        let dir = directoryURL(base: base)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = fileURL(base: base)
            let text = format(name: name, reason: reason)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(text.utf8))
            } else {
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
            return url
        } catch {
            return nil
        }
    }
}
