import AppKit
import XCTest
@testable import FlowFinder

final class FFDuplicateLayoutTests: XCTestCase {
    @MainActor
    func testDuplicateWindowShowsFourSectionEmptyState() {
        let controller = DuplicateScanWindowController.shared
        controller.showWindow(scanPath: "/tmp")
        defer { controller.close() }

        XCTAssertTrue(controller.isEmptyStateForTesting)
        XCTAssertEqual(controller.primaryActionTitleForTesting, "开始扫描")
    }
}
