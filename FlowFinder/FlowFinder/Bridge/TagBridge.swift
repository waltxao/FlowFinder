import Foundation

/// xattr 标签读写桥接
///
/// 标签同时存储在两个扩展属性中，实现与 macOS Finder 的双向同步：
/// - `com.flowfinder.tags`：自有格式，JSON 数组（含 id 与任意 hex 颜色），App 内以此为准
/// - `com.apple.metadata:_kMDItemUserTags`：macOS 原生标签，Finder 可见
///   **必须是 binary plist 的字符串数组**，每项为 "标签名\n颜色索引"
///   （颜色索引 0=无色, 1=红, 2=橙, 3=黄, 4=绿, 5=蓝, 6=紫, 7=灰）
///   写成纯文本换行串时 Finder 不显示、Spotlight 也不索引，因此写入只能走 plist。
public final class TagBridge {
    public static let shared = TagBridge()

    /// 自有标签 xattr 名（JSON 数组）
    private let xattrName = "com.flowfinder.tags"
    /// macOS 原生标签 xattr 名（Finder 可见）
    private let nativeXattrName = "com.apple.metadata:_kMDItemUserTags"

    /// 标签内存缓存：大目录下避免对每个文件重复 getxattr 系统调用。
    /// key 为文件路径，value 为标签数组。
    /// 写操作时自动失效对应 key；外部文件变更可通过 invalidateCache 失效。
    private let cache: NSCache<NSString, NSArray> = {
        let c = NSCache<NSString, NSArray>()
        c.countLimit = 5000
        return c
    }()

    private init() {}

    /// 获取文件的标签（合并自有与 macOS 原生两个来源，按标签名去重）
    /// 优先查内存缓存，未命中才做 getxattr I/O
    public func getTags(path: String) -> [Tag] {
        let cacheKey = NSString(string: path)
        if let cached = cache.object(forKey: cacheKey) as? [Tag] {
            return cached
        }

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

        cache.setObject(result as NSArray, forKey: cacheKey)
        return result
    }

    /// **只读缓存**的标签（不触发 I/O）。
    ///
    /// 2026-10-20 #4：渲染路径必须用它，不能用 `getTags`——后者在缓存未命中时
    /// 会同步做 getxattr，主线程在 22 个条目上就能卡 1–2 分钟（`sample` 抓到
    /// 主线程卡在 getxattr）。渲染先按「无标签」出，预热完成后由通知刷新。
    public func cachedTags(path: String) -> [Tag] {
        cache.object(forKey: NSString(string: path)) as? [Tag] ?? []
    }

    /// 失效指定路径的标签缓存（FSEvents 检测到文件变更时调用）
    public func invalidateCache(path: String) {
        cache.removeObject(forKey: NSString(string: path))
    }

