import AppKit

// Lucide 图标层。所有小图标从这里取，不再直接用 SF Symbol。
// 资源：Resources/Icons/<name>.svg（Lucide 0.544，ISC，见同目录 LICENSE-lucide.txt）
// 本文件由 scripts/gen-icon-names.py 生成，改图标请改资源后重跑脚本。

struct FFIconName: RawRepresentable, Hashable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

extension FFIconName {
    static let archive = FFIconName("archive")
    static let arrowDown = FFIconName("arrow-down")
    static let arrowDownAZ = FFIconName("arrow-down-a-z")
    static let arrowLeft = FFIconName("arrow-left")
    static let arrowRight = FFIconName("arrow-right")
    static let arrowUp = FFIconName("arrow-up")
    static let arrowUpAZ = FFIconName("arrow-up-a-z")
    static let arrowUpDown = FFIconName("arrow-up-down")
    static let box = FFIconName("box")
    static let check = FFIconName("check")
    static let chevronDown = FFIconName("chevron-down")
    static let chevronLeft = FFIconName("chevron-left")
    static let chevronRight = FFIconName("chevron-right")
    static let chevronUp = FFIconName("chevron-up")
    static let chevronsUpDown = FFIconName("chevrons-up-down")
    static let circleAlert = FFIconName("circle-alert")
    static let circleCheck = FFIconName("circle-check")
    static let circleDot = FFIconName("circle-dot")
    static let circleHelp = FFIconName("circle-help")
    static let circleX = FFIconName("circle-x")
    static let clipboard = FFIconName("clipboard")
    static let clipboardPaste = FFIconName("clipboard-paste")
    static let cloud = FFIconName("cloud")
    static let code = FFIconName("code")
    static let columns2 = FFIconName("columns-2")
    static let columns3 = FFIconName("columns-3")
    static let compass = FFIconName("compass")
    static let copy = FFIconName("copy")
    static let database = FFIconName("database")
    static let download = FFIconName("download")
    static let ellipsis = FFIconName("ellipsis")
    static let ellipsisVertical = FFIconName("ellipsis-vertical")
    static let externalLink = FFIconName("external-link")
    static let eye = FFIconName("eye")
    static let eyeOff = FFIconName("eye-off")
    static let file = FFIconName("file")
    static let fileArchive = FFIconName("file-archive")
    static let fileAudio = FFIconName("file-audio")
    static let fileCode = FFIconName("file-code")
    static let fileImage = FFIconName("file-image")
    static let fileSpreadsheet = FFIconName("file-spreadsheet")
    static let fileText = FFIconName("file-text")
    static let fileType = FFIconName("file-type")
    static let fileVideo = FFIconName("file-video")
    static let film = FFIconName("film")
    static let folder = FFIconName("folder")
    static let folderOpen = FFIconName("folder-open")
    static let folderPlus = FFIconName("folder-plus")
    static let folderTree = FFIconName("folder-tree")
    static let grid2x2 = FFIconName("grid-2x2")
    static let hardDrive = FFIconName("hard-drive")
    static let image = FFIconName("image")
    static let info = FFIconName("info")
    static let layers = FFIconName("layers")
    static let layoutGrid = FFIconName("layout-grid")
    static let link = FFIconName("link")
    static let link2 = FFIconName("link-2")
    static let list = FFIconName("list")
    static let listChecks = FFIconName("list-checks")
    static let loaderCircle = FFIconName("loader-circle")
    static let maximize = FFIconName("maximize")
    static let minimize = FFIconName("minimize")
    static let minus = FFIconName("minus")
    static let monitor = FFIconName("monitor")
    static let moon = FFIconName("moon")
    static let music = FFIconName("music")
    static let network = FFIconName("network")
    static let palette = FFIconName("palette")
    static let panelLeft = FFIconName("panel-left")
    static let panelLeftClose = FFIconName("panel-left-close")
    static let panelLeftOpen = FFIconName("panel-left-open")
    static let panelRight = FFIconName("panel-right")
    static let panelTop = FFIconName("panel-top")
    static let penLine = FFIconName("pen-line")
    static let pencil = FFIconName("pencil")
    static let plus = FFIconName("plus")
    static let presentation = FFIconName("presentation")
    static let redo2 = FFIconName("redo-2")
    static let refreshCw = FFIconName("refresh-cw")
    static let replace = FFIconName("replace")
    static let rotateCcw = FFIconName("rotate-ccw")
    static let rotateCw = FFIconName("rotate-cw")
    static let rows3 = FFIconName("rows-3")
    static let scanSearch = FFIconName("scan-search")
    static let scissors = FFIconName("scissors")
    static let search = FFIconName("search")
    static let server = FFIconName("server")
    static let settings = FFIconName("settings")
    static let sparkles = FFIconName("sparkles")
    static let square = FFIconName("square")
    static let squareSplitHorizontal = FFIconName("square-split-horizontal")
    static let star = FFIconName("star")
    static let sun = FFIconName("sun")
    static let tag = FFIconName("tag")
    static let tags = FFIconName("tags")
    static let terminal = FFIconName("terminal")
    static let trash2 = FFIconName("trash-2")
    static let triangleAlert = FFIconName("triangle-alert")
    static let type = FFIconName("type")
    static let undo2 = FFIconName("undo-2")
    static let upload = FFIconName("upload")
    static let wandSparkles = FFIconName("wand-sparkles")
    static let wifiOff = FFIconName("wifi-off")
    static let wrench = FFIconName("wrench")
    static let x = FFIconName("x")
}

