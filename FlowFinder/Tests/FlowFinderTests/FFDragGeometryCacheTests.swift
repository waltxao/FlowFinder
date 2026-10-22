import AppKit
import XCTest
@testable import FlowFinder

final class FFDragGeometryCacheTests: XCTestCase {

    func testCacheBuildsTabStripAndPaneGeometry() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let cache = FFDragGeometryCache()
        cache.update(for: controller)

        let geometry = cache.all().first
        XCTAssertNotNil(geometry)
        XCTAssertEqual(geometry?.isSinglePane, false)
        XCTAssertNotNil(geometry?.tabStrips[.left])
        XCTAssertNotNil(geometry?.tabStrips[.right])
        XCTAssertNotNil(geometry?.paneContents[.left])
        XCTAssertNotNil(geometry?.paneContents[.right])
        XCTAssertFalse(geometry?.invalidRects.isEmpty ?? true)
    }

    func testSinglePaneCacheHasOnlyVisibleStrip() {
        let controller = MainWindowController(startsWithSinglePane: true,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let cache = FFDragGeometryCache()
        cache.update(for: controller)
        let geometry = cache.all().first

        XCTAssertEqual(geometry?.isSinglePane, true)
        XCTAssertEqual(geometry?.tabStrips.count, 1)
        XCTAssertEqual(geometry?.paneContents.count, 1)
    }

    func testRemoveDropsGeometry() {
        let controller = MainWindowController(showImmediately: false, runsSelfTests: false)
        defer { controller.close() }
        let cache = FFDragGeometryCache()
        cache.update(for: controller)
        XCTAssertEqual(cache.all().count, 1)
        cache.remove(controller)
        XCTAssertTrue(cache.all().isEmpty)
    }
}