    /// Wave3 Task 7: 批量后台预热标签缓存（async P1-4）
    ///
    /// 首次进入大目录后，渲染/滚动路径（列表 rebuildDisplayRows/viewFor、网格 item didSet）
    /// 会逐条调 getTags——缓存未命中即主线程 getxattr（本地 5k 文件 ≈ 20-100ms，SMB 秒级）。
    /// loadDirectory 完成后取前 500 条路径调用本方法：后台 utility 队列循环 getTags 填充缓存，
    /// 后续主线程渲染直接读缓存，滚动不再有逐条 xattr 卡顿。
    ///
    /// 线程安全：NSCache 线程安全；getTags 读 xattr 为纯函数，读幂等。
    /// 与既有 tagFilter 异步读标签路径（applyFilter 后台读标签）不打架——同一缓存，
    /// 预热只会让该路径更快命中，不改变其行为。
    /// 取舍：预热完成后不补发刷新通知——若渲染早于预热命中，该批条目在渲染时已同步
    /// 读到标签并填充缓存，视觉结果一致，无需二次 reload。
    public func warmCache(paths: [String], completion: (() -> Void)? = nil) {
        guard !paths.isEmpty else {
            completion?()
            return
        }
        DispatchQueue.global(qos: .utility).async {
            for path in paths {
                _ = self.getTags(path: path)
            }
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    /// 失效全部缓存（导航到新目录或批量操作后调用）
    public func invalidateAllCache() {
        cache.removeAllObjects()
    }

    /// 设置文件的标签（覆盖），同时同步到自有与 macOS 原生两个位置
    public func setTags(_ tags: [Tag], path: String) -> Bool {
        // 1. 写入自有格式（保留 id 与 hex 颜色）
        let ownOK = writeOwnTags(tags, path: path)

        // 2. 写入 macOS 原生格式（让 Finder 可见）
        let nativeOK = writeNativeTags(tags, path: path)

        // 失效缓存（写入后旧缓存不再有效）
        cache.removeObject(forKey: NSString(string: path))

        // 3. 同步标签倒排索引（删除标签时靠它反查所有受影响文件）。
        //    只在写入成功时记录，避免索引里出现「其实没打上」的路径。
        if ownOK || nativeOK {
            TagIndexStore.shared.record(tags: tags, path: path)
        }

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

    /// 移除标签（同时按 id 和 name 匹配，兼容原生标签的随机 id）
    public func removeTag(_ tagId: String, path: String) -> Bool {
        var tags = getTags(path: path)
        // 先尝试按 id 匹配
        tags.removeAll(where: { $0.id == tagId })
        // 再尝试按 name 匹配（原生标签 id 每次随机，需按 name 补充移除）
        // 通过 tagId 查找对应的 tag name（调用方可能传入 name 作为 tagId）
        tags.removeAll(where: { $0.name == tagId })
        return setTags(tags, path: path)
    }

    /// 按名称移除标签
    public func removeTagByName(_ name: String, path: String) -> Bool {
        var tags = getTags(path: path)
        tags.removeAll(where: { $0.name == name })
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

        // 1. 标准格式：binary plist 字符串数组，每项 "标签名\n颜色索引"
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let array = plist as? [Any] {
            return array.compactMap { entry -> Tag? in
                let text = (entry as? String) ?? String(describing: entry)
                // 单项内部自带换行：拆出名称与颜色索引
                let parts = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                guard let rawName = parts.first else { return nil }
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                var colorIndex = 0
                for extra in parts.dropFirst() {
                    if let idx = Int(extra.trimmingCharacters(in: .whitespacesAndNewlines)), (0...7).contains(idx) {
                        colorIndex = idx
                        break
                    }
                }
                return Tag(name: name, color: macOSColorIndexToHex(colorIndex))
            }
        }

        // 2. 兼容旧数据：早期误写成纯文本换行串，按两两配对解析
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
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

            let name = line
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
    /// 系统要求 `_kMDItemUserTags` 为 binary plist 的字符串数组，每项 "标签名\n颜色索引"。
    /// App 的标签色可以是任意 hex，写入原生时取最接近的 7 个系统色之一。
    private func writeNativeTags(_ tags: [Tag], path: String) -> Bool {
        // 空标签列表时移除原生 xattr，避免残留空标签
        if tags.isEmpty {
            return removeExtendedAttribute(path: path, name: nativeXattrName)
        }

        let entries: [String] = tags.map { tag in
            "\(tag.name)\n\(hexToMacOSColorIndex(tag.color))"
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: entries,
                                                             format: .binary,
                                                             options: 0) else {
            return false
        }
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

    /// hex 颜色字符串 -> macOS 颜色索引（1–7）
    /// App 允许任意色，原生只认 7 种，取最接近的一个；无法解析时回退蓝色（5）
    private func hexToMacOSColorIndex(_ hex: String) -> Int {
        let cleaned = Self.normalizedHex(hex)
        if let exact = Self.hexToIndexMap[cleaned] { return exact }

        guard let target = Self.rgbComponents(cleaned) else { return 5 }
        var bestIndex = 5
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, hexText) in Self.indexToHexMap where index != 0 {
            guard let candidate = Self.rgbComponents(Self.normalizedHex(hexText)) else { continue }
            // 按人眼敏感度加权，避免橙色被误判成红色
            let dr = target.r - candidate.r
            let dg = target.g - candidate.g
            let db = target.b - candidate.b
            let distance = 0.30 * dr * dr + 0.59 * dg * dg + 0.11 * db * db
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// 统一为 "#rrggbb" 小写形式，支持 #abc / abc / #AABBCC
    private static func normalizedHex(_ hex: String) -> String {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        return "#" + s
    }

    private static func rgbComponents(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255)
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