enum FFIconStyle {
    /// 纯描边，最常用
    case line
    /// 18% 填色 + 描边，用于文件类型与文件夹
    case duotone
}

/// 图标来源（2026-10-21 用户确认混合方案）：
/// 系统 chrome 用 SF Symbols，文件类型/文件夹/标签用 Phosphor（MIT）。
enum FFIconBackend: Equatable {
    case sfSymbol(String)
    case phosphor(String)
}

enum FFIconResolver {
    static let backends: [FFIconName: FFIconBackend] = [
        .archive: .phosphor("archive"),
        .arrowDown: .sfSymbol("arrow.down"),
        .arrowDownAZ: .sfSymbol("arrow.down.to.line"),
        .arrowLeft: .sfSymbol("arrow.left"),
        .arrowRight: .sfSymbol("arrow.right"),
        .arrowUp: .sfSymbol("arrow.up"),
        .arrowUpAZ: .sfSymbol("arrow.up.to.line"),
        .arrowUpDown: .sfSymbol("arrow.up.arrow.down"),
        .box: .sfSymbol("shippingbox"),
        .check: .sfSymbol("checkmark"),
        .chevronDown: .sfSymbol("chevron.down"),
        .chevronLeft: .sfSymbol("chevron.left"),
        .chevronRight: .sfSymbol("chevron.right"),
        .chevronUp: .sfSymbol("chevron.up"),
        .chevronsUpDown: .sfSymbol("chevron.up.chevron.down"),
        .circleAlert: .sfSymbol("exclamationmark.circle"),
        .circleCheck: .sfSymbol("checkmark.circle"),
        .circleDot: .sfSymbol("circle.inset.filled"),
        .circleHelp: .sfSymbol("questionmark.circle"),
        .circleX: .sfSymbol("xmark.circle"),
        .clipboard: .sfSymbol("doc.on.clipboard"),
        .clipboardPaste: .sfSymbol("doc.on.clipboard"),
        .cloud: .sfSymbol("cloud"),
        .code: .sfSymbol("chevron.left.forwardslash.chevron.right"),
        .columns2: .sfSymbol("rectangle.split.2x1"),
        .columns3: .sfSymbol("rectangle.split.3x1"),
        .compass: .sfSymbol("location.north.circle"),
        .copy: .sfSymbol("doc.on.doc"),
        .database: .sfSymbol("cylinder.split.1x2"),
        .download: .sfSymbol("arrow.down.circle"),
        .ellipsis: .sfSymbol("ellipsis"),
        .ellipsisVertical: .sfSymbol("ellipsis"),
        .externalLink: .sfSymbol("arrow.up.right.square"),
        .eye: .sfSymbol("eye"),
        .eyeOff: .sfSymbol("eye.slash"),
        .file: .phosphor("file"),
        .fileArchive: .phosphor("file-zip"),
        .fileAudio: .phosphor("file-audio"),
        .fileCode: .phosphor("file-code"),
        .fileImage: .phosphor("file-image"),
        .fileSpreadsheet: .phosphor("file-xls"),
        .fileText: .phosphor("file-text"),
        .fileType: .phosphor("file"),
        .fileVideo: .phosphor("file-video"),
        .film: .sfSymbol("film"),
        .folder: .phosphor("folder"),
        .folderOpen: .phosphor("folder-open"),
        .folderPlus: .phosphor("folder-plus"),
        .folderTree: .sfSymbol("list.bullet.indent"),
        .grid2x2: .sfSymbol("square.grid.2x2"),
        .hardDrive: .sfSymbol("internaldrive"),
        .image: .sfSymbol("photo"),
        .info: .sfSymbol("info.circle"),
        .layers: .sfSymbol("square.3.layers.3d"),
        .layoutGrid: .sfSymbol("square.grid.2x2"),
        .link: .sfSymbol("link"),
        .link2: .sfSymbol("link"),
        .list: .sfSymbol("list.bullet"),
        .listChecks: .sfSymbol("checklist"),
        .loaderCircle: .sfSymbol("arrow.triangle.2.circlepath"),
        .maximize: .sfSymbol("arrow.up.left.and.arrow.down.right"),
        .minimize: .sfSymbol("arrow.down.right.and.arrow.up.left"),
        .minus: .sfSymbol("minus"),
        .monitor: .sfSymbol("display"),
        .moon: .sfSymbol("moon"),
        .music: .sfSymbol("music.note"),
        .network: .sfSymbol("network"),
        .palette: .sfSymbol("paintpalette"),
        .panelLeft: .sfSymbol("sidebar.left"),
        .panelLeftClose: .sfSymbol("sidebar.leading"),
        .panelLeftOpen: .sfSymbol("sidebar.leading"),
        .panelRight: .sfSymbol("sidebar.right"),
        .panelTop: .sfSymbol("menubar.rectangle"),
        .penLine: .sfSymbol("pencil"),
        .pencil: .sfSymbol("pencil"),
        .plus: .sfSymbol("plus"),
        .presentation: .sfSymbol("rectangle.on.rectangle"),
        .redo2: .sfSymbol("arrow.uturn.forward"),
        .refreshCw: .sfSymbol("arrow.clockwise"),
        .replace: .sfSymbol("arrow.left.arrow.right"),
        .rotateCcw: .sfSymbol("arrow.counterclockwise"),
        .rotateCw: .sfSymbol("arrow.clockwise"),
        .rows3: .sfSymbol("rectangle.grid.1x2"),
        .scanSearch: .sfSymbol("doc.text.magnifyingglass"),
        .scissors: .sfSymbol("scissors"),
        .search: .sfSymbol("magnifyingglass"),
        .server: .sfSymbol("server.rack"),
        .settings: .sfSymbol("gearshape"),
        .sparkles: .sfSymbol("sparkles"),
        .square: .sfSymbol("square"),
        .squareSplitHorizontal: .sfSymbol("rectangle.split.1x2"),
        .star: .sfSymbol("star"),
        .sun: .sfSymbol("sun.max"),
        .tag: .sfSymbol("tag"),
        .tags: .sfSymbol("tag.fill"),
        .terminal: .sfSymbol("terminal"),
        .trash2: .sfSymbol("trash"),
        .triangleAlert: .sfSymbol("exclamationmark.triangle"),
        .type: .sfSymbol("textformat"),
        .undo2: .sfSymbol("arrow.uturn.backward"),
        .upload: .sfSymbol("arrow.up.circle"),
        .wandSparkles: .sfSymbol("wand.and.stars"),
        .wifiOff: .sfSymbol("wifi.slash"),
        .wrench: .sfSymbol("wrench.and.screwdriver"),
        .x: .sfSymbol("xmark"),
    ]

