import Cocoa
import Combine

// MARK: - FFQuickLookTableView

/// 拦截空格键的 NSTableView 子类：
/// first responder 是 NSTableView 时，空格键事件到达 tableView.keyDown 即被
/// interpretKeyEvents 消耗，不会冒泡到 FileListView.keyDown——QuickLook 无法触发
/// （问题 6 根因）。此子类在 keyDown 拦截空格并发送通知转发给 MainWindowController。
final class FFQuickLookTableView: NSTableView {
    /// 空格键触发 QuickLook 通知（userInfo 携带 side）
    var onSpaceKey: ((String) -> Void)?
    /// 当前所属面板标识（left/right）
    var side: String = "left"

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags
        if event.keyCode == 49 && modifiers.isEmpty {
            // 空格：发送通知触发 QuickLook（不消费事件，让 FileListView.keyDown 兜底链路也走）
            onSpaceKey?(side)
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - FFDebug (file-based debug logger)

/// 文件日志工具：写入 /tmp/ff-debug.log，不依赖系统日志
enum FFDebug {
    private static let logPath = "/tmp/ff-debug.log"
    private static let queue = DispatchQueue(label: "ff.debug.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ msg: String) {
        queue.async {
            let ts = formatter.string(from: Date())
            let line = "[\(ts)] \(msg)\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logPath) {
                    if let handle = FileHandle(forWritingAtPath: logPath) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    FileManager.default.createFile(atPath: logPath, contents: data)
                }
            }
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(atPath: logPath)
    }
}

// MARK: - FFPillHeaderCell

/// 任务 F10-7: 访达风格药丸列头（圆角背景 + 文字 + 排序箭头）
///
/// 自定义 NSTableHeaderCell：
/// - 列头文字绘制在圆角药丸背景内（半透明次级填充色），仿访达列头视觉
/// - 当前排序列在右侧绘制升降序箭头（chevron.up / chevron.down）
/// - 点击列头切换排序的逻辑由 NSTableView 标准机制处理（sortDescriptorPrototype +
///   tableView(_:sortDescriptorsDidChange:)），本类仅负责绘制
private final class FFPillHeaderCell: NSTableHeaderCell {

    /// 药丸内边距（左右）
    private let horizontalPadding: CGFloat = 10
    /// 文字与箭头间距
    private let arrowGap: CGFloat = 4
    /// 箭头尺寸
    private let arrowSize: CGFloat = 10

    /// 绘制列头：圆角药丸背景 + 居中文字 + （排序列）排序箭头
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        // 任务 F10-7: 圆角药丸背景（次级填充色，仿访达列头）
        // 上下各留 3pt 边距，使药丸在列头条内垂直居中
        let pillInsetY: CGFloat = 3
        let pillRect = NSRect(x: cellFrame.origin.x + 2,
                              y: cellFrame.origin.y + pillInsetY,
                              width: cellFrame.width - 4,
                              height: cellFrame.height - pillInsetY * 2)
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            // 药丸背景：次级填充色（浅灰，在玻璃材质上有层次感）
            // macOS 14+ 用 secondarySystemFill，旧系统回退 controlBackgroundColor
            if #available(macOS 14.0, *) {
                NSColor.secondarySystemFill.setFill()
            } else {
                NSColor.controlBackgroundColor.setFill()
            }
            let path = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)
            path.fill()
            context.restoreGState()
        }

        // 文字颜色：标签色
        // 任务 F10-11: 列头字号统一 11pt（访达列头标准，修正此前 13pt 偏大）（v0.6.6）
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        let title = self.title as NSString

        // 检查本列是否为当前排序列，并取得升降序方向
        // 通过 controlView（NSTableHeaderView）-> tableView -> sortDescriptors 反查
        let ascending = self.sortAscendingForCurrentColumn(controlView: controlView)
        let hasSortIndicator = ascending != nil

        // 文字区域：药丸内左右各留 horizontalPadding；排序列右侧为箭头预留空间
        var textRect = pillRect
        textRect.origin.x += horizontalPadding
        textRect.size.width -= horizontalPadding * 2
        if hasSortIndicator {
            textRect.size.width -= (arrowSize + arrowGap)
        }

        // 文字垂直居中
        let titleHeight = title.size(withAttributes: titleAttr).height
        textRect.origin.y = pillRect.origin.y + (pillRect.height - titleHeight) / 2
        textRect.size.height = titleHeight

        title.draw(in: textRect, withAttributes: titleAttr)

        // 绘制排序箭头（仅排序列）
        if let ascending = ascending {
            self.drawSortIndicator(withFrame: cellFrame, in: controlView, ascending: ascending, priority: 0)
        }
    }

    /// 绘制排序指示器（升降序箭头）
    /// 仅当本列为当前排序列时，NSTableView 才会调用此方法
    override func drawSortIndicator(withFrame cellFrame: NSRect, in controlView: NSView, ascending: Bool, priority: Int) {
        // 仅绘制主排序（priority == 0）
        guard priority == 0 else { return }
        let arrowRect = self.sortIndicatorRect(forBounds: cellFrame)
        let symbolName = ascending ? "chevron.up" : "chevron.down"
        if let arrow = NSImage(systemSymbolName: symbolName, accessibilityDescription: ascending ? "升序" : "降序") {
            // 配置符号权重与大小
            let config = NSImage.SymbolConfiguration(pointSize: arrowSize, weight: .regular)
            let configured = arrow.withSymbolConfiguration(config) ?? arrow
            // 次级标签色（与文字协调）
            NSColor.secondaryLabelColor.set()
            configured.draw(in: arrowRect)
        }
    }

    /// 排序指示器位置：列头右侧，垂直居中
    override func sortIndicatorRect(forBounds rect: NSRect) -> NSRect {
        return NSRect(x: rect.maxX - horizontalPadding - arrowSize,
                      y: rect.origin.y + (rect.height - arrowSize) / 2,
                      width: arrowSize,
                      height: arrowSize)
    }

    /// 反查当前列是否为排序列，返回升降序方向（nil 表示非排序列）
    /// 通过 controlView（NSTableHeaderView）-> tableView -> sortDescriptors 反查
    private func sortAscendingForCurrentColumn(controlView: NSView?) -> Bool? {
        guard let headerView = controlView as? NSTableHeaderView,
              let tableView = headerView.tableView else { return nil }
        // 找到本 cell 所属列
        guard let column = tableView.tableColumns.first(where: { ($0.headerCell as AnyObject) === self }) else {
            return nil
        }
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key else { return nil }
        // 列 identifier 与 sortDescriptor key 对应关系
        let identifier = column.identifier.rawValue
        let matched: Bool
        switch key {
        case "name": matched = identifier == "name"
        case "modifiedAt": matched = identifier == "modifiedAt"
        case "type": matched = identifier == "type"
        case "size": matched = identifier == "size"
        default: matched = false
        }
        return matched ? descriptor.ascending : nil
    }
}

// MARK: - FFTableCellView

/// 自定义 NSTableCellView：layer-backed，背景保持透明（.clear）以让 NSTableRowView
/// 的标准 drawSelection 选中绘制可见。选中高亮完全由 rowView 标准机制处理，
/// cellView 不参与选中绘制。
private class FFTableCellView: NSTableCellView {
    /// 任务 F8：记录该 cell 当前显示文件的完整路径。
    /// 用于缩略图异步回调时校验 cell 仍显示同一文件（避免旧请求覆盖新 cell）。
    /// 注意：不能用 cellView.identifier 记录路径--identifier 用于 NSTableView
    /// 的复用匹配（makeView(withIdentifier:owner:)），覆写会破坏 cell 复用机制。
    var currentFilePath: String?

    /// 任务 F11-7: 记录该 cell 当前工作区图标对应的文件路径（含目录）。
    /// 与 currentFilePath 分离：currentFilePath 仅记录文件（用于缩略图取消），
    /// 目录时为 nil；而 iconPath 同时覆盖目录与文件，用于工作区图标回调校验，
    /// 避免目录的异步图标回调无法通过 currentFilePath 校验而被丢弃。
    var iconPath: String?

    /// 任务 F11-7: 标记该 cell 是否已收到缩略图。
    /// 缩略图返回后置 true，工作区图标回调若此时才返回则跳过覆盖（缩略图优先级更高）。
    /// 每次 viewFor 重新绑定文件时复位为 false。
    var didReceiveThumbnail: Bool = false

    /// 任务 F11-5: 名称列图标 leading 约束引用。
    /// 分组开启时文件行需缩进（仿访达），通过动态调整此约束的 constant 实现。
    /// 复用时每次 tableView(_:viewFor:row:) 重新设置 constant。
    var nameLeadingConstraint: NSLayoutConstraint?
}

// MARK: - FFTableRowView

/// 自定义 NSTableRowView：不覆盖任何绘制方法，完全使用 NSTableView 标准选中绘制。
///
/// 设计决策（A3 修复）：此前覆盖 drawSelection 硬编码亮蓝色 RGB(0.039, 0.518, 1.0)
/// 用于诊断选中不可见问题。诊断完成后应恢复标准行为：
/// - 窗口处于 key 状态时：选中行为强调色（systemBlue）+ 白色文字
/// - 窗口失焦时：选中为灰色（de-emphasized）+ 黑色文字
/// 这正是访达的标准行为，无需任何自定义。
private class FFTableRowView: NSTableRowView {
    // 空实现：仅作为扩展点保留（如将来添加 hover 效果）
}

/// 任务 F10-8 / F11-5: 分组标题行的 rowView。
/// 仿访达列表视图分组：浅灰背景、小字号标题 + 计数徽章，不参与选中绘制（标题行不可选）。
///
/// 任务 F11-5 重叠 bug 根因（v0.6.6 问题14）：
/// 此前标题文字在两处同时绘制——本类的 draw() 绘制 sectionTitle，
/// 而 makeSectionHeaderCell 又在 name 列 cell 中添加 NSTextField 显示 "key  (count)"。
/// 两层文字重叠（rowView 的 draw 与 cellView 的 textField 各画一遍），造成肉眼可见的重影。
/// 修复方案：单一绘制源——所有标题文字（分组名 + 计数）仅由本类 draw() 绘制，
/// makeSectionHeaderCell 返回完全透明的空 cell（仅占位保持列对齐，不显示任何文本）。
private final class FFSectionHeaderRowView: NSTableRowView {
    /// 分组名（用于绘制）
    var sectionTitle: String = ""
    /// 分组内文件数量（用于绘制计数徽章，如 "图片  12"）
    var sectionCount: Int = 0

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // 浅灰背景（次级填充色，仿访达 section header）
        if #available(macOS 14.0, *) {
            NSColor.tertiarySystemFill.setFill()
        } else {
            NSColor.controlBackgroundColor.withAlphaComponent(0.6).setFill()
        }
        dirtyRect.fill()

        // 标题文字：小字号、次级标签色，左对齐留 12pt 边距
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let title = sectionTitle as NSString
        let titleSize = title.size(withAttributes: attrs)

        // 标题绘制区域：垂直居中，左侧 12pt 边距
        let titleX: CGFloat = 12
        let titleY = (bounds.height - titleSize.height) / 2
        let titleRect = NSRect(x: titleX, y: titleY, width: bounds.width - 24, height: titleSize.height)
        title.draw(in: titleRect, withAttributes: attrs)

        // 计数徽章：标题右侧 6pt，使用更弱的次级标签色（仿访达分组数量样式）
        // 仅当数量 > 0 时绘制，避免单 "全部" 分组显示无意义的 0
        if sectionCount > 0 {
            let countText = "\(sectionCount)" as NSString
            let countAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let countSize = countText.size(withAttributes: countAttrs)
            let countX = titleX + titleSize.width + 6
            let countY = (bounds.height - countSize.height) / 2
            let countRect = NSRect(x: countX, y: countY, width: countSize.width, height: countSize.height)
            countText.draw(in: countRect, withAttributes: countAttrs)
        }

        // 底部细分隔线（增强分组层次，仿访达）
        if #available(macOS 14.0, *) {
            NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        } else {
            NSColor.gridColor.withAlphaComponent(0.5).setFill()
        }
        NSRect(x: 0, y: 0, width: bounds.width, height: 0.5).fill()
    }

    // 标题行不绘制选中高亮
    override func drawSelection(in dirtyRect: NSRect) {
        // 空实现：标题行不可选，不绘制选中
    }
}

// MARK: - FFStickySectionHeaderView

