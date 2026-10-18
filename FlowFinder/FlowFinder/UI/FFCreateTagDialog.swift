import Cocoa

// MARK: - FFCreateTagDialog（统一新建标签弹窗）

/// 全应用统一的「新建标签」弹窗（v0.7.4 项 1 需求）。
/// 此前三个入口（右键菜单 FFPaneActionsController / 设置页 TagManagementRowView /
/// 侧边栏 SidebarView）各自实现了一套弹窗，颜色选择方式各不相同。
/// 本类统一：名称输入 + 预设色块 + 自定义颜色（系统 NSColorPanel）。
///
/// 用法：
///   FFCreateTagDialog.showCreateTagDialog(on: window) { tag in
///       // 创建成功回调，tag 已保存到 SidebarTags
///       // 可选：TagBridge.shared.addTag(tag, path: somePath) 应用到文件
///   }
///
/// 颜色选择说明（v0.7.4 修订）：
/// - 默认显示 8 个色块：按「颜色被标签使用数」从多到少排序，
///   不足 8 个用默认色补足；使用数为 0 的按默认色顺序排列
/// - 「+」号按钮（与色块同尺寸）：点击弹出系统颜色选择器，选色后添加到色板列表
/// - 「...」按钮：点击向下展开第二行，显示更多颜色；再点收起
enum FFCreateTagDialog {

    /// 默认色板（与访达标签色接近的 8 色），用于补足不足 8 个的情况
    static let presetColors: [String] = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#AF52DE", "#8E8E93", "#FF2D55"
    ]

    /// 弹出新建标签弹窗（sheet 形式）。
    /// - Parameters:
    ///   - window: 宿主窗口
    ///   - completion: 创建成功后回调（参数为已保存的新标签）。取消不回调。
    static func showCreateTagDialog(on window: NSWindow, completion: @escaping (Tag) -> Void) {
        let alert = NSAlert()
        alert.messageText = "新建标签"
        alert.informativeText = "输入标签名称并选择颜色："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        let containerWidth: CGFloat = 300
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 132))

        // 名称输入框（顶部）
        let nameField = NSTextField(frame: NSRect(x: 0, y: 100, width: containerWidth, height: 24))
        nameField.placeholderString = "标签名称"
        container.addSubview(nameField)

        // 颜色选择器视图（色块 + 加号 + 省略号，可展开第二行）
        let colorPicker = FFTagColorPickerView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 94))
        container.addSubview(colorPicker)

        // v0.7.4 修订：监听展开/收起，调整容器高度（第二行显示时增高）
        // F3: 保存 observer token，alert 关闭后必须移除，避免闭包强捕获容器/视图导致泄漏
        let heightObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("FFTagColorPickerHeightChanged"),
            object: colorPicker, queue: .main
        ) { _ in
            let newHeight: CGFloat = colorPicker.isExpanded ? 120 : 94
            container.frame = NSRect(x: 0, y: 0, width: containerWidth, height: newHeight)
            colorPicker.frame = NSRect(x: 0, y: 0, width: containerWidth, height: newHeight)
            nameField.frame = NSRect(x: 0, y: newHeight - 32, width: containerWidth, height: 24)
            alert.accessoryView = container
        }

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField

        alert.beginSheetModal(for: window) { response in
            // F3: 弹窗关闭后移除高度监听，打破 NotificationCenter → 闭包 → 视图 的保留环
            NotificationCenter.default.removeObserver(heightObserver)
            guard response == .alertFirstButtonReturn else { return }
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let tag = Tag(name: name, color: colorPicker.selectedHex)
            completion(tag)
        }
    }

    /// 弹出新建标签弹窗，并将新标签保存到 SidebarTags（公共存储）。
    /// 三个入口统一调用此方法；如需同时把标签应用到某个文件，在 completion 中
    /// 调用 TagBridge.shared.addTag(tag, path:)。
    static func showCreateTagDialogAndSave(on window: NSWindow, completion: @escaping (Tag) -> Void = { _ in }) {
        showCreateTagDialog(on: window) { tag in
            // 保存到 UserDefaults "SidebarTags"（与侧边栏/设置页共享存储）
            var allTags = loadAllSidebarTags()
            if !allTags.contains(where: { $0.name == tag.name }) {
                allTags.append(tag)
                saveAllSidebarTags(allTags)
            }
            // 通知侧边栏刷新
            NotificationCenter.default.post(name: NSNotification.Name("SidebarTagsDidRefresh"), object: nil)
            // 通知文件标签变更（供详情栏/右键菜单刷新）
            NotificationCenter.default.post(name: NSNotification.Name("FileTagsDidChange"), object: nil,
                                            userInfo: ["tags": allTags])
            completion(tag)
        }
    }

    // MARK: - SidebarTags 存储辅助（与 SidebarView/TagManagementRowView 共享同一 key）

    static func loadAllSidebarTags() -> [Tag] {
        guard let data = UserDefaults.standard.data(forKey: "SidebarTags"),
              let tags = try? JSONDecoder().decode([Tag].self, from: data) else {
            return []
        }
        return tags
    }

    static func saveAllSidebarTags(_ tags: [Tag]) {
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: "SidebarTags")
        }
    }
}

