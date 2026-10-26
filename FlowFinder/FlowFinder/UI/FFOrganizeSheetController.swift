import AppKit

// MARK: - J3-10 批量整理预览 Sheet
//
// 定稿（决策台账）：模态 Sheet 列完整计划——顶部统计 + 可滚动计划清单
// （原文件 → 归入目录，重名项标黄「跳过」）+ 执行/取消；日期三档可选默认 YYYY/MM。
// 两个入口（工具页「批量整理」行 / 右键「整理当前目录…」）共用本 Sheet。

/// 计划清单行
struct FFOrganizeSheetRow {
    let fileName: String
    let destination: String
    let isConflict: Bool
}

final class FFOrganizeSheet: FFModalSheet {

    var onExecute: ((FFOrganizePlan, String) -> Void)?

    private let directory: String
    private let entries: [FileEntry]
    private var mode: FFOrganizeMode = .date(.ym)
    private var plan: FFOrganizePlan = FFOrganizePlan(moves: [], conflicts: [])

    private let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let formatTitle = NSTextField(labelWithString: "日期格式")
    private let statsLabel = NSTextField(labelWithString: "")
    private let undoHintLabel = NSTextField(labelWithString: "执行后可 ⌘Z 一次撤销整批")
    private let planTable = NSTableView()
    private var rows: [FFOrganizeSheetRow] = []

    static let formatTitles = FFOrganizeDateFormat.allCases.map { $0.rawValue }
    private static let modeTitles = ["按日期", "按类型"]

    init(directory: String, entries: [FileEntry]) {
        self.directory = directory
        self.entries = entries

        let body = NSView()
        let box = FFClosureBox()
        super.init(title: "整理预览 — \((directory as NSString).lastPathComponent)",
                   bodyView: body,
                   primaryButton: ("执行整理", .default),
                   secondaryButton: "取消",
                   primaryAction: { box.closure?() })
        box.closure = { [weak self] in self?.execute() }

        buildBody(body)
        regenerate()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Body

    private func buildBody(_ body: NSView) {
        let modeTitle = NSTextField(labelWithString: "整理方式")
        modeTitle.font = FFVisualTokens.Font.body
        modeTitle.textColor = .secondaryLabelColor

        modePopup.addItems(withTitles: Self.modeTitles)
        modePopup.selectItem(at: 0)
        modePopup.controlSize = .small
        modePopup.font = FFVisualTokens.Font.caption
        modePopup.target = self
        modePopup.action = #selector(modeChanged(_:))
        modePopup.setAccessibilityLabel("整理方式")

        formatTitle.font = FFVisualTokens.Font.body
        formatTitle.textColor = .secondaryLabelColor

        formatPopup.addItems(withTitles: Self.formatTitles)
        formatPopup.selectItem(at: FFOrganizeDateFormat.allCases.firstIndex(of: .ym) ?? 0)
        formatPopup.controlSize = .small
        formatPopup.font = FFVisualTokens.Font.caption
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))
        formatPopup.setAccessibilityLabel("日期格式")

        statsLabel.font = FFVisualTokens.Font.caption
        statsLabel.textColor = .secondaryLabelColor
        undoHintLabel.font = FFVisualTokens.Font.caption
        undoHintLabel.textColor = FFVisualTokens.hint