/// 任务 F11-5: 粘性分组标题浮层。
///
/// 访达行为：列表滚动时，当前可见分组的标题固定在列表顶部，直到下一分组标题顶上来再切换。
/// NSTableView 无原生粘性 section header 支持，本类作为 scrollView.contentView 之上的
/// 浮层视图实现该效果：由 FileListView 监听 clipView 滚动，计算当前应固定的分组并刷新本视图。
///
/// 视觉与 FFSectionHeaderRowView 完全一致（浅灰背景 + 标题 + 计数徽章 + 底部分隔线），
/// 保证粘性标题与行内标题无缝衔接。分组关闭（groupBy == "none"）时本视图隐藏。
private final class FFStickySectionHeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.backgroundColor = .clear
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        countLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = NSColor.tertiaryLabelColor
        countLabel.backgroundColor = .clear
        countLabel.isBezeled = false
        countLabel.drawsBackground = false
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 配置粘性标题内容（标题 + 计数），空标题时隐藏整个视图
    func configure(title: String, count: Int) {
        if title.isEmpty {
            isHidden = true
            return
        }
        isHidden = false
        titleLabel.stringValue = title
        countLabel.stringValue = count > 0 ? "\(count)" : ""
    }

    override func draw(_ dirtyRect: NSRect) {
        // 浅灰背景（与 FFSectionHeaderRowView 一致）
        if #available(macOS 14.0, *) {
            NSColor.tertiarySystemFill.setFill()
        } else {
            NSColor.controlBackgroundColor.withAlphaComponent(0.6).setFill()
        }
        dirtyRect.fill()
        // 底部分隔线
        if #available(macOS 14.0, *) {
            NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        } else {
            NSColor.gridColor.withAlphaComponent(0.5).setFill()
        }
        NSRect(x: 0, y: 0, width: bounds.width, height: 0.5).fill()
    }
}

// MARK: - FileListView

/// 任务 F10-8: 分组渲染用的单行映射条目。
/// - isHeader == true 时该行为分组标题，key 为分组名（如"图片"），fileIndex 为 nil
/// - isHeader == false 时该行为文件行，fileIndex 为该文件在 viewModel.files 中的下标
private struct FFDisplayRow {
    let isHeader: Bool
    let key: String
    let fileIndex: Int
    /// v0.6.9: 预计算该文件是否有标签，避免 heightOfRow 高频调用 TagBridge I/O
    var hasTags: Bool = false
}

/// NSTableView-based file list view with 4 columns (名称/修改日期/类型/大小)
/// 标签以药丸形式内联显示在名称列的文件名之后
public class FileListView: NSView {
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var cancellables = Set<AnyCancellable>()
    private var lastFilesCount: Int = -1

    // 任务 F11-5: 粘性分组标题浮层（仿访达，滚动时固定当前分组标题于列表顶部）
    private var stickyHeader: FFStickySectionHeaderView?
    // 任务 F11-5: 滚动监听观察者（clipView.boundsDidChange 通知）
    private var clipViewObserver: NSObjectProtocol?

    // 任务 F10-8: 显示行映射缓存。
    // 将"分组渲染"的显示行号映射为 (是否分组标题行, 文件在 viewModel.files 中的下标)。
    // groupBy == "none" 时仅含文件行（fileIndex 与行号一一对应），保持原有行为。
    // 每次 reloadData / state.files 变更时重建。
    private var displayRows: [FFDisplayRow] = []

    // Bug 9 修复：reload 期间标志位，防止 selectionDidChange -> state 变更 -> reload 形成循环
    private var isReloading: Bool = false

    // 内联重命名状态
    private var renamingRow: Int = -1
    private var renamingOriginalName: String = ""
    private var renamingPath: String = ""
    private weak var renamingTextField: NSTextField?
    private var renameCancelled: Bool = false

