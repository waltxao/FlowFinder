import Foundation

// MARK: - 通知名

extension Notification.Name {
    /// 侧栏标签列表变化（新增/改名/删除后广播，供侧栏与详情栏重建）
    static let sidebarTagsDidRefresh = Notification.Name("SidebarTagsDidRefresh")
    /// 某个标签被删除（携带 name），用于解除正在生效的标签筛选
    static let sidebarTagsDidRemoveTag = Notification.Name("SidebarTagsDidRemoveTag")
    /// 文件标签变化（取消/打上标签后广播）
    static let fileTagsDidChange = Notification.Name("FileTagsDidChange")
}

/// 标签 → 路径 的本地索引。
///
/// 为什么需要它：标签写在每个文件的 xattr 上，没有中央表。删除一个标签时
/// 要「从所有已索引文件移除」，就必须能反查哪些文件带了这个标签。
/// 靠全盘遍历不现实（SMB 下分钟级），所以这里维护一份增量索引：
///
/// - 每次 `TagBridge` 写入成功的标签都会 `record` 进来（浏览目录、打标签、
///   `TagCountService` 计数时都会顺带写入），索引随使用自然变全。
/// - 删除标签时，索引 + Spotlight 查询 (`mdfind`) 两路合并取并集，
///   索引覆盖本地已见过的文件，Spotlight 补充历史遗留的。
///
/// 存储：`~/Library/Application Support/FlowFinder/TagIndex.json`
/// 结构：`{"version":1,"tags":{"重要":["/a","/b"]}}`
///
/// 并发：所有读写走串行队列；内存态为真值，写盘防抖 2 秒合并一次。
final class TagIndexStore {

    static let shared = TagIndexStore()

    /// 索引格式版本，将来结构变更时用于迁移
    private static let schemaVersion = 1

    private let queue = DispatchQueue(label: "com.flowfinder.tagindex", qos: .utility)

    /// 标签名（小写归一）→ 路径集合
    private var tagsToPaths: [String: Set<String>] = [:]
    /// 路径 → 标签名（小写归一）集合，用于 record 时快速摘除旧关系
    private var pathsToTags: [String: Set<String>] = [:]

    /// 写盘防抖：改动后延迟合并写入，避免批量打标签时频繁 IO
    private var flushWorkItem: DispatchWorkItem?
    private static let flushDelay: TimeInterval = 2.0

    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("FlowFinder", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("TagIndex.json")
        load()
    }

    // MARK: - 写入

    /// 记录某路径当前的标签集合（覆盖该路径的旧关系，不追加）。
    /// `TagBridge.setTags` 成功后调用；空标签数组等于清空该路径的关系。
    func record(tags: [Tag], path: String) {
        let names = Set(tags.map { Self.normalize($0.name) }.filter { !$0.isEmpty })
        queue.async { [weak self] in
            guard let self else { return }
            self.replaceRelations(path: path, with: names)
            self.scheduleFlush()
        }
    }

