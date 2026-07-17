import Cocoa
import SwiftUI

// MARK: - Duplicate Scan View

/// View for scanning and displaying duplicate files
public class DuplicateScanView: NSView {

    private var progressBar: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var startButton: NSButton!
    private var cancelButton: NSButton!
    private var resultsTableView: NSTableView!
    private var deleteButton: NSButton!

    private var duplicateGroups: [FFDuplicateGroup] = []
    private var isScanning = false

    public var onDeleteDuplicates: (([FFDuplicateGroup]) -> Void)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        // Progress bar
        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        // Status label
        statusLabel = NSTextField(labelWithString: "Ready to scan")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // Start button
        startButton = NSButton(title: "Start Scan", target: self, action: #selector(startScan))
        startButton.translatesAutoresizingMaskIntoConstraints = false

        // Cancel button
        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelScan))
        cancelButton.isEnabled = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        // Delete button
        deleteButton = NSButton(title: "Delete Duplicates", target: self, action: #selector(deleteDuplicates))
        deleteButton.isEnabled = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        // Results table
        resultsTableView = NSTableView()
        resultsTableView.allowsMultipleSelection = true
        resultsTableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let pathColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Path"))
        pathColumn.title = "Path"
        pathColumn.width = 300
        resultsTableView.addTableColumn(pathColumn)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Size"))
        sizeColumn.title = "Size"
        sizeColumn.width = 100
        resultsTableView.addTableColumn(sizeColumn)

        let hashColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Hash"))
        hashColumn.title = "Hash"
        hashColumn.width = 200
        resultsTableView.addTableColumn(hashColumn)

        let scrollView = NSScrollView()
        scrollView.documentView = resultsTableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Add subviews
        addSubview(progressBar)
        addSubview(statusLabel)
        addSubview(startButton)
        addSubview(cancelButton)
        addSubview(deleteButton)
        addSubview(scrollView)

        // Layout constraints
        NSLayoutConstraint.activate([
            progressBar.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            statusLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            startButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            startButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            cancelButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            cancelButton.leadingAnchor.constraint(equalTo: startButton.trailingAnchor, constant: 10),

            deleteButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            deleteButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 10),

            scrollView.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        ])
    }

    @objc private func startScan() {
        isScanning = true
        startButton.isEnabled = false
        cancelButton.isEnabled = true
        deleteButton.isEnabled = false
        progressBar.doubleValue = 0
        statusLabel.stringValue = "Scanning for duplicates..."

        // Start the scan via bridge
        DuplicateScanBridge.shared.scanDuplicates(
            path: FileManager.default.homeDirectoryForCurrentUser.path,
            progressHandler: { [weak self] scanned, total in
                DispatchQueue.main.async {
                    let progress = total > 0 ? Double(scanned) / Double(total) * 100 : 0
                    self?.progressBar.doubleValue = progress
                    self?.statusLabel.stringValue = "Scanned \(scanned) of \(total) files"
                }
            },
            groupHandler: { [weak self] group in
                self?.duplicateGroups.append(group)
            },
            completion: { [weak self] error in
                DispatchQueue.main.async {
                    self?.isScanning = false
                    self?.startButton.isEnabled = true
                    self?.cancelButton.isEnabled = false
                    self?.deleteButton.isEnabled = !(self?.duplicateGroups.isEmpty ?? true)

                    if let error = error {
                        self?.statusLabel.stringValue = "Error: \(error.localizedDescription)"
                    } else {
                        let count = self?.duplicateGroups.count ?? 0
                        self?.statusLabel.stringValue = "Found \(count) duplicate groups"
                    }
                    self?.resultsTableView.reloadData()
                }
            }
        )
    }

    @objc private func cancelScan() {
        DuplicateScanBridge.shared.cancelScan()
        isScanning = false
        startButton.isEnabled = true
        cancelButton.isEnabled = false
        statusLabel.stringValue = "Scan cancelled"
    }

    @objc private func deleteDuplicates() {
        guard !duplicateGroups.isEmpty else { return }
        onDeleteDuplicates?(duplicateGroups)
    }
}

// MARK: - Duplicate Results View

/// View for displaying duplicate file groups in a table
public class DuplicateResultsView: NSView, NSTableViewDataSource, NSTableViewDelegate {

    private var tableView: NSTableView!
    private var scrollView: NSScrollView!

    public var duplicateGroups: [FFDuplicateGroup] = [] {
        didSet {
            tableView?.reloadData()
        }
    }

    public var onSelectGroup: ((FFDuplicateGroup) -> Void)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        scrollView = NSScrollView(frame: bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        tableView = NSTableView()
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.usesAlternatingRowBackgroundColors = true

        // Group ID column
        let idColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("GroupID"))
        idColumn.title = "Group"
        idColumn.width = 100
        tableView.addTableColumn(idColumn)

        // Hash column
        let hashColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Hash"))
        hashColumn.title = "Hash"
        hashColumn.width = 200
        tableView.addTableColumn(hashColumn)

        // Size column
        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Size"))
        sizeColumn.title = "Size"
        sizeColumn.width = 100
        tableView.addTableColumn(sizeColumn)

        // File count column
        let countColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Count"))
        countColumn.title = "Files"
        countColumn.width = 80
        tableView.addTableColumn(countColumn)

        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        addSubview(scrollView)
    }

    // MARK: - NSTableViewDataSource

    public func numberOfRows(in tableView: NSTableView) -> Int {
        return duplicateGroups.count
    }

    // MARK: - NSTableViewDelegate

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < duplicateGroups.count else { return nil }

        let group = duplicateGroups[row]
        let cellView = NSTableCellView()
        let textField = NSTextField(labelWithString: "")
        textField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        cellView.textField = textField

        switch tableColumn?.identifier.rawValue {
        case "GroupID":
            textField.stringValue = group.id
        case "Hash":
            textField.stringValue = group.hash
        case "Size":
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            textField.stringValue = formatter.string(fromByteCount: Int64(group.size))
        case "Count":
            textField.stringValue = "\(group.files.count)"
        default:
            break
        }

        return cellView
    }

    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 24
    }
}