    public var viewModel: PaneViewModel? {
        didSet {
            // 清空旧订阅，防止累积泄漏
            cancellables.removeAll()
            tableView.dataSource = self
            tableView.delegate = self
            // 任务 F10-7: 初始同步排序描述符，使列头箭头显示在当前排序列上
            applySortDescriptorsFromViewModel()
            // 任务 F10-8: 初始构建 displayRows（分组渲染映射）
            rebuildDisplayRows()
            viewModel?.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self else { return }
                    // 任务 F10-7: 排序字段/方向变化时同步列头排序描述符与箭头
                    self.applySortDescriptorsFromViewModel()
                    // 任务 F10-8: files 数量变化 或 分组维度变化 或 排序变化（顺序变化）时刷新
                    // - lastFilesCount 检测数量变化（导航/删除/新增）
                    // - 分组维度变化需刷新（displayRows 结构改变）
                    // - 排序变化虽数量不变但顺序变了，需刷新（applySort 仅在顺序变化时改 state.files，
                    //   但我们无法直接对比顺序，故 sortField/sortAscending 变化也触发刷新）
                    let needReload = self.lastFilesCount != state.files.count
                        || self.currentGroupBy != state.groupBy
                        || self.currentSortField != state.sortField
                        || self.currentSortAscending != state.sortAscending
                    if needReload {
                        // 大目录优化：检测是否为纯追加（分页追加批次），仅当无分组、
                        // 排序/分组维度未变、文件数增加时，使用增量 insertRows 避免全量重建
                        let delta = state.files.count - self.lastFilesCount
                        let isAppendOnly = delta > 0
                            && self.currentGroupBy == state.groupBy
                            && self.currentSortField == state.sortField
                            && self.currentSortAscending == state.sortAscending
                            && state.groupBy == "none"

                        self.lastFilesCount = state.files.count
                        self.currentGroupBy = state.groupBy
                        self.currentSortField = state.sortField
                        self.currentSortAscending = state.sortAscending

                        if isAppendOnly {
                            self.appendDisplayRows(newCount: delta)
                        } else {
                            self.reloadData()
                        }
                    }
                }
                .store(in: &cancellables)
            reloadData()
        }
    }

    // 任务 F10-8: 上次刷新时记录的分组/排序状态，用于检测变化决定是否刷新
    private var currentGroupBy: String = "none"
    private var currentSortField: SortField = .name
    private var currentSortAscending: Bool = true

    /// 任务 F10-8: 根据 viewModel.groupedFiles 重建 displayRows 映射。
    /// groupBy == "none" 时返回纯文件行（与原有行为一致，fileIndex 与行号一一对应）。
    /// 大目录优化：使用字典预构建 path→index 映射，将 O(n²) 线性搜索降为 O(n)。
    private func rebuildDisplayRows() {
        guard let viewModel = viewModel else {
            displayRows = []
            return
        }
        var rows: [FFDisplayRow] = []
        let groups = viewModel.groupedFiles

        // 预构建 path → index 字典，避免循环内 firstIndex(where:) 的 O(n²) 搜索
        var pathToIndex: [String: Int] = [:]
        pathToIndex.reserveCapacity(viewModel.state.files.count)
        for (i, entry) in viewModel.state.files.enumerated() {
            pathToIndex[entry.path] = i
        }

        for group in groups {
            // 分组标题行（仅当不止一个分组时才显示标题；"全部" 单分组且 groupBy==none 时不显示）
            let showHeader = !(groups.count == 1 && viewModel.state.groupBy == "none")
            if showHeader {
                rows.append(FFDisplayRow(isHeader: true, key: group.key, fileIndex: -1))
            }
            // 组内文件行（fileIndex 指向 viewModel.files 中的下标）
            for entry in group.entries {
                if let idx = pathToIndex[entry.path] {
                    // v0.6.9: 预计算标签状态，避免 heightOfRow 高频 I/O
                    // TagBridge 已有内存缓存，重复调用为 O(1)
                    let hasTags = !TagBridge.shared.getTags(path: entry.path).isEmpty
                    rows.append(FFDisplayRow(isHeader: false, key: group.key, fileIndex: idx, hasTags: hasTags))
                }
            }
        }
        displayRows = rows
    }

    /// 大目录优化：分页追加时的增量行构建，避免全量 rebuildDisplayRows + reloadData。
    /// 仅适用于 groupBy == "none"（无分组），新文件追加到 state.files 末尾的场景。
    /// - Parameter newCount: 新增的文件数量
    private func appendDisplayRows(newCount: Int) {
        guard let viewModel = viewModel, newCount > 0 else { return }
        let startIndex = viewModel.state.files.count - newCount
        guard startIndex >= 0 else { return }

        var newRows: [FFDisplayRow] = []
        newRows.reserveCapacity(newCount)
        for i in startIndex..<viewModel.state.files.count {
            let entry = viewModel.state.files[i]
            let hasTags = !TagBridge.shared.getTags(path: entry.path).isEmpty
            newRows.append(FFDisplayRow(isHeader: false, key: "全部", fileIndex: i, hasTags: hasTags))
        }

        let insertStart = displayRows.count
        displayRows.append(contentsOf: newRows)

        // 增量插入行，而非全量 reloadData
        isReloading = true
        let indexSet = IndexSet(integersIn: insertStart..<(insertStart + newRows.count))
        tableView.insertRows(at: indexSet, withAnimation: [])
        restoreSelectionFromViewModel()
        updateStickyHeader()
        DispatchQueue.main.async { [weak self] in
            self?.isReloading = false
            self?.updateStickyHeader()
        }
    }

    /// 任务 F10-7: 将 viewModel 的排序状态同步到 tableView.sortDescriptors
    ///
    /// NSTableView 依据 sortDescriptors 在对应列头绘制排序箭头（通过 indicatorImage）。
    /// 当外部（PaneToolbar 排序下拉框）或内部变更排序时，需同步 sortDescriptors，
    /// 否则列头箭头不会更新。本方法用 viewModel 的 sortField/sortAscending 构造描述符，
    /// 并匹配到对应列的 sortDescriptorPrototype 的 key。
    /// 注意：避免无限循环——仅当描述符确实不同时才 set，且 set 会触发
    /// tableView(_:sortDescriptorsDidChange:)，但该回调会调用 viewModel.setSortField，
    /// 此时 viewModel 状态与本方法构造的一致，applySort 不会触发 @Published 重新发射，
    /// 故不形成循环。
    private func applySortDescriptorsFromViewModel() {
        guard let vm = viewModel else { return }
        // 任务 F10-7: 使用与列 sortDescriptorPrototype 一致的 key
        // （列 prototype key：name/modifiedAt/type/size，与列 identifier 相同）
        // 注意：不能用 SortField.key（.type 返回 "extension"），否则与列 prototype 不匹配，
        // NSTableView 无法识别排序列，箭头不会显示。
        let key: String
        switch vm.state.sortField {
        case .name: key = "name"
        case .modifiedAt: key = "modifiedAt"
        case .type: key = "type"
        case .size: key = "size"
        }
        let ascending = vm.state.sortAscending
        let current = tableView.sortDescriptors
        // 仅在变化时更新，避免重复 set 触发不必要的回调
        if current.first?.key != key || current.first?.ascending != ascending {
            tableView.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        }
    }

    /// 对侧面板的 ViewModel（由 MainWindowController 在 setupUI 中注入），
    /// 用于拖拽 undo/redo 后刷新对侧面板（跨面板拖拽时源面板需同步更新）
    weak var counterpartViewModel: PaneViewModel?

    public var onDoubleClick: ((FileEntry) -> Void)?
    public var onSelectionChanged: (([FileEntry]) -> Void)?
    public var onActivatePane: (() -> Void)?

    // Reuse identifiers
    private let nameCellID = NSUserInterfaceItemIdentifier("NameCell")
    private let modifiedCellID = NSUserInterfaceItemIdentifier("ModifiedCell")
    private let typeCellID = NSUserInterfaceItemIdentifier("TypeCell")
    private let sizeCellID = NSUserInterfaceItemIdentifier("SizeCell")
    // 任务 F10-8: 分组标题行复用标识符
    private let sectionHeaderCellID = NSUserInterfaceItemIdentifier("SectionHeaderCell")

    /// 面板方向（由 MainWindowController 注入），用于右键菜单"移动/复制到另一面板"的箭头方向
    /// 注：PaneSide 为 internal 类型，故此属性为 internal（同模块内可访问）
    var panelSide: PaneSide?

    /// 当前面板方向（优先使用 panelSide，否则根据 identifier 推断）
    private var effectiveSide: PaneSide {
        if let panelSide = panelSide { return panelSide }
        return identifier?.rawValue == "right" ? .right : .left
    }

    /// 标签二级菜单（动态构建：每次显示前由 NSMenuDelegate 重建内容）
    private lazy var tagsSubmenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }()

    // Icons
    private lazy var folderIcon: NSImage? = {
        NSImage(systemSymbolName: "folder", accessibilityDescription: "文件夹")
            ?? NSImage(named: NSImage.folderName)
    }()
    private lazy var fileIcon: NSImage? = {
        NSImage(systemSymbolName: "doc", accessibilityDescription: "文件")
            ?? NSImage(named: NSImage.multipleDocumentsName)
    }()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        FFDebug.log("FileListView.init frame=\(frameRect)")
        setupUI()
        setupContextMenu()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupContextMenu()
    }

    deinit {
        // 任务 F11-5: 移除 clipView 滚动观察者，防止悬空通知回调
        if let observer = clipViewObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        // 任务 F11-1: 操作区实体背景（v0.6.7）
        // 此前为透明背景透出 NSVisualEffectView 玻璃态；现改为实体（日间#F5F5F5/夜间#2D2D2D），
        // 与 MainWindowController.createPaneContainer 的容器实体背景一致，
        // 实体背景上选中蓝色清晰可见（解决 v0.6.6 问题14 的最终方案）
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        // 任务 S1: 强制使用自定义细滚动条
        scrollView.verticalScroller = FFScroller()
        scrollView.horizontalScroller = FFScroller()
        scrollView.scrollerStyle = .overlay

        // 任务 T5: QuickLook 空格键修复。
        // first responder 是 NSTableView 时，空格事件被 tableView 的 keyDown/interpretKeyEvents 消耗，
        // 不会冒泡到 FileListView.keyDown → 改用 FFQuickLookTableView 子类在 keyDown 拦截空格并转发通知。
        // 注意：side 不能在此刻用 getSide() 固定——identifier 由 MainWindowController 在 init 之后才设置，
        // 故在 onSpaceKey 回调中动态取 self.getSide()。
        let qlTableView = FFQuickLookTableView()
        qlTableView.onSpaceKey = { [weak self] _ in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .fileListRequestQuickLook, object: nil, userInfo: ["side": self.getSide()])
        }
        tableView = qlTableView
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        // 任务 F10-7: 启用列拖动重排（访达风格，用户可拖动列头调整列顺序）
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        // 使用 NSTableView 标准选中绘制（.regular 默认值）。
        // 根因（systematic-debugging）：
        //   此前设置 selectionHighlightStyle = .none 禁用了标准绘制，转而用
        //   updateSelectionHighlight 手动设置 layer.backgroundColor。但手动方案在
        //   cellView 复用、layer 时序竞态、wantsLayer=true 等情况下失效。
        //   恢复标准绘制后，NSTableRowView.drawSelection 自动根据 isSelected 状态
        //   绘制选中色（key window + firstResponder 时为强调蓝色）。
        //   cellView.layer.backgroundColor 已在 tableView(_:viewFor:row:) 中设为 .clear，
        //   不会遮挡 rowView 的标准选中绘制。
        // 不显式赋值，使用 NSTableView 默认 selectionHighlightStyle = .regular
        // 列宽模式：sequentialColumnAutoresizingStyle（四列按比例伸缩，无横向滚动条）。
        // 用户仍可手动拖拽列头分隔条调整各列宽度。
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.rowHeight = 26
        // 任务 F11-1: tableView 实体背景（v0.6.7）
        // 配合操作区容器实体背景，不再透明。实体背景上选中蓝色清晰可见（解决 v0.6.6 问题14 的最终方案）
        // 保留 selectionHighlightStyle = .regular（标准选中绘制，默认值，不显式赋值）
        let isDark = ThemeManager.shared.resolvedIsDark
        tableView.backgroundColor = isDark
            ? NSColor(srgbRed: 0.176, green: 0.176, blue: 0.176, alpha: 1.0)  // #2D2D2D
            : NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 1.0)  // #F5F5F5
        tableView.enclosingScrollView?.drawsBackground = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = NSColor.clear
        // NSClipView 默认绘制 controlBackgroundColor（浅灰），必须显式清除
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self

        // 四列按比例伸缩：任何窗口宽度下列宽总和 = 操作区可用宽，永不出现横向滚动条。
        // 名称列初始占比最大（240/540 ≈ 44%），窗口变化时获得最多增量，视觉上名称列弹性最大（仿访达）。
        tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle

        // 列顺序：名称 → 修改日期 → 类型 → 大小（匹配 macOS Finder）
        // 名称列（带图标）— 用户可手动拖宽
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "名称"
        nameCol.headerCell = FFPillHeaderCell()
        nameCol.headerCell.stringValue = "名称"
        nameCol.width = 240
        nameCol.minWidth = 80
        nameCol.maxWidth = 2000
        nameCol.resizingMask = [.userResizingMask, .autoresizingMask]
        nameCol.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        tableView.addTableColumn(nameCol)

        // 修改日期列（设计稿 130px）
        let modifiedCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("modifiedAt"))
        modifiedCol.title = "修改日期"
        modifiedCol.headerCell = FFPillHeaderCell()
        modifiedCol.headerCell.stringValue = "修改日期"
        modifiedCol.width = 130
        modifiedCol.minWidth = 80
        modifiedCol.resizingMask = [.userResizingMask, .autoresizingMask]
        modifiedCol.sortDescriptorPrototype = NSSortDescriptor(key: "modifiedAt", ascending: true)
        tableView.addTableColumn(modifiedCol)

        // 类型列（设计稿 100px）
        let typeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeCol.title = "类型"
        typeCol.headerCell = FFPillHeaderCell()
        typeCol.headerCell.stringValue = "类型"
        typeCol.width = 100
        typeCol.minWidth = 50
        typeCol.resizingMask = [.userResizingMask, .autoresizingMask]
        typeCol.sortDescriptorPrototype = NSSortDescriptor(key: "type", ascending: true)
        tableView.addTableColumn(typeCol)

        // 大小列（设计稿 70px，右对齐）
        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeCol.title = "大小"
        sizeCol.headerCell = FFPillHeaderCell()
        sizeCol.headerCell.stringValue = "大小"
        sizeCol.width = 70
        sizeCol.minWidth = 40
        sizeCol.resizingMask = [.userResizingMask, .autoresizingMask]
        sizeCol.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: true)
        tableView.addTableColumn(sizeCol)

        // C12: 标签列已移除，改为在名称列内联显示标签药丸

        // Double-click
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)

        scrollView.documentView = tableView
        addSubview(scrollView)

        // 使用 Auto Layout 约束确保 scrollView 正确填充
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // 注意：不调用 sizeToFit()，避免它压缩列宽导致第 5 列不可见。
        // columnAutoresizingStyle = .none 时，各列保持 width 设定的固定宽度，
        // 用户可通过列分隔条手动拖宽（userResizingMask 已启用）。

        // 任务 F11-5: 粘性分组标题浮层。
        // 添加为 clipView 的子视图并置于最前（覆盖在 tableView 行之上），
        // 通过监听 clipView.boundsDidChange 滚动通知动态更新位置与内容。
        let sticky = FFStickySectionHeaderView()
        sticky.translatesAutoresizingMaskIntoConstraints = false
        sticky.isHidden = true
        scrollView.contentView.addSubview(sticky)
        NSLayoutConstraint.activate([
            sticky.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            sticky.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            sticky.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            sticky.heightAnchor.constraint(equalToConstant: 24),
        ])
        self.stickyHeader = sticky

        // 任务 F11-5: 监听 clipView 滚动，刷新粘性标题
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        clipViewObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            self?.updateStickyHeader()
        }

        // 注册 tableView 为拖拽目标（NSTableViewDataSource 的 validateDrop/acceptDrop
        // 方法要求 tableView 自身注册拖拽类型，在父 NSView 上注册不会触发回调）
        tableView.registerForDraggedTypes([.fileURL])

        // 启用拖拽源（通过 tableView）
        tableView.setDraggingSourceOperationMask([.copy, .move, .delete], forLocal: false)
    }

    // MARK: - Context Menu (in-app dialog, no NSOpenPanel/NSSavePanel)

    private func setupContextMenu() {
        let menu = NSMenu()
        // 启用动态菜单：右键菜单显示前由 menuNeedsUpdate 更新图标/可见性/标签二级子菜单
        menu.delegate = self

        // 1. 打开（图标由 menuNeedsUpdate 根据选中项是文件夹还是文件动态设置：folder / doc）
        menu.addItem(withTitle: "打开", action: #selector(openSelected(_:)), keyEquivalent: "")
        // 2. 分隔线
        menu.addItem(.separator())
        // 3. 复制 — doc.on.doc
        let copyItem = menu.addItem(withTitle: "复制", action: #selector(copySelected(_:)), keyEquivalent: "c")
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制")
        // 4. 剪切 — scissors
        let cutItem = menu.addItem(withTitle: "剪切", action: #selector(cutSelected(_:)), keyEquivalent: "x")
        cutItem.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "剪切")
        // 5. 粘贴 — doc.on.clipboard
        let pasteItem = menu.addItem(withTitle: "粘贴", action: #selector(pasteSelected(_:)), keyEquivalent: "v")
        pasteItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "粘贴")
        // 6. 分隔线
        menu.addItem(.separator())
        // 7. 移动到另一面板（图标根据当前面板方向：左面板→arrow.right，右面板→arrow.left）
        let moveItem = menu.addItem(withTitle: "移动到另一面板", action: #selector(moveToOtherPane(_:)), keyEquivalent: "")
        moveItem.image = NSImage(systemSymbolName: effectiveSide == .left ? "arrow.right" : "arrow.left",
                                 accessibilityDescription: "移动到另一面板")
        // 8. 复制到另一面板（图标根据当前面板方向：左面板→arrow.right.square，右面板→arrow.left.square）
        let copyOtherItem = menu.addItem(withTitle: "复制到另一面板", action: #selector(copyToOtherPane(_:)), keyEquivalent: "")
        copyOtherItem.image = NSImage(systemSymbolName: effectiveSide == .left ? "arrow.right.square" : "arrow.left.square",
                                      accessibilityDescription: "复制到另一面板")
        // 任务 F10-10: 新增"在对侧面板打开"菜单项（仅文件夹显示）（修复问题13）
        // 点击后导航对侧面板到该文件夹（仿访达"在新窗口打开"的跨面板版本）
        // 可见性由 menuNeedsUpdate 控制：仅当右键点击项为文件夹时显示
        let openOtherItem = menu.addItem(withTitle: "在对侧面板打开", action: #selector(openInOtherPane(_:)), keyEquivalent: "")
        openOtherItem.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "在对侧面板打开")
        // 初始隐藏，由 menuNeedsUpdate 根据右键点击项是否为文件夹动态显示
        openOtherItem.isHidden = true
        // 9. 分隔线
        menu.addItem(.separator())
        // 10. 重命名 — pencil
        let renameItem = menu.addItem(withTitle: "重命名", action: #selector(renameSelected(_:)), keyEquivalent: "")
        renameItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "重命名")
        // 11. 移到废纸篓 — trash（红色文字）
        let trashItem = menu.addItem(withTitle: "移到废纸篓", action: #selector(deleteSelected(_:)), keyEquivalent: "\u{7F}")
        trashItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "移到废纸篓")
        let redAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
        trashItem.attributedTitle = NSAttributedString(string: "移到废纸篓", attributes: redAttrs)
        // 12. 分隔线
        menu.addItem(.separator())
        // 13. 新建文件夹 — folder.badge.plus
        let newFolderItem = menu.addItem(withTitle: "新建文件夹", action: #selector(createDirectory(_:)), keyEquivalent: "n")
        newFolderItem.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "新建文件夹")
        // 14. 分隔线
        menu.addItem(.separator())
        // 15. 添加到我的收藏 — star
        let favItem = menu.addItem(withTitle: "添加到我的收藏", action: #selector(addToFavorites(_:)), keyEquivalent: "")
        favItem.image = NSImage(systemSymbolName: "star", accessibilityDescription: "添加到我的收藏")
        // 16. 标签（二级菜单） — tag
        //     仅当选中单个文件时显示（多选时由 menuNeedsUpdate 隐藏）
        let tagsItem = menu.addItem(withTitle: "标签", action: nil, keyEquivalent: "")
        tagsItem.image = NSImage(systemSymbolName: "tag", accessibilityDescription: "标签")
        tagsItem.submenu = tagsSubmenu
        // 17. AI 自动打标签 — sparkles
        let aiTagItem = menu.addItem(withTitle: "AI 自动打标签", action: #selector(generateAITags(_:)), keyEquivalent: "")
        aiTagItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI 自动打标签")
        // 18. 查重扫描 — rectangle.dashed
        let dupItem = menu.addItem(withTitle: "查重扫描", action: #selector(duplicateScan(_:)), keyEquivalent: "")
        dupItem.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "查重扫描")
        // 19. 分隔线
        menu.addItem(.separator())
        // 20. 显示简介 — info.circle
        let infoItem = menu.addItem(withTitle: "显示简介", action: #selector(showInfoMenu(_:)), keyEquivalent: "i")
        infoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "显示简介")

        for item in menu.items where item.action != nil {
            item.target = self
            if item.keyEquivalent == "n" {
                item.keyEquivalentModifierMask = [.command, .shift]
            } else if !item.keyEquivalent.isEmpty {
                item.keyEquivalentModifierMask = .command
            }
        }
        tableView.menu = menu
    }

    // MARK: - Context Menu Actions

    @objc private func openSelected(_ sender: Any?) {
        guard let entry = clickedEntry else { return }
        if entry.isDirectory {
            onDoubleClick?(entry)
        } else {
            NSWorkspace.shared.openFile(entry.path)
        }
    }

    @objc private func copySelected(_ sender: Any?) {
        // 剪贴板操作将由 MainWindowController 统一管理
        NotificationCenter.default.post(name: .fileListDidCopy, object: nil, userInfo: ["side": getSide()])
    }

    @objc private func cutSelected(_ sender: Any?) {
        NotificationCenter.default.post(name: .fileListDidCut, object: nil, userInfo: ["side": getSide()])
    }

    @objc private func pasteSelected(_ sender: Any?) {
        NotificationCenter.default.post(name: .fileListDidPaste, object: nil, userInfo: ["side": getSide()])
    }

    @objc private func renameSelected(_ sender: Any?) {
        guard let entry = clickedEntry else { return }
        let alert = NSAlert()
        alert.messageText = "重命名 \"\(entry.name)\""
        alert.informativeText = "输入新名称："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "重命名")
        alert.addButton(withTitle: "取消")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = entry.name
        alert.accessoryView = textField
        alert.beginSheetModal(for: window!) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty, newName != entry.name else { return }
            self?.viewModel?.renameFile(entry.path, to: newName)
        }
    }

    @objc private func deleteSelected(_ sender: Any?) {
        let entries = viewModel?.selectedFiles ?? []
        guard !entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = entries.count == 1 ? "删除\"\(entries[0].name)\"？" : "删除 \(entries.count) 个项目？"
        alert.informativeText = "此操作可通过 ⌘Z 撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window!) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.viewModel?.deleteSelected()
        }
    }

    @objc private func createDirectory(_ sender: Any?) {
        guard let currentPath = viewModel?.currentPath else { return }
        let alert = NSAlert()
        alert.messageText = "新建文件夹"
        alert.informativeText = "输入文件夹名称："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = "未命名文件夹"
        textField.selectText(nil)
        alert.accessoryView = textField
        alert.beginSheetModal(for: window!) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let folderName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !folderName.isEmpty else { return }
            let newPath = (currentPath as NSString).appendingPathComponent(folderName)
            do {
                try CoreBridge.shared.createDirectory(path: newPath)
                self?.viewModel?.refresh()
            } catch {
                self?.showError(error: error)
            }
        }
    }

    @objc private func addToFavorites(_ sender: Any?) {
        guard let entry = clickedEntry else { return }
        NotificationCenter.default.post(name: .fileListDidAddFavorite, object: nil, userInfo: ["name": entry.name, "path": entry.path])
    }

    @objc private func addTagMenu(_ sender: Any?) {
        guard let entry = clickedEntry else { return }
        NotificationCenter.default.post(name: .fileListAddTag, object: nil, userInfo: ["path": entry.path])
    }

    @objc private func showInfoMenu(_ sender: Any?) {
        // F9-C: 弹出独立 FileInfoWindow（仿访达 Get Info）。
        // 优先取右键点击的文件，回退到当前选中项的第一项（访达行为：显示第一个文件信息）。
        let targetPath = clickedEntry?.path ?? viewModel?.selectedFiles.first?.path
        // 任务 F10-10: 入口日志（修复问题15/16 诊断）+ path 空回退提示
        FFLog.debug("[F10-10] showInfoMenu clicked, clickedEntry=\(clickedEntry?.path ?? "nil"), fallback selectedFirst=\(viewModel?.selectedFiles.first?.path ?? "nil"), final=\(targetPath ?? "nil")", log: FFLog.ui)
        // 若无目标路径（既无右键点击项也无选中项），给出提示而非静默无响应
        if targetPath == nil || (targetPath?.isEmpty ?? true) {
            let alert = NSAlert()
            alert.messageText = "显示简介"
            alert.informativeText = "请先选择一个文件后再查看简介。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            if let window = window { alert.beginSheetModal(for: window) { _ in } }
            return
        }
        NotificationCenter.default.post(name: .fileListShowInfo, object: nil, userInfo: ["path": targetPath ?? ""])
    }

    /// C13: 查重扫描 — 打开查重扫描窗口
    @objc private func duplicateScan(_ sender: Any?) {
        DuplicateScanWindowController.shared.showWindow()
    }

    @objc private func generateAITags(_ sender: Any?) {
        // 任务 F11-11: 复用公共入口（供侧边栏工具面板 AI 工具入口调用，C1）
        triggerAITagGeneration()
    }

    /// 任务 F11-11: AI 自动打标签公共入口（C1）。
    /// 供 MainWindowController 在收到侧边栏工具面板 AI 工具点击通知后调用。
    /// 优先使用当前选中文件列表，无选中时回退到右键点击的文件；两者皆无则不执行。
    public func triggerAITagGeneration() {
        // 优先使用选中的文件列表，无选中时回退到右键点击的文件
        var entries = viewModel?.selectedFiles ?? []
        if entries.isEmpty {
            if let entry = clickedEntry {
                entries = [entry]
            } else {
                return
            }
        }

        let paths = entries.map { $0.path }
        let totalCount = paths.count

        // 后台线程批量生成标签并写入 xattr
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var successCount = 0
            var totalTagsAdded = 0
            var xattrFailCount = 0
            var firstError: String?

            for path in paths {
                do {
                    let generatedTags = try CoreBridge.shared.generateAITags(path: path)
                    for genTag in generatedTags {
                        let tag = Tag(name: genTag.name, color: genTag.color)
                        if TagBridge.shared.addTag(tag, path: path) {
                            totalTagsAdded += 1
                        } else {
                            xattrFailCount += 1
                        }
                    }
                    successCount += 1
                } catch {
                    if firstError == nil {
                        firstError = error.localizedDescription
                    }
                }
            }

            DispatchQueue.main.async {
                guard let self = self, let window = self.window else { return }

                if successCount == 0 {
                    // 全部失败
                    let alert = NSAlert()
                    alert.messageText = "AI 标签生成失败"
                    alert.informativeText = firstError ?? "未知错误"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "关闭")
                    alert.beginSheetModal(for: window)
                    return
                }

                // 部分或全部成功
                let alert = NSAlert()
                if successCount == totalCount {
                    alert.messageText = "已为 \(successCount) 个文件生成 AI 标签"
                    if totalTagsAdded > 0 {
                        var info = "共添加 \(totalTagsAdded) 个标签。"
                        if xattrFailCount > 0 {
                            info += "\n\(xattrFailCount) 个标签写入失败（权限不足或不支持扩展属性）。"
                        }
                        alert.informativeText = info
                    } else if xattrFailCount > 0 {
                        alert.informativeText = "标签写入失败（权限不足或不支持扩展属性）。"
                    } else {
                        alert.informativeText = "未识别到可分类的文件类型。"
                    }
                } else {
                    alert.messageText = "部分文件标签生成失败"
                    alert.informativeText = "成功 \(successCount) / 总计 \(totalCount)。\n\(firstError ?? "")"
                }
                alert.alertStyle = totalTagsAdded > 0 ? .informational : .warning
                alert.addButton(withTitle: "关闭")
                alert.beginSheetModal(for: window)

                // 刷新列表以更新标签显示
                self.reloadData()
            }
        }
    }

    // MARK: - Cross-Pane Actions

    @objc private func copyToOtherPane(_ sender: Any?) {
        // 任务 F10-10: 入口日志（修复问题15/16 诊断）
        FFLog.debug("[F10-10] copyToOtherPane clicked, side=\(getSide()), clickedEntry=\(clickedEntry?.path ?? "nil"), selectedCount=\(viewModel?.selectedFiles.count ?? 0)", log: FFLog.ui)
        // 问题12修复：传递右键点击文件路径，供空选兜底使用
        NotificationCenter.default.post(name: .fileListDidCopyToOther, object: nil, userInfo: ["side": getSide(), "clickedPath": clickedEntry?.path])
    }

    @objc private func moveToOtherPane(_ sender: Any?) {
        // 任务 F10-10: 入口日志（修复问题15/16 诊断）
        FFLog.debug("[F10-10] moveToOtherPane clicked, side=\(getSide()), clickedEntry=\(clickedEntry?.path ?? "nil"), selectedCount=\(viewModel?.selectedFiles.count ?? 0)", log: FFLog.ui)
        // 问题12修复：传递右键点击文件路径，供空选兜底使用
        NotificationCenter.default.post(name: .fileListDidMoveToOther, object: nil, userInfo: ["side": getSide(), "clickedPath": clickedEntry?.path])
    }

    @objc private func openInOtherPane(_ sender: Any?) {
        guard let entry = clickedEntry else { return }
        NotificationCenter.default.post(name: .fileListDidOpenInOther, object: nil, userInfo: ["side": getSide(), "path": entry.path])
    }

    // MARK: - Drag Source

    /// 开始拖拽（在 tableView 的 mouseDown 中触发）
    @objc private func handleTableDrag() {
        // 任务 F10-8: 通过 displayRows 映射 selectedRow -> viewModel.files 下标
        guard let viewModel = viewModel,
              let selectedRow = tableView.selectedRow as Int?,
              selectedRow >= 0, selectedRow < displayRows.count else { return }
        let displayRow = displayRows[selectedRow]
        guard !displayRow.isHeader, displayRow.fileIndex < viewModel.files.count else { return }

        let entry = viewModel.files[displayRow.fileIndex]
        let url = URL(fileURLWithPath: entry.path)

        let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        draggingItem.setDraggingFrame(tableView.rect(ofRow: selectedRow), contents: nil)

        beginDraggingSession(with: [draggingItem], event: NSApp.currentEvent!, source: self)
    }

    // MARK: - Helpers

    private var clickedEntry: FileEntry? {
        // 任务 F10-8: 通过 displayRows 映射 clickedRow -> viewModel.files 下标
        guard let viewModel = viewModel,
              let row = tableView.clickedRow as Int?,
              row >= 0, row < displayRows.count else { return nil }
        let displayRow = displayRows[row]
        guard !displayRow.isHeader, displayRow.fileIndex < viewModel.files.count else { return nil }
        return viewModel.files[displayRow.fileIndex]
    }

    private func getSide() -> String {
        // 由 MainWindowController 在设置 viewModel 时通过 identifier 标记
        return identifier?.rawValue ?? "left"
    }

    private func showError(error: Error) {
        let alert = NSAlert()
        alert.messageText = "错误"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "好")
        if let window = window { alert.beginSheetModal(for: window) { _ in } }
    }

    // MARK: - C12: Inline Tag Pills（名称列双行标签药丸）

    /// 名称列 cell 双行标签药丸配置：
    /// - 名称列 cell 结构（双行）：
    ///   上行：[文件图标] [文件名]
    ///   下行：[标签药丸容器]（横向排列，最多 3 个药丸 + "+N"）
    /// - 无标签时药丸容器隐藏，行高保持单行高度（26pt）
    /// - 有标签时药丸容器显示在文件名下方，行高增加（48pt）
    /// - 药丸不响应左键点击（仅显示），右键可弹出移除标签菜单
    private func configureInlineTagPills(in cellView: NSTableCellView, entry: FileEntry) {
        guard let textField = cellView.textField else { return }
        // v0.6.9: 根据 showFileTags 设置决定是否显示标签药丸
        let showTags = UserDefaults.standard.object(forKey: FFUserDefaultsKeys.showFileTags) as? Bool ?? true
        let containerID = "inlineTagPillContainer"
        // 复用已存在的容器（cell 复用时避免重复创建）
        var pillContainer: NSStackView? = nil
        for sv in cellView.subviews {
            if let stack = sv as? NSStackView, stack.identifier?.rawValue == containerID {
                pillContainer = stack
                break
            }
        }
        // v0.6.9: 若关闭标签显示，隐藏药丸容器并返回
        if !showTags {
            pillContainer?.isHidden = true
            return
        }
        if pillContainer == nil {
            // 双行布局：药丸容器位于文件名下方（而非右侧）
            let stack = NSStackView()
            stack.identifier = NSUserInterfaceItemIdentifier(containerID)
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.setHuggingPriority(.defaultLow, for: .horizontal)
            stack.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
            cellView.addSubview(stack)
            NSLayoutConstraint.activate([
                // 药丸与文件名左对齐（紧跟图标之后）
                stack.leadingAnchor.constraint(equalTo: textField.leadingAnchor),
                // 允许药丸溢出到后续列
                stack.trailingAnchor.constraint(lessThanOrEqualTo: cellView.trailingAnchor, constant: -4),
                // 药丸位于文件名下方 4pt
                stack.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 4),
            ])
            pillContainer = stack
        }

        // 清除旧药丸
        pillContainer?.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // 获取文件标签并填充药丸
        let tags = TagBridge.shared.getTags(path: entry.path)
        if tags.isEmpty {
            pillContainer?.isHidden = true
        } else {
            pillContainer?.isHidden = false
            // 最多显示 3 个药丸，超出显示 "+N"
            for tag in tags.prefix(3) {
                if let pill = makeTagPill(tag: tag) {
                    // 每个药丸独立右键菜单：右键任意位置 → "移除标签"（仅移除该文件的此标签）
                    let menu = NSMenu()
                    menu.autoenablesItems = false
                    let item = NSMenuItem(title: "移除标签", action: #selector(removeTagByNameFromPill(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = ["tagName": tag.name, "path": entry.path]
                    menu.addItem(item)
                    pill.menu = menu
                    pillContainer?.addArrangedSubview(pill)
                }
            }
            if tags.count > 3 {
                if let countPill = makeCountPill(count: tags.count - 3) {
                    pillContainer?.addArrangedSubview(countPill)
                }
            }
        }
    }

    /// 创建单个标签药丸（参考设计稿 ff-pill-tag）
    /// - 高度 18pt，圆角 9（胶囊形）
    /// - 8x8 圆点（颜色来自 tag.color）
    /// - 文字 11pt
    /// - 左右内边距 8pt，圆点与文字间距 4pt
    private func makeTagPill(tag: Tag) -> NSView? {
        let pill = SquircleMaskedView()
        pill.wantsLayer = true
        // 任务 F5: 药丸背景带标签色浅色，提高对比度
        let tagColor = NSColor(hex: tag.color) ?? .systemBlue
        pill.layer?.backgroundColor = tagColor.withAlphaComponent(0.15).cgColor
        pill.squircleRadius = 9
        pill.translatesAutoresizingMaskIntoConstraints = false
        // 设置最小宽度约束，保证至少显示 4 个字符（防止药丸在空间不足时塌缩）
        pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = (NSColor(hex: tag.color) ?? .systemBlue).cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(dot)

        // 标签名完整显示，由 label 的 truncation 和药丸最小宽度约束自动处理
        // 空间不足时 label 会截断显示，但药丸最小宽度 40pt 保证至少显示 4 个字符
        let label = NSTextField(labelWithString: tag.name)
        label.font = NSFont.systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        // 禁止文本换行，确保截断而非换行；末尾可见行截断
        label.cell?.wraps = false
        label.cell?.truncatesLastVisibleLine = true
        label.translatesAutoresizingMaskIntoConstraints = false
        // 设置 hugging 优先级：让 label 保持自然宽度，空间不足时才截断
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            pill.heightAnchor.constraint(equalToConstant: 18),
            dot.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            dot.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
        return pill
    }

    /// 创建 "+N" 计数药丸（无圆点，仅文字）
    private func makeCountPill(count: Int) -> NSView? {
        let pill = SquircleMaskedView()
        pill.wantsLayer = true
        // 任务 F5: 计数药丸背景用次级填充色（macOS 14+），旧系统回退 controlBackgroundColor
        if #available(macOS 14.0, *) {
            pill.layer?.backgroundColor = NSColor.secondarySystemFill.cgColor
        } else {
            pill.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
        pill.squircleRadius = 9
        pill.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "+\(count)")
        label.font = NSFont.systemFont(ofSize: 11)
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            pill.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
        return pill
    }

    /// 任务 F10-8 / F11-5: 创建分组标题行的 cell。
    ///
    /// 任务 F11-5 重叠 bug 修复：标题文字（分组名 + 计数）完全由 FFSectionHeaderRowView.draw()
    /// 统一绘制，cell 仅作为 NSTableView 列填充的透明占位（避免列错位），不显示任何文本。
    /// 此前 cell 内的 NSTextField 与 rowView.draw 同时绘制标题，造成重影（问题14）。
    private func makeSectionHeaderCell(tableView: NSTableView, tableColumn: NSTableColumn?, key: String) -> NSView? {
        let cellView = tableView.makeView(withIdentifier: sectionHeaderCellID, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cellView.identifier = sectionHeaderCellID
        cellView.wantsLayer = true
        cellView.layer?.backgroundColor = NSColor.clear.cgColor
        // 透明占位：不添加 textField，不清空已存在的 textField（复用时可能残留旧 cellView，
        // 但 makeView(withIdentifier:) 在我们未设置 textField 的前提下不会创建文本视图）。
        // 显式置空以防复用残留导致重影。
        cellView.textField?.stringValue = ""
        return cellView
    }

    public func reloadData() {
        // 任务 F10-8: 重建分组显示行映射后再 reload tableView
        rebuildDisplayRows()
        // Bug 9 修复：reloadData 可能引起 selectionDidChange 回调（行被清空/重建），
        // 若不抑制则会触发 viewModel.state.selectedFiles 变更 -> @Published 发射 ->
        // 上游 sink 再次 reloadData，形成循环。设置标志位并在下一 runloop 复位，
        // 既能覆盖同步触发的回调，也能覆盖同 runloop 内异步派发的回调。
        isReloading = true
        tableView?.reloadData()
        // 任务 F10-8: 分组渲染后恢复选中行的显示（基于 viewModel.state.selectedFiles 的路径）
        restoreSelectionFromViewModel()
        // 任务 F11-5: 数据变更后刷新粘性标题（分组维度/内容可能变化）
        updateStickyHeader()
        DispatchQueue.main.async { [weak self] in
            self?.isReloading = false
            // reload 后行视图坐标可能尚未更新，下一 runloop 再刷新一次粘性标题
            self?.updateStickyHeader()
        }
    }

    /// 任务 F11-5: 更新粘性分组标题（仿访达）。
    ///
    /// 算法：根据 clipView 当前可见区域的顶部 Y（document 坐标系），找到该位置所属的分组
    /// （向上回溯最近的 header 行）。若顶部正好压在某个 header 行的可见区域内，则让粘性标题
    /// "贴住"该 header 行顶部（视差上推），实现下一分组顶上来时粘性标题被平滑顶替的访达效果。
    /// groupBy == "none" 时隐藏粘性标题。
    private func updateStickyHeader() {
        guard let tableView = tableView, let viewModel = viewModel else { return }
        // 分组关闭：隐藏粘性标题
        guard viewModel.state.groupBy != "none" else {
            stickyHeader?.isHidden = true
            return
        }
        guard !displayRows.isEmpty else {
            stickyHeader?.isHidden = true
            return
        }

        let clipView = scrollView.contentView
        // clipView 的 bounds.origin.y 是 document 坐标系下可见区域顶部的 Y（NSTableView isFlipped=true）
        let visibleTopY = clipView.bounds.origin.y

        // 定位可见区域顶部落在哪一行
        guard visibleTopY >= 0,
              let topRow = tableView.row(at: NSPoint(x: 0, y: visibleTopY + 1)) as Int?,
              topRow >= 0, topRow < displayRows.count else {
            // 顶部点未命中任何行（如表格尚未布局完成或行高未就绪）：保守隐藏，避免显示错误分组
            stickyHeader?.isHidden = true
            return
        }

        // 从 topRow 向上找最近的 header 行（当前所属分组）
        var headerRow = topRow
        while headerRow > 0 && !displayRows[headerRow].isHeader {
            headerRow -= 1
        }
        guard displayRows[headerRow].isHeader else {
            stickyHeader?.isHidden = true
            return
        }

        // 当前粘性分组信息
        let currentKey = displayRows[headerRow].key
        let currentCount = sectionCount(forKey: currentKey)

        // 判断当前 header 行是否已被顶部完全裁切：
        // - 若 header 仍有部分处于可见区顶部（headerBottomInDoc > visibleTopY 且 headerTopInDoc <= visibleTopY），
        //   则隐藏粘性标题，让行内标题显示（避免重影）；
        // - 若 header 已完全滚出顶部（headerBottomInDoc <= visibleTopY），显示粘性标题。
        let headerRect = tableView.rect(ofRow: headerRow)
        let headerTopInDoc = headerRect.origin.y
        let headerBottomInDoc = headerTopInDoc + headerRect.height

        if headerBottomInDoc > visibleTopY && headerTopInDoc <= visibleTopY {
            // header 仍部分可见：隐藏粘性标题，让行内标题显示
            stickyHeader?.isHidden = true
            return
        }
        // header 已完全滚出顶部：显示粘性标题
        applySticky(title: currentKey, count: currentCount)
    }

    /// 取指定分组键的文件数量
    private func sectionCount(forKey key: String) -> Int {
        return viewModel?.groupedFiles.first(where: { $0.key == key })?.entries.count ?? 0
    }

    /// 应用粘性标题内容（统一入口，便于未来扩展）
    private func applySticky(title: String, count: Int) {
        guard let sticky = stickyHeader else { return }
        sticky.configure(title: title, count: count)
        sticky.needsDisplay = true
    }

    /// 任务 F10-8: 根据 viewModel.state.selectedFiles 恢复 tableView 的选中行。
    /// 分组渲染后行号与 viewModel.files 下标不再一一对应，reload 会清空选中，
    /// 需通过路径匹配找到对应的显示行号并重新选中。
    private func restoreSelectionFromViewModel() {
        guard let viewModel = viewModel else { return }
        let selectedPaths = Set(viewModel.state.selectedFiles.map { $0.path })
        guard !selectedPaths.isEmpty else { return }
        var indices: [Int] = []
        for (rowNum, row) in displayRows.enumerated() where !row.isHeader {
            if row.fileIndex < viewModel.state.files.count,
               selectedPaths.contains(viewModel.state.files[row.fileIndex].path) {
                indices.append(rowNum)
            }
        }
        if !indices.isEmpty {
            // 使用 IndexSet 选中多行（不触发 selectionDidChange 循环：isReloading 仍为 true）
            tableView?.selectRowIndexes(IndexSet(indices), byExtendingSelection: false)
        }
    }

    // MARK: - Layout

    // 任务 F7: 显式同步 appearance，确保选中色解析正确（v0.6.5）
    // FileListView 是 NSView（非 NSViewController），无 viewDidLayout；改用 layout()。
    // layout() 在布局变更时被频繁调用，appearance 赋值是轻量指针赋值，开销可忽略。
    public override func layout() {
        super.layout()
        tableView.appearance = NSApp.appearance
        // 任务 F11-5: 布局变化（列宽/窗口尺寸）后刷新粘性标题宽度与位置
        updateStickyHeader()
    }

    /// 任务 F7: 供外部（MainWindowController 主题监听）显式刷新 appearance（v0.6.5）
    /// 任务 F11-1: 同时刷新 tableView 实体背景色（日间/夜间切换，v0.6.7）
    public func refreshAppearance() {
        tableView.appearance = NSApp.appearance
        // 任务 F11-1: 主题切换时同步刷新 tableView 实体背景色
        let isDark = ThemeManager.shared.resolvedIsDark
        tableView.backgroundColor = isDark
            ? NSColor(srgbRed: 0.176, green: 0.176, blue: 0.176, alpha: 1.0)  // #2D2D2D
            : NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 1.0)  // #F5F5F5
        // 任务 F11-5: 主题切换时刷新粘性标题重绘（语义色自动解析，需触发 needsDisplay）
        stickyHeader?.needsDisplay = true
        updateStickyHeader()
    }

    // MARK: - Double Click

    @objc private func handleDoubleClick() {
        // 任务 F10-8: 通过 displayRows 映射 clickedRow -> viewModel.files 下标
        guard let viewModel = viewModel,
              let row = tableView.clickedRow as Int?,
              row >= 0, row < displayRows.count else { return }
        let displayRow = displayRows[row]
        guard !displayRow.isHeader, displayRow.fileIndex < viewModel.files.count else { return }
        let entry = viewModel.files[displayRow.fileIndex]
        onDoubleClick?(entry)
    }
}

