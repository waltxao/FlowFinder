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

    private func spinRunLoop(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.05)))
        }
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

    func testSearchScopeCurrentFiltersOnlyCurrentDirectory() throws {
        let dir = try makeTempDir("scope_current")
        let sub = (dir as NSString).appendingPathComponent("sub")
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        try write("alpha.txt", in: dir)
        try write("alpha-deep.txt", in: sub)
        let vm = PaneViewModel()
        load(vm, dir)

        vm.setSearchScope(.current)
        vm.setSearchQuery("alpha")
        XCTAssertTrue(waitUntil { vm.state.files.map(\.name) == ["alpha.txt"] })
        spinRunLoop(0.5)
        XCTAssertEqual(vm.state.files.map(\.name), ["alpha.txt"],
                       "本栏范围不得追加子目录结果")
    }

    func testSearchScopeRecursiveAppendsSubdirectoryMatches() throws {
        let dir = try makeTempDir("scope_recursive")
        let sub = (dir as NSString).appendingPathComponent("sub")
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        try write("alpha.txt", in: dir)
        try write("alpha-deep.txt", in: sub)
        let vm = PaneViewModel()
        load(vm, dir)

        vm.setSearchScope(.recursive)
        vm.setSearchQuery("alpha")
        XCTAssertTrue(waitUntil {
            Set(vm.state.files.map(\.name)) == Set(["alpha.txt", "alpha-deep.txt"])
        }, "含子目录范围应追加递归结果")
    }

    func testSearchScopeBothPanesFiltersCurrentDirectoryOnly() throws {
        let dir = try makeTempDir("scope_both")
        let sub = (dir as NSString).appendingPathComponent("sub")
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        try write("alpha.txt", in: dir)
        try write("alpha-deep.txt", in: sub)
        let vm = PaneViewModel()
        load(vm, dir)

        vm.setSearchScope(.bothPanes)
        vm.setSearchQuery("alpha")
        XCTAssertTrue(waitUntil { vm.state.files.map(\.name) == ["alpha.txt"] })
        spinRunLoop(0.5)
        XCTAssertEqual(vm.state.files.map(\.name), ["alpha.txt"],
                       "双栏范围只看各自当前目录，不递归")
    }

    func testSearchScopeBothPanesMirrorsQueryAcrossPanes() throws {
        let leftDir = try makeTempDir("scope_mirror_left")
        let rightDir = try makeTempDir("scope_mirror_right")
        try write("alpha-left.txt", in: leftDir)
        try write("beta-left.txt", in: leftDir)
        try write("alpha-right.txt", in: rightDir)
        try write("beta-right.txt", in: rightDir)
        let controller = makeController()
        defer { controller.close() }
        load(controller.leftPaneViewModel, leftDir)
        load(controller.rightPaneViewModel, rightDir)
        let leftToolbar = try XCTUnwrap(controller.leftPaneToolbar)
        let rightToolbar = try XCTUnwrap(controller.rightPaneToolbar)

        controller.paneToolbar(leftToolbar, didChangeSearchScope: .bothPanes)
        controller.paneToolbar(leftToolbar, didChangeSearchQuery: "alpha")

        XCTAssertTrue(waitUntil {
            Set(controller.leftPaneViewModel.state.files.map(\.name)) == ["alpha-left.txt"]
                && Set(controller.rightPaneViewModel.state.files.map(\.name)) == ["alpha-right.txt"]
        }, "双栏搜索应各自过滤当前目录")
        XCTAssertEqual(controller.leftPaneViewModel.state.searchScope, .bothPanes)
        XCTAssertEqual(controller.rightPaneViewModel.state.searchScope, .bothPanes)
        XCTAssertEqual(rightToolbar.searchFieldForTesting.stringValue, "alpha")
        XCTAssertEqual(rightToolbar.scopePopupForTesting.titleOfSelectedItem, "双栏")

        // 从右栏退出双栏：左栏停止镜像并恢复完整列表，右栏保留自己的搜索结果
        controller.paneToolbar(rightToolbar, didChangeSearchScope: .current)
        XCTAssertTrue(waitUntil {
            controller.leftPaneViewModel.state.searchQuery.isEmpty
                && controller.leftPaneViewModel.state.files.count == 2
        }, "退出双栏后左栏应恢复完整列表")
        XCTAssertEqual(controller.rightPaneViewModel.state.searchQuery, "alpha")
        XCTAssertEqual(Set(controller.rightPaneViewModel.state.files.map(\.name)), ["alpha-right.txt"])
        XCTAssertEqual(leftToolbar.searchFieldForTesting.stringValue, "")
        XCTAssertEqual(leftToolbar.scopePopupForTesting.titleOfSelectedItem, "本栏")
    }

    /// P1 回归：清空搜索后 Enter 不得落到首项并打开（否则会直接进入第一个文件夹）。
    func testSearchEnterWithEmptyQueryDoesNotOpenFirstItem() throws {
        let dir = try makeTempDir("search_enter_empty")
        let sub = (dir as NSString).appendingPathComponent("sub")
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        try write("alpha.txt", in: dir)
        let controller = makeController()
        defer { controller.close() }
        load(controller.leftPaneViewModel, dir)
        let toolbar = try XCTUnwrap(controller.leftPaneToolbar)

        // 先搜一次再清空，复现「搜完 → ⌘A/Delete → Enter」路径
        controller.paneToolbar(toolbar, didChangeSearchQuery: "alpha")
        XCTAssertTrue(waitUntil { controller.leftPaneViewModel.state.files.map(\.name) == ["alpha.txt"] })
        controller.paneToolbar(toolbar, didChangeSearchQuery: "")
        XCTAssertTrue(waitUntil { controller.leftPaneViewModel.state.files.count == 2 })

        controller.paneToolbarDidRequestOpenResult(toolbar)
        spinRunLoop(0.5)

        XCTAssertEqual(controller.leftPaneViewModel.state.path, dir, "空搜索词回车不得打开首项")
        XCTAssertTrue(controller.leftPaneViewModel.selectedFiles.isEmpty, "空搜索词回车不得自动选中首项")
    }

    /// P2 回归：移动走选中文件后，详情栏必须回到「未选择文件」
    func testDetailsBarClearsAfterMovedSelection() throws {
        let src = try makeTempDir("detail_src")
        let dst = try makeTempDir("detail_dst")
        try write("alpha.txt", in: src)
        let controller = makeController()
        defer { controller.close() }
        load(controller.leftPaneViewModel, src)
        load(controller.rightPaneViewModel, dst)

        controller.activatePane(.left)
        let alpha = try XCTUnwrap(controller.leftPaneViewModel.state.files.first)
        controller.leftPaneViewModel.selectFile(alpha)
        XCTAssertTrue(waitUntil { controller.leftDetailsBarForTesting?.compactNameForTesting ?? "<nil>" == "alpha.txt" })

        controller.menuMoveToOther(nil)
        let target = (dst as NSString).appendingPathComponent("alpha.txt")
        XCTAssertTrue(waitUntil(20) { FileManager.default.fileExists(atPath: target) })
        XCTAssertTrue(waitUntil(3) { controller.leftDetailsBarForTesting?.compactNameForTesting ?? "<nil>" == "未选择文件" },
                      "移动后详情栏应清空，实际=\(controller.leftDetailsBarForTesting?.compactNameForTesting ?? "<nil>")")
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

    // 2026-10-24：侧栏工具页已退役（工具迁到底栏右侧圆钮），原工具页 Tab 环测试删除。

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

// MARK: - J3-11: Finder 注释存取与旧数据迁移

final class FFFinderCommentStoreTests: XCTestCase {

    private var tempDir: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: "/tmp/ff-comment-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        suiteName = "FFFinderCommentStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        if let suiteName { defaults?.removePersistentDomain(forName: suiteName) }
        try super.tearDownWithError()
    }

    private func makeFile(_ name: String) throws -> String {
        let path = tempDir.appendingPathComponent(name).path
        try Data("x".utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    func testFinderCommentRoundTrip() throws {
        let path = try makeFile("roundtrip.txt")
        XCTAssertTrue(FFFinderCommentStore.write(path: path, comment: "第一行说明"))
        XCTAssertEqual(FFFinderCommentStore.read(path: path), "第一行说明")

        XCTAssertTrue(FFFinderCommentStore.write(path: path, comment: "  \n"))
        XCTAssertNil(FFFinderCommentStore.read(path: path), "空白说明应移除 xattr")
    }

    func testReadsPlainTextFallback() throws {
        let path = try makeFile("plain.txt")
        let data = Data("纯文本说明".utf8)
        let rc = data.withUnsafeBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return setxattr(path, FFFinderCommentStore.xattrName, base, data.count, 0, 0)
        }
        XCTAssertEqual(rc, 0)
        XCTAssertEqual(FFFinderCommentStore.read(path: path), "纯文本说明")
    }

    func testMigrationWritesOnlyWhenFinderCommentEmpty() throws {
        let migratedPath = try makeFile("migrated.txt")
        let existingPath = try makeFile("existing.txt")
        XCTAssertTrue(FFFinderCommentStore.write(path: existingPath, comment: "已有 Finder 说明"))
        let missingPath = tempDir.appendingPathComponent("missing.txt").path
        defaults.set([migratedPath: "旧说明 A",
                      existingPath: "旧说明 B",
                      missingPath: "失效路径说明"],
                     forKey: FFFinderCommentStore.legacyDefaultsKey)

        let report = FFFinderCommentStore.migrateLegacyDescriptionsIfNeeded(defaults: defaults)

        XCTAssertEqual(report.migrated, 1)
        XCTAssertEqual(report.keptLegacy, 2)
        XCTAssertEqual(report.failed, 0)
        XCTAssertEqual(FFFinderCommentStore.read(path: migratedPath), "旧说明 A")
        XCTAssertEqual(FFFinderCommentStore.read(path: existingPath), "已有 Finder 说明")

        let remaining = defaults.dictionary(forKey: FFFinderCommentStore.legacyDefaultsKey) as? [String: String]
        XCTAssertEqual(remaining?[existingPath], "旧说明 B")
        XCTAssertEqual(remaining?[missingPath], "失效路径说明")
        XCTAssertNil(remaining?[migratedPath])
        XCTAssertTrue(defaults.bool(forKey: FFFinderCommentStore.migrationDefaultsKey))
    }

    func testMigrationRunsOnlyOnce() throws {
        let path = try makeFile("once.txt")
        defaults.set([path: "第一次"], forKey: FFFinderCommentStore.legacyDefaultsKey)
        _ = FFFinderCommentStore.migrateLegacyDescriptionsIfNeeded(defaults: defaults)
        defaults.set([path: "第二次"], forKey: FFFinderCommentStore.legacyDefaultsKey)

        var writeCalls = 0
        let report = FFFinderCommentStore.migrateLegacyDescriptionsIfNeeded(
            defaults: defaults,
            writeComment: { _, _ in writeCalls += 1; return true }
        )

        XCTAssertTrue(report.skipped)
        XCTAssertEqual(writeCalls, 0)
        XCTAssertEqual(FFFinderCommentStore.read(path: path), "第一次")
    }

    func testMigrationKeepsEntryWhenWriteFails() throws {
        let path = try makeFile("fail.txt")
        defaults.set([path: "写不进去"], forKey: FFFinderCommentStore.legacyDefaultsKey)

        let report = FFFinderCommentStore.migrateLegacyDescriptionsIfNeeded(
            defaults: defaults,
            writeComment: { _, _ in false }
        )

        XCTAssertEqual(report.failed, 1)
        let remaining = defaults.dictionary(forKey: FFFinderCommentStore.legacyDefaultsKey) as? [String: String]
        XCTAssertEqual(remaining?[path], "写不进去")
        XCTAssertTrue(defaults.bool(forKey: FFFinderCommentStore.migrationDefaultsKey))
    }
}

// MARK: - J2-07 搜索范围

final class FFSearchScopeTests: XCTestCase {

    func testScopeTitlesAndBehavior() {
        XCTAssertEqual(FFSearchScope.current.title, "本栏")
        XCTAssertEqual(FFSearchScope.recursive.title, "含子目录")
        XCTAssertEqual(FFSearchScope.bothPanes.title, "双栏")
        XCTAssertTrue(FFSearchScope.recursive.searchesSubdirectories)
        XCTAssertFalse(FFSearchScope.current.searchesSubdirectories)
        XCTAssertFalse(FFSearchScope.bothPanes.searchesSubdirectories)
        XCTAssertTrue(FFSearchScope.bothPanes.searchesBothPanes)
        XCTAssertFalse(FFSearchScope.recursive.searchesBothPanes)
    }

    func testToolbarExposesScopeMenu() {
        let toolbar = PaneToolbar(frame: NSRect(x: 0, y: 0, width: 900, height: 72))
        XCTAssertEqual(toolbar.scopePopupForTesting.itemTitles, ["本栏", "含子目录", "双栏"])
        XCTAssertEqual(toolbar.scopePopupForTesting.accessibilityLabel(), "搜索范围")

        toolbar.setSearchScope(.bothPanes)
        XCTAssertEqual(toolbar.scopePopupForTesting.titleOfSelectedItem, "双栏")
    }

    func testToolbarSearchFieldCanBeProgrammaticallyUpdated() {
        let toolbar = PaneToolbar(frame: NSRect(x: 0, y: 0, width: 900, height: 72))
        toolbar.setSearchQuery("报告")
        XCTAssertEqual(toolbar.searchFieldForTesting.stringValue, "报告")
    }

    func testToolbarSortAndGroupPopupsSyncFromState() {
        let toolbar = PaneToolbar(frame: NSRect(x: 0, y: 0, width: 900, height: 72))

        toolbar.setSortField(.size)
        XCTAssertEqual(toolbar.sortPopupForTesting.titleOfSelectedItem, "大小")

        toolbar.setGroupBy("kind")
        XCTAssertEqual(toolbar.groupPopupForTesting.titleOfSelectedItem, "按种类")
        toolbar.setGroupBy("date")
        XCTAssertEqual(toolbar.groupPopupForTesting.titleOfSelectedItem, "按日期")
        toolbar.setGroupBy("size")
        XCTAssertEqual(toolbar.groupPopupForTesting.titleOfSelectedItem, "按大小")
        toolbar.setGroupBy("none")
        XCTAssertEqual(toolbar.groupPopupForTesting.titleOfSelectedItem, "无分组")
    }
}

// MARK: - P0 rename collision

final class FFRenameCollisionTests: XCTestCase {

    private func makeTempDir() throws -> String {
        let dir = "/tmp/ff_rename_collision_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    func testRenameToExistingFileDoesNotOverwrite() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let source = (dir as NSString).appendingPathComponent("a.txt")
        let existing = (dir as NSString).appendingPathComponent("b.txt")
        try "source".write(toFile: source, atomically: true, encoding: .utf8)
        try "existing".write(toFile: existing, atomically: true, encoding: .utf8)

        let vm = PaneViewModel()
        vm.renameFile(source, to: "b.txt")

        XCTAssertEqual(try String(contentsOfFile: existing, encoding: .utf8), "existing",
                       "同名目标文件不得被重命名覆盖")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source),
                      "冲突时源文件应保留")
        XCTAssertNotNil(vm.state.error)
        XCTAssertTrue(vm.state.error?.contains("已存在") == true)
    }

    func testRenameToFreshNameStillWorks() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let source = (dir as NSString).appendingPathComponent("a.txt")
        let target = (dir as NSString).appendingPathComponent("c.txt")
        try "source".write(toFile: source, atomically: true, encoding: .utf8)

        let vm = PaneViewModel()
        vm.renameFile(source, to: "c.txt")

        XCTAssertFalse(FileManager.default.fileExists(atPath: source))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target))
    }
}
