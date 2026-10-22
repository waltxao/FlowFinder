import AppKit

/// 标签选色器（统一入口）。
///
/// 底层用 vendored 的 `macColorPicker`（MIT，`Libraries/macColorPicker/`），
/// 提供「App 色板 + 任意色」两种选择：
/// - 首行 8 个 App 标签色，点一下即选中
/// - 末尾「自定义颜色」按钮打开系统色盘，可调任意色
///
/// 全应用三处入口（侧栏「+」、侧栏右键「编辑颜色」、文件右键标签）
/// 都必须走这里，否则同一标签在不同入口能选到不同色。
enum FFTagColorPalette {

    /// App 标签色板。
    /// 蓝色取 `FFAccent.defaultHex`，其余与系统标签色同色系但由 App 定义，
    /// 保证侧栏与文件列表读到的是同一份 hex。
    static let paletteHexes: [String] = [
        "#0a84ff",  // 蓝（App 强调色）
        "#ff3b30",  // 红
        "#ff9500",  // 橙
        "#ffcc00",  // 黄
        "#34c759",  // 绿
        "#bf5af2",  // 紫
        "#ff2d55",  // 粉
        "#8e8e93",  // 灰
    ]

    /// 默认新标签色（色板第一项）
    static let defaultHex = paletteHexes[0]

    /// 旧版内置色 → 现行色板。
    /// v0.8 及之前侧栏内置标签用的是 iOS 色值，与文件里存的 hex 不是同一个来源；
    /// 这里把存量数据一次性归到现行色板，避免「同一个标签两种蓝」。
    private static let legacyMap: [String: String] = [
        "#007aff": "#0a84ff",  // 旧蓝 → App 强调色
        "#af52de": "#bf5af2",  // 旧紫
        "#5856d6": "#5e5ce6",  // 旧靛蓝
        "#ff9500": "#ff9500",
        "#8e8e93": "#8e8e93",
    ]

    /// 把任意来源的 hex 归一到现行色板（大小写不敏感）。未收录的原样返回。
    static func normalizedHex(_ hex: String) -> String {
        let key = hex.lowercased()
        return legacyMap[key] ?? hex
    }

    /// 色板对应的 NSColor 数组
    static var paletteColors: [NSColor] {
        paletteHexes.compactMap { NSColor(hex: $0) }
    }

    /// 把任意 NSColor 转成大写字 HEX（`#RRGGBB`），用于写进 `com.flowfinder.tags`
    static func hexString(from color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return defaultHex }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// 在某个视图下方弹出选色器。
    /// - Parameters:
    ///   - anchor: 弹层锚点视图（通常是点下去的色块/按钮）
    ///   - currentHex: 当前颜色，用于高亮
    ///   - onPick: 选中回调（回主线程），返回 `#RRGGBB`
    /// - Returns: 已展示的 popover，调用方如需可持有关闭
    @discardableResult
    static func present(from anchor: NSView,
                        currentHex: String,
                        onPick: @escaping (String) -> Void) -> NSPopover {
        let controller = FFTagPalettePopoverController(currentHex: currentHex, onPick: onPick)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 232, height: 128)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        return popover
    }
}

// MARK: - 弹层内容

/// 包装 macColorPicker 的 `ColorPickerViewController`：
/// 固定使用 App 色板 + 显示自定义色入口，选中后回调并关闭。
private final class FFTagPalettePopoverController: NSViewController, ColorPickerViewControllerDelegate {

    private let currentHex: String
    private let onPick: (String) -> Void
    private let picker = ColorPickerViewController()

    init(currentHex: String, onPick: @escaping (String) -> Void) {
        self.currentHex = currentHex
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("FFTagPalettePopoverController 不支持从 XIB/Storyboard 加载")
    }

    override func loadView() {
        // 宿主视图只做容器；真正的色块由 picker 铺满
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 232, height: 128))
        container.wantsLayer = true
        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // macColorPicker 的 `hideCustomColorButton` 命名与实际语义相反：
        // 为 true 时才显示「自定义颜色」按钮（见 numberOfSections 的实现）。
        // 这里要的正是「色板 + 任意色」，所以保持 true。
        picker.hideCustomColorButton = true
        picker.customColorButtonTitle = "自定义颜色…"
        picker.colors = FFTagColorPalette.paletteColors
        picker.selectedColor = NSColor(hex: currentHex)
        picker.colorCellCornerRadius = 5
        picker.delegate = self

        // 固定 7 列布局，与 232pt 宽度匹配
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 8, right: 0)
        picker.collectionViewLayout = layout

        addChild(picker)
        picker.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker.view)
        NSLayoutConstraint.activate([
            picker.view.topAnchor.constraint(equalTo: view.topAnchor),
            picker.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            picker.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            picker.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func didSelectColor(_ color: NSColor) {
        let hex = FFTagColorPalette.hexString(from: color)
        onPick(hex)
        // 瞬时弹层在点击外部才关；选完主动收起，避免挡住下一处操作
        DispatchQueue.main.async { [weak self] in
            self?.dismiss(nil)
        }
    }
}