// MARK: - NSTableViewDataSource

extension FileListView: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        // 任务 F10-8: 返回显示行数（含分组标题行）
        return displayRows.count
    }

    public func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let viewModel = viewModel else { return }
        let key = descriptor.key ?? "name"
        let field: SortField
        switch key {
        case "name": field = .name
        case "modifiedAt": field = .modifiedAt
        case "type": field = .type
        case "size": field = .size
        default: field = .name
        }
        viewModel.setSortField(field, ascending: descriptor.ascending)
        tableView.reloadData()
    }
}

// MARK: - NSTableViewDelegate

extension FileListView: NSTableViewDelegate {
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // 任务 F10-8: 分组标题行单独渲染
        guard row < displayRows.count else { return nil }
        let displayRow = displayRows[row]

        if displayRow.isHeader {
            // 分组标题行：仅名称列渲染标题文本（跨列视觉效果由 rowView 背景实现）
            // 其他列返回空 cell，保持列对齐
            return makeSectionHeaderCell(tableView: tableView, tableColumn: tableColumn, key: displayRow.key)
        }

        guard let viewModel = viewModel, displayRow.fileIndex < viewModel.files.count else { return nil }
        let entry = viewModel.files[displayRow.fileIndex]

        let cellID = NSUserInterfaceItemIdentifier(tableColumn?.identifier.rawValue ?? "")
        // 使用 FFTableCellView：背景保持透明（.clear），让 NSTableRowView 的标准
        // drawSelection 选中绘制可见。cellView 自身不参与选中绘制。
        let cellView = tableView.makeView(withIdentifier: cellID, owner: self) as? FFTableCellView
            ?? FFTableCellView()
        cellView.identifier = cellID
        cellView.wantsLayer = true
        cellView.layer?.backgroundColor = NSColor.clear.cgColor

