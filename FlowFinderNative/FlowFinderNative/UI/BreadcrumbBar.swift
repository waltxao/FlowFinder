import AppKit

protocol BreadcrumbBarDelegate: AnyObject {
    func breadcrumbBar(_ bar: BreadcrumbBar, didSelectPath path: String)
}

/// 路径面包屑导航栏
/// 显示当前路径，每段可点击跳转
class BreadcrumbBar: NSView {

    weak var delegate: BreadcrumbBarDelegate?

    private(set) var path: String = "" {
        didSet { updateBreadcrumbs() }
    }

    private let scrollView = NSScrollView()
    private let containerStackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        containerStackView.orientation = .horizontal
        containerStackView.spacing = 4
        containerStackView.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        containerStackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = containerStackView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerStackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
        ])
    }

    func setPath(_ path: String) {
        self.path = path
    }

    private func updateBreadcrumbs() {
        containerStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let components = path.split(separator: "/").map(String.init)
        var currentPath = ""

        for (index, component) in components.enumerated() {
            if index > 0 {
                currentPath += "/"
            }
            currentPath += component

            if index > 0 {
                let chevronImage = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
                let chevronImageView = NSImageView(image: chevronImage ?? NSImage())
                chevronImageView.contentTintColor = .secondaryLabelColor
                chevronImageView.translatesAutoresizingMaskIntoConstraints = false
                chevronImageView.widthAnchor.constraint(equalToConstant: 8).isActive = true
                chevronImageView.heightAnchor.constraint(equalToConstant: 8).isActive = true
                containerStackView.addArrangedSubview(chevronImageView)
            }

            let button = NSButton(title: component, target: self, action: #selector(pathClicked(_:)))
            button.bezelStyle = .inline
            button.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 20).isActive = true
            button.identifier = NSUserInterfaceItemIdentifier(currentPath)
            containerStackView.addArrangedSubview(button)
        }
    }

    @objc private func pathClicked(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        delegate?.breadcrumbBar(self, didSelectPath: path)
    }
}
