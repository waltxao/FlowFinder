import AppKit

/// 列表列定义与可见性状态（2026-10-20 #3）。
///
/// 为什么单独一个文件：列的「有哪些、怎么排序、宽多少、能不能关」是**数据**，
/// 不是视图逻辑。放在这里以后加一列 = 往 `FFListColumn` 加一个 case，
/// 不用改 `FileListView` 的建列代码。
enum FFListColumn: String, CaseIterable {
    case name
    case kind
    case size
    case modified
    case created
    case tags
    case comment

    /// 列表头标题
    var title: String {
        switch self {
        case .name: return "名称"
        case .kind: return "类型"
        case .size: return "大小"
        case .modified: return "修改日期"
        case .created: return "创建日期"
        case .tags: return "标签"
        case .comment: return "说明"
        }
    }

    /// 默认宽度
    var defaultWidth: CGFloat {
        switch self {
        case .name: return 280
        case .kind: return 140
        case .size: return 80
        case .modified: return 150
        case .created: return 150
        case .tags: return 130
        case .comment: return 200
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .name: return 120
        case .size: return 70
        case .kind: return 80
        default: return 110
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .name: return 2000
        case .size: return 120
        case .kind: return 260
        default: return 400
        }
    }

    /// 列内对齐：文本左对齐、数值右对齐（不是列内水平居中，见 R-10）
    var alignment: NSTextAlignment {
        switch self {
        case .size: return .right
        case .name, .kind, .modified, .created, .comment: return .left
        case .tags: return .left
        }
    }

    /// 名称是唯一必选列
    var isRequired: Bool { self == .name }

    /// 默认可见的四列：名称、类型、大小、修改日期
    var defaultVisible: Bool {
        switch self {
        case .name, .kind, .size, .modified: return true
        case .created, .tags, .comment: return false
        }
    }

    /// 排序键。nil = 该列不支持排序（点列头无效）。
    ///
    /// `sortDescriptorsDidChange` 只认 name / modifiedAt / type / size 四个 key，
    /// 所以可选列一律不给 prototype——点了也不会误改排序。
    var sortKey: String? {
        switch self {
        case .name: return "name"
        case .kind: return "type"
        case .size: return "size"
        case .modified: return "modifiedAt"
        case .created, .tags, .comment: return nil
        }
    }

    /// 面板变窄时的收起顺序，数字越大越先被收起。
    /// 名称永不收（`isRequired`）。
    var fitPriority: Int {
        switch self {
        case .name: return 0
        case .modified: return 1
        case .size: return 2
        case .kind: return 3
        case .created: return 4
        case .tags: return 5
        case .comment: return 6
        }
    }

    /// 创建 NSTableColumn
    func makeColumn(width: CGFloat? = nil) -> NSTableColumn {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue))
        col.title = title
        col.headerCell = FFPillHeaderCell()
        col.headerCell.stringValue = title
        let w = width ?? defaultWidth
        col.width = w
        col.minWidth = minWidth
        col.maxWidth = maxWidth
        // 名称列吃掉全部弹性增量，其余定宽（面板变窄先省略名称）
        col.resizingMask = self == .name ? [.userResizingMask, .autoresizingMask] : [.userResizingMask]
        if let key = sortKey {
            col.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true)
        }
        return col
    }
}

/// 列可见性与列宽的持久化（2026-10-20 #3）。
enum FFListColumnsState {

    static let didChangeNotification = Notification.Name("FFListColumnsDidChange")

    private static let visibleKey = "list_visible_columns"
    private static let widthsKey = "list_column_widths"

    /// 当前可见列（按 `allCases` 的固定顺序返回，与用户勾选顺序无关）
    static func visibleColumns() -> [FFListColumn] {
        guard let raw = UserDefaults.standard.array(forKey: visibleKey) as? [String] else {
            return FFListColumn.allCases.filter { $0.defaultVisible }
        }
        let set = Set(raw)
        let cols = FFListColumn.allCases.filter { set.contains($0.rawValue) }
        // 必选列永远在
        if cols.contains(where: { $0.isRequired }) { return cols }
        return [FFListColumn.name] + cols
    }