        // Ensure text field exists (NSTableCellView handles layout)
        if cellView.textField == nil {
            let tf = NSTextField(labelWithString: "")
            tf.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            tf.lineBreakMode = .byTruncatingTail
            // 任务 F5: 文件名截断不换行，不挤压药丸
            tf.cell?.truncatesLastVisibleLine = true
            tf.cell?.wraps = false
            tf.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(tf)
            cellView.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }

        switch tableColumn?.identifier.rawValue {
        case "name":
            // v0.6.9: 根据 showFileExtensions 设置决定是否显示文件后缀
            let showExtensions = UserDefaults.standard.object(forKey: FFUserDefaultsKeys.showFileExtensions) as? Bool ?? true
            cellView.textField?.stringValue = showExtensions ? entry.name : entry.displayName
            // 隐藏文件灰色，系统保护文件红色
            if entry.isSystemProtected {
                cellView.textField?.textColor = NSColor.systemRed
            } else if entry.isHidden {
                cellView.textField?.textColor = NSColor.tertiaryLabelColor
            } else {
                cellView.textField?.textColor = NSColor.labelColor
            }
            // 使用 Auto Layout 约束布局 imageView，避免手动 frame 冲突
            // 双行布局：图标和文件名在上方行，标签药丸在下方行
            if cellView.imageView == nil {
                let iv = NSImageView()
                iv.imageScaling = .scaleProportionallyDown
                iv.translatesAutoresizingMaskIntoConstraints = false
                cellView.imageView = iv
                cellView.addSubview(iv)
                // 任务 F11-5: 基础 leading constant 4，分组开启时由下方缩进逻辑动态调整。
                // 保存约束引用到 cellView，便于复用时按分组状态调整 constant。
                let leadingC = iv.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4)
                NSLayoutConstraint.activate([
                    leadingC,
                    // 双行布局：图标顶部对齐（上方留 4pt 边距）
                    iv.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 4),
                    iv.widthAnchor.constraint(equalToConstant: 18),
                    iv.heightAnchor.constraint(equalToConstant: 18),
                ])
                cellView.nameLeadingConstraint = leadingC
                // 更新 textField 的 leading 和垂直约束
                if let tf = cellView.textField {
                    // 移除旧的 leading 和 centerY 约束，改为双行布局
                    cellView.removeConstraints(cellView.constraints.filter {
                        $0.firstItem === tf && ($0.firstAttribute == .leading || $0.firstAttribute == .centerY)
                    })
                    tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 4).isActive = true
                    // 双行布局：文件名顶部对齐（上方留 4pt 边距，与图标一致）
                    tf.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 4).isActive = true
                }
            }
            // 任务 F11-5: 分组内文件缩进（仿访达）。
            // groupBy != "none" 时文件行图标整体右移 16pt，对齐访达分组内文件的缩进层级。
            // groupBy == "none" 时恢复无缩进（base constant 4），保证非分组视图不受影响。
            let isGrouped = (viewModel.state.groupBy != "none")
            cellView.nameLeadingConstraint?.constant = isGrouped ? 20 : 4

            // 任务 F11-7: 卡顿修复 - NSWorkspace.shared.icon 异步化 + 应用层缓存。
            // 原实现每次 viewFor 都在主线程同步调用 NSWorkspace.shared.icon(forFile:)，
            // 大目录（数百文件）下叠加 LaunchServices 同步查询造成明显卡顿。
            // 现改为：
            // 1) 先查应用层缓存（workspaceIconCache），命中则同步显示（O(1) 内存查找）
            // 2) 未命中先显示通用占位图标（folder/doc），再后台异步获取真实图标
            // 3) 回调主线程更新 imageView，校验 cell 仍显示同一文件（复用安全）
            // 目录用 folder 占位，文件用 doc 占位（与 FileGridView 一致）
            let iconPointSize: CGFloat = 18
            let path = entry.path
            // 先更新 iconPath 标记并复位缩略图标志（cell 重新绑定文件）
            cellView.iconPath = path
            cellView.didReceiveThumbnail = false
            if let cached = ThumbnailManager.shared.cachedWorkspaceIcon(for: path, pointSize: iconPointSize) {
                cellView.imageView?.image = cached
            } else {
                // 占位图标：目录用 folder，文件用 doc（缩略图返回前先显示）
                let placeholder = entry.isDirectory
                    ? (NSImage(systemSymbolName: "folder", accessibilityDescription: "文件夹") ?? NSImage(named: NSImage.folderName))
                    : (NSImage(systemSymbolName: "doc", accessibilityDescription: "文件") ?? NSImage(named: NSImage.multipleDocumentsName))
                placeholder?.size = NSSize(width: iconPointSize, height: iconPointSize)
                cellView.imageView?.image = placeholder

                // 后台异步获取真实工作区图标
                ThumbnailManager.shared.fetchWorkspaceIcon(for: path, pointSize: iconPointSize) { [weak cellView] image in
                    guard let image = image else { return }
                    // 校验 cell 仍显示同一文件（含目录，复用安全，避免旧请求覆盖新 cell）
                    guard let cell = cellView, cell.iconPath == path else { return }
                    // 缩略图优先级更高：若缩略图已返回则不覆盖（避免用工作区图标盖掉缩略图）
                    guard !cell.didReceiveThumbnail else { return }
                    cell.imageView?.image = image
                }
            }

            // 任务 F8: 缩略图加载层修复（v0.6.5）
            // 1) 取消该 cell 上一次的缩略图请求（避免旧请求覆盖新 cell）
            // 2) 回调校验改为完整路径（避免同名文件误覆盖）
            // 3) 先显示文件类型图标作为占位，缩略图返回后再替换
            // 注意：路径校验用 cellView.currentFilePath 而非 cellView.identifier，
            // 因为 identifier 被 NSTableView 的复用机制依赖（见 makeView(withIdentifier:)）。
            if !entry.isDirectory {
                let path = entry.path
                // 取消旧请求（用 cell 的 currentFilePath 记录上一次路径）
                if let oldPath = cellView.currentFilePath, oldPath != path {
                    ThumbnailManager.shared.cancelGeneration(for: oldPath)
                }
                // 更新 cell 的当前路径标记
                cellView.currentFilePath = path

                // ThumbnailManager 的 completion 已在主线程回调，
                // 此处无需再包 DispatchQueue.main.async。
                ThumbnailManager.shared.generateThumbnail(path: path, size: CGSize(width: 32, height: 32)) { [weak cellView] image in
                    guard let image = image else { return }
                    // 校验 cell 仍显示同一文件（用完整路径而非文件名）
                    guard let cell = cellView,
                          cell.currentFilePath == path else { return }
                    // 任务 F11-7: 标记已收到缩略图，阻止后续工作区图标回调覆盖
                    cell.didReceiveThumbnail = true
                    cell.imageView?.image = image
                }
            } else {
                // 目录不加载缩略图：workspaceIcon 已在上方设置（文件夹图标），
                // 此处仅清除路径标记，避免旧回调误覆盖目录图标。
                cellView.currentFilePath = nil
            }

            // C12: 内联标签药丸容器（位于文件名右侧、cell 右侧）
            // 名称列 cell 结构：[文件图标] [文件名] [标签药丸容器]
            configureInlineTagPills(in: cellView, entry: entry)

        case "modifiedAt":
            cellView.textField?.stringValue = entry.formattedModificationDate

        case "type":
            cellView.textField?.stringValue = entry.kindDescription

        case "size":
            cellView.textField?.stringValue = entry.formattedSize

        default:
            break
        }

        return cellView
    }

    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        // 任务 F10-8 / F11-5: 分组标题行高度 24（仿访达，留出标题+计数徽章+底部分隔线空间）
        // 双行布局：有标签的文件行高度 48（文件名行 + 标签药丸行），无标签 26
        guard row < displayRows.count else { return 26 }
        let displayRow = displayRows[row]
        if displayRow.isHeader { return 24 }
        // v0.6.9: 使用预计算的 hasTags 避免高频 TagBridge I/O
        // 若关闭标签显示，始终使用单行高度
        let showTags = UserDefaults.standard.object(forKey: FFUserDefaultsKeys.showFileTags) as? Bool ?? true
        if !showTags { return 26 }
        return displayRow.hasTags ? 48 : 26
    }

    /// 返回自定义 FFTableRowView。标准 NSTableRowView.drawSelection 已能正确绘制
    /// 选中高亮（key window + firstResponder 时为强调蓝色），FFTableRowView 当前
    /// 仅作为扩展点保留（如将来添加 hover 效果），不覆盖任何绘制方法。
    /// 任务 F10-8: 分组标题行返回 FFSectionHeaderRowView（绘制浅灰背景 + 标题）。
    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard row < displayRows.count else { return FFTableRowView() }
        if displayRows[row].isHeader {
            let hv = FFSectionHeaderRowView()
            hv.sectionTitle = displayRows[row].key
            // 任务 F11-5: 传入分组内文件数量，用于绘制计数徽章
            hv.sectionCount = viewModel?.groupedFiles.first(where: { $0.key == displayRows[row].key })?.entries.count ?? 0
            return hv
        }
        return FFTableRowView()
    }

    public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        FFDebug.log("shouldSelectRow row=\(row) firstResponder=\(tableView.window?.firstResponder === tableView)")
        // 任务 F10-8: 分组标题行不可选
        guard row < displayRows.count else { return true }
        return !displayRows[row].isHeader
    }

    // Bug #2 修复：实现拖拽源方法，使表格行可作为拖拽提供者
    // 此前 handleTableDrag() 为死代码，NSTableViewDelegate 未实现 pasteboardWriterForRowAt:，
    // 导致拖拽完全不生效。现在由 NSTableView 标准机制驱动拖拽。
    public func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row < displayRows.count else { return nil }
        let displayRow = displayRows[row]
        guard !displayRow.isHeader, displayRow.fileIndex < viewModel?.files.count ?? 0 else { return nil }
        let entry = viewModel!.files[displayRow.fileIndex]
        return NSURL(fileURLWithPath: entry.path)
    }

    // MARK: - Drag & Drop Destination

    /// 拖拽目标校验：决定是否接受拖拽及操作类型（move/copy）。
    /// 问题1 修复：通过 NSTableViewDataSource 标准方法接管拖放目标，
    /// 替代被 tableView 子视图拦截、永不触发的 NSView 层
    /// draggingEntered/draggingUpdated/performDragOperation。
    public func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        // 检查拖拽内容是否包含文件 URL
        guard let items = info.draggingPasteboard.pasteboardItems, !items.isEmpty else { return [] }
        for item in items {
            guard item.types.contains(.fileURL) else { continue }
            // 计算本次判定使用的目标路径（拖到文件夹行上 → 该文件夹；否则 → 当前目录）
            var destPath = viewModel?.currentPath ?? ""
            if dropOperation == .on, row < displayRows.count {
                let displayRow = displayRows[row]
                if !displayRow.isHeader, displayRow.fileIndex < viewModel?.files.count ?? 0 {
                    let entry = viewModel!.files[displayRow.fileIndex]
                    if entry.isDirectory {
                        destPath = entry.path
                    }
                }
            }
            // 判断目标位置：.on 拖到文件夹行上 → 移入文件夹；.above 拖到行间/空白 → 移到当前目录
            if dropOperation == .on, row < displayRows.count {
                let displayRow = displayRows[row]
                if !displayRow.isHeader, displayRow.fileIndex < viewModel?.files.count ?? 0 {
                    let entry = viewModel!.files[displayRow.fileIndex]
                    // 仅文件夹行允许 .on（移入文件夹）；文件行/标题行回退为 .above
                    if entry.isDirectory {
                        return isMoveOperation(info, destPath: destPath) ? .move : .copy
                    }
                }
                // 拖到文件行/标题行上 → 改为 .above，避免歧义
                tableView.setDropRow(row, dropOperation: .above)
                return isMoveOperation(info, destPath: destPath) ? .move : .copy
            }
            return isMoveOperation(info, destPath: destPath) ? .move : .copy
        }
        return []
    }

    /// 接受拖拽并执行文件操作（move/copy）。
    /// 保留原 performDragOperation 的异步执行 / 撤销注册 / 跨面板刷新 / 部分失败提示逻辑，
    /// 并新增“拖到文件夹行上 → 移入该文件夹”的目标判定。
    public func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let viewModel = viewModel else { return false }

        // 解析拖拽的文件路径
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else {
            return false
        }

        // 确定目标路径：拖到文件夹行上 → 移入该文件夹；否则 → 当前目录
        var destPath = viewModel.currentPath
        if dropOperation == .on, row < displayRows.count {
            let displayRow = displayRows[row]
            if !displayRow.isHeader, displayRow.fileIndex < viewModel.files.count {
                let entry = viewModel.files[displayRow.fileIndex]
                if entry.isDirectory {
                    destPath = entry.path
                }
            }
        }
        guard !destPath.isEmpty else { return false }

        let isMove = isMoveOperation(info, destPath: destPath)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let srcs = urls.map { $0.path }
            let total = srcs.count
            do {
                let success: Int
                if isMove {
                    success = try CoreBridge.shared.parallelMove(srcs: srcs, dstDir: destPath)
                } else {
                    success = try CoreBridge.shared.parallelCopy(srcs: srcs, dstDir: destPath)
                }

                // I2: 失效缓存使刷新反映新状态。目标目录总会变化；
                // move 操作下每个源父目录也会变化（条目离开了这些目录），best-effort。
                try? CoreBridge.shared.invalidateCache(path: destPath)
                if isMove {
                    let sourceDirs = Set(srcs.map { ($0 as NSString).deletingLastPathComponent })
                    for dir in sourceDirs where !dir.isEmpty {
                        try? CoreBridge.shared.invalidateCache(path: dir)
                    }
                }

                // I3: 在异步 UI 刷新前捕获详细的部分失败信息（getLastError 为读一次即失效）
                let partialDetail = (success < total) ? CoreBridge.shared.getLastError() : ""

                // 计算 dst 路径用于撤销注册（best-effort：假设 srcs 都成功）
                let dstPaths = srcs.map { src -> String in
                    let name = (src as NSString).lastPathComponent
                    return (destPath as NSString).appendingPathComponent(name)
                }

                DispatchQueue.main.async {
                    self?.viewModel?.refresh()

                    // Bug 3 修复：跨面板拖拽时，若源文件来自对侧面板的当前目录，需刷新对侧面板
                    // （仅 move 操作会改变源目录；copy 不改变源，但为安全起见也刷新对侧）
                    if let counterpartPath = self?.counterpartViewModel?.currentPath,
                       !counterpartPath.isEmpty,
                       srcs.contains(where: { ($0 as NSString).deletingLastPathComponent == counterpartPath }) {
                        self?.counterpartViewModel?.refresh()
                    }

                    // 注册撤销（通过 viewModel?.undoManager 访问 per-window UndoManager）
                    if success > 0, let vm = self?.viewModel, let undoManager = vm.undoManager {
                        let counterpart = self?.counterpartViewModel
                        if isMove {
                            let pairs = zip(srcs, dstPaths).map { (src: $0, dst: $1) }
                            undoManager.registerUndo(withTarget: vm) { [weak counterpart] targetVM in
                                // undo: 移回原位
                                for (src, dst) in pairs {
                                    try? CoreBridge.shared.moveFile(src: dst, dst: src)
                                }
                                // 注册 redo：再次移动
                                targetVM.undoManager?.registerUndo(withTarget: targetVM) { [weak counterpart] vm2 in
                                    for (src, dst) in pairs {
                                        try? CoreBridge.shared.moveFile(src: src, dst: dst)
                                    }
                                    vm2.refresh()
                                    counterpart?.refresh()
                                }
                                targetVM.undoManager?.setActionName("移动 \(success) 个项目")
                                // I1: 刷新双面板（跨面板移动 undo 后源面板需同步）
                                targetVM.refresh()
                                counterpart?.refresh()
                            }
                            undoManager.setActionName("移动 \(success) 个项目")
                        } else {
                            let pairs = zip(srcs, dstPaths).map { (src: $0, dst: $1) }
                            undoManager.registerUndo(withTarget: vm) { [weak counterpart] targetVM in
                                // undo: 删除复制项
                                for (_, dst) in pairs {
                                    try? CoreBridge.shared.deleteFile(path: dst)
                                }
                                // 注册 redo：重新复制
                                targetVM.undoManager?.registerUndo(withTarget: targetVM) { [weak counterpart] vm2 in
                                    for (src, dst) in pairs {
                                        try? CoreBridge.shared.copyFile(src: src, dst: dst)
                                    }
                                    vm2.refresh()
                                    counterpart?.refresh()
                                }
                                targetVM.undoManager?.setActionName("复制 \(success) 个项目")
                                // I1: 刷新双面板
                                targetVM.refresh()
                                counterpart?.refresh()
                            }
                            undoManager.setActionName("复制 \(success) 个项目")
                        }
                    }

                    if success < total {
                        self?.showError(error: NSError(
                            domain: "FlowFinder", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "\(total - success) 个项目操作失败：\(partialDetail)"])
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showError(error: error)
                }
            }
        }

        return true
    }

    // 选择变更时才执行选择逻辑（单击选中、Cmd+点击多选、Shift+范围选）
    public func tableViewSelectionDidChange(_ notification: Notification) {
        FFDebug.log("selectionDidChange selectedRows=\(tableView.selectedRowIndexes) isReloading=\(isReloading) filesCount=\(viewModel?.files.count ?? -1)")
        // Bug 9 修复：reloadData 期间触发的 selectionDidChange 应忽略，
        // 避免与 reload 形成循环（reload → selectionDidChange → state 变更 → reload）
        if isReloading { return }

        guard let viewModel = viewModel else { return }
        // 点击行时激活当前面板（tableView 作为子视图拦截了 mouseDown，
        // FileListView.mouseDown 不会触发，需在此补充激活）
        onActivatePane?()
        // 问题2 修复：移除选中变更时的 makeKey + makeFirstResponder 调用。
        // 透明窗口的 key 状态切换会触发系统重绘导致可见抖动/跳动。
        // 选中变更不应改变窗口层级或第一响应者，key 状态与 firstResponder
        // 应在 mouseDown 或 windowDidBecomeKey 时处理。
        let selectedRows = tableView.selectedRowIndexes
        // 任务 F10-8: 通过 displayRows 映射显示行号 -> viewModel.files 下标
        let entries = selectedRows.compactMap { rowNum -> FileEntry? in
            guard rowNum >= 0, rowNum < displayRows.count else { return nil }
            let displayRow = displayRows[rowNum]
            guard !displayRow.isHeader, displayRow.fileIndex < viewModel.files.count else { return nil }
            return viewModel.files[displayRow.fileIndex]
        }
        // 同步更新 viewModel 的选择状态
        viewModel.state.selectedFiles = entries

        // 任务 L1: 移除自定义文字色切换，恢复 NSTableView 标准选中绘制
        // 标准行为：选中行背景为 systemBlue（window key 状态）+ 白色文字（由 NSTableRowView.drawSelection 自动处理）
        // 失焦时：选中为灰色（de-emphasized）+ 黑色文字
        // 这正是 Finder 的标准行为，无需任何自定义

        // 异步触发回调，避免阻塞双击事件
        DispatchQueue.main.async { [weak self] in
            self?.onSelectionChanged?(entries)
        }
    }
}