    static func backend(for name: FFIconName) -> FFIconBackend {
        backends[name] ?? .sfSymbol("questionmark.square.dashed")
    }

    static var unmappedNames: [FFIconName] {
        FFIconName.allCases.filter { backends[$0] == nil }
    }
}

enum FFIcon {
    enum Metrics {
        static let toolbar: CGFloat = 15
        static let inline: CGFloat = 13
        static let menu: CGFloat = 16
        static let list: CGFloat = 18
    }

    private static let lock = NSLock()
    private static var imageCache: [String: NSImage] = [:]
    private static var svgCache: [String: String] = [:]

    /// 模板图（跟随控件 tint / 深浅色自动反色）。按钮、菜单项优先用这个。
    static func template(_ name: FFIconName, size: CGFloat = Metrics.toolbar) -> NSImage {
        switch FFIconResolver.backend(for: name) {
        case .sfSymbol(let symbol):
            return symbolImage(symbol, size: size, color: nil, duotone: false, isTemplate: true)
        case .phosphor(let phosphor):
            return phosphorImage(phosphor, size: size, hex: "000000", duotone: false, isTemplate: true)
        }
    }

    /// 指定颜色的实色图，用于文件类型、文件夹、彩色标签等需要固定色的场景。
    static func image(_ name: FFIconName,
                      size: CGFloat = Metrics.toolbar,
                      color: NSColor = .labelColor,
                      style: FFIconStyle = .line) -> NSImage {
        switch FFIconResolver.backend(for: name) {
        case .sfSymbol(let symbol):
            return symbolImage(symbol,
                               size: size,
                               color: color,
                               duotone: style == .duotone,
                               isTemplate: false)
        case .phosphor(let phosphor):
            return phosphorImage(phosphor,
                                 size: size,
                                 hex: color.ffHexString,
                                 duotone: style == .duotone,
                                 isTemplate: false)
        }
    }

