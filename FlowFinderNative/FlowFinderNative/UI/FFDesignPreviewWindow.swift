#if DEBUG
import AppKit

// MARK: - 设计系统预览窗口（仅 Debug 构建）
//
// 用途：在把新设计语言铺到主窗口之前，先让设计决策可被肉眼验收。
// Release 构建不编译本文件，因此不会进入发行包。
//
// 入口：菜单「窗口 → 设计系统预览」(⌥⌘D)

final class FFDesignPreviewWindowController: NSWindowController {

    static let shared = FFDesignPreviewWindowController()

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "设计系统预览"
        window.titlebarAppearsTransparent = true
        window.center()
        self.init(window: window)
        window.contentView = makeContentView()
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 内容

    private func makeContentView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = FFDesign.Color.window.cgColor

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = FFDesign.Spacing.x5
        stack.edgeInsets = NSEdgeInsets(top: FFDesign.Spacing.x5,
                                        left: FFDesign.Spacing.x5,
                                        bottom: FFDesign.Spacing.x5,
                                        right: FFDesign.Spacing.x5)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(sectionTitle("① 独立面板 + 4pt 间隙（布局模型）"))
        stack.addArrangedSubview(makePanelLayoutDemo())

        stack.addArrangedSubview(sectionTitle("② 颜色令牌（自动跟随深浅色）"))
        stack.addArrangedSubview(makeColorSwatches())

        stack.addArrangedSubview(sectionTitle("③ 字体层级（正文基准 13pt）"))
        stack.addArrangedSubview(makeTypographyDemo())

        stack.addArrangedSubview(sectionTitle("④ 侧栏行状态：常态 / 悬停 / 选中"))
        stack.addArrangedSubview(makeRowStatesDemo())

        stack.addArrangedSubview(sectionTitle("⑤ 空态"))
        let empty = FFEmptyStateView(
            symbolName: "folder.badge.plus",
            title: "还没有收藏",
            subtitle: "把文件夹拖到侧边栏即可添加",
            actionTitle: "选择文件夹",
            action: nil
        )
        empty.translatesAutoresizingMaskIntoConstraints = false
        empty.widthAnchor.constraint(equalToConstant: 640).isActive = true
        empty.heightAnchor.constraint(equalToConstant: 140).isActive = true
        stack.addArrangedSubview(empty)