// MARK: - Keyboard Events

extension FileListView {
    /// 重写 mouseDown，先激活面板再传递事件给 tableView 处理选中
    public override func mouseDown(with event: NSEvent) {
        FFDebug.log("FileListView.mouseDown hit=\(hitTest(event.locationInWindow))")
        onActivatePane?()
        super.mouseDown(with: event)
    }

    /// 重写 keyDown，空格键触发 QuickLook 预览，Enter 触发内联重命名
    public override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags

        // Space: QuickLook 预览
        if event.keyCode == 49 && modifiers.isEmpty {
            // 发送通知让 MainWindowController 处理
            NotificationCenter.default.post(name: .fileListRequestQuickLook, object: nil, userInfo: ["side": getSide()])
            return
        }

        // Enter / Return：触发内联重命名（拦截事件，不再沿响应链传递到 MainWindowController 的打开逻辑）
        // macOS Finder 风格：Enter=重命名，Cmd+O/Cmd+Down=打开
        if (event.keyCode == 36 || event.keyCode == 76) && modifiers.isEmpty {
            beginInlineRename()
            return
        }

        // Bug 5 修复：Cmd+Down (keyCode 125) / Cmd+O (keyCode 31) 打开选中项（Finder 风格）
        // 仅 Cmd 修饰，不含 Shift/Option/Control
        let isPureCommand = modifiers.contains(.command)
            && !modifiers.contains(.shift)
            && !modifiers.contains(.option)
            && !modifiers.contains(.control)
        if isPureCommand && (event.keyCode == 125 || event.keyCode == 31) {
            openSelectedEntry()
            return
        }