        // 计划清单
        planTable.identifier = NSUserInterfaceItemIdentifier("FFOrganizePlanTable")
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "文件"
        nameColumn.width = 170
        let destColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("dest"))
        destColumn.title = "归入"
        destColumn.width = 140
        planTable.addTableColumn(nameColumn)
        planTable.addTableColumn(destColumn)
        planTable.headerView = nil
        planTable.rowHeight = 22
        planTable.backgroundColor = .clear
        planTable.setAccessibilityLabel("整理计划清单")
        let dataSource = FFOrganizeSheetDataSource(sheet: self)
        planTable.dataSource = dataSource
        planTable.delegate = dataSource
        objc_setAssociatedObject(self, &FFOrganizeSheet.dataSourceKey, dataSource,
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let scroll = NSScrollView()
        scroll.documentView = planTable
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .bezelBorder

        body.addSubview(modeTitle)
        body.addSubview(modePopup)
        body.addSubview(formatTitle)
        body.addSubview(formatPopup)
        body.addSubview(statsLabel)
        body.addSubview(undoHintLabel)
        body.addSubview(scroll)
        for sub in [modeTitle, modePopup, formatTitle, formatPopup, statsLabel, undoHintLabel, scroll] {
            sub.translatesAutoresizingMaskIntoConstraints = false
        }

        let tableHeight: CGFloat = 210
        NSLayoutConstraint.activate([
            body.widthAnchor.constraint(equalToConstant: 380),

            modeTitle.topAnchor.constraint(equalTo: body.topAnchor),
            modeTitle.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            modePopup.leadingAnchor.constraint(equalTo: modeTitle.trailingAnchor, constant: 8),
            modePopup.centerYAnchor.constraint(equalTo: modeTitle.centerYAnchor),
            modePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 84),

            formatTitle.leadingAnchor.constraint(equalTo: modePopup.trailingAnchor, constant: 16),
            formatTitle.centerYAnchor.constraint(equalTo: modeTitle.centerYAnchor),
            formatPopup.leadingAnchor.constraint(equalTo: formatTitle.trailingAnchor, constant: 8),
            formatPopup.centerYAnchor.constraint(equalTo: modeTitle.centerYAnchor),
            formatPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),

            scroll.topAnchor.constraint(equalTo: modeTitle.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: tableHeight),

            statsLabel.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            statsLabel.leadingAnchor.constraint(equalTo: body.leadingAnchor),

            undoHintLabel.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 4),
            undoHintLabel.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            undoHintLabel.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])
    }

    // MARK: - 计划

    private func regenerate() {
        plan = FFOrganizePlanner.plan(mode: mode, directory: directory, entries: entries)
        var sheetRows: [FFOrganizeSheetRow] = plan.moves.map {
            FFOrganizeSheetRow(fileName: $0.fileName,
                               destination: relativeSubdirectory(of: $0.targetDirectory),
                               isConflict: false)
        }
        sheetRows.append(contentsOf: plan.conflicts.map {
            FFOrganizeSheetRow(fileName: $0.fileName,
                               destination: $0.reason,
                               isConflict: true)
        })
        rows = sheetRows
        planTable.reloadData()

        if plan.isEmpty {
            statsLabel.stringValue = "没有可整理的文件"
        } else {
            var text = "\(plan.moves.count) 项移动"
            if !plan.conflicts.isEmpty {
                text += " · \(plan.conflicts.count) 项重名跳过"
            }
            statsLabel.stringValue = text
        }
        setPrimaryButtonEnabled(!plan.moves.isEmpty)
    }

    private func relativeSubdirectory(of targetDirectory: String) -> String {
        let prefix = (directory as NSString).appendingPathComponent("")
        guard targetDirectory.hasPrefix(prefix) else { return targetDirectory }
        return String(targetDirectory.dropFirst(prefix.count))
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        if sender.indexOfSelectedItem == 0 {
            mode = .date(selectedFormat)
        } else {
            mode = .type
        }
        formatTitle.isHidden = sender.indexOfSelectedItem != 0
        formatPopup.isHidden = sender.indexOfSelectedItem != 0
        regenerate()
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        guard case .date = mode else { return }
        mode = .date(selectedFormat)
        regenerate()
    }

    private var selectedFormat: FFOrganizeDateFormat {
        let index = formatPopup.indexOfSelectedItem
        let all = FFOrganizeDateFormat.allCases
        return index >= 0 && index < all.count ? all[index] : .ym
    }

    private func execute() {
        guard !plan.moves.isEmpty else { return }
        onExecute?(plan, directory)
    }

    private static var dataSourceKey: UInt8 = 0
}

// MARK: - 计划清单数据源

private final class FFOrganizeSheetDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    private weak var sheet: FFOrganizeSheet?

    init(sheet: FFOrganizeSheet) {
        self.sheet = sheet
        super.init()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        sheet?.rowDataSourceCount ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let row0 = sheet?.rowDataSourceRow(at: row) else { return nil }
        let isDest = tableColumn?.identifier.rawValue == "dest"
        let text = isDest ? row0.destination : row0.fileName
        let label = NSTextField(labelWithString: text)
        label.font = FFVisualTokens.Font.caption
        label.lineBreakMode = .byTruncatingMiddle
        if row0.isConflict {
            label.textColor = .systemOrange
        } else if isDest {
            label.textColor = .secondaryLabelColor
        } else {
            label.textColor = .labelColor
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}

// MARK: - 测试 / 数据源桥

extension FFOrganizeSheet {
    var rowDataSourceCount: Int { rows.count }
    func rowDataSourceRow(at index: Int) -> FFOrganizeSheetRow? {
        index >= 0 && index < rows.count ? rows[index] : nil
    }
}
