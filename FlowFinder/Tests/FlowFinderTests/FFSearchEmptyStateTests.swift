import AppKit
import XCTest
@testable import FlowFinder

final class FFSearchEmptyStateTests: XCTestCase {
    @MainActor
    func testSearchWithoutQueryShowsCenteredEmptyState() {
        let controller = SearchPanelController.shared
        controller.showPanel(initialQuery: "", searchPath: "/tmp")
        defer { controller.close() }

        XCTAssertTrue(controller.isEmptyStateForTesting)
        XCTAssertEqual(controller.emptyStatePrimaryTitleForTesting, "构建内容索引")
    }
}
