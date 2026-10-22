import AppKit
import XCTest
@testable import FlowFinder

final class FFDetailsIntegrationTests: XCTestCase {

    private func makeController() -> MainWindowController {
        MainWindowController(startsWithSinglePane: false,
                             showImmediately: false,
                             runsSelfTests: false)
    }

    private func entry(_ name: String) -> FileEntry {
        FileEntry(path: "/tmp/\(name)", name: name, isDirectory: false, size: 1_024)
    }

    func testCmdIExpandsActivePaneDetailsBar() {
        let controller = makeController()
        defer { controller.close() }

        controller.focus.activate(.right)
        controller.rightPaneViewModel.state.selectedFiles = [entry("right.txt")]
        controller.showDetailsForActiveSelection()

        XCTAssertTrue(controller.detailsBar(for: .right)?.isExpandedForTesting ?? false)
        XCTAssertFalse(controller.detailsBar(for: .left)?.isExpandedForTesting ?? true)
    }

    func testCmdIWithoutSelectionKeepsCollapsedSummary() {
        let controller = makeController()
        defer { controller.close() }

        controller.leftPaneViewModel.state.selectedFiles = []
        controller.showDetailsForActiveSelection()

        XCTAssertFalse(controller.detailsBar(for: .left)?.isExpandedForTesting ?? true)
    }

    func testCmdIDoesNotExpandInactivePane() {
        let controller = makeController()
        defer { controller.close() }

        controller.focus.activate(.left)
        controller.leftPaneViewModel.state.selectedFiles = [entry("left.txt")]
        controller.showDetailsForActiveSelection()

        XCTAssertTrue(controller.detailsBar(for: .left)?.isExpandedForTesting ?? false)
        XCTAssertFalse(controller.detailsBar(for: .right)?.isExpandedForTesting ?? true)
    }

    private final class DetailsSpyProvider: FFMetadataProviding {
        var paths: [String] = []
        func load(path: String,
                  completion: @escaping (Result<FFFileMetadata, Error>) -> Void) -> UUID {
            paths.append(path)
            return UUID()
        }
        func cancel(_ token: UUID) {}
    }

    func testExpandedDetailsBarUsesInjectedMetadataProvider() {
        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 500, height: 54))
        let spy = DetailsSpyProvider()
        bar.metadataProvider = spy
        bar.expand()
        bar.update(with: [entry("probe.txt")])
        XCTAssertEqual(spy.paths, ["/tmp/probe.txt"])
    }

    func testMenuGetInfoExpandsDetailsBarInsteadOfLegacyWindow() {
        let controller = makeController()
        defer { controller.close() }

        controller.leftPaneViewModel.state.selectedFiles = [entry("left.txt")]
        controller.menuGetInfo(nil)

        XCTAssertTrue(controller.detailsBar(for: .left)?.isExpandedForTesting ?? false)
        XCTAssertNil(controller.fileInfoWindowController)
    }
}
