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

enum FFDetailsLayoutPolicy {
    static let defaultIconSize: CGFloat = 64
    static let minimumIconSize: CGFloat = 48
    static let maximumIconSize: CGFloat = 96
    /// 2026-10-21 Phase 4：展开高度 132–300，默认 132。
    static let defaultExpandedHeight: CGFloat = 132
    static let minimumExpandedHeight: CGFloat = 132
    static let maximumExpandedHeight: CGFloat = 300
    /// 左侧预览列宽 96–200，默认 132。
    static let defaultPreviewColumnWidth: CGFloat = 132
    static let minimumPreviewColumnWidth: CGFloat = 96
    static let maximumPreviewColumnWidth: CGFloat = 200

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

    static func clampedIconSize(_ value: CGFloat) -> CGFloat {
        min(maximumIconSize, max(minimumIconSize, value))
    }

    static func storedIconSize(defaults: UserDefaults = .standard) -> CGFloat {
        let raw = defaults.object(forKey: FFUserDefaultsKeys.detailsPreviewSize) as? Double
        let value = raw.map { CGFloat($0) } ?? defaultIconSize
        return clampedIconSize(value)
    }
}