        scroll.documentView = stack
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])
        return root
    }

    private func sectionTitle(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = FFDesign.Text.lg
        label.textColor = FFDesign.Color.textPrimary
        return label
    }

    /// 布局模型演示：窗口底 + 三块独立面板 + 4pt 间隙
    private func makePanelLayoutDemo() -> NSView {
        let container = FFPanelView(tone: .panel)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: 640).isActive = true
        container.heightAnchor.constraint(equalToConstant: 180).isActive = true

        let sidebar = FFPanelView(tone: .sidebar)
        let main = FFPanelView(tone: .header)
        let detail = FFPanelView(tone: .card)

        for (panel, title) in [(sidebar, "侧栏"), (main, "文件列表"), (detail, "详情")] {
            panel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(panel)
            let label = NSTextField(labelWithString: title)
            label.font = FFDesign.Text.caption
            label.textColor = FFDesign.Color.textTertiary
            label.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            ])
        }

        let gap = FFDesign.Layout.panelGap
        let inset = FFDesign.Layout.windowInset
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            sidebar.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            sidebar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
            sidebar.widthAnchor.constraint(equalToConstant: 140),

            main.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: gap),
            main.topAnchor.constraint(equalTo: sidebar.topAnchor),
            main.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),

            detail.leadingAnchor.constraint(equalTo: main.trailingAnchor, constant: gap),
            detail.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            detail.topAnchor.constraint(equalTo: sidebar.topAnchor),
            detail.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            detail.widthAnchor.constraint(equalToConstant: 160),
        ])
        return container
    }

    /// 颜色令牌色板
    private func makeColorSwatches() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = FFDesign.Spacing.x2
        row.alignment = .top

        let tokens: [(String, NSColor)] = [
            ("window", FFDesign.Color.window),
            ("panel", FFDesign.Color.panel),
            ("sidebar", FFDesign.Color.sidebar),
            ("header", FFDesign.Color.header),
            ("card", FFDesign.Color.card),
            ("border", FFDesign.Color.border),
            ("hover", FFDesign.Color.rowHover),
            ("selected", FFDesign.Color.rowSelected),
            ("text1", FFDesign.Color.textPrimary),
            ("text2", FFDesign.Color.textSecondary),
            ("text3", FFDesign.Color.textTertiary),
        ]

        for (name, color) in tokens {
            let box = NSView()
            box.wantsLayer = true
            box.layer?.backgroundColor = color.cgColor
            box.layer?.cornerRadius = FFDesign.Radius.md
            box.layer?.borderWidth = 1
            box.layer?.borderColor = FFDesign.Color.border.cgColor
            box.translatesAutoresizingMaskIntoConstraints = false
            box.widthAnchor.constraint(equalToConstant: 48).isActive = true
            box.heightAnchor.constraint(equalToConstant: 40).isActive = true

            let label = NSTextField(labelWithString: name)
            label.font = FFDesign.Text.xs
            label.textColor = FFDesign.Color.textTertiary

            let col = NSStackView(views: [box, label])
            col.orientation = .vertical
            col.spacing = FFDesign.Spacing.x1
            col.alignment = .centerX
            row.addArrangedSubview(col)
        }
        return row
    }

    /// 字体层级
    private func makeTypographyDemo() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = FFDesign.Spacing.x2

        let samples: [(String, String, NSFont)] = [
            ("xl 17 semibold", "空态标题 / 引导页", FFDesign.Text.xl),
            ("lg 15 semibold", "分区标题 / 详情栏文件名", FFDesign.Text.lg),
            ("base 13", "正文、文件名、按钮", FFDesign.Text.base),
            ("baseEmphasis 13 medium", "选中项、当前分区", FFDesign.Text.baseEmphasis),
            ("caption 12", "次要说明、路径", FFDesign.Text.caption),
            ("sm 11", "辅助信息、tooltip", FFDesign.Text.sm),
            ("xs 10", "徽标 / 计数 / 快捷键", FFDesign.Text.xs),
            ("mono 12", "/Users/waltxao/Desktop/report.pdf", FFDesign.Text.mono),
        ]
        for (token, desc, font) in samples {
            let line = NSStackView()
            line.orientation = .horizontal
            line.spacing = FFDesign.Spacing.x3
            let tag = NSTextField(labelWithString: token)
            tag.font = FFDesign.Text.xs
            tag.textColor = FFDesign.Color.textTertiary
            tag.translatesAutoresizingMaskIntoConstraints = false
            tag.widthAnchor.constraint(equalToConstant: 170).isActive = true
            let sample = NSTextField(labelWithString: desc)
            sample.font = font
            sample.textColor = FFDesign.Color.textPrimary
            line.addArrangedSubview(tag)
            line.addArrangedSubview(sample)
            stack.addArrangedSubview(line)
        }
        return stack
    }

    /// 侧栏行三态
    private func makeRowStatesDemo() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = FFDesign.Spacing.x1
        stack.alignment = .leading

        for (state, bg, accent) in [
            ("常态", NSColor.clear, false),
            ("悬停", FFDesign.Color.rowHover, false),
            ("选中", FFDesign.Color.rowSelected, true),
        ] {
            let row = NSView()
            row.wantsLayer = true
            row.layer?.backgroundColor = bg.cgColor
            row.layer?.cornerRadius = FFDesign.Radius.md
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 320).isActive = true
            row.heightAnchor.constraint(equalToConstant: 28).isActive = true

            if accent {
                let bar = NSView()
                bar.wantsLayer = true
                bar.layer?.backgroundColor = FFDesign.Color.textPrimary.cgColor
                bar.layer?.cornerRadius = 1
                bar.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(bar)
                NSLayoutConstraint.activate([
                    bar.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 2),
                    bar.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                    bar.widthAnchor.constraint(equalToConstant: 2),
                    bar.heightAnchor.constraint(equalToConstant: 14),
                ])
            }

            let icon = NSImageView(image: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = FFDesign.Color.textSecondary
            icon.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(icon)

            let label = NSTextField(labelWithString: state)
            label.font = accent ? FFDesign.Text.baseEmphasis : FFDesign.Text.base
            label.textColor = FFDesign.Color.textPrimary
            label.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(label)

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: FFDesign.Spacing.x2 + (accent ? 2 : 0)),
                icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: FFDesign.Spacing.x2),
                label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ])
            stack.addArrangedSubview(row)
        }
        return stack
    }
}
#endif