    /// 单个标签挂到路径上（增量，不覆盖该路径其它标签）
    func add(tagName: String, path: String) {
        let name = Self.normalize(tagName)
        guard !name.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.tagsToPaths[name, default: []].insert(path)
            self.pathsToTags[path, default: []].insert(name)
            self.scheduleFlush()
        }
    }

    /// 摘掉路径上的某个标签
    func remove(tagName: String, path: String) {
        let name = Self.normalize(tagName)
        guard !name.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.tagsToPaths[name]?.remove(path)
            if self.tagsToPaths[name]?.isEmpty == true {
                self.tagsToPaths.removeValue(forKey: name)
            }
            self.pathsToTags[path]?.remove(name)
            if self.pathsToTags[path]?.isEmpty == true {
                self.pathsToTags.removeValue(forKey: path)
            }
            self.scheduleFlush()
        }
    }

    /// 文件被删除/移动后清掉它的全部关系
    func forget(path: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.replaceRelations(path: path, with: [])
            self.scheduleFlush()
        }
    }

    // MARK: - 读取

    /// 查所有带该标签的路径（同步，会阻塞调用线程；删除流程在后台队列调用）
    func paths(forTagNamed name: String) -> Set<String> {
        let key = Self.normalize(name)
        return queue.sync { tagsToPaths[key] ?? [] }
    }

    /// 索引里出现过的全部标签名（原始大小写已丢失，仅作诊断用）
    func indexedTagNames() -> [String] {
        queue.sync { Array(tagsToPaths.keys).sorted() }
    }

    /// 索引条目总数（诊断用）
    func entryCount() -> Int {
        queue.sync { pathsToTags.count }
    }

    /// 立即落盘（退出前调用；平时靠防抖）
    func flushNow() {
        queue.sync {
            flushWorkItem?.cancel()
            flushWorkItem = nil
            writeToDisk()
        }
    }

    // MARK: - 内部

    private func replaceRelations(path: String, with names: Set<String>) {
        // 先摘掉旧关系
        if let old = pathsToTags[path] {
            for name in old {
                tagsToPaths[name]?.remove(path)
                if tagsToPaths[name]?.isEmpty == true {
                    tagsToPaths.removeValue(forKey: name)
                }
            }
        }
        // 再建立新关系
        if names.isEmpty {
            pathsToTags.removeValue(forKey: path)
        } else {
            pathsToTags[path] = names
            for name in names {
                tagsToPaths[name, default: []].insert(path)
            }
        }
    }

    private func scheduleFlush() {
        flushWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.writeToDisk()
        }
        flushWorkItem = item
        queue.asyncAfter(deadline: .now() + Self.flushDelay, execute: item)
    }

    private func writeToDisk() {
        var tagsObject: [String: [String]] = [:]
        for (name, paths) in tagsToPaths where !paths.isEmpty {
            tagsObject[name] = paths.sorted()
        }
        let payload: [String: Any] = [
            "version": Self.schemaVersion,
            "tags": tagsObject
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.sortedKeys]) else { return }
        // 原子写：避免中途崩溃留下半截 JSON
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagsObject = root["tags"] as? [String: [String]] else {
            return
        }
        var forward: [String: Set<String>] = [:]
        var backward: [String: Set<String>] = [:]
        for (name, paths) in tagsObject {
            let key = Self.normalize(name)
            guard !key.isEmpty, !paths.isEmpty else { continue }
            forward[key] = Set(paths)
            for path in paths {
                backward[path, default: []].insert(key)
            }
        }
        tagsToPaths = forward
        pathsToTags = backward
    }

    /// 标签名归一化：大小写不敏感、去首尾空白。
    /// 用 lowercased 而非折叠变音符号——中文标签不受影响，
    /// 英文标签「Work」与「work」视为同一个是合理预期。
    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - 批量移除

/// 一次「从所有文件移除某标签」的任务句柄，支持取消。
final class TagRemovalTask {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

extension TagIndexStore {

    /// 收集带某标签的所有文件路径：本地索引 ∪ Spotlight 结果。
    ///
    /// Spotlight 覆盖本机已索引但 App 从未浏览过的文件；索引覆盖
    /// Spotlight 未开或未索引的卷（例如外接硬盘、网络卷）。
    /// 两路都失败时至少返回索引里的部分，不会误报「全部删除成功」。
    func collectPaths(forTagNamed name: String,
                      includeSpotlight: Bool,
                      completion: @escaping (Set<String>) -> Void) {
        let indexed = paths(forTagNamed: name)
        guard includeSpotlight else {
            completion(indexed)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let found = Self.spotlightPaths(forTagNamed: name)
            completion(indexed.union(found))
        }
    }

    /// 调用 `mdfind` 查询 Spotlight 标签索引。
    /// 标签名里的单引号会破坏查询语法，按 shell 习惯转义为 `'\''`。
    static func spotlightPaths(forTagNamed name: String) -> Set<String> {        let escaped = name.replacingOccurrences(of: "'", with: "'\\''")
        let query = "kMDItemUserTags == '\(escaped)'"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            NSLog("[TagIndexStore] mdfind 启动失败: %@", error.localizedDescription)
            return []
        }