// MARK: - FFTagColorPickerView（色块 + 加号 + 省略号）

/// 标签颜色选择视图（v0.7.4 修订）：
/// - 第一行：按使用频率排序的 8 个色块 + 「+」号按钮 + 「...」按钮
/// - 点「...」向下展开第二行，显示更多颜色；再点收起
/// - 点「+」弹系统颜色选择器，选色后添加到色板列表并成为选中色
final class FFTagColorPickerView: NSView {

    /// 当前选中的颜色 hex
    private(set) var selectedHex: String

    /// 全部可用色（含自定义添加色），按使用频率排序
    private var allHexes: [String] = []
    /// 色块视图引用
    private var colorDots: [NSView] = []
    /// 第二行是否展开（供 FFCreateTagDialog 调整容器高度）
    var isExpanded = false

    /// 色块尺寸与间距
    private let dotSize: CGFloat = 24
    private let spacing: CGFloat = 8
    /// 第一行最多显示 8 个色块（不含 + 和 ... 按钮）
    private let firstRowCount = 8

    init(frame: NSRect, initialHex: String = "#FF3B30") {
        self.selectedHex = initialHex
        super.init(frame: frame)
        rebuildColorList()
        setupUI()
    }

    required init?(coder: NSCoder) {
        self.selectedHex = "#FF3B30"
        super.init(coder: coder)
        rebuildColorList()
        setupUI()
    }

    // MARK: - 颜色列表构建（按使用频率排序）

    /// 构建颜色列表：按「颜色被标签使用数」从多到少排序，
    /// 不足 8 个用默认色补足；自定义添加色合并参与排序。
    private func rebuildColorList() {
        // 统计每个颜色被多少标签使用（来自 SidebarTags）
        var usageCount: [String: Int] = [:]
        for tag in FFCreateTagDialog.loadAllSidebarTags() {
            usageCount[tag.color.uppercased(), default: 0] += 1
        }

        // 收集所有已知颜色：预设色 + 自定义添加色（从历史使用中收集）
        var known: Set<String> = Set(FFCreateTagDialog.presetColors.map { $0.uppercased() })
        for tag in FFCreateTagDialog.loadAllSidebarTags() {
            known.insert(tag.color.uppercased())
        }

        // 排序：使用数多的在前；使用数相同按预设色顺序
        let presetOrder: [String: Int] = Dictionary(
            uniqueKeysWithValues: FFCreateTagDialog.presetColors.enumerated().map { ($0.element.uppercased(), $0.offset) }
        )
        let sorted = known.sorted { a, b in
            let ca = usageCount[a] ?? 0
            let cb = usageCount[b] ?? 0
            if ca != cb { return ca > cb }
            return (presetOrder[a] ?? Int.max) < (presetOrder[b] ?? Int.max)
        }

        // 第一行 8 个 + 其余进第二行（展开时显示）
        // 确保当前选中色始终在可见列表中（若不在，加到最前）
        var list = sorted
        if let idx = list.firstIndex(where: { $0 == selectedHex.uppercased() }), idx >= firstRowCount {
            list.remove(at: idx)
            list.insert(selectedHex.uppercased(), at: 0)
        }
        allHexes = list
    }

    // MARK: - UI

    private func setupUI() {
        wantsLayer = true
        rebuildDots()
    }

