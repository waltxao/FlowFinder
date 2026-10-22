import AppKit
import XCTest
@testable import FlowFinder

/// 批次 2：功能回归 6 组（跨栏 / 搜索 / 键盘 / 标签互通 / 设置生效 / 静态 lint）。
final class FFBatch2IntegrationTests: XCTestCase {

    private var defaults: UserDefaults { .standard }
    private var savedValues: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        for key in [FFUserDefaultsKeys.folderFirstSort,
                    FFUserDefaultsKeys.keepSelectionPosition,
                    FFUserDefaultsKeys.confirmFileOperations,
                    FFUserDefaultsKeys.defaultFileBehavior] {
            savedValues[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for (key, value) in savedValues {
            if let value { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        savedValues.removeAll()
        super.tearDown()
    }

    // MARK: - 工具

    private func makeTempDir(_ prefix: String) throws -> String {
        // 与 PaneStateDeleteFilterTests 同理：/var/folders 在 XCTest harness 下
        // 被 Rust 的 getattrlistbulk 静默枚举为 0 条，必须用 /tmp。
        let dir = "/tmp/ff_b2_\(prefix)_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ name: String, in dir: String) throws {
        try "x".write(toFile: (dir as NSString).appendingPathComponent(name),
                      atomically: true, encoding: .utf8)
    }

    private func waitUntil(_ timeout: TimeInterval = 10,
                           _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    private func makeController() -> MainWindowController {
        let controller = MainWindowController(startsWithSinglePane: false,
                                              showImmediately: false,
                                              runsSelfTests: false)
        _ = controller.window
        return controller
    }

    private func load(_ vm: PaneViewModel, _ path: String) {
        vm.navigate(to: path)
        XCTAssertTrue(waitUntil { !vm.state.isLoading && vm.state.path == path },
                      "目录未加载完成: \(path)")
    }

    private func xattr(_ path: String, _ name: String) -> Data? {
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes {
            getxattr(path, name, $0.baseAddress, size, 0, 0)
        }
        return read > 0 ? data : nil
    }

    // MARK: - 1. 跨栏操作

    func testCopyToOtherPaneLandsInDestination() throws {
        let src = try makeTempDir("copy_src")
        let dst = try makeTempDir("copy_dst")
        try write("alpha.txt", in: src)
        let controller = makeController()
        defer { controller.close() }
        load(controller.leftPaneViewModel, src)
        load(controller.rightPaneViewModel, dst)

        controller.activatePane(.left)
        controller.leftPaneViewModel.selectFile(controller.leftPaneViewModel.state.files[0])
        controller.menuCopyToOther(nil)

        let target = (dst as NSString).appendingPathComponent("alpha.txt")
        XCTAssertTrue(waitUntil(20) { FileManager.default.fileExists(atPath: target) },
                      "⌘⇧C 后目标目录应出现文件")
        XCTAssertTrue(FileManager.default.fileExists(atPath: (src as NSString).appendingPathComponent("alpha.txt")),
                      "复制不应删除源文件")
    }

    func testMoveToOtherPaneRemovesSource() throws {
        let src = try makeTempDir("move_src")
        let dst = try makeTempDir("move_dst")
        try write("beta.txt", in: src)
        let controller = makeController()
        defer { controller.close() }
        load(controller.leftPaneViewModel, src)
        load(controller.rightPaneViewModel, dst)

        controller.activatePane(.left)
        controller.leftPaneViewModel.selectFile(controller.leftPaneViewModel.state.files[0])
        controller.menuMoveToOther(nil)

        let target = (dst as NSString).appendingPathComponent("beta.txt")
        XCTAssertTrue(waitUntil(20) { FileManager.default.fileExists(atPath: target) },
                      "⌘⇧X 后目标目录应出现文件")
        XCTAssertFalse(FileManager.default.fileExists(atPath: (src as NSString).appendingPathComponent("beta.txt")),
                       "移动后源文件应消失")
    }

    func testOpenInOtherPaneNavigatesRight() throws {
        let src = try makeTempDir("open_src")
        let dst = try makeTempDir("open_dst")
        let sub = (src as NSString).appendingPathComponent("Sub")
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        let controller = makeController()
        defer { controller.close() }
        load(controller.leftPaneViewModel, src)
        load(controller.rightPaneViewModel, dst)

        controller.activatePane(.left)
        let folder = try XCTUnwrap(controller.leftPaneViewModel.state.files.first { $0.isDirectory })
        controller.leftPaneViewModel.selectFile(folder)
        controller.menuOpenInOther(nil)

        XCTAssertTrue(waitUntil { controller.rightPaneViewModel.state.path == sub },
                      "在另一侧打开应让右栏跳到该文件夹")
    }

    // MARK: - 2. 搜索

    func testSearchFiltersByNameAndClears() throws {
        let dir = try makeTempDir("search")
        try write("alpha.txt", in: dir)
        try write("beta.txt", in: dir)
        let vm = PaneViewModel()
        load(vm, dir)
        XCTAssertEqual(vm.state.files.count, 2)

        vm.setSearchQuery("alpha")
        XCTAssertTrue(waitUntil { vm.state.files.map(\.name) == ["alpha.txt"] },
                      "搜索应只保留匹配项")

        vm.setSearchQuery("")
        XCTAssertTrue(waitUntil { vm.state.files.count == 2 },
                      "清空搜索应恢复全部")
    }

    func testSearchPolicyLimits() {
        XCTAssertEqual(FFSearchPolicy.maxDepth, 3)
        XCTAssertEqual(FFSearchPolicy.maxResults, 500)
    }

    // MARK: - 3. 键盘与焦点

    func testCmdFFocusesActivePaneSearchField() {
        let controller = makeController()
        defer { controller.close() }
        controller.window?.makeKey()
        controller.activatePane(.left)

        controller.menuSearch(nil)

        let field = controller.leftPaneToolbar.searchFieldForTesting
        XCTAssertTrue(controller.window?.firstResponder === field.currentEditor(),
                      "⌘F 后焦点应在当前面板搜索框")
    }

    func testKeyViewLoopIncludesToolPillAndRows() {
        let controller = makeController()
        defer { controller.close() }
        controller.setSidebarVisible(true, animated: false)
        controller.sidebarView.toggleToolPage()

        let loop = controller.keyViewLoopForTesting()
        XCTAssertTrue(loop.contains(controller.sidebarView.toolPillFocusView),
                      "Tab 环应包含工具胶囊")
        let rows = controller.sidebarView.toolPageForTesting?.focusableViewsForTesting() ?? []
        XCTAssertEqual(rows.count, 5)
        XCTAssertTrue(rows.allSatisfy { loop.contains($0) },
                      "工具页 5 行都应在 Tab 环内")
    }

    func testTextEditingCopyDoesNotTouchFileClipboard() {
        let controller = makeController()
        defer { controller.close() }
        let field = controller.leftPaneToolbar.searchFieldForTesting
        controller.window?.makeFirstResponder(field)
        field.stringValue = "alpha"
        field.currentEditor()?.selectAll(nil)

        // 文本编辑中 ⌘C 应走 NSText.copy，而不是文件复制
        controller.menuCopy(nil)
        XCTAssertNil(NSPasteboard.general.string(forType: .fileURL),
                     "文本编辑中的复制不应写入文件 URL")
    }

    // MARK: - 4. 标签互通

    func testTagWriteUsesFinderBinaryPlistArray() throws {
        let dir = try makeTempDir("tag")
        let file = (dir as NSString).appendingPathComponent("note.txt")
        try "x".write(toFile: file, atomically: true, encoding: .utf8)

        let tag = Tag(name: "回归红", color: "#ff3b30")
        XCTAssertTrue(TagBridge.shared.setTags([tag], path: file))

        let data = try XCTUnwrap(xattr(file, "com.apple.metadata:_kMDItemUserTags"))
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let array = try XCTUnwrap(plist as? [String])
        XCTAssertTrue(array.contains { $0.hasPrefix("回归红\n") },
                      "写入必须是 Finder 的 binary plist 字符串数组，实际: \(array)")
    }

    func testTagReadsBackNativeTags() throws {
        let dir = try makeTempDir("tag_read")
        let file = (dir as NSString).appendingPathComponent("note.txt")
        try "x".write(toFile: file, atomically: true, encoding: .utf8)
        let tag = Tag(name: "读回绿", color: "#34c759")
        XCTAssertTrue(TagBridge.shared.setTags([tag], path: file))
        XCTAssertTrue(TagBridge.shared.getTags(path: file).contains { $0.name == "读回绿" })
    }

    // MARK: - 5. 设置生效

    func testFolderFirstSortOnAndOff() throws {
        let dir = try makeTempDir("sort")
        try FileManager.default.createDirectory(
            atPath: (dir as NSString).appendingPathComponent("z_folder"),
            withIntermediateDirectories: true)
        try write("a_file.txt", in: dir)

        let vm = PaneViewModel()
        load(vm, dir)
        XCTAssertEqual(vm.state.files.map(\.name), ["z_folder", "a_file.txt"],
                       "默认文件夹优先")

        defaults.set(false, forKey: FFUserDefaultsKeys.folderFirstSort)
        vm.refresh()
        XCTAssertTrue(waitUntil { vm.state.files.map(\.name) == ["a_file.txt", "z_folder"] },
                      "关闭文件夹优先后应按名称混排")
    }

    func testRefreshKeepsSelectionWhenEnabled() throws {
        let dir = try makeTempDir("keep_sel")
        try write("alpha.txt", in: dir)
        try write("beta.txt", in: dir)
        let vm = PaneViewModel()
        load(vm, dir)
        let alpha = try XCTUnwrap(vm.state.files.first { $0.name == "alpha.txt" })
        vm.selectFile(alpha)
        defaults.set(true, forKey: FFUserDefaultsKeys.keepSelectionPosition)

        vm.refresh()
        XCTAssertTrue(waitUntil { !vm.state.isLoading })
        XCTAssertEqual(vm.state.selectedFiles.map(\.name), ["alpha.txt"])
    }

    func testRefreshClearsSelectionWhenDisabled() throws {
        let dir = try makeTempDir("clear_sel")
        try write("alpha.txt", in: dir)
        try write("beta.txt", in: dir)
        let vm = PaneViewModel()
        load(vm, dir)
        let alpha = try XCTUnwrap(vm.state.files.first { $0.name == "alpha.txt" })
        vm.selectFile(alpha)
        defaults.set(false, forKey: FFUserDefaultsKeys.keepSelectionPosition)

        vm.refresh()
        XCTAssertTrue(waitUntil { !vm.state.isLoading })
        XCTAssertTrue(vm.state.selectedFiles.isEmpty)
    }

    // MARK: - 6. 静态 lint（棘轮）

    func testHardcodedTokenBudget() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // FlowFinderTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // FlowFinder (project dir)
            .deletingLastPathComponent()   // repo root
        let ui = root.appendingPathComponent("FlowFinder/FlowFinder/UI")
        let files = try FileManager.default.contentsOfDirectory(at: ui, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var fontCount = 0
        var colorCount = 0
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            fontCount += text.components(separatedBy: "NSFont.systemFont(ofSize:").count - 1
            colorCount += text.components(separatedBy: "NSColor(srgbRed:").count - 1
            colorCount += text.components(separatedBy: "NSColor(red:").count - 1
        }
        XCTAssertLessThanOrEqual(fontCount, 127, "硬编码字体不得增加（当前预算 127）")
        XCTAssertLessThanOrEqual(colorCount, 9, "颜色字面量不得增加（当前预算 9）")
    }

    // MARK: - 7. 权限用途声明

    func testRequiredUsageDescriptionsPresent() {
        let required = ["NSDesktopFolderUsageDescription",
                        "NSDocumentsFolderUsageDescription",
                        "NSDownloadsFolderUsageDescription",
                        "NSRemovableVolumesUsageDescription",
                        "NSNetworkVolumesUsageDescription"]
        for key in required {
            XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: key),
                            "Info.plist 缺少用途声明: \(key)")
        }
    }
}