        // Bug 5 修复：Cmd+Up (keyCode 126) 上级目录（Finder 风格）
        if isPureCommand && event.keyCode == 126 {
            viewModel?.goUp()
            return
        }

        // 其他键传给 nextResponder（沿响应链传递到 MainWindowController）
        super.keyDown(with: event)
    }

    /// 打开当前选中的条目（Cmd+O / Cmd+Down 触发，与双击行为一致）
    private func openSelectedEntry() {
        guard let entry = viewModel?.selectedFiles.first else { return }
        onDoubleClick?(entry)
    }

    // MARK: - Inline Rename（内联重命名）

    /// 开始内联重命名：选中单个文件时按 Enter 触发
    private func beginInlineRename() {
        // 正在重命名时不重复触发
        guard renamingRow < 0 else { return }
        guard let viewModel = viewModel else { return }

        // 仅单选时触发重命名
        let selectedRows = tableView.selectedRowIndexes
        guard selectedRows.count == 1, let row = selectedRows.first,
              row >= 0, row < displayRows.count else { return }
        // 任务 F10-8: 通过 displayRows 映射行号 -> viewModel.files 下标
        let displayRow = displayRows[row]
        guard !displayRow.isHeader, displayRow.fileIndex < viewModel.files.count else { return }

        let entry = viewModel.files[displayRow.fileIndex]

        // 获取名称列的 cell view
        guard let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              let textField = cellView.textField else { return }

        // 记录重命名上下文
        renamingRow = row
        renamingOriginalName = entry.name
        renamingPath = entry.path
        renamingTextField = textField
        renameCancelled = false

        // 进入编辑模式：将名称 textField 设为可编辑并获取焦点
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = self

        guard window?.makeFirstResponder(textField) == true else {
            // 无法进入编辑模式，清理状态
            textField.isEditable = false
            textField.delegate = nil
            renamingRow = -1
            renamingOriginalName = ""
            renamingPath = ""
            renamingTextField = nil
            renameCancelled = false
            return
        }

        // 选中文件名（不含扩展名），与访达行为一致
        if let editor = textField.currentEditor() {
            let name = entry.name as NSString
            let extRange = name.range(of: ".", options: .backwards)
            if entry.isDirectory || extRange.location == NSNotFound || extRange.location == 0 {
                editor.selectAll(nil)
            } else {
                editor.selectedRange = NSRange(location: 0, length: extRange.location)
            }
        }
    }

    /// 结束内联重命名，根据取消标志决定是否提交
    private func endInlineRename() {
        guard renamingRow >= 0 else { return }
        let textField = renamingTextField
        let originalName = renamingOriginalName
        let path = renamingPath
        let cancelled = renameCancelled

        // 清理状态
        renamingRow = -1
        renamingOriginalName = ""
        renamingPath = ""
        renamingTextField = nil
        renameCancelled = false

        // 恢复 textField 为非编辑状态
        textField?.delegate = nil
        if let tf = textField {
            tf.isEditable = false
            // 取消时恢复原名称显示
            if cancelled {
                tf.stringValue = originalName
            }
        }

        // 取消则不重命名
        guard !cancelled else { return }

        // 提交重命名（复用 viewModel.renameFile，与右键菜单重命名一致）
        guard let tf = textField else { return }
        let newName = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != originalName else { return }
        viewModel?.renameFile(path, to: newName)
    }
}

// MARK: - NSTextFieldDelegate（内联重命名编辑事件）

extension FileListView: NSTextFieldDelegate {
    /// 处理编辑中的特殊按键（Enter 确认 / Esc 取消）
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            // Esc：取消重命名
            renameCancelled = true
            window?.makeFirstResponder(tableView)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            // Enter/Return：确认重命名（交还焦点触发 controlTextDidEndEditing）
            window?.makeFirstResponder(tableView)
            return true
        default:
            return false
        }
    }

    /// 编辑结束（Enter 确认 / 失焦自动确认 / Esc 取消）
    public func controlTextDidEndEditing(_ obj: Notification) {
        guard renamingRow >= 0 else { return }
        endInlineRename()
    }
}

// MARK: - Drag and Drop

extension FileListView: NSDraggingSource {
    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .move, .delete]
    }
}

extension FileListView {
    /// 判断是否为移动操作（访达语义）：
    /// 同盘 + 无修饰键 = 移动；同盘 + ⌘ = 复制
    /// 跨盘 + 无修饰键 = 复制；跨盘 + ⌘ = 移动
    /// - Parameter destPath: 真实拖放目标路径（拖到文件夹行时为该文件夹路径，否则当前目录）
    private func isMoveOperation(_ sender: NSDraggingInfo, destPath: String? = nil) -> Bool {
        // 直接读取当前按键状态（比依赖 draggingSourceOperationMask 的间接过滤更可靠）
        // 注意：若 validateDrop 回调中 NSApp.currentEvent 为 nil，回退到 Cmd 未按下（默认行为）
        let commandPressed = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false

        // 源与目标卷判定
        let dest = destPath ?? viewModel?.currentPath
        guard let dest = dest, !dest.isEmpty else { return false }
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let srcPath = urls.first?.path else { return false }
        let sameVolume = isSameVolume(srcPath: srcPath, destPath: dest)

        // ⌘ 按下时反转默认行为（复制↔移动切换，访达语义）
        return commandPressed ? !sameVolume : sameVolume
    }

