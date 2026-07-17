import Cocoa
import QuickLook

// MARK: - QuickLook Preview Panel

/// QuickLook preview panel using macOS QLPreviewPanel API
public class QuickLookPreviewPanel: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {

    public static let shared = QuickLookPreviewPanel()

    private var previewItems: [QLPreviewItem] = []
    private var currentPath: String?

    private override init() {
        super.init()
    }

    /// Show QuickLook preview for a file path
    /// - Parameter path: File path to preview
    public func showPreview(for path: String) {
        currentPath = path
        previewItems = [QLPreviewItem(url: URL(fileURLWithPath: path))]

        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = self
            panel.delegate = self
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Toggle QuickLook preview panel visibility
    public func togglePreview(for path: String) {
        if let panel = QLPreviewPanel.shared() {
            if panel.isVisible {
                panel.orderOut(nil)
            } else {
                showPreview(for: path)
            }
        }
    }

    /// Close the preview panel
    public func closePreview() {
        if let panel = QLPreviewPanel.shared() {
            panel.orderOut(nil)
        }
    }

    // MARK: - QLPreviewPanelDataSource

    public func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        return previewItems.count
    }

    public func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        return previewItems[index]
    }

    // MARK: - QLPreviewPanelDelegate

    public func previewPanel(_ panel: QLPreviewPanel, sourceFrameOnScreenFor item: QLPreviewItem) -> NSRect {
        return .zero
    }

    public func previewPanel(_ panel: QLPreviewPanel, transitionImageFor item: QLPreviewItem, contentRect: UnsafeMutablePointer<NSRect>) -> Any? {
        return nil
    }
}

// MARK: - QuickLook Preview Sidebar

/// Sidebar view for QuickLook preview with toggle functionality
public class QuickLookPreviewSidebar: NSView {

    private var previewView: NSImageView!
    private var placeholderLabel: NSTextField!
    private var toggleButton: NSButton!

    public var isVisible: Bool = true
    public var onToggle: ((Bool) -> Void)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        // Toggle button
        toggleButton = NSButton(title: "Preview", target: self, action: #selector(togglePreview))
        toggleButton.bezelStyle = .texturedRounded
        toggleButton.translatesAutoresizingMaskIntoConstraints = false

        // Preview view
        previewView = NSImageView()
        previewView.imageScaling = .scaleProportionallyUpOrDown
        previewView.translatesAutoresizingMaskIntoConstraints = false

        // Placeholder label
        placeholderLabel = NSTextField(labelWithString: "Select a file to preview")
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(toggleButton)
        addSubview(previewView)
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            toggleButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            toggleButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            toggleButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            previewView.topAnchor.constraint(equalTo: toggleButton.bottomAnchor, constant: 8),
            previewView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            previewView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            previewView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            placeholderLabel.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: previewView.centerYAnchor)
        ])
    }

    @objc private func togglePreview() {
        isVisible.toggle()
        onToggle?(isVisible)
    }

    /// Show preview for a file path
    /// - Parameter path: File path to preview
    public func showPreview(for path: String) {
        let url = URL(fileURLWithPath: path)

        // Try to load as image
        if let image = NSImage(contentsOf: url) {
            previewView.image = image
            placeholderLabel.isHidden = true
            previewView.isHidden = false
        } else {
            // Show placeholder for non-image files
            placeholderLabel.stringValue = "Preview not available for this file type"
            placeholderLabel.isHidden = false
            previewView.isHidden = true
        }
    }

    /// Clear the preview
    public func clearPreview() {
        previewView.image = nil
        placeholderLabel.stringValue = "Select a file to preview"
        placeholderLabel.isHidden = false
        previewView.isHidden = true
    }
}

// MARK: - QuickLook Preview Item

/// Wrapper for QLPreviewItem protocol
private class QLPreviewItem: NSObject, QLPreviewItem {

    private let itemURL: URL

    init(url: URL) {
        self.itemURL = url
        super.init()
    }

    var previewItemURL: URL? {
        return itemURL
    }

    var previewItemTitle: String? {
        return itemURL.lastPathComponent
    }
}
