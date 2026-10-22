import AppKit
import XCTest
@testable import FlowFinder

final class FFDragPerformanceStructureTests: XCTestCase {

    private func session(_ path: String) -> PaneTabSession {
        PaneTabSession(state: PaneState(path: path))
    }

    func testInsertionIndicatorUsesFrameNotAutoLayout() {
        let strip = PaneTabStripView(frame: NSRect(x: 0, y: 0, width: 500, height: 36))
        strip.side = .left
        strip.refresh(sessions: [session("/tmp/a"), session("/tmp/b")], activeIndex: 0)
        strip.layoutSubtreeIfNeeded()

        strip.showInsertionIndicator(atIndex: 1)

        let indicator = strip.insertionIndicatorForTesting
        XCTAssertNotNil(indicator)
        XCTAssertTrue(indicator!.translatesAutoresizingMaskIntoConstraints,
                      "插入线必须用 frame，不能再加 Auto Layout 约束")
        XCTAssertTrue(indicator!.constraints.isEmpty)
    }

    func testColumnFitPolicyOnlyFitsWhenWidthChanges() {
        XCTAssertFalse(FFColumnFitPolicy.shouldFit(previousWidth: 500, currentWidth: 500.2))
        XCTAssertTrue(FFColumnFitPolicy.shouldFit(previousWidth: 500, currentWidth: 520))
    }

    func testFrameSchedulerCoalescesToLatestPointer() {
        var received: [CGPoint] = []
        let scheduler = FFDragFrameScheduler { received.append($0) }
        scheduler.update(CGPoint(x: 1, y: 1))
        scheduler.update(CGPoint(x: 2, y: 2))
        scheduler.update(CGPoint(x: 3, y: 3))
        XCTAssertEqual(scheduler.latestPoint, CGPoint(x: 3, y: 3))
        scheduler.stop()
        XCTAssertTrue(received.isEmpty, "未启动时不应触发帧回调")
    }

    func testSelectionOnlyChangeDoesNotReloadList() {
        var a = PaneState(path: "/tmp")
        a.files = [FileEntry(path: "/tmp/a", name: "a", isDirectory: false)]
        var b = a
        b.selectedFiles = a.files
        XCTAssertFalse(FFPaneReloadPolicy.shouldReloadList(previous: a, current: b))
        b.files = [FileEntry(path: "/tmp/b", name: "b", isDirectory: false)]
        XCTAssertTrue(FFPaneReloadPolicy.shouldReloadList(previous: a, current: b))
    }
}