    /// 检查两个路径是否在同一卷（通过 statfs）
    private func isSameVolume(srcPath: String, destPath: String) -> Bool {
        var srcStat = statfs()
        var dstStat = statfs()

        let srcResult = srcPath.withCString { statfs($0, &srcStat) }
        let dstResult = destPath.withCString { statfs($0, &dstStat) }

        guard srcResult == 0 && dstResult == 0 else { return false }

        // 比较设备 ID (使用 memcmp 比较 fsid_t 原始字节)
        var srcFsid = srcStat.f_fsid
        var dstFsid = dstStat.f_fsid
        return withUnsafeBytes(of: &srcFsid) { srcBytes in
            withUnsafeBytes(of: &dstFsid) { dstBytes in
                srcBytes.elementsEqual(dstBytes)
            }
        }
    }
}

// MARK: - C13: NSMenuDelegate（动态构建右键菜单 + 标签二级子菜单）

extension FileListView: NSMenuDelegate {

    /// 菜单即将显示时更新：
    /// - 主菜单："打开"项图标根据选中项是文件夹还是文件动态切换（folder / doc）
    ///           "标签"项仅当选中单个文件时显示（多选时隐藏）
    /// - 标签子菜单：每次显示前重建（列出所有标签 + ✓标记当前文件已有 + "新建标签..."）
    public func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === tableView.menu {
            updateMainMenu(menu)
        } else if menu === tagsSubmenu {
            rebuildTagsSubmenu(menu)
        }
    }

    /// 更新主右键菜单的动态项
    private func updateMainMenu(_ menu: NSMenu) {
        // "打开"项图标：文件夹用 folder，文件用 doc
        if let openItem = menu.items.first(where: { $0.title == "打开" }) {
            let isOpenFolder = clickedEntry?.isDirectory == true
            openItem.image = NSImage(systemSymbolName: isOpenFolder ? "folder" : "doc",
                                     accessibilityDescription: "打开")
        }

        // "标签"项：仅当选中单个文件时显示
        if let tagsItem = menu.items.first(where: { $0.title == "标签" }) {
            let selectedCount = tableView.selectedRowIndexes.count
            // 单选或无选中但有右键点击行时显示（右键点击单个文件可操作）
            let singleSelected = selectedCount == 1
            let hasClickedSingle = selectedCount == 0 && tableView.clickedRow >= 0
            tagsItem.isHidden = !(singleSelected || hasClickedSingle)
        }

        // "移动/复制到另一面板"箭头方向：panelSide 可能在 init 后才被设置，每次显示菜单时同步
        let isLeftPane = effectiveSide == .left
        if let moveItem = menu.items.first(where: { $0.title == "移动到另一面板" }) {
            moveItem.image = NSImage(systemSymbolName: isLeftPane ? "arrow.right" : "arrow.left",
                                     accessibilityDescription: "移动到另一面板")
        }
        if let copyOtherItem = menu.items.first(where: { $0.title == "复制到另一面板" }) {
            copyOtherItem.image = NSImage(systemSymbolName: isLeftPane ? "arrow.right.square" : "arrow.left.square",
                                          accessibilityDescription: "复制到另一面板")
        }

        // 任务 F10-10: "在对侧面板打开"仅当右键点击项为文件夹时显示（修复问题13）
        // 文件无此操作意义（文件无法被"打开"为目录导航目标）
        if let openOtherItem = menu.items.first(where: { $0.title == "在对侧面板打开" }) {
            openOtherItem.isHidden = !(clickedEntry?.isDirectory ?? false)
        }
    }

    /// 重建标签二级子菜单
    /// - 顶部：列出现有所有标签（彩色圆点 + 名称，当前文件已有的显示 ✓）
    /// - 分隔线
    /// - "新建标签..." 项
    private func rebuildTagsSubmenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // 目标文件路径：优先右键点击的文件，其次单选的文件
        let targetEntry = clickedEntry ?? viewModel?.selectedFiles.first
        guard let entry = targetEntry else {
            // 无目标文件：仅显示"新建标签..."
            let createItem = NSMenuItem(title: "新建标签...", action: #selector(showCreateTagDialog(_:)), keyEquivalent: "")
            createItem.target = self
            createItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建标签")
            menu.addItem(createItem)
            return
        }

        // 获取当前文件已有的标签
        let currentTags = TagBridge.shared.getTags(path: entry.path)
        let currentTagIds = Set(currentTags.map { $0.id })
        let currentTagNames = Set(currentTags.map { $0.name })

        // 列出所有现有标签
        let allTags = loadAllSidebarTags()
        for tag in allTags {
            let item = NSMenuItem(title: tag.name, action: #selector(toggleTagOnFile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ["tagId": tag.id, "tagName": tag.name, "tagColor": tag.color, "path": entry.path]
            // 彩色圆点图标
            item.image = makeDotImage(colorHex: tag.color)
            // 当前文件已有此标签则显示 ✓（使用 onStateImage）
            if currentTagIds.contains(tag.id) || currentTagNames.contains(tag.name) {
                item.state = .on
            }
            menu.addItem(item)
        }

        if !allTags.isEmpty {
            menu.addItem(.separator())
        }

        // "新建标签..."
        let createItem = NSMenuItem(title: "新建标签...", action: #selector(showCreateTagDialog(_:)), keyEquivalent: "")
        createItem.target = self
        createItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建标签")
        menu.addItem(createItem)
    }

    /// 创建带颜色的圆点 NSImage（用于标签子菜单项图标）
    private func makeDotImage(colorHex: String) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        let color = NSColor(hex: colorHex) ?? .systemBlue
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 8, height: 8)).fill()
        image.unlockFocus()
        return image
    }
}

// MARK: - C13: Tag Helpers（标签数据读写 + 对话框）

extension FileListView {

    /// 读取所有现有标签（从 UserDefaults "SidebarTags" 读取，与 SidebarView.TagsSidebarDataSource 共享存储）
    /// 注：TagBridge 无 getAllTags API，此处直接读 UserDefaults 以满足"不修改其他文件"约束
    private func loadAllSidebarTags() -> [Tag] {
        guard let data = UserDefaults.standard.data(forKey: "SidebarTags"),
              let tags = try? JSONDecoder().decode([Tag].self, from: data) else {
            return []
        }
        return tags
    }

    /// 写回所有标签到 UserDefaults（新建标签后同步给侧边栏）
    private func saveAllSidebarTags(_ tags: [Tag]) {
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: "SidebarTags")
        }
    }

    /// 切换文件标签：已有则移除，没有则添加
    @objc private func toggleTagOnFile(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let tagId = info["tagId"],
              let tagName = info["tagName"],
              let path = info["path"] else { return }
        let tagColor = info["tagColor"] ?? "#007AFF"

        let currentTags = TagBridge.shared.getTags(path: path)
        if currentTags.contains(where: { $0.id == tagId || $0.name == tagName }) {
            // 已有 → 移除
            _ = TagBridge.shared.removeTag(tagId, path: path)
        } else {
            // 没有 → 添加
            let tag = Tag(id: tagId, name: tagName, color: tagColor)
            _ = TagBridge.shared.addTag(tag, path: path)
        }

        // 刷新列表以更新名称列内联药丸
        reloadData()
        // 通知侧边栏刷新标签列表，携带文件当前标签以同步侧边栏
        let updatedTags = TagBridge.shared.getTags(path: path)
        NotificationCenter.default.post(name: NSNotification.Name("FileTagsDidChange"), object: nil, userInfo: ["tags": updatedTags])
    }

    /// 右键药丸移除标签（按名称移除，兼容原生标签随机 id）
    @objc private func removeTagByNameFromPill(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let tagName = info["tagName"],
              let path = info["path"] else { return }
        _ = TagBridge.shared.removeTagByName(tagName, path: path)
        reloadData()
        // 通知侧边栏刷新，携带文件当前标签以同步侧边栏
        let updatedTags = TagBridge.shared.getTags(path: path)
        NotificationCenter.default.post(name: NSNotification.Name("FileTagsDidChange"), object: nil, userInfo: ["tags": updatedTags])
    }

    /// 新建标签对话框（参考 SidebarView.showCreateTagDialog 实现）
    /// 创建后同时添加到当前右键目标文件
    @objc private func showCreateTagDialog(_ sender: Any?) {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "新建标签"
        alert.informativeText = "输入标签名称并选择颜色："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        let containerWidth: CGFloat = 300
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 64))

        // 名称输入框
        let nameField = NSTextField(frame: NSRect(x: 0, y: 36, width: containerWidth, height: 24))
        nameField.placeholderString = "标签名称"
        container.addSubview(nameField)

        // 预设颜色圆点按钮
        let presetColors: [String] = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#5856D6"]
        let dotSize: CGFloat = 22
        let spacing: CGFloat = 8
        let totalDotsWidth = CGFloat(presetColors.count) * dotSize + CGFloat(presetColors.count - 1) * spacing
        let startX = (containerWidth - totalDotsWidth) / 2

        let colorHolder = FFCreateTagColorHolder(colors: presetColors)

        for (i, hex) in presetColors.enumerated() {
            let x = startX + CGFloat(i) * (dotSize + spacing)
            let btn = NSButton(frame: NSRect(x: x, y: 4, width: dotSize, height: dotSize))
            btn.bezelStyle = .circular
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.backgroundColor = (NSColor(hex: hex) ?? .systemBlue).cgColor
            btn.layer?.cornerRadius = dotSize / 2
            btn.layer?.borderColor = NSColor.labelColor.cgColor
            btn.layer?.borderWidth = (i == 0) ? 2 : 0
            btn.target = colorHolder
            btn.action = #selector(FFCreateTagColorHolder.selectColor(_:))
            btn.tag = i
            container.addSubview(btn)
        }

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField

        // 目标文件路径（创建后同时添加到该文件）
        let targetPath = clickedEntry?.path ?? viewModel?.selectedFiles.first?.path

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let tag = Tag(name: name, color: colorHolder.selectedHex)

            // 1) 写入全局标签库（UserDefaults，与侧边栏共享）
            var allTags = self?.loadAllSidebarTags() ?? []
            if !allTags.contains(where: { $0.name == tag.name }) {
                allTags.append(tag)
                self?.saveAllSidebarTags(allTags)
            }

            // 2) 同时添加到当前文件
            if let path = targetPath {
                _ = TagBridge.shared.addTag(tag, path: path)
                self?.reloadData()
            }

            // 3) 通知侧边栏刷新标签显示，携带新标签以同步侧边栏
            var notifyTags = allTags
            if !notifyTags.contains(where: { $0.name == tag.name }) {
                notifyTags.append(tag)
            }
            NotificationCenter.default.post(name: NSNotification.Name("FileTagsDidChange"), object: nil, userInfo: ["tags": notifyTags])
        }
    }
}

// MARK: - FFCreateTagColorHolder（新建标签对话框颜色选择辅助类）

/// 颜色选择 holder：与 SidebarView.TagColorHolder 同结构，但 FileListView 不能引用 private 类，
/// 故在此单独定义（仅在 FileListView 内部使用）
final class FFCreateTagColorHolder: NSObject {
    private let colors: [String]
    private(set) var selectedHex: String

    init(colors: [String]) {
        self.colors = colors
        self.selectedHex = colors.first ?? "#007AFF"
        super.init()
    }

    @objc func selectColor(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < colors.count else { return }
        selectedHex = colors[idx]
        // 更新按钮选中边框
        if let container = sender.superview {
            for case let btn as NSButton in container.subviews {
                btn.layer?.borderWidth = btn === sender ? 2 : 0
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let fileListDidCopy = Notification.Name("fileListDidCopy")
    static let fileListDidCut = Notification.Name("fileListDidCut")
    static let fileListDidPaste = Notification.Name("fileListDidPaste")
    static let fileListDidCopyToOther = Notification.Name("fileListDidCopyToOther")
    static let fileListDidMoveToOther = Notification.Name("fileListDidMoveToOther")
    static let fileListDidOpenInOther = Notification.Name("fileListDidOpenInOther")
    static let fileListRequestQuickLook = Notification.Name("fileListRequestQuickLook")
    static let fileListDidAddFavorite = Notification.Name("fileListDidAddFavorite")
    /// C13: 标签变更通知（新建/切换标签后通知侧边栏刷新）
    static let fileListTagsChanged = Notification.Name("FileListTagsChanged")
    /// F9-C: 请求显示"显示简介"独立窗口（仿访达 Get Info）
    static let fileListShowInfo = Notification.Name("FileListShowInfo")
}