    static func isVisible(_ column: FFListColumn) -> Bool {
        visibleColumns().contains(column)
    }

    /// 设成指定可见集合（必选列会被强制保留）
    static func setVisible(_ columns: [FFListColumn]) {
        var set = Set(columns)
        set.insert(.name)
        let ordered = FFListColumn.allCases.filter { set.contains($0) }
        UserDefaults.standard.set(ordered.map { $0.rawValue }, forKey: visibleKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// 切换一列（必选列忽略）
    @discardableResult
    static func toggle(_ column: FFListColumn) -> Bool {
        guard !column.isRequired else { return false }
        var current = Set(visibleColumns())
        if current.contains(column) { current.remove(column) } else { current.insert(column) }
        setVisible(Array(current))
        return true
    }

    /// 列宽记忆
    static func width(for column: FFListColumn, default fallback: CGFloat) -> CGFloat {
        guard let dict = UserDefaults.standard.dictionary(forKey: widthsKey),
              let w = dict[column.rawValue] as? Double, w > 0 else { return fallback }
        return CGFloat(w)
    }

    static func setWidth(_ width: CGFloat, for column: FFListColumn) {
        var dict = UserDefaults.standard.dictionary(forKey: widthsKey) as? [String: Double] ?? [:]
        dict[column.rawValue] = Double(width)
        UserDefaults.standard.set(dict, forKey: widthsKey)
    }

    /// 面板宽度不够时，按 `fitPriority` 从高到低依次收起，返回还能显示的列。
    ///
    /// - Parameters:
    ///   - available: 面板内容宽度
    ///   - columns: 当前可见列（按显示顺序）
    static func columnsFitting(in available: CGFloat,
                               from columns: [FFListColumn],
                               widths: [FFListColumn: CGFloat]? = nil) -> [FFListColumn] {
        var current = columns
        func widthOf(_ c: FFListColumn) -> CGFloat {
            widths?[c] ?? width(for: c, default: c.defaultWidth)
        }
        func total() -> CGFloat {
            current.reduce(0) { $0 + widthOf($1) }
        }
        // 名称列有 minWidth 兜底，其余列整列收起
        for col in columns.sorted(by: { $0.fitPriority > $1.fitPriority }) where !col.isRequired {
            if total() <= available { break }
            current.removeAll { $0 == col }
        }
        return current
    }

    // MARK: - 临时收起的列（R4-03）

    /// 因面板太窄被**临时**收起的列，按面板分别记录。
    /// 只存内存、不写 UserDefaults：用户勾过但被宽度挤掉的列不该变成持久设置。
    private static var fittedOutBySide: [PaneSide: Set<FFListColumn>] = [:]

    static func setFittedOut(_ columns: [FFListColumn], for side: PaneSide) {
        fittedOutBySide[side] = Set(columns)
    }

    /// 任一侧收起即算收起：「显示列」菜单是双栏共用的，只报一侧会漏标。
    static func fittedOutColumns() -> Set<FFListColumn> {
        var result: Set<FFListColumn> = []
        for set in fittedOutBySide.values { result.formUnion(set) }
        return result
    }

    /// 列在菜单里的标题：被宽度挤掉时说明原因，不让列无声消失。
    static func title(forDisplay column: FFListColumn) -> String {
        fittedOutColumns().contains(column) ? "\(column.title)（面板太窄）" : column.title
    }
}

/// 列头右键菜单 / 显示菜单 / 工具栏视图面板共用的菜单构建器。
///
/// 三个入口建构同一份菜单，避免「菜单里能开、右键里不能开」这类不一致。
enum FFListColumnMenu {

    /// 构建「显示列」菜单。每个 item 的 `representedObject` 是列 rawValue，
    /// `state` 直接反映当前可见性，必选列 disable。
    static func build(target: AnyObject?, action: Selector) -> NSMenu {
        let menu = NSMenu(title: "显示列")
        menu.autoenablesItems = false
        for column in FFListColumn.allCases {
            let item = NSMenuItem(title: FFListColumnsState.title(forDisplay: column),
                                  action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = column.rawValue
            item.state = FFListColumnsState.isVisible(column) ? .on : .off
            item.isEnabled = !column.isRequired
            menu.addItem(item)
        }
        return menu
    }

    /// 处理一次菜单点击（三个入口共用）
    static func handleSelection(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String,
              let column = FFListColumn(rawValue: raw) else { return }
        FFListColumnsState.toggle(column)
    }
}

/// 菜单打开时刷新勾选态。
///
/// 三个入口的菜单可能是常驻的（菜单栏「显示列」子菜单），建成后不会重建，
/// 所以在 `menuNeedsUpdate` 里按当前状态重刷勾。
final class FFListColumnMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = FFListColumnMenuDelegate()

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            guard let raw = item.representedObject as? String,
                  let column = FFListColumn(rawValue: raw) else { continue }
            item.state = FFListColumnsState.isVisible(column) ? .on : .off
            item.title = FFListColumnsState.title(forDisplay: column)
        }
    }
}