        // 30 秒上限：索引损坏时 mdfind 可能长时间无响应，不能挂住删除流程
        let deadline = DispatchTime.now() + .seconds(30)
        let group = DispatchGroup()
        group.enter()
        var output = Data()
        DispatchQueue.global(qos: .utility).async {
            output = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: deadline) == .timedOut {
            process.terminate()
            NSLog("[TagIndexStore] mdfind 超时，仅使用本地索引")
            return []
        }
        process.waitUntilExit()

        guard let text = String(data: output, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }
}

// MARK: - 改色传播

extension TagIndexStore {

    /// 把标签的新颜色同步到所有已带该标签的文件。
    ///
    /// 为什么需要：标签的颜色存在两处——侧栏的标签定义（UserDefaults）
    /// 与每个文件的 `com.flowfinder.tags`。只改前者会让同一标签在文件详情栏
    /// 保持旧色。这里以后台任务把后者一并改写。
    ///
    /// - 路径来源与删除流程一致（本地索引 ∪ Spotlight）；
    /// - 文件已被删除的跳过；单个失败不影响其余；
    /// - 完成后回主线程广播刷新。
    static func propagateColorChange(tagName: String,
                                     newHex: String,
                                     completion: (() -> Void)? = nil) {
        shared.collectPaths(forTagNamed: tagName, includeSpotlight: true) { paths in
            guard !paths.isEmpty else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .fileTagsDidChange, object: nil)
                    completion?()
                }
                return
            }

            DispatchQueue.global(qos: .utility).async {
                let fm = FileManager.default
                for path in paths {
                    guard fm.fileExists(atPath: path) else { continue }
                    var tags = TagBridge.shared.getTags(path: path)
                    guard let index = tags.firstIndex(where: { $0.name == tagName }) else { continue }
                    guard tags[index].color.lowercased() != newHex.lowercased() else { continue }
                    tags[index].color = newHex
                    _ = TagBridge.shared.setTags(tags, path: path)
                }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .fileTagsDidChange, object: nil)
                    completion?()
                }
            }
        }
    }
}

// MARK: - 标签目录（唯一真值）

/// 标签定义/排序的唯一入口。设置页、侧栏、选择器都读写这里，
/// 避免 UserDefaults 多处各写一份导致同名标签漂移。
final class TagCatalog {
    static let shared = TagCatalog()

    private(set) var tags: [Tag] = []
    private let key = FFUserDefaultsKeys.sidebarTags

    private init() { reload() }

