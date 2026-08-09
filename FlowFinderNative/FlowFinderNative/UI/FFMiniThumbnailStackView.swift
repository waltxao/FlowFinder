import Cocoa

// MARK: - FFMouseInterceptorView

/// 鼠标拦截视图：覆盖在详情栏玻璃背景上方，确保所有落到详情栏区域的鼠标事件
/// 都被本视图消费（mouseDown/ mouseMoved 等返回空实现），不再穿透到下层的文件列表。
///
/// 关键点：
/// 1. NSView 默认 `mouseDown` 会把事件继续传递给下一 responder（通常父 view），
///    最终可能到达窗口的其他兄弟视图（包括下层的文件列表）——这是穿透根因。
///    本类重写 mouse 事件为空实现，主动「吃掉」事件，终止传递。
/// 2. 子视图（详情栏内的图标、标签等控件）的 hitTest 优先级高于父视图，
///    鼠标落在控件上时仍返回控件，本拦截器只兜底"控件之间的空白区域"。
/// E4: 从 ExpandableDetailsBar.swift 拆出（internal 供同 module 使用方访问）。
final class FFMouseInterceptorView: NSView {
    override func mouseDown(with event: NSEvent) { }
    override func mouseUp(with event: NSEvent) { }
    override func mouseDragged(with event: NSEvent) { }
    override func mouseMoved(with event: NSEvent) { }
    override func rightMouseDown(with event: NSEvent) { }
    override func rightMouseUp(with event: NSEvent) { }
    override func rightMouseDragged(with event: NSEvent) { }
}

// MARK: - FFMiniThumbnailStackView（v0.7.4 修订 4：多选缩略图堆叠图标）

/// 多选时的大图标：仿访达的缩略图堆叠效果。
/// 取选中项的前 4 个，每个生成小缩略图（64pt），后一张向右下偏移 20pt 层叠，
/// 形成"多选"的视觉暗示。图片不足 4 个时按实际数量堆叠；异步加载完成回调刷新。
final class FFMiniThumbnailStackView: NSView {

    private var thumbnails: [NSImage?] = []
    /// 当前显示的路径（避免过期回调覆盖）
    private var displayPaths: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    /// 更新堆叠内容（传入选中项的 FileEntry，取前几个生成缩略图）
    func update(with entries: [FileEntry]) {
        // 清理旧状态
        displayPaths = entries.map { $0.path }
        thumbnails = Array(repeating: nil, count: entries.count)
        needsDisplay = true

        // 为每个条目异步生成缩略图（小尺寸，最多 4 个）
        for (i, entry) in entries.prefix(4).enumerated() {
            let path = entry.path
            ThumbnailManager.shared.generateThumbnail(path: path, size: CGSize(width: 64, height: 64)) { [weak self] image in
                guard let self = self, let image = image else { return }
                // 校验仍显示同一批条目（避免过期回调覆盖）
                guard i < self.displayPaths.count, self.displayPaths[i] == path else { return }
                self.thumbnails[i] = image
                self.needsDisplay = true
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 堆叠绘制：每张图 64pt，后一张向右下偏移 20pt
        let thumbSize: CGFloat = 64
        let offset: CGFloat = 20
        let maxCount = min(thumbnails.count, 4)

        // 第一张（最底）从 (0, 高-64) 开始，后一张依次向右下偏移
        let startX: CGFloat = 0
        let startY: CGFloat = bounds.height - thumbSize

        for i in 0..<maxCount {
            let x = startX + CGFloat(i) * offset
            let y = startY - CGFloat(i) * offset
            let rect = NSRect(x: x, y: y, width: thumbSize, height: thumbSize)

            if let img = thumbnails[i] {
                // 有缩略图：绘制（带轻微阴影和圆角边框，突出层叠）
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
                shadow.shadowBlurRadius = 2
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                NSGraphicsContext.saveGraphicsState()
                shadow.set()
                img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
                NSGraphicsContext.restoreGraphicsState()
                // 圆角边框
                let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
                NSColor.separatorColor.setStroke()
                border.lineWidth = 0.5
                border.stroke()
            } else {
                // 缩略图未就绪：画浅色占位
                let placeholder = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                NSColor.quaternaryLabelColor.withAlphaComponent(0.15).setFill()
                placeholder.fill()
                let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
                NSColor.separatorColor.setStroke()
                border.lineWidth = 0.5
                border.stroke()
            }
        }
    }
}