/// Finder 说明（kMDItemFinderComment）读写与旧 UserDefaults 迁移。
///
/// Finder 的「显示简介 → 注释」把说明存成 `com.apple.metadata:kMDItemFinderComment`
/// 扩展属性，值是 binary plist 字符串。直接走 xattr 比等 Spotlight 索引更可靠，
/// 且文件改名/移动时 xattr 随文件走，不会像绝对路径 key 一样丢失。
enum FFFinderCommentStore {

    struct MigrationReport: Equatable {
        var migrated = 0
        var keptLegacy = 0
        var failed = 0
        var skipped = false
    }

    static let xattrName = "com.apple.metadata:kMDItemFinderComment"
    static let legacyDefaultsKey = "fileDescriptions"
    static let migrationDefaultsKey = "fileDescriptionsMigratedToFinderCommentV1"

    static func read(path: String) -> String? {
        guard let data = readXattr(path: path) else { return nil }
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let text = plist as? String {
            return nonEmpty(text)
        }
        // 兼容早期写入的纯文本 xattr
        if let text = String(data: data, encoding: .utf8) {
            return nonEmpty(text)
        }
        return nil
    }

    @discardableResult
    static func write(path: String, comment: String) -> Bool {
        guard nonEmpty(comment) != nil else {
            return removeXattr(path: path)
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: comment,
                                                             format: .binary,
                                                             options: 0) else {
            return false
        }
        return setXattr(path: path, data: data)
    }

    static func legacyDescription(path: String, defaults: UserDefaults = .standard) -> String? {
        let dict = defaults.dictionary(forKey: legacyDefaultsKey) ?? [:]
        return nonEmpty(dict[path] as? String ?? "")
    }

    static func removeLegacyDescription(path: String, defaults: UserDefaults = .standard) {
        var dict = defaults.dictionary(forKey: legacyDefaultsKey) ?? [:]
        guard dict.removeValue(forKey: path) != nil else { return }
        if dict.isEmpty {
            defaults.removeObject(forKey: legacyDefaultsKey)
        } else {
            defaults.set(dict, forKey: legacyDefaultsKey)
        }
    }