    func reload() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Tag].self, from: data) else {
            tags = [
                Tag(name: "重要", color: "#FF453A"),
                Tag(name: "工作", color: "#0A84FF"),
                Tag(name: "个人", color: "#30D158"),
            ]
            save()
            return
        }
        var migrated = decoded
        var changed = false
        for index in migrated.indices {
            let normalized = FFTagColorPalette.normalizedHex(migrated[index].color)
            if normalized != migrated[index].color {
                migrated[index].color = normalized
                changed = true
            }
        }
        tags = migrated
        if changed { save() }
    }

    func tag(named name: String) -> Tag? {
        let key = TagIndexStore.normalize(name)
        return tags.first { TagIndexStore.normalize($0.name) == key }
    }

    func tag(id: String) -> Tag? { tags.first { $0.id == id } }

    @discardableResult
    func add(name: String, color: String) -> Tag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = tag(named: trimmed) { return existing }
        let tag = Tag(name: trimmed, color: FFTagColorPalette.normalizedHex(color))
        tags.append(tag)
        save()
        return tag
    }

    /// 改名；目标名已存在时合并到目标标签（文件上的旧名统一改成目标名）。
    @discardableResult
    func rename(id: String, to newName: String, includeSpotlight: Bool = true) -> Tag? {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return nil }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let oldName = tags[index].name
        let normalizedNew = TagIndexStore.normalize(trimmed)

        if let targetIndex = tags.firstIndex(where: {
            $0.id != id && TagIndexStore.normalize($0.name) == normalizedNew
        }) {
            let target = tags[targetIndex]
            tags.remove(at: index)
            save()
            TagIndexStore.mutateTag(oldName: oldName,
                                    newName: target.name,
                                    newColor: target.color,
                                    includeSpotlight: includeSpotlight)
            return target
        }

        tags[index].name = trimmed
        let color = tags[index].color
        save()
        TagIndexStore.mutateTag(oldName: oldName,
                                newName: trimmed,
                                newColor: color,
                                includeSpotlight: includeSpotlight)
        return tags[index]
    }

    func recolor(id: String, hex: String) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        let name = tags[index].name
        tags[index].color = FFTagColorPalette.normalizedHex(hex)
        save()
        TagIndexStore.propagateColorChange(tagName: name, newHex: tags[index].color)
    }

    /// 只移除标签定义，不触碰文件（文件已由调用方批量清理时使用）。
    func removeDefinition(id: String, name: String) {
        tags.removeAll { $0.id == id || TagIndexStore.normalize($0.name) == TagIndexStore.normalize(name) }
        save()
    }

    func delete(id: String, includeSpotlight: Bool = true) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        let name = tags[index].name
        tags.remove(at: index)
        save()
        TagIndexStore.mutateTag(oldName: name,
                                newName: nil,
                                newColor: nil,
                                includeSpotlight: includeSpotlight)
        NotificationCenter.default.post(name: .sidebarTagsDidRemoveTag,
                                        object: nil, userInfo: ["name": name])
    }

    func move(id: String, to destination: Int) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        let tag = tags.remove(at: index)
        let target = min(max(destination, 0), tags.count)
        tags.insert(tag, at: target)
        save()
    }

    /// 目标文件数（本地索引 ∪ Spotlight），用于删除/改名前的影响提示。
    func affectedPathCount(forTagNamed name: String,
                           completion: @escaping (Int) -> Void) {
        TagIndexStore.shared.collectPaths(forTagNamed: name, includeSpotlight: true) { paths in
            completion(paths.count)
        }
    }

    func addTag(_ tag: Tag, to paths: [String], completion: (() -> Void)? = nil) {
        guard !paths.isEmpty else { completion?(); return }
        DispatchQueue.global(qos: .userInitiated).async {
            for path in paths {
                _ = TagBridge.shared.addTag(tag, path: path)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .fileTagsDidChange, object: nil)
                completion?()
            }
        }
    }

    func removeTag(named name: String, from paths: [String], completion: (() -> Void)? = nil) {
        guard !paths.isEmpty else { completion?(); return }
        DispatchQueue.global(qos: .userInitiated).async {
            for path in paths {
                _ = TagBridge.shared.removeTagByName(name, path: path)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .fileTagsDidChange, object: nil)
                completion?()
            }
        }
    }

    func clearTags(on paths: [String], completion: (() -> Void)? = nil) {
        guard !paths.isEmpty else { completion?(); return }
        DispatchQueue.global(qos: .userInitiated).async {
            for path in paths {
                _ = TagBridge.shared.setTags([], path: path)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .fileTagsDidChange, object: nil)
                completion?()
            }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tags) else { return }
        UserDefaults.standard.set(data, forKey: key)
        NotificationCenter.default.post(name: .sidebarTagsDidRefresh, object: nil)
    }
}

extension TagIndexStore {
    /// 跨文件改名/改色/删除。newName=nil 表示删除；newColor=nil 表示保留原色。
    static func mutateTag(oldName: String,
                          newName: String?,
                          newColor: String?,
                          includeSpotlight: Bool = true,
                          completion: ((Int) -> Void)? = nil) {
        shared.collectPaths(forTagNamed: oldName, includeSpotlight: includeSpotlight) { paths in
            DispatchQueue.global(qos: .userInitiated).async {
                var changed = 0
                for path in paths {
                    guard FileManager.default.fileExists(atPath: path) else { continue }
                    var tags = TagBridge.shared.getTags(path: path)
                    guard let index = tags.firstIndex(where: { $0.name == oldName }) else { continue }
                    if let newName, !newName.isEmpty {
                        tags[index].name = newName
                        if let newColor { tags[index].color = newColor }
                        var seen = Set<String>()
                        tags = tags.filter { seen.insert($0.name).inserted }
                    } else {
                        tags.remove(at: index)
                    }
                    if TagBridge.shared.setTags(tags, path: path) { changed += 1 }
                }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .fileTagsDidChange, object: nil)
                    completion?(changed)
                }
            }
        }
    }
}
