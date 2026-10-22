import AppKit
import XCTest
@testable import FlowFinder

final class FFShellCoordinatorTests: XCTestCase {

    private func makeShell() -> WindowShellCoordinator {
        WindowShellCoordinator(
            window: nil,
            panes: PaneCoordinator(leftState: PaneState(path: "/tmp/left"),
                                   rightState: PaneState(path: "/tmp/right")),
            sidebar: SidebarCoordinator(),
            tools: ToolCoordinator(),
            tasks: TaskCoordinator()
        )
    }

    func testShellExposesAllSeams() {
        let shell = makeShell()
        XCTAssertEqual(shell.panes.activePane, .left)
        XCTAssertNotNil(shell.sidebar.view)
        XCTAssertFalse(shell.tools.registry.registeredTools.isEmpty)
        XCTAssertNotNil(shell.tasks.service)
    }

    func testPaneCoordinatorActivePaneFollowsFocus() {
        let panes = PaneCoordinator(leftState: PaneState(), rightState: PaneState())
        panes.activePane = .right
        XCTAssertEqual(panes.focus.activePane, .right)
        XCTAssertEqual(panes.activePane, .right)
        XCTAssertTrue(panes.store(for: .right) === panes.rightStore)
    }

    func testToolCoordinatorBuildsContextFromPaneState() {
        let tools = ToolCoordinator()
        let file = FileEntry(path: "/tmp/a.txt", name: "a.txt", isDirectory: false, size: 1)
        let context = tools.context(activePane: .right,
                                    currentPath: "/tmp",
                                    selection: [file],
                                    window: nil)
        XCTAssertEqual(context.activePane, .right)
        XCTAssertEqual(context.selectionSummary, "a.txt")
        XCTAssertFalse(tools.tools(for: context).isEmpty)
    }

    func testMainWindowExposesCoordinatorSeams() {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        defer { controller.close() }
        XCTAssertTrue(controller.shellCoordinator.panes.focus === controller.focus)
        XCTAssertTrue(controller.shellCoordinator.sidebar.view === controller.sidebarView)
        XCTAssertTrue(controller.shellCoordinator.panes.leftStore === controller.leftPaneStore)
    }
}