    /// 重建所有色块 + 加号 + 省略号（在两条 24pt 高的行内）
    private func rebuildDots() {
        // 清除旧视图
        for v in subviews { v.removeFromSuperview() }
        colorDots.removeAll()

        // F3: 真正的两行布局——第一行 8 个 + 「+」/「...」，展开后第二行在下方。
        // 行间距 = spacing，两行 y 不同，避免展开时所有色块挤同一行溢出。
        let row1Y: CGFloat = 44
        let row2Y: CGFloat = 44 - dotSize - spacing  // 第一行下方
        var x: CGFloat = 0
        let visibleCount = isExpanded ? allHexes.count : min(firstRowCount, allHexes.count)
        for i in 0..<visibleCount {
            let y = i < firstRowCount ? row1Y : row2Y
            x = addDot(hex: allHexes[i], x: x, y: y)
        }
        // 「+」号按钮（第一行末尾，与色块同尺寸同外观：纯视图圆形 + 手势）
        let addView = makeControlDot(symbol: "plus", tooltip: "添加颜色", action: #selector(addColorClicked(_:)))
        addView.frame = NSRect(x: x + 2, y: row1Y, width: dotSize, height: dotSize)
        addSubview(addView)
        x += dotSize + spacing

        // 「...」按钮（第一行末尾，展开/收起第二行，与色块同尺寸同外观）
        let moreView = makeControlDot(symbol: "ellipsis", tooltip: isExpanded ? "收起" : "更多颜色", action: #selector(moreClicked(_:)))
        moreView.frame = NSRect(x: x + 2, y: row1Y, width: dotSize, height: dotSize)
        addSubview(moreView)
    }

    /// 添加一个色块，返回下一个 x 位置
    private func addDot(hex: String, x: CGFloat, y: CGFloat) -> CGFloat {
        let dot = NSView(frame: NSRect(x: x, y: y, width: dotSize, height: dotSize))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = (NSColor(hex: hex) ?? .systemBlue).cgColor
        dot.layer?.cornerRadius = dotSize / 2
        dot.layer?.borderColor = NSColor.labelColor.cgColor
        dot.layer?.borderWidth = (hex.lowercased() == selectedHex.lowercased()) ? 2 : 0
        let click = NSClickGestureRecognizer(target: self, action: #selector(dotClicked(_:)))
        dot.addGestureRecognizer(click)
        dot.toolTip = hex
        addSubview(dot)
        colorDots.append(dot)
        return x + dotSize + spacing
    }

    /// 创建「+」/「...」控制按钮：纯视图圆形（与色块完全同尺寸同外观），
    /// 中央绘制 SF Symbol 图标，点击手势触发。避免 NSButton.circular 在
    /// macOS 26 上渲染尺寸/样式与色块不一致的问题。
    private func makeControlDot(symbol: String, tooltip: String, action: Selector) -> NSView {
        let dot = NSView(frame: NSRect(x: 0, y: 0, width: dotSize, height: dotSize))
        dot.wantsLayer = true
        // 浅灰底 + 细边框，与色块轮廓一致，突出"按钮"性质
        dot.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.15).cgColor
        dot.layer?.cornerRadius = dotSize / 2
        dot.layer?.borderColor = NSColor.separatorColor.cgColor
        dot.layer?.borderWidth = 1

        // 中央图标（SF Symbol，模板色）
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        icon.contentTintColor = NSColor.labelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        dot.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: dot.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: dot.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 13),
            icon.heightAnchor.constraint(equalToConstant: 13),
        ])

        let click = NSClickGestureRecognizer(target: self, action: action)
        dot.addGestureRecognizer(click)
        dot.toolTip = tooltip
        return dot
    }

    // MARK: - Actions

    @objc private func dotClicked(_ sender: NSClickGestureRecognizer) {
        guard let dot = sender.view,
              let idx = colorDots.firstIndex(of: dot),
              idx < allHexes.count else { return }
        select(hex: allHexes[idx])
    }

    /// 点「+」：弹系统颜色选择器，选色后插入色板首位并选中（原色右移）
    @objc private func addColorClicked(_ sender: NSClickGestureRecognizer) {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.color = NSColor(hex: selectedHex) ?? .systemBlue
        panel.makeKeyAndOrderFront(nil)
    }

    deinit {
        // F3: dialog 关闭后清理 NSColorPanel.shared 的 target，避免 panel 保留
        // 指向已释放视图的悬空指针，用户再改色时崩溃。
        // 注意：NSColorPanel 无 target getter，只能在面板仍可见时无条件清理
        //（面板关闭时 target 已被系统重置，直接 setTarget(nil) 无副作用）。
        if NSColorPanel.shared.isVisible {
            NSColorPanel.shared.setTarget(nil)
        }
    }

    /// 点「...」：展开/收起第二行
    @objc private func moreClicked(_ sender: NSClickGestureRecognizer) {
        isExpanded.toggle()
        rebuildDots()
        // 通知弹窗容器更新高度（由 FFCreateTagDialog 处理）
        NotificationCenter.default.post(name: NSNotification.Name("FFTagColorPickerHeightChanged"), object: self)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        guard let rgb = sender.color.usingColorSpace(.sRGB) else { return }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        let hex = String(format: "#%02X%02X%02X", r, g, b)
        // 添加到色板（若未存在）并选中
        if !allHexes.contains(where: { $0.lowercased() == hex.lowercased() }) {
            allHexes.insert(hex.uppercased(), at: 0)
        }
        select(hex: hex)
        rebuildDots()
    }

    private func select(hex: String) {
        selectedHex = hex
        // 更新所有色块选中边框（F3: 加下标保护，allHexes 与 colorDots 数量可能短暂不一致）
        for (i, dot) in colorDots.enumerated() {
            guard i < allHexes.count else { break }
            dot.layer?.borderWidth = (allHexes[i].lowercased() == hex.lowercased()) ? 2 : 0
        }
    }
}