    /// 资源自检：返回 Phosphor SVG 缺失的图标名
    static func missingAssets() -> [String] {
        FFIconName.allCases.compactMap { name in
            guard case .phosphor(let phosphor) = FFIconResolver.backend(for: name) else { return nil }
            let hasRegular = rawPhosphor(phosphor, duotone: false) != nil
            let hasDuotone = rawPhosphor(phosphor, duotone: true) != nil
            return hasRegular && hasDuotone ? nil : name.rawValue
        }
    }

    /// SF Symbols 自检：返回当前系统不存在的符号名
    static func missingSymbols() -> [String] {
        FFIconName.allCases.compactMap { name in
            guard case .sfSymbol(let symbol) = FFIconResolver.backend(for: name) else { return nil }
            return NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? symbol : nil
        }
    }

    private static func symbolImage(_ name: String,
                                    size: CGFloat,
                                    color: NSColor?,
                                    duotone: Bool,
                                    isTemplate: Bool) -> NSImage {
        let key = "sf|\(name)|\(size)|\(color?.ffHexString ?? "t")|\(duotone)|\(isTemplate)"
        lock.lock()
        if let hit = imageCache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        var config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        if !isTemplate, let color {
            let colors = duotone ? [color, color.withAlphaComponent(0.2)] : [color]
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: colors))
        }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            NSLog("[FFIcon] 缺少 SF Symbol: %@", name)
            return NSImage(size: NSSize(width: size, height: size))
        }
        image.isTemplate = isTemplate
        lock.lock()
        imageCache[key] = image
        lock.unlock()
        return image
    }

    private static func phosphorImage(_ name: String,
                                      size: CGFloat,
                                      hex: String,
                                      duotone: Bool,
                                      isTemplate: Bool) -> NSImage {
        let key = "p|\(name)|\(size)|\(hex)|\(duotone)|\(isTemplate)"
        lock.lock()
        if let hit = imageCache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard var svg = rawPhosphor(name, duotone: duotone) else {
            NSLog("[FFIcon] 缺少 Phosphor 图标: %@ (%@)", name, duotone ? "duotone" : "regular")
            return symbolImage("questionmark.square.dashed",
                               size: size,
                               color: isTemplate ? nil : NSColor.labelColor,
                               duotone: false,
                               isTemplate: isTemplate)
        }
        svg = svg.replacingOccurrences(of: "currentColor", with: "#\(hex)")
        guard let data = svg.data(using: .utf8), let image = NSImage(data: data) else {
            NSLog("[FFIcon] Phosphor 图标解析失败: %@", name)
            return NSImage(size: NSSize(width: size, height: size))
        }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = isTemplate
        lock.lock()
        imageCache[key] = image
        lock.unlock()
        return image
    }

    private static func rawPhosphor(_ name: String, duotone: Bool) -> String? {
        let variant = duotone ? "duotone" : "regular"
        let resourceName = duotone ? "\(name)-duotone" : name
        let key = "phosphor/\(variant)/\(name)"
        lock.lock()
        if let hit = svgCache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let url = Bundle.main.url(forResource: resourceName,
                                        withExtension: "svg",
                                        subdirectory: "Icons/Phosphor/\(variant)"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        lock.lock()
        svgCache[key] = text
        lock.unlock()
        return text
    }
}

