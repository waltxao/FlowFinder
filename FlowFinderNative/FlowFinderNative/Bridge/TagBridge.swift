import Foundation

/// xattr 标签读写桥接
///
/// 标签同时存储在两个扩展属性中，实现与 macOS Finder 的双向同步：
/// - `com.flowfinder.tags`：自有格式，JSON 数组（含 id 与 hex 颜色）
/// - `com.apple.metadata:_kMDItemUserTags`：macOS 原生标签，Finder 可见
///   格式为换行分隔字符串，每项为 "标签名" 或 "标签名\n颜色索引"
///   （颜色索引 0=无色, 1=红, 2=橙, 3=黄, 4=绿, 5=蓝, 6=紫, 7=灰）
public final class TagBridge {
    public static let shared = TagBridge()

    /// 自有标签 xattr 名（JSON 数组）
    private let xattrName = "com.flowfinder.tags"
    /// macOS 原生标签 xattr 名（Finder 可见）
    private let nativeXattrName = "com.apple.metadata:_kMDItemUserTags"

    private init() {}

    /// 获取文件的标签（合并自有与 macOS 原生两个来源，按标签名去重）
    public func getTags(path: String) -> [Tag] {
        // 1. 读取自有标签（保留 id 与 hex 颜色），仅读一次
        let ownTags = readOwnTags(path: path) ?? []

        // 2. 读取 macOS 原生标签（Finder 可见）
        let nativeTags = readNativeTags(path: path) ?? []

        // 3. 合并去重：自有标签优先（颜色信息更精确），
        //    保持自有标签原始顺序，原生独有标签按名称字典序追加
        var seenNames = Set<String>()
        var result: [Tag] = []
        for tag in ownTags {
            seenNames.insert(tag.name)
            result.append(tag)
        }
        let nativeOnly = nativeTags
            .filter { !seenNames.contains($0.name) }
            .sorted { $0.name < $1.name }
        result.append(contentsOf: nativeOnly)

        return result
    }

    /// 设置文件的标签（覆盖），同时同步到自有与 macOS 原生两个位置
    public func setTags(_ tags: [Tag], path: String) -> Bool {
        // 1. 写入自有格式（保留 id 与 hex 颜色）
        let ownOK = writeOwnTags(tags, path: path)

        // 2. 写入 macOS 原生格式（让 Finder 可见）
        let nativeOK = writeNativeTags(tags, path: path)

        // 任一成功即视为成功（避免某一方写入失败导致整体不可用）
        return ownOK || nativeOK
    }

    /// 添加标签
    public func addTag(_ tag: Tag, path: String) -> Bool {
        var tags = getTags(path: path)
        if tags.contains(where: { $0.name == tag.name }) { return true }
        tags.append(tag)
        return setTags(tags, path: path)
    }

    /// 移除标签
    public func removeTag(_ tagId: String, path: String) -> Bool {
        var tags = getTags(path: path)
        tags.removeAll(where: { $0.id == tagId })
        return setTags(tags, path: path)
    }

    // MARK: - 自有格式读写（com.flowfinder.tags，JSON 数组）

    private func readOwnTags(path: String) -> [Tag]? {
        guard let data = getExtendedAttribute(path: path, name: xattrName),
              let tags = try? JSONDecoder().decode([Tag].self, from: data) else {
            return nil
        }
        return tags
    }

    private func writeOwnTags(_ tags: [Tag], path: String) -> Bool {
        guard let data = try? JSONEncoder().encode(tags) else { return false }
        return setExtendedAttribute(path: path, name: xattrName, data: data)
    }

    // MARK: - macOS 原生标签读写（com.apple.metadata:_kMDItemUserTags）

    /// 读取 macOS 原生标签
    /// 格式可能为 plist 数组或换行分隔字符串，统一解析为 [Tag]
    private func readNativeTags(path: String) -> [Tag]? {
        guard let data = getExtendedAttribute(path: path, name: nativeXattrName) else {
            return nil
        }

        // 尝试作为 plist 解析（NSArray）
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let array = plist as? [Any] {
            return parseNativeEntries(array.map { String(describing: $0) })
        }

        // 退化为字符串解析（换行分隔）
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        // 原生格式中每项可能包含内嵌换行（"标签名\n颜色索引"），
        // 项之间也以换行分隔，因此先按换行拆分后两两配对
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return parseNativeEntries(lines)
    }

