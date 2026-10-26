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

    func testMenuToggleDetailsBarExpandsDetailsBarInsteadOfLegacyWindow() {
        let controller = makeController()
        defer { controller.close() }

        controller.leftPaneViewModel.state.selectedFiles = [entry("left.txt")]
        controller.menuToggleDetailsBar(nil)

        XCTAssertTrue(controller.detailsBar(for: .left)?.isExpandedForTesting ?? false)
        XCTAssertNil(controller.fileInfoWindowController)
    }

    // MARK: - R4-21 详情栏：文件夹大小汇总 / 空说明占位 / 路径 tooltip

    @MainActor
    func testFolderSizeIsSummedInsteadOfDashes() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ff-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(count: 4096).write(to: dir.appendingPathComponent("blob.bin"))

        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        bar.update(with: FileEntry(path: dir.path, name: dir.lastPathComponent, isDirectory: true))

        XCTAssertEqual(bar.sizeFieldTextForTesting, "计算中…",
                       "目录大小不该是 `--`，应先用计算中占位（R4-21）")

        let deadline = Date().addingTimeInterval(5)
        while bar.sizeFieldTextForTesting == "计算中…" && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let text = bar.sizeFieldTextForTesting
        XCTAssertFalse(text.isEmpty, "异步汇总完成后大小行不能空着")
        XCTAssertTrue(text.contains("B"), "目录大小应显示递归汇总后的字节数，实测 \(text)")
    }

    @MainActor
    func testEmptyDescriptionShowsHintInsteadOfHangingLabel() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ff-desc-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        bar.update(with: FileEntry(path: file.path, name: file.lastPathComponent, isDirectory: false))

        XCTAssertEqual(bar.descriptionDisplayTextForTesting, "双击添加说明",
                       "没有说明时不能只剩标签悬挂（R4-21）")
        XCTAssertTrue(bar.descriptionIsHintForTesting, "占位文案要用提示样式，不能像真实内容")

        XCTAssertTrue(FFFinderCommentStore.write(path: file.path, comment: "真实说明"))
        bar.update(with: FileEntry(path: file.path, name: file.lastPathComponent, isDirectory: false))
        XCTAssertEqual(bar.descriptionDisplayTextForTesting, "真实说明")
        XCTAssertFalse(bar.descriptionIsHintForTesting)
    }

    @MainActor
    func testLocationFieldToolTipCarriesFullPath() {
        let path = "/tmp/ff-很-长-的-目-录-\(UUID().uuidString)/子目录/文件.txt"
        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        bar.update(with: FileEntry(path: path, name: "文件.txt", isDirectory: false))

        XCTAssertEqual(bar.locationToolTipForTesting, path,
                       "路径被折行截断时，悬停必须能看到完整路径（R4-21）")
    }
}
