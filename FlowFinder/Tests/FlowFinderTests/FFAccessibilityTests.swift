import AppKit
import XCTest
@testable import FlowFinder

final class FFAccessibilityTests: XCTestCase {

    func testToolbarConfigButtonHasAccessibilityLabel() {
        UserDefaults.standard.removeObject(forKey: FFToolbarRow2Preferences.storageKey)
        let toolbar = PaneToolbar(frame: NSRect(x: 0, y: 0, width: 600, height: 72))
        XCTAssertEqual(toolbar.displaySettingsButton.accessibilityLabel(), "显示设置")
        XCTAssertFalse(toolbar.displaySettingsButton.toolTip?.isEmpty ?? true)
        XCTAssertFalse(toolbar.displaySettingsButton.isHidden)
    }

    func testHitTargetsMeetDesktopMinimum() {
        XCTAssertGreaterThanOrEqual(FFVisualTokens.rowHeight, 24)
        XCTAssertGreaterThanOrEqual(FFVisualTokens.statusBarHeight, 24)
        XCTAssertGreaterThanOrEqual(FFToolRowView.preferredHeight, 24)
        XCTAssertGreaterThanOrEqual(FFVisualTokens.activePaneEdge, 2)
    }

    func testContextMenuDoesNotStealCmdIFromDetailsBar() {
        let menu = FFPaneMenuBuilder.buildMenu(for: NSObject(), isLeft: true, tagsSubmenu: nil)
        let infoItem = menu.items.first { $0.title == "显示简介" }
        XCTAssertEqual(infoItem?.keyEquivalent, "",
                       "⌘I 应由主菜单打开区内详情栏，右键菜单不得抢占")
    }

    func testKeyboardContractEveryActionHasDisplay() {
        for action in FFShortcutAction.allCases {
            XCTAssertFalse(FFKeyboardContract.shortcut(for: action).display.isEmpty,
                           "\(action) 缺少显示文案")
        }
    }

    func testPrimaryTextContrastMeetsWCAGAAInLightAndDark() {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            guard let appearance = NSAppearance(named: appearanceName) else { continue }
            appearance.performAsCurrentDrawingAppearance {
                let ratio = FFContrast.ratio(.labelColor, .windowBackgroundColor)
                XCTAssertGreaterThanOrEqual(ratio, 4.5,
                                            "\(appearanceName.rawValue) 主文本对比度不足")
            }
        }
    }

    func testPrimaryTextContrastMeetsWCAGAAInHighContrastModes() {
        let names: [NSAppearance.Name] = [.accessibilityHighContrastAqua,
                                          .accessibilityHighContrastDarkAqua]
        for appearanceName in names {
            guard let appearance = NSAppearance(named: appearanceName) else { continue }
            appearance.performAsCurrentDrawingAppearance {
                let ratio = FFContrast.ratio(.labelColor, .windowBackgroundColor)
                XCTAssertGreaterThanOrEqual(ratio, 4.5,
                                            "\(appearanceName.rawValue) 主文本对比度不足")
            }
        }
    }
}

// MARK: - R-26: AX 行虚拟化

private final class FFAXFakeRowSource: NSObject, FFAXRowDataSource, NSTableViewDataSource {
    var rowCount: Int
    var lastSelectedRow: Int?

    init(rowCount: Int) {
        self.rowCount = rowCount
    }

    var axRowCount: Int { rowCount }

    func axLabel(forRow row: Int) -> String? {
        guard row >= 0, row < rowCount else { return nil }
        return "Row \(row)"
    }

    func axSelect(row: Int) -> Bool {
        guard row >= 0, row < rowCount else { return false }
        lastSelectedRow = row
        return true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rowCount }
}

private final class FFAXCountingTableDelegate: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let rowCount: Int
    private(set) var viewForCount = 0

    init(rowCount: Int) {
        self.rowCount = rowCount
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rowCount }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        viewForCount += 1
        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("counting-cell")
        let label = NSTextField(labelWithString: "Row \(row)")
        cell.addSubview(label)
        cell.textField = label
        return cell
    }
}

final class FFAXVirtualizationTests: XCTestCase {

    private func makeTable(rows: Int) -> (FFQuickLookTableView, FFAXFakeRowSource) {
        let table = FFQuickLookTableView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        table.addTableColumn(column)
        let source = FFAXFakeRowSource(rowCount: rows)
        table.axDataSource = source
        table.dataSource = source
        table.reloadData()
        return (table, source)
    }

