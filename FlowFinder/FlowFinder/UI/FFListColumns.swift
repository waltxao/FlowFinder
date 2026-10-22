import AppKit
import CoreServices

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
            let item = NSMenuItem(title: column.title, action: action, keyEquivalent: "")
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
        }
    }
}

/// Finder 说明（kMDItemFinderComment）缓存。
///
/// 说明列不在文件系统属性里，只能走 Spotlight 元数据；同步查询会拖慢滚动，
/// 因此先返回缓存（未命中返回 nil，界面显示占位），后台取到后再回调刷新。
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
            var comment: String?
            if let item = MDItemCreateWithURL(nil, URL(fileURLWithPath: path) as CFURL),
               let value = MDItemCopyAttribute(item, kMDItemFinderComment) as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                comment = value
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.lock.lock()
                self.pending.remove(path)
                if let comment { self.cache[path] = comment }
                self.lock.unlock()
                completion(comment)
            }
        }
    }
}

/// 列宽重算的触发策略：窗口宽度没变时不重算，避免拖动/布局抖动引发列重建。
enum FFColumnFitPolicy {
    static func shouldFit(previousWidth: CGFloat, currentWidth: CGFloat) -> Bool {
        abs(currentWidth - previousWidth) > 0.5
    }
}