    /// 将原生标签条目解析为 [Tag]
    ///
    /// 输入为已按换行拆分的字符串数组。原生格式中每个标签条目可能为：
    /// - 纯标签名（如 "Red"）
    /// - "标签名\n颜色索引"（拆分后为相邻两行："Red", "1"）
    ///
    /// 因此本方法按两两配对解析：遇到非数字行视为标签名，
    /// 若下一行为 0-7 的数字则视为该标签的颜色索引，否则标签名为单独条目。
    private func parseNativeEntries(_ entries: [String]) -> [Tag] {
        var tags: [Tag] = []
        var i = 0
        while i < entries.count {
            let line = entries[i].trimmingCharacters(in: .whitespacesAndNewlines)
            // 跳过空行与孤立数字行（数字行应作为前一标签的颜色索引被消费）
            if line.isEmpty || Int(line) != nil {
                i += 1
                continue
            }

            var name = line
            var colorIndex = 0
            // 下一行若为 0-7 的数字，视为颜色索引
            if i + 1 < entries.count {
                let nextLine = entries[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if let idx = Int(nextLine), idx >= 0 && idx <= 7 {
                    colorIndex = idx
                    i += 2
                } else {
                    i += 1
                }
            } else {
                i += 1
            }

            let hex = macOSColorIndexToHex(colorIndex)
            tags.append(Tag(name: name, color: hex))
        }
        return tags
    }

    /// 写入 macOS 原生标签
    /// 采用换行分隔字符串格式："标签名\n颜色索引\n标签名\n颜色索引..."
    private func writeNativeTags(_ tags: [Tag], path: String) -> Bool {
        // 空标签列表时移除原生 xattr，避免残留空标签
        if tags.isEmpty {
            return removeExtendedAttribute(path: path, name: nativeXattrName)
        }

        // 构建换行分隔字符串
        var lines: [String] = []
        for tag in tags {
            let index = hexToMacOSColorIndex(tag.color)
            // 每项为 "标签名\n颜色索引"，项之间以换行分隔
            lines.append("\(tag.name)\n\(index)")
        }
        let raw = lines.joined(separator: "\n")
        guard let data = raw.data(using: .utf8) else { return false }
        return setExtendedAttribute(path: path, name: nativeXattrName, data: data)
    }

    // MARK: - 颜色映射（hex <-> macOS 颜色索引）

    /// macOS 原生标签颜色索引：1=红 2=橙 3=黄 4=绿 5=蓝 6=紫 7=灰，0=无色
    /// 与 FlowFinder 默认调色板（DesignTokens.tagColors / TagSelectorDialog）对应
    private static let hexToIndexMap: [String: Int] = [
        "#ff453a": 1, "#ff9f0a": 2, "#ffd60a": 3,
        "#30d158": 4, "#0a84ff": 5, "#bf5af2": 6, "#8e8e93": 7,
    ]

    private static let indexToHexMap: [Int: String] = [
        0: "#8E8E93", // 无色 -> 默认灰
        1: "#FF453A", 2: "#FF9F0A", 3: "#FFD60A",
        4: "#30D158", 5: "#0A84FF", 6: "#BF5AF2", 7: "#8E8E93",
    ]

    /// hex 颜色字符串 -> macOS 颜色索引（0 表示无色/未识别）
    private func hexToMacOSColorIndex(_ hex: String) -> Int {
        let normalized = hex.lowercased().trimmingCharacters(in: .whitespaces)
        // 去掉可能的 0x 前缀或多余空格
        let cleaned = normalized.hasPrefix("#") ? normalized : "#" + normalized
        return Self.hexToIndexMap[cleaned] ?? 0
    }

    /// macOS 颜色索引 -> hex 颜色字符串
    private func macOSColorIndexToHex(_ index: Int) -> String {
        return Self.indexToHexMap[index] ?? "#8E8E93"
    }

    // MARK: - xattr helpers

    private func getExtendedAttribute(path: String, name: String) -> Data? {
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: length)
        let result = getxattr(path, name, &buffer, length, 0, 0)
        guard result > 0 else { return nil }

        return Data(buffer)
    }

    private func setExtendedAttribute(path: String, name: String, data: Data) -> Bool {
        let result = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return -1 }
            return setxattr(path, name, baseAddress, data.count, 0, 0)
        }
        return result == 0
    }

    private func removeExtendedAttribute(path: String, name: String) -> Bool {
        let result = removexattr(path, name, 0)
        return result == 0
    }
}