extension NSColor {
    /// "0a84ff" 形式（不带 #），供 SVG 染色使用
    var ffHexString: String {
        let c = usingColorSpace(.sRGB) ?? NSColor.black
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "%02x%02x%02x", r, g, b)
    }
}

extension FFIconName {
    static let allCases: [FFIconName] = [.archive, .arrowDown, .arrowDownAZ, .arrowLeft, .arrowRight, .arrowUp, .arrowUpAZ, .arrowUpDown, .box, .check, .chevronDown, .chevronLeft, .chevronRight, .chevronUp, .chevronsUpDown, .circleAlert, .circleCheck, .circleDot, .circleHelp, .circleX, .clipboard, .clipboardPaste, .cloud, .code, .columns2, .columns3, .compass, .copy, .database, .download, .ellipsis, .ellipsisVertical, .externalLink, .eye, .eyeOff, .file, .fileArchive, .fileAudio, .fileCode, .fileImage, .fileSpreadsheet, .fileText, .fileType, .fileVideo, .film, .folder, .folderOpen, .folderPlus, .folderTree, .grid2x2, .hardDrive, .image, .info, .layers, .layoutGrid, .link, .link2, .list, .listChecks, .loaderCircle, .maximize, .minimize, .minus, .monitor, .moon, .music, .network, .palette, .panelLeft, .panelLeftClose, .panelLeftOpen, .panelRight, .panelTop, .penLine, .pencil, .plus, .presentation, .redo2, .refreshCw, .replace, .rotateCcw, .rotateCw, .rows3, .scanSearch, .scissors, .search, .server, .settings, .sparkles, .square, .squareSplitHorizontal, .star, .sun, .tag, .tags, .terminal, .trash2, .triangleAlert, .type, .undo2, .upload, .wandSparkles, .wifiOff, .wrench, .x]
}

extension NSButton {
    /// 统一的按钮图标设置：模板图 + 只显示图
    func ffIcon(_ name: FFIconName, size: CGFloat = FFIcon.Metrics.toolbar) {
        image = FFIcon.template(name, size: size)
        imagePosition = .imageOnly
    }
}
