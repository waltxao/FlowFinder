import AppKit
import XCTest
@testable import FlowFinder

final class FFDuplicateLayoutTests: XCTestCase {

    /// C8：小于 1 KB 一律按字节并带单位；1 KB 起走 KB/MB 档。
    func testByteTextKeepsUnitBelowOneKilobyte() {
        XCTAssertEqual(FFByteText.format(0), "0 字节")
        XCTAssertEqual(FFByteText.format(6), "6 字节")
        XCTAssertEqual(FFByteText.format(1000), "1 KB")   // file 档按 1000 进制，与访达一致
    }

    /// C7：组名不再暴露内容 hash，改用「数量 + 首个文件名」。
    func testGroupTitleUsesFileNameInsteadOfHash() {
        XCTAssertEqual(DuplicateGroupTitle.text(fileCount: 3, firstName: "报告.pdf"),
                       "3 个相同文件 · 报告.pdf")
        XCTAssertEqual(DuplicateGroupTitle.text(fileCount: 2, firstName: nil),
                       "2 个相同文件")
    }
    @MainActor
    func testDuplicateWindowShowsFourSectionEmptyState() {
        let controller = DuplicateScanWindowController.shared
        controller.showWindow(scanPath: "/tmp")
        defer { controller.close() }

        XCTAssertTrue(controller.isEmptyStateForTesting)
        XCTAssertEqual(controller.primaryActionTitleForTesting, "开始扫描")
    }

    // MARK: - R4-30 只读路径外观 + 最小尺寸

    @MainActor
    func testReadOnlyPathFieldDoesNotLookEditable() {
        let controller = DuplicateScanWindowController.shared
        controller.showWindow(scanPath: "/tmp")
        defer { controller.close() }
        guard let field = controller.pathFieldForTesting else {
            return XCTFail("扫描路径字段未构建")
        }

        XCTAssertFalse(field.isEditable, "扫描路径走「浏览…」，字段本身不该可编辑")
        XCTAssertTrue(field.isSelectable, "路径要能选中复制")
        XCTAssertFalse(field.isBezeled, "只读展示不该有输入框描边（R4-30）")
        XCTAssertFalse(field.drawsBackground, "只读展示不该有输入框底色（R4-30）")
        XCTAssertEqual(field.toolTip, field.stringValue, "路径被截断时悬停要能看到完整路径")
    }

    @MainActor
    func testMinimumWindowSizeKeepsResultsTableVisible() {
        let controller = DuplicateScanWindowController.shared
        controller.showWindow(scanPath: "/tmp")
        defer { controller.close() }
        guard let window = controller.window else { return XCTFail("窗口未创建") }

        XCTAssertEqual(window.minSize, DuplicateScanWindowController.minWindowSize)
        window.setContentSize(DuplicateScanWindowController.minWindowSize)
        window.layoutIfNeeded()

        XCTAssertGreaterThanOrEqual(controller.resultsScrollSizeForTesting.height, 120,
                                    "最小尺寸下结果区被挤没了（R4-30）")
    }
}
