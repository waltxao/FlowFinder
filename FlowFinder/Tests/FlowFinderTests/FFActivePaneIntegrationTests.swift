import AppKit
import XCTest
@testable import FlowFinder

final class FFActivePaneIntegrationTests: XCTestCase {
    func testActivatePaneUpdatesFocusAndActivePane() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.activatePane(.right)
        XCTAssertEqual(controller.focus.activePane, .right)
        XCTAssertEqual(controller.activePane, .right)
    }

    func testFocusDirectlyDrivesActivePane() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.focus.activate(.right)
        XCTAssertEqual(controller.activePane, .right)
    }
}
