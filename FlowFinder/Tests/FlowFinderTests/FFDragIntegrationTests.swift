import AppKit
import XCTest
@testable import FlowFinder

final class FFDragIntegrationTests: XCTestCase {

    private func session(_ path: String) -> PaneTabSession {
        PaneTabSession(state: PaneState(path: path))
    }

    private func makeSinglePaneController(paths: [String]) -> MainWindowController {
        let controller = MainWindowController(startsWithSinglePane: true,
                                              showImmediately: false,
                                              runsSelfTests: false)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let sessions = paths.map(session)
        controller.leftTabsStore?.replaceAll(sessions, activeAt: 0)
        controller.refreshTabStrip(side: .left)
        return controller
    }

    private func operationPoint(_ controller: MainWindowController,
                                rightHalf: Bool) -> NSPoint {
        let content = controller.window!.contentView!
        let sidebarRight = controller.sidebarView.convert(controller.sidebarView.bounds,
                                                          to: content).maxX
        let midX = (sidebarRight + content.bounds.maxX) / 2
        return NSPoint(x: rightHalf ? midX + 60 : midX - 60,
                       y: content.bounds.midY)
    }

    func testSinglePaneRightHalfReportsRight() {
        let controller = makeSinglePaneController(paths: ["/tmp/a", "/tmp/b", "/tmp/c"])
        defer { controller.close() }
        XCTAssertEqual(controller.operationSide(near: operationPoint(controller, rightHalf: true)),
                       .right)
    }

    func testSinglePaneDropOnRightHalfPreservesSiblings() {
        let controller = makeSinglePaneController(paths: ["/tmp/a", "/tmp/b", "/tmp/c"])
        defer { controller.close() }
        let point = operationPoint(controller, rightHalf: true)
        let side = controller.operationSide(near: point)!
        guard let taken = controller.takeTabOut(side: .left, index: 1) else {
            return XCTFail("takeTabOut failed")
        }
        controller.acceptTab(taken, into: .paneContent(window: controller, side: side))

        XCTAssertEqual(controller.leftTabsStore?.tabs.map { $0.state.path }, ["/tmp/a", "/tmp/c"])
        XCTAssertEqual(controller.rightTabsStore?.tabs.map { $0.state.path }, ["/tmp/b"])
        XCTAssertFalse(controller.isSinglePaneMode)
    }

    func testSinglePaneDropOnLeftHalfPreservesSiblings() {
        let controller = makeSinglePaneController(paths: ["/tmp/a", "/tmp/b", "/tmp/c"])
        defer { controller.close() }
        let point = operationPoint(controller, rightHalf: false)
        let side = controller.operationSide(near: point)!
        guard let taken = controller.takeTabOut(side: .left, index: 1) else {
            return XCTFail("takeTabOut failed")
        }
        controller.acceptTab(taken, into: .paneContent(window: controller, side: side))

        XCTAssertEqual(controller.leftTabsStore?.tabs.map { $0.state.path }, ["/tmp/b"])
        XCTAssertEqual(controller.rightTabsStore?.tabs.map { $0.state.path }, ["/tmp/a", "/tmp/c"])
        XCTAssertFalse(controller.isSinglePaneMode)
    }

    func testTargetSinglePaneSplitOnRightPreservesTargetTabs() {
        let source = makeSinglePaneController(paths: ["/tmp/source"])
        let target = makeSinglePaneController(paths: ["/tmp/x", "/tmp/y"])
        defer { source.close(); target.close() }

        guard let taken = source.takeTabOut(side: .left, index: 0) else {
            return XCTFail("takeTabOut failed")
        }
        target.acceptTab(taken, into: .paneContent(window: target, side: .right))

        XCTAssertEqual(target.leftTabsStore?.tabs.map { $0.state.path }, ["/tmp/x", "/tmp/y"])
        XCTAssertEqual(target.rightTabsStore?.tabs.map { $0.state.path }, ["/tmp/source"])
        XCTAssertFalse(target.isSinglePaneMode)
    }

    func testTargetSinglePaneSplitOnLeftPreservesTargetTabs() {
        let source = makeSinglePaneController(paths: ["/tmp/source"])
        let target = makeSinglePaneController(paths: ["/tmp/x", "/tmp/y"])
        defer { source.close(); target.close() }

        guard let taken = source.takeTabOut(side: .left, index: 0) else {
            return XCTFail("takeTabOut failed")
        }
        target.acceptTab(taken, into: .paneContent(window: target, side: .left))

        XCTAssertEqual(target.leftTabsStore?.tabs.map { $0.state.path }, ["/tmp/source"])
        XCTAssertEqual(target.rightTabsStore?.tabs.map { $0.state.path }, ["/tmp/x", "/tmp/y"])
        XCTAssertFalse(target.isSinglePaneMode)
    }

    func testInvalidDropResolvesToSourceAndCreatesNoWindow() {
        let controller = makeSinglePaneController(paths: ["/tmp/a", "/tmp/b"])
        defer { controller.close() }
        let before = NSApp.windows.filter { $0.windowController is MainWindowController }.count
        let geometry = controller.dragGeometry()!
        let sidebar = geometry.invalidRects.first!
        let source = FFDragSource(windowID: geometry.windowID, side: .left, index: 0)
        let decision = FFDropResolver.resolve(source: source,
                                              pointer: CGPoint(x: sidebar.midX, y: sidebar.midY),
                                              geometries: [geometry])
        XCTAssertEqual(decision, .returnToSource)
        let after = NSApp.windows.filter { $0.windowController is MainWindowController }.count
        XCTAssertEqual(before, after)
    }

    func testReopenCreatesWindowWhenNoneVisible() {
        guard let delegate = NSApp.delegate as? AppDelegate else {
            return XCTFail("NSApp.delegate is not AppDelegate")
        }
        let before = Set(NSApp.windows
            .filter { $0.windowController is MainWindowController }
            .map { ObjectIdentifier($0) })

        _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)

        let created = NSApp.windows.first {
            $0.windowController is MainWindowController
                && !before.contains(ObjectIdentifier($0))
        }
        XCTAssertNotNil(created, "无窗口时 Dock 重开应创建一个新窗口")
        created?.close()
    }
}
