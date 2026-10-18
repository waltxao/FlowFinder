import AppKit

/// 标准位置专属彩色图标（DESIGN-SPEC §5.1 / B-06）
///
/// 系统 `NSWorkspace.icon(forFile:)` 对桌面 / 文稿 / 下载 / 应用程序返回的是
/// 「蓝色文件夹 + 淡色内嵌符号」，在 20pt 下内嵌符号几乎不可见，多个标准位置
/// 看起来完全一样。本类型对标准位置改用「语义色圆角容器 + 白色符号」的合成图标，
/// 保证一眼可区分；非标准位置返回 nil，由调用方回退到真实文件图标（B-05）。
enum FFStandardLocationIcon {

    /// 侧栏图标边长（与 B-05 的 20pt 一致）
    static let side: CGFloat = 20

    // MARK: - 规格

    struct Spec: Equatable {
        /// SF Symbol 名
        let symbol: String
        /// 容器填充色（语义色，不随深浅色反转，与访达的彩色位置图标一致）
        let color: NSColor
    }

    /// 标准位置 → 图标规格。路径均为标准化后的绝对路径。
    /// 顺序无关：一律按标准化路径做全等比对，不做前缀匹配（避免 ~/Desktop2 误命中）。
    private static func specs() -> [(path: String, spec: Spec)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        return [
            (normalize("\(home)/Desktop"), Spec(symbol: "display", color: color("#4A90D9"))),
            (normalize("\(home)/Documents"), Spec(symbol: "doc.text", color: color("#5B7FB8"))),
            (normalize("\(home)/Downloads"), Spec(symbol: "arrow.down", color: color("#3E9BC4"))),
            (normalize("/Applications"), Spec(symbol: "square.grid.2x2.fill", color: color("#7E6BC4"))),
            (normalize("\(home)/Pictures"), Spec(symbol: "photo", color: color("#E0A33A"))),
            (normalize("\(home)/Movies"), Spec(symbol: "film", color: color("#D4683C"))),
            (normalize("\(home)/Music"), Spec(symbol: "music.note", color: color("#C2564E"))),
            (normalize(home), Spec(symbol: "house", color: color("#4A90D9"))),
        ]
    }

    /// NSColor(hex:) 为可失败构造，此处给出确定回退色（蓝），避免规格表变成 optional
    private static func color(_ hex: String) -> NSColor {
        NSColor(hex: hex) ?? .systemBlue
    }

    /// 命中标准位置则返回规格，否则 nil
    static func spec(forPath path: String) -> Spec? {
        guard !path.isEmpty else { return nil }
        let normalized = normalize(path)
        for entry in specs() where entry.path == normalized {
            return entry.spec
        }
        return nil
    }

    /// 路径标准化：展开 ~、去掉尾斜杠、解析符号链接（/Applications 可能指向其他卷）
    private static func normalize(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let standardized = (expanded as NSString).standardizingPath
        // 标准位置通常是真实目录，解析符号链接可覆盖 /Applications 被替换的情况；
        // 解析失败时退回标准化结果
        let resolved = URL(fileURLWithPath: standardized).resolvingSymlinksInPath().path
        return resolved.isEmpty ? standardized : resolved
    }

    // MARK: - 缓存

    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        return c
    }()

    // MARK: - 生成

    /// 返回标准位置的专属彩色图标；非标准位置返回 nil（调用方应回退到真实图标）
    static func icon(forPath path: String) -> NSImage? {
        guard let spec = spec(forPath: path) else { return nil }
        let key = normalize(path) as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let image = makeIcon(spec: spec, side: side)
        cache.setObject(image, forKey: key)
        return image
    }

    /// 矢量绘制：drawingHandler 在每次实际渲染时按目标缩放调用，Retina 下自动清晰。
    /// 容器 20pt 内缩 1pt（18×18 实心块），圆角 4pt（DESIGN-SPEC §5.1）。
    static func makeIcon(spec: Spec, side: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let inset: CGFloat = side * 0.05
            let container = rect.insetBy(dx: inset, dy: inset)
            let radius = side * 0.2

            let background = NSBezierPath(roundedRect: container, xRadius: radius, yRadius: radius)
            spec.color.setFill()
            background.fill()

            // 符号白色：用 paletteColors 而非 template，避免依赖绘制上下文当前色
            let pointSize = container.width * 0.62
            let base = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            let white = NSImage.SymbolConfiguration(paletteColors: [.white])
            guard let symbol = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(base.applying(white)) else {
                return true
            }

            // 按符号实际比例缩放到容器的 56%，避免宽符号（如 display）溢出容器
            let maxSide = container.width * 0.56
            let size = symbol.size
            let scale = min(maxSide / max(size.width, 0.001), maxSide / max(size.height, 0.001))
            let drawSize = NSSize(width: size.width * scale, height: size.height * scale)
            let target = NSRect(
                x: container.midX - drawSize.width / 2,
                y: container.midY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            symbol.draw(in: target)
            return true
        }
        image.isTemplate = false
        return image
    }
}