    func testAXRowsKeepFullCountWithoutCellChildren() {
        let (table, source) = makeTable(rows: 5000)

        XCTAssertEqual(source.axRowCount, 5000)
        XCTAssertEqual(table.accessibilityRowCount(), 5000)
        XCTAssertEqual(table.accessibilityRows()?.count, 5000)
        XCTAssertEqual(table.accessibilityChildren()?.count, 5000)
        XCTAssertEqual(table.accessibilityChildrenInNavigationOrder()?.count, 5000)

        let children = table.accessibilityChildren() as? [FFAXRowElement]
        XCTAssertEqual(children?.first?.accessibilityIndex(), 0)
        XCTAssertEqual(children?.first?.accessibilityLabel(), "Row 0")
        XCTAssertEqual(children?.first?.accessibilityChildren()?.count, 0)
        XCTAssertEqual(children?.last?.accessibilityIndex(), 4999)
        XCTAssertEqual(children?.last?.accessibilityLabel(), "Row 4999")
    }

    func testAXEnumerationDoesNotCreateCellViews() {
        let table = FFQuickLookTableView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        let source = FFAXFakeRowSource(rowCount: 5000)
        let counter = FFAXCountingTableDelegate(rowCount: 5000)
        table.axDataSource = source
        table.dataSource = counter
        table.delegate = counter
        table.reloadData()

        let before = counter.viewForCount
        if let children = table.accessibilityChildren() as? [FFAXRowElement] {
            for row in children {
                _ = row.accessibilityLabel()
                _ = row.accessibilityFrame()
                _ = row.isAccessibilitySelected()
            }
        }
        XCTAssertEqual(counter.viewForCount, before,
                       "AX 枚举不得为不可见行创建 cell view")
    }

    func testAXSelectionRoundTripAndPress() {
        let (table, source) = makeTable(rows: 100)

        table.selectRowIndexes(IndexSet(integer: 42), byExtendingSelection: false)
        let selected = table.accessibilitySelectedRows()
        XCTAssertEqual(selected?.count, 1)
        XCTAssertEqual((selected?.first as? FFAXRowElement)?.accessibilityIndex(), 42)

        table.deselectAll(nil)
        table.setAccessibilitySelectedRows(selected ?? [])
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 42))

        guard let row7 = table.accessibilityChildren()?[7] as? FFAXRowElement else {
            return XCTFail("第 7 行应为 FFAXRowElement")
        }
        XCTAssertTrue(row7.accessibilityPerformPress())
        XCTAssertEqual(source.lastSelectedRow, 7)
    }

    func testAXRowsInvalidateAfterReload() {
        let (table, source) = makeTable(rows: 5000)
        XCTAssertEqual(table.accessibilityChildren()?.count, 5000)

        source.rowCount = 10
        table.reloadData()

        XCTAssertEqual(table.accessibilityRowCount(), 10)
        XCTAssertEqual(table.accessibilityChildren()?.count, 10)
    }

    /// 外来行（别的表产出的行元素）必须被忽略，不能凭它的 accessibilityIndex 去改本表选中。
    /// 2026-10-23 接手实测：AX 客户端写入 AXSelectedRows 时应用 SIGTRAP 崩溃（FileListView.swift:153），
    /// 崩溃点在 `$0.accessibilityIndex()`；本测试锁住「只接受本表行元素」的契约。
    func testSetAccessibilitySelectedRowsIgnoresForeignRows() {
        let (table, _) = makeTable(rows: 10)
        let (other, _) = makeTable(rows: 10)
        table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        guard let foreign = other.accessibilityRows()?.first else {
            return XCTFail("另一张表应产出行元素")
        }

        table.setAccessibilitySelectedRows([foreign])

        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 2),
                       "外来行不得改变选中；应按无效输入忽略")
    }

    func testSetAccessibilitySelectedRowsAcceptsOwnRows() {
        let (table, _) = makeTable(rows: 10)
        guard let rows = table.accessibilityRows(), rows.count == 10 else {
            return XCTFail("应有 10 行元素")
        }
        table.setAccessibilitySelectedRows([rows[3], rows[7]])
        XCTAssertEqual(table.selectedRowIndexes, IndexSet([3, 7]))
    }
}