    /// 首次启动把旧绝对路径字典迁移到 Finder 注释。
    /// - 路径仍存在且 Finder 注释为空：写入并移除旧条目
    /// - Finder 注释已有值：不覆盖，保留旧条目
    /// - 路径失效或写入失败：保留旧条目，详情栏仍可回退读取
    @discardableResult
    static func migrateLegacyDescriptionsIfNeeded(
        defaults: UserDefaults = .standard,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        readComment: (String) -> String? = { FFFinderCommentStore.read(path: $0) },
        writeComment: (String, String) -> Bool = { path, comment in
            FFFinderCommentStore.write(path: path, comment: comment)
        }
    ) -> MigrationReport {
        if defaults.bool(forKey: migrationDefaultsKey) {
            return MigrationReport(skipped: true)
        }

        let raw = defaults.dictionary(forKey: legacyDefaultsKey) ?? [:]
        let legacy = raw.compactMapValues { $0 as? String }
        var remaining: [String: String] = [:]
        var report = MigrationReport()

        for (path, value) in legacy {
            guard nonEmpty(value) != nil else { continue }
            guard fileExists(path) else {
                remaining[path] = value
                report.keptLegacy += 1
                continue
            }
            if nonEmpty(readComment(path) ?? "") != nil {
                remaining[path] = value
                report.keptLegacy += 1
                continue
            }
            if writeComment(path, value) {
                report.migrated += 1
            } else {
                remaining[path] = value
                report.failed += 1
            }
        }

        if remaining.isEmpty {
            defaults.removeObject(forKey: legacyDefaultsKey)
        } else {
            defaults.set(remaining, forKey: legacyDefaultsKey)
        }
        defaults.set(true, forKey: migrationDefaultsKey)
        return report
    }

    // MARK: - private

    private static func nonEmpty(_ text: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private static func readXattr(path: String) -> Data? {
        let length = getxattr(path, xattrName, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        let result = getxattr(path, xattrName, &buffer, length, 0, 0)
        guard result > 0 else { return nil }
        return Data(buffer)
    }

    private static func setXattr(path: String, data: Data) -> Bool {
        let result = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return -1 }
            return setxattr(path, xattrName, baseAddress, data.count, 0, 0)
        }
        return result == 0
    }

    private static func removeXattr(path: String) -> Bool {
        let result = removexattr(path, xattrName, 0)
        return result == 0 || errno == ENOENT
    }
}

/// Finder 说明缓存：列表滚动时先读内存，未命中再后台读 xattr。
/// 写入说明后由详情栏调用 `setComment` 直接更新缓存，避免等下一次重读。
final class FFFinderCommentCache {

    static let shared = FFFinderCommentCache()

    private var cache: [String: String] = [:]
    private var pending: Set<String> = []
    private let lock = NSLock()

    /// 已缓存的说明（未命中返回 nil）
    func cachedComment(for path: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return cache[path]
    }

    /// 异步取说明；取到后主线程回调（失败回调 nil）
    func fetchComment(for path: String, completion: @escaping (String?) -> Void) {
        lock.lock()
        if let hit = cache[path] {
            lock.unlock()
            completion(hit)
            return
        }
        if pending.contains(path) {
            lock.unlock()
            completion(nil)
            return
        }
        pending.insert(path)
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let comment = FFFinderCommentStore.read(path: path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.lock.lock()
                self.pending.remove(path)
                if let comment { self.cache[path] = comment }
                else { self.cache.removeValue(forKey: path) }
                self.lock.unlock()
                completion(comment)
            }
        }
    }

    func setComment(_ comment: String?, for path: String) {
        lock.lock(); defer { lock.unlock() }
        if let comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cache[path] = comment
        } else {
            cache.removeValue(forKey: path)
        }
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
        pending.removeAll()
    }
}

/// 列宽重算的触发策略：窗口宽度没变时不重算，避免拖动/布局抖动引发列重建。
enum FFColumnFitPolicy {
    static func shouldFit(previousWidth: CGFloat, currentWidth: CGFloat) -> Bool {
        abs(currentWidth - previousWidth) > 0.5
    }

    /// 名称列下限 = 可用宽度的 40%，且不低于 160pt。
    /// 类型/日期等次要列不得把主信息列挤得比它们更窄。
    static func nameFloor(available: CGFloat) -> CGFloat {
        max(160, available * 0.4)
    }
}
