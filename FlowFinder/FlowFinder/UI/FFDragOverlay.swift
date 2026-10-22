import AppKit

/// 拖动期间的轻量反馈层：完整标签浮层 + 1px 落点描边。
/// 所有视图都是 frame-based，不参与 Auto Layout，拖动中只改 frame/opacity。
final class FFDragOverlay {

    private var ghostPanel: NSPanel?
    private var outlineView: NSView?

    func beginGhost(from item: NSView, at point: CGPoint, grabOffset: CGPoint) {
        guard let image = FFPaneDrag.snapshot(of: item,
                                              background: FFDesign.operationAreaBackground) else { return }
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: image.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0.55

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image
        panel.contentView = imageView
        panel.setFrameOrigin(NSPoint(x: point.x - grabOffset.x,
                                     y: point.y - grabOffset.y))
        ghostPanel = panel
        panel.orderFrontRegardless()
    }

    func moveGhost(to point: CGPoint, grabOffset: CGPoint) {
        ghostPanel?.setFrameOrigin(NSPoint(x: point.x - grabOffset.x,
                                           y: point.y - grabOffset.y))
    }

    func showOutline(rect: CGRect, in host: NSView) {
        let view: NSView
        if let outlineView {
            view = outlineView
        } else {
            view = NSView()
            view.wantsLayer = true
            view.layer?.borderWidth = 1
            view.layer?.cornerRadius = 8
            view.translatesAutoresizingMaskIntoConstraints = true
            outlineView = view
        }
        if view.superview !== host {
            view.removeFromSuperview()
            host.addSubview(view)
        }
        view.layer?.borderColor = FFAccent.current.cgColor
        view.frame = rect
        view.isHidden = false
    }

    func hideOutline() {
        outlineView?.isHidden = true
    }

    func end() {
        ghostPanel?.orderOut(nil)
        ghostPanel = nil
        outlineView?.removeFromSuperview()
        outlineView = nil
    }
}
