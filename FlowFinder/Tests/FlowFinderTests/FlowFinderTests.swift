import AppKit
import XCTest
@testable import FlowFinder

final class FlowFinderTests: XCTestCase {

    // MARK: - FFI Loading Tests

    func testLibraryCanBeLoaded() {
        // The dylib is bundled at Contents/Frameworks and loaded via @rpath by
        // the "Copy Dylib to Bundle" build phase, so that is the authoritative
        // location to assert against.
        let bundledPath = Bundle.main.bundlePath + "/Contents/Frameworks/libflowfinder_core.dylib"
        let fileManager = FileManager.default

        var libraryExists = fileManager.fileExists(atPath: bundledPath)

        if !libraryExists {
            let projectLibPath = "./FlowFinder/Libraries/libflowfinder_core.dylib"
            libraryExists = fileManager.fileExists(atPath: projectLibPath)
        }

        XCTAssertTrue(libraryExists, "Rust core library (libflowfinder_core.dylib) should exist")
    }

    // MARK: - CoreBridge Tests

    func testCoreBridgeSingleton() {
        let bridge1 = CoreBridge.shared
        let bridge2 = CoreBridge.shared
        XCTAssertTrue(bridge1 === bridge2, "CoreBridge.shared should return the same instance")
    }

    func testListDirectoryReturnsEntries() throws {
        let bridge = CoreBridge.shared
        let testPath = FileManager.default.currentDirectoryPath

        let entries = try bridge.listDirectory(path: testPath)
        XCTAssertGreaterThanOrEqual(entries.count, 0, "listDirectory should return an array (may be empty)")
    }

    func testListDirectoryWithInvalidPathThrows() {
        let bridge = CoreBridge.shared
        let invalidPath = "/nonexistent/path/that/does/not/exist"

        XCTAssertThrowsError(try bridge.listDirectory(path: invalidPath)) { error in
            XCTAssertTrue(error is CoreBridgeError, "Should throw CoreBridgeError")
        }
    }

    func testListDirectoryWithEmptyPathThrows() {
        let bridge = CoreBridge.shared

        XCTAssertThrowsError(try bridge.listDirectory(path: "")) { error in
            XCTAssertTrue(error is CoreBridgeError, "Should throw CoreBridgeError for empty path")
        }
    }

    // MARK: - File Operations Tests

    func testCopyFile() throws {
        let bridge = CoreBridge.shared
        let tmpDir = FileManager.default.temporaryDirectory
        let srcPath = tmpDir.appendingPathComponent("test_src.txt").path
        let dstPath = tmpDir.appendingPathComponent("test_dst.txt").path

        try? FileManager.default.removeItem(atPath: srcPath)
        try? FileManager.default.removeItem(atPath: dstPath)

        try "hello world".write(toFile: srcPath, atomically: true, encoding: .utf8)
        try bridge.copyFile(src: srcPath, dst: dstPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: dstPath), "Destination file should exist after copy")

        try? FileManager.default.removeItem(atPath: srcPath)
        try? FileManager.default.removeItem(atPath: dstPath)
    }

    func testMoveFile() throws {
        let bridge = CoreBridge.shared
        let tmpDir = FileManager.default.temporaryDirectory
        let srcPath = tmpDir.appendingPathComponent("test_move_src.txt").path
        let dstPath = tmpDir.appendingPathComponent("test_move_dst.txt").path

        try? FileManager.default.removeItem(atPath: srcPath)
        try? FileManager.default.removeItem(atPath: dstPath)

        try "move me".write(toFile: srcPath, atomically: true, encoding: .utf8)
        try bridge.moveFile(src: srcPath, dst: dstPath)

        XCTAssertFalse(FileManager.default.fileExists(atPath: srcPath), "Source file should not exist after move")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstPath), "Destination file should exist after move")

        try? FileManager.default.removeItem(atPath: dstPath)
    }

    func testDeleteFile() throws {
        let bridge = CoreBridge.shared
        let tmpDir = FileManager.default.temporaryDirectory
        let filePath = tmpDir.appendingPathComponent("test_delete.txt").path

        try? FileManager.default.removeItem(atPath: filePath)

        try "delete me".write(toFile: filePath, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath), "File should exist before delete")

        try bridge.deleteFile(path: filePath)

        XCTAssertFalse(FileManager.default.fileExists(atPath: filePath), "File should not exist after delete")
    }

    func testCreateAndDeleteDirectory() throws {
        let bridge = CoreBridge.shared
        let tmpDir = FileManager.default.temporaryDirectory
        let dirPath = tmpDir.appendingPathComponent("test_create_dir").path

        try? FileManager.default.removeItem(atPath: dirPath)

        try bridge.createDirectory(path: dirPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirPath), "Directory should exist after create")

        try bridge.deleteDirectory(path: dirPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dirPath), "Directory should not exist after delete")
    }

    func testRenameFile() throws {
        let bridge = CoreBridge.shared
        let tmpDir = FileManager.default.temporaryDirectory
        let srcPath = tmpDir.appendingPathComponent("test_rename_old.txt").path
        let dstPath = tmpDir.appendingPathComponent("test_rename_new.txt").path

        try? FileManager.default.removeItem(atPath: srcPath)
        try? FileManager.default.removeItem(atPath: dstPath)

        try "rename me".write(toFile: srcPath, atomically: true, encoding: .utf8)
        try bridge.renameFile(src: srcPath, dst: dstPath)

        XCTAssertFalse(FileManager.default.fileExists(atPath: srcPath), "Old file should not exist after rename")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstPath), "New file should exist after rename")

        try? FileManager.default.removeItem(atPath: dstPath)
    }

    func testParallelCopySingleFile() throws {
        // The async copy path is now `parallelCopy` (rayon-backed batch copy into
        // a destination directory, preserving basenames). It returns the number of
        // successfully copied files and throws on a negative FFI result.
        let bridge = CoreBridge.shared
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
        let srcDir = tmpDir.appendingPathComponent("ff_t11_copy_src_\(UUID().uuidString)")
        let dstDir = tmpDir.appendingPathComponent("ff_t11_copy_dst_\(UUID().uuidString)")
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: srcDir)
            try? fm.removeItem(at: dstDir)
        }

        let srcPath = srcDir.appendingPathComponent("test_async_src.txt").path
        try "async copy".write(toFile: srcPath, atomically: true, encoding: .utf8)

        let copied = try bridge.parallelCopy(srcs: [srcPath], dstDir: dstDir.path)

        XCTAssertEqual(copied, 1, "parallelCopy should report exactly one copied file")
        let dstPath = dstDir.appendingPathComponent("test_async_src.txt").path
        XCTAssertTrue(fm.fileExists(atPath: dstPath), "Destination file should exist after parallel copy")
    }

    func testParallelMoveSingleFile() throws {
        // The async move path is `parallelMove` (rayon-backed batch move). The
        // source disappears and the destination appears, preserving the
        // "async file operation" intent of the removed async-delete API.
        let bridge = CoreBridge.shared
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
        let srcDir = tmpDir.appendingPathComponent("ff_t11_move_src_\(UUID().uuidString)")
        let dstDir = tmpDir.appendingPathComponent("ff_t11_move_dst_\(UUID().uuidString)")
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: srcDir)
            try? fm.removeItem(at: dstDir)
        }

        let srcPath = srcDir.appendingPathComponent("test_async_move.txt").path
        try "async move".write(toFile: srcPath, atomically: true, encoding: .utf8)

        let moved = try bridge.parallelMove(srcs: [srcPath], dstDir: dstDir.path)

        XCTAssertEqual(moved, 1, "parallelMove should report exactly one moved file")
        XCTAssertFalse(fm.fileExists(atPath: srcPath), "Source file should no longer exist after parallel move")
        let dstPath = dstDir.appendingPathComponent("test_async_move.txt").path
        XCTAssertTrue(fm.fileExists(atPath: dstPath), "Destination file should exist after parallel move")
    }

    // MARK: - FileEntry Tests

    func testFileEntryInitialization() {
        let entry = FileEntry(
            path: "/test/path/file.txt",
            name: "file.txt",
            isDirectory: false,
            size: 1024,
            modificationDate: Date()
        )

        XCTAssertEqual(entry.path, "/test/path/file.txt")
        XCTAssertEqual(entry.name, "file.txt")
        XCTAssertFalse(entry.isDirectory)
        XCTAssertEqual(entry.size, 1024)
        XCTAssertEqual(entry.fileExtension, "txt")
        XCTAssertEqual(entry.displayName, "file")
    }

    func testFileEntryDirectoryProperties() {
        let entry = FileEntry(
            path: "/test/path",
            name: "path",
            isDirectory: true,
            size: 0,
            modificationDate: Date()
        )

        XCTAssertTrue(entry.isDirectory)
        XCTAssertEqual(entry.formattedSize, "--", "Directory should show -- for size")
        XCTAssertEqual(entry.displayName, "path", "Directory display name should be the name")
    }

    func testFileEntryKindDescription() {
        let jpgEntry = FileEntry(path: "/test.jpg", name: "test.jpg", isDirectory: false)
        XCTAssertEqual(jpgEntry.kindDescription, "JPEG 图像")

        let pdfEntry = FileEntry(path: "/test.pdf", name: "test.pdf", isDirectory: false)
        XCTAssertEqual(pdfEntry.kindDescription, "PDF 文档")

        let unknownEntry = FileEntry(path: "/test.xyz", name: "test.xyz", isDirectory: false)
        XCTAssertEqual(unknownEntry.kindDescription, "XYZ 文件")

        let dirEntry = FileEntry(path: "/testdir", name: "testdir", isDirectory: true)
        XCTAssertEqual(dirEntry.kindDescription, "文件夹")
    }

    func testFileEntryFormattedSize() {
        let smallFile = FileEntry(path: "/small.txt", name: "small.txt", isDirectory: false, size: 512, modificationDate: Date())
        let sizeString = smallFile.formattedSize
        XCTAssertFalse(sizeString.isEmpty, "Formatted size should not be empty")
    }

    // MARK: - PaneViewModel Tests

    func testViewModelInitialState() {
        let viewModel = PaneViewModel()
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
        XCTAssertEqual(viewModel.currentPath, "")
    }

    func testViewModelNavigateToPath() {
        let viewModel = PaneViewModel()
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        viewModel.navigate(to: homePath)

        XCTAssertEqual(viewModel.currentPath, homePath)
    }

    // MARK: - Error Tests

    func testCoreBridgeErrorDescriptions() {
        let ffiError = CoreBridgeError.ffiError("test error")
        XCTAssertEqual(ffiError.errorDescription, "FFI Error: test error")

        let invalidPath = CoreBridgeError.invalidPath("/bad/path")
        XCTAssertEqual(invalidPath.errorDescription, "Invalid path: /bad/path")

        let conversion = CoreBridgeError.stringConversionFailed
        XCTAssertEqual(conversion.errorDescription, "Failed to convert string to C string")

        let notLoaded = CoreBridgeError.rustCoreNotLoaded
        XCTAssertEqual(notLoaded.errorDescription, "Rust core library not loaded")
    }

    // MARK: - Duplicate Scan Bridge Tests

    func testDuplicateScanBridgeSingleton() {
        let bridge1 = DuplicateScanBridge.shared
        let bridge2 = DuplicateScanBridge.shared
        XCTAssertTrue(bridge1 === bridge2, "DuplicateScanBridge.shared should return the same instance")
    }

    func testDuplicateScanBridgeCancelScan() {
        let bridge = DuplicateScanBridge.shared
        // Should not crash when cancel is called without active scan
        bridge.cancelScan()
    }

    // MARK: - Search Bridge Tests

    func testSearchBridgeSingleton() {
        let bridge1 = SearchBridge.shared
        let bridge2 = SearchBridge.shared
        XCTAssertTrue(bridge1 === bridge2, "SearchBridge.shared should return the same instance")
    }

    // MARK: - Search Filters Tests

    func testSearchFiltersInitialization() {
        let filters = FFSearchFilters(
            fileTypes: "jpg,png",
            minSize: 1024,
            maxSize: 1048576
        )

        XCTAssertEqual(filters.fileTypes, "jpg,png")
        XCTAssertEqual(filters.minSize, 1024)
        XCTAssertEqual(filters.maxSize, 1048576)
        XCTAssertNil(filters.modifiedAfter)
        XCTAssertNil(filters.modifiedBefore)
    }

    func testSearchFiltersDefaultInitialization() {
        let filters = FFSearchFilters()

        XCTAssertNil(filters.fileTypes)
        XCTAssertNil(filters.minSize)
        XCTAssertNil(filters.maxSize)
        XCTAssertNil(filters.modifiedAfter)
        XCTAssertNil(filters.modifiedBefore)
    }

    // MARK: - Duplicate Group Tests

    func testDuplicateFileInitialization() {
        let file = FFDuplicateFile(
            id: "test-id",
            path: "/test/path/file.txt",
            name: "file.txt",
            size: 1024,
            modified: 1234567890
        )

        XCTAssertEqual(file.id, "test-id")
        XCTAssertEqual(file.path, "/test/path/file.txt")
        XCTAssertEqual(file.name, "file.txt")
        XCTAssertEqual(file.size, 1024)
        XCTAssertEqual(file.modified, 1234567890)
    }

    func testDuplicateGroupInitialization() {
        let files = [
            FFDuplicateFile(id: "1", path: "/a.txt", name: "a.txt", size: 100, modified: 0),
            FFDuplicateFile(id: "2", path: "/b.txt", name: "b.txt", size: 100, modified: 0)
        ]

        let group = FFDuplicateGroup(
            id: "group-1",
            hash: "abc123",
            size: 100,
            files: files
        )

        XCTAssertEqual(group.id, "group-1")
        XCTAssertEqual(group.hash, "abc123")
        XCTAssertEqual(group.size, 100)
        XCTAssertEqual(group.files.count, 2)
    }

    // MARK: - Search Result Tests

    func testSearchResultInitialization() {
        let result = FFSearchResult(
            path: "/test/file.txt",
            name: "file.txt",
            size: 1024,
            modified: 1234567890,
            isDir: false
        )

        XCTAssertEqual(result.path, "/test/file.txt")
        XCTAssertEqual(result.name, "file.txt")
        XCTAssertEqual(result.size, 1024)
        XCTAssertEqual(result.modified, 1234567890)
        XCTAssertFalse(result.isDir)
    }

    func testSearchResultDirectory() {
        let result = FFSearchResult(
            path: "/test/folder",
            name: "folder",
            size: 0,
            modified: 1234567890,
            isDir: true
        )

        XCTAssertTrue(result.isDir)
        XCTAssertEqual(result.size, 0)
    }
}

// MARK: - FFDividerGlowMath（分隔线手柄光效纯计算）

final class FFDividerGlowMathTests: XCTestCase {

    /// 逐元素带精度断言（XCTest 无数组 accuracy 重载，直接传数组会编译失败）
    private func assertLocations(_ actual: [CGFloat], _ expected: [CGFloat],
                                 file: StaticString = #filePath, line: UInt = #line) {
        guard actual.count == expected.count else {
            XCTFail("locations 数量不符: \(actual) vs \(expected)", file: file, line: line)
            return
        }
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a, e, accuracy: 0.0001, file: file, line: line)
        }
    }

    // MARK: glowCenter — 鼠标 Y → 渐变轴中心比例

    func testGlowCenterTopMiddleBottom() {
        // AppKit 对 layer-backed 视图保持 layer 与 view 翻转一致，
        // f = mouseY/height 恒成立：视图高 800 时顶部 800→1.0、中部 400→0.5、底部 0→0.0
        XCTAssertEqual(FFDividerGlowMath.glowCenter(mouseY: 800, boundsHeight: 800), 1.0, accuracy: 0.0001)
        XCTAssertEqual(FFDividerGlowMath.glowCenter(mouseY: 400, boundsHeight: 800), 0.5, accuracy: 0.0001)
        XCTAssertEqual(FFDividerGlowMath.glowCenter(mouseY: 0, boundsHeight: 800), 0.0, accuracy: 0.0001)
    }

    func testGlowCenterClampsOutOfRangeMouseY() {
        // 事件坐标可能越界（拖拽划出窗口），clamp 到 [0,1]
        XCTAssertEqual(FFDividerGlowMath.glowCenter(mouseY: 1000, boundsHeight: 800), 1.0, accuracy: 0.0001)
        XCTAssertEqual(FFDividerGlowMath.glowCenter(mouseY: -50, boundsHeight: 800), 0.0, accuracy: 0.0001)
    }

    func testGlowCenterZeroHeightSafeDefault() {
        // 高度 0（窗口最小化等）时返回 0.5 正中，避免除零
        XCTAssertEqual(FFDividerGlowMath.glowCenter(mouseY: 0, boundsHeight: 0), 0.5, accuracy: 0.0001)
    }

    // MARK: gradientLocations — 中心比例 + 渐隐半径比例 → locations

    func testGradientLocationsCentered() {
        assertLocations(FFDividerGlowMath.gradientLocations(center: 0.5, radiusFraction: 0.15),
                        [0.35, 0.5, 0.65])
    }

    func testGradientLocationsClampsAtBottomEdge() {
        // 亮点贴边：下端截断为 0，locations 仍保持递增（贴边截断需求）
        assertLocations(FFDividerGlowMath.gradientLocations(center: 0.02, radiusFraction: 0.1),
                        [0.0, 0.02, 0.12])
    }

    func testGradientLocationsClampsAtTopEdge() {
        assertLocations(FFDividerGlowMath.gradientLocations(center: 0.98, radiusFraction: 0.1),
                        [0.88, 0.98, 1.0])
    }

    func testGradientLocationsOversizedRadiusClamps() {
        assertLocations(FFDividerGlowMath.gradientLocations(center: 0.5, radiusFraction: 1.5),
                        [0.0, 0.5, 1.0])
    }

    func testGradientLocationsOutOfRangeCenterStillOrdered() {
        // 防御：中心超出 [0,1] 时先收敛再算端点，保证 locations 恒有序
        assertLocations(FFDividerGlowMath.gradientLocations(center: 1.2, radiusFraction: 0.1),
                        [0.9, 1.0, 1.0])
    }

    // MARK: clampedDividerPosition — 鼠标 X → 分隔线目标位置

    func testClampedDividerPositionWithinRange() {
        XCTAssertEqual(FFDividerGlowMath.clampedDividerPosition(mouseX: 500, boundsWidth: 1400), 500)
        XCTAssertEqual(FFDividerGlowMath.clampedDividerPosition(mouseX: 460, boundsWidth: 1400), 460)
    }

    func testClampedDividerPositionEnforcesMinPaneWidth() {
        XCTAssertEqual(FFDividerGlowMath.clampedDividerPosition(mouseX: 100, boundsWidth: 1400), 450)
    }

    func testClampedDividerPositionEnforcesMaxPaneWidth() {
        // 左侧最大 = 总宽 - 450（右面板最小宽度）
        XCTAssertEqual(FFDividerGlowMath.clampedDividerPosition(mouseX: 1300, boundsWidth: 1400), 950)
    }

    func testClampedDividerPositionNarrowWindow() {
        // 窗口过窄（<900pt）时上下限收敛到 450
        XCTAssertEqual(FFDividerGlowMath.clampedDividerPosition(mouseX: 700, boundsWidth: 800), 450)
        XCTAssertEqual(FFDividerGlowMath.clampedDividerPosition(mouseX: 100, boundsWidth: 800), 450)
    }

    /// DESIGN-SPEC B-01：侧栏分隔用 160 最小宽，右侧仍是操作区 450 保底。
    /// 侧栏可拖 160–280，故 160 不能被双操作区的 450 覆盖。
    func testClampedDividerPositionSidebarLeadingMin() {
        XCTAssertEqual(
            FFDividerGlowMath.clampedDividerPosition(mouseX: 100, boundsWidth: 1400, leadingMin: 160),
            160
        )
        XCTAssertEqual(
            FFDividerGlowMath.clampedDividerPosition(mouseX: 240, boundsWidth: 1400, leadingMin: 160),
            240
        )
        // 上限仍受右侧 450 保底约束
        XCTAssertEqual(
            FFDividerGlowMath.clampedDividerPosition(mouseX: 1200, boundsWidth: 1400, leadingMin: 160),
            950
        )
    }
}

// MARK: - FFDetailsFlowLayout（详情栏流动填充分配）

final class FFDetailsFlowLayoutTests: XCTestCase {

    func testFlowSplitBasic() {
        // 4 行每行 16pt、间距 4：累计 16/36/56/76
        XCTAssertEqual(FFDetailsFlowLayout.flowSplit(itemHeights: [16, 16, 16, 16], availableHeight: 68), 3)
        XCTAssertEqual(FFDetailsFlowLayout.flowSplit(itemHeights: [16, 16, 16, 16], availableHeight: 76), 4)
    }

    func testFlowSplitUneven() {
        // 首行较高（如名称行）：30/50/70 → 恰好 3 行
        XCTAssertEqual(FFDetailsFlowLayout.flowSplit(itemHeights: [30, 16, 16, 16, 16], availableHeight: 70), 3)
    }

    func testFlowSplitAtLeastOne() {
        // 可用高度不足首行时仍返回 1（名称行始终可见）；高度 0 同理
        XCTAssertEqual(FFDetailsFlowLayout.flowSplit(itemHeights: [30, 16, 16], availableHeight: 10), 1)
        XCTAssertEqual(FFDetailsFlowLayout.flowSplit(itemHeights: [16, 16], availableHeight: 0), 1)
    }

    func testFlowSplitEmpty() {
        XCTAssertEqual(FFDetailsFlowLayout.flowSplit(itemHeights: [], availableHeight: 100), 0)
    }

    func testVisibleItemCountBothColumns() {
        let heights = [CGFloat](repeating: 16, count: 10)
        // 列1 装 3，剩余 7 中列2 再装 3 → 可见 6
        XCTAssertEqual(FFDetailsFlowLayout.visibleItemCount(itemHeights: heights, availableHeight: 68), 6)
        // 列1 装 6（累计 116）、剩余 4 全进列2 → 全可见
        XCTAssertEqual(FFDetailsFlowLayout.visibleItemCount(itemHeights: heights, availableHeight: 120), 10)
    }

    func testVisibleItemCountEmpty() {
        XCTAssertEqual(FFDetailsFlowLayout.visibleItemCount(itemHeights: [], availableHeight: 100), 0)
    }

    // MARK: - 多列自适应（D-05 / D-06）

    func testMaxColumnLimitByWidth() {
        // (宽度 + 间距) / (最小列宽 + 间距)，向下取整，上限 4
        XCTAssertEqual(FFDetailsFlowLayout.maxColumnLimit(forWidth: 300), 1)   // 308/178 = 1.7
        XCTAssertEqual(FFDetailsFlowLayout.maxColumnLimit(forWidth: 400), 2)   // 408/178 = 2.2
        XCTAssertEqual(FFDetailsFlowLayout.maxColumnLimit(forWidth: 600), 3)   // 608/178 = 3.4
        XCTAssertEqual(FFDetailsFlowLayout.maxColumnLimit(forWidth: 2000), 4)  // 受上限 4 约束
        XCTAssertEqual(FFDetailsFlowLayout.maxColumnLimit(forWidth: 0), 1)     // 下限 1
    }

    func testColumnCountGrowsWithAvailableHeight() {
        let heights = [CGFloat](repeating: 16, count: 8)
        let width: CGFloat = 900  // 4 列可用
        // 总高 = 16*8 + 4*7 = 156
        XCTAssertEqual(FFDetailsFlowLayout.columnCount(itemHeights: heights, availableHeight: 160, availableWidth: width), 1)
        // 80 装不下 8 行 → 需要更多列
        XCTAssertGreaterThan(FFDetailsFlowLayout.columnCount(itemHeights: heights, availableHeight: 80, availableWidth: width), 1)
        // 高度极小时取上限
        XCTAssertEqual(FFDetailsFlowLayout.columnCount(itemHeights: heights, availableHeight: 16, availableWidth: width), 4)
    }

    func testColumnCountRespectsWidthLimit() {
        let heights = [CGFloat](repeating: 16, count: 20)
        // 宽度只够 2 列：即使高度不足也不应超过 2 列
        XCTAssertEqual(FFDetailsFlowLayout.columnCount(itemHeights: heights, availableHeight: 16, availableWidth: 400), 2)
    }

    func testDistributeIsBalancedAndOrdered() {
        let heights = [CGFloat](repeating: 16, count: 6)
        let columns = FFDetailsFlowLayout.distribute(itemHeights: heights, columnCount: 2)
        // 均衡：各 3 行
        XCTAssertEqual(columns.count, 2)
        XCTAssertEqual(columns[0], [0, 1, 2])
        XCTAssertEqual(columns[1], [3, 4, 5])
    }

    func testDistributeKeepsOrderAcrossColumns() {
        let heights: [CGFloat] = [40, 16, 16, 16, 16, 16]
        let columns = FFDetailsFlowLayout.distribute(itemHeights: heights, columnCount: 2)
        let flattened = columns.flatMap { $0 }
        // 顺序必须保持（阅读顺序不可乱）
        XCTAssertEqual(flattened, flattened.sorted())
        XCTAssertEqual(Set(flattened).count, heights.count)
        // 首行最高，应落在第一列首项
        XCTAssertEqual(columns.first?.first, 0)
    }

    func testColumnLayoutNeverOverflowsHeight() {
        let heights = [CGFloat](repeating: 30, count: 12)
        let layout = FFDetailsFlowLayout.columnLayout(
            itemHeights: heights,
            availableHeight: 50,        // 每列最多 1 行（30 + 4 + 30 = 64 > 50）
            availableWidth: 900
        )
        for column in layout {
            XCTAssertLessThanOrEqual(
                FFDetailsFlowLayout.columnHeight(of: column, itemHeights: heights),
                50
            )
        }
        // 4 列各 1 行 → 最多可见 4 行，其余隐藏
        XCTAssertLessThanOrEqual(layout.flatMap { $0 }.count, 4)
    }

    func testColumnLayoutSingleColumnWhenHeightPlenty() {
        let heights = [CGFloat](repeating: 16, count: 3)
        let layout = FFDetailsFlowLayout.columnLayout(
            itemHeights: heights,
            availableHeight: 500,
            availableWidth: 900
        )
        XCTAssertEqual(layout.count, 1)
        XCTAssertEqual(layout[0], [0, 1, 2])
    }

    func testColumnLayoutEmptyInput() {
        XCTAssertTrue(FFDetailsFlowLayout.columnLayout(itemHeights: [], availableHeight: 100, availableWidth: 900).isEmpty)
    }
}

// MARK: - FFDetailsBarLayoutTests（详情栏三模块布局回归）

final class FFDetailsBarLayoutTests: XCTestCase {

    /// 记忆键快照（测试清理用，复核 Minor 2）
    private var barDefaultsSnapshot: Any?


    @MainActor
    func testExpandedDividerStripsHaveFullHeight() {
        // modules 高度确定链回归：展开后两条分界线热区必须有完整高度（曾因
        // modules.bottom 为 lessThanOrEqual 而无高度来源，布局歧义塌缩为 0）
        // 测试不依赖用户机器上的记忆值，保持布局日志干净
        barDefaultsSnapshot = UserDefaults.standard.object(forKey: "FFDetailsBarExpandedHeight")
        UserDefaults.standard.removeObject(forKey: "FFDetailsBarExpandedHeight")
        defer {
            // 快照恢复（复核 Minor 2 补全：不在测试域留下删除痕迹）
            if let snapshot = barDefaultsSnapshot {
                UserDefaults.standard.set(snapshot, forKey: "FFDetailsBarExpandedHeight")
            } else {
                UserDefaults.standard.removeObject(forKey: "FFDetailsBarExpandedHeight")
            }
        }
        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 210))
        bar.isExpanded = true
        bar.layoutSubtreeIfNeeded()

        // 期望值由栏自身尺寸推导，不依赖默认展开高度记忆值
        let expected = bar.frame.height - 6 - 18
        XCTAssertEqual(bar.dividerIconToCol1.bounds.height, expected, accuracy: 1.0)
        // D-05 起信息区内部不再有分界线（列宽等分、列数按高度推导），
        // 改为核对各可见列高度一致（等分后并排、同一 top/bottom）
        let visibleHeights = bar.infoColumns.filter { !$0.isHidden }.map { $0.bounds.height }
        XCTAssertFalse(visibleHeights.isEmpty)
        for height in visibleHeights {
            XCTAssertEqual(height, visibleHeights[0], accuracy: 1.0)
        }
    }
}

// MARK: - 类型专属行注册表 × 流动填充 回归（审查 Critical 修复）

final class FFDetailsBarTypeRowsFlowTests: XCTestCase {

    /// 记忆键快照（测试清理用，复核 Minor 2）
    private var barDefaultsSnapshot: Any?


    /// 审查修复回归：rearrangeFlow 多次执行后，类型专属行仍持有于注册表并被列摆放。
    /// 此前 setColumn 的注销副作用会在测量步骤清空 appendedTypeInfoRows，导致
    /// 分界线拖拽/窗口尺寸变化后的下一次重排把专属信息（分辨率/EXIF 等）整段摘除。
    @MainActor
    func testTypeSpecificRowsSurviveRepeatedRearrange() throws {
        // 写一个真实 PNG 到临时目录（CGImageSource 可读出像素宽高），使
        // gatherImageInfo 产出 ≥1 条专属信息行（分辨率/尺寸/文件大小…）
        let ctx = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        let cgImage = try XCTUnwrap(ctx?.makeImage(), "应能生成 8×8 位图")
        let pngData = try XCTUnwrap(
            NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]),
            "应能编码为 PNG")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowfinder-type-rows-\(UUID().uuidString).png")
        try pngData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let entry = FileEntry(path: url.path, name: url.lastPathComponent, isDirectory: false)

        // 测试不依赖用户机器上的记忆值，保持布局日志干净
        barDefaultsSnapshot = UserDefaults.standard.object(forKey: "FFDetailsBarExpandedHeight")
        UserDefaults.standard.removeObject(forKey: "FFDetailsBarExpandedHeight")
        defer {
            // 快照恢复（复核 Minor 2 补全：不在测试域留下删除痕迹）
            if let snapshot = barDefaultsSnapshot {
                UserDefaults.standard.set(snapshot, forKey: "FFDetailsBarExpandedHeight")
            } else {
                UserDefaults.standard.removeObject(forKey: "FFDetailsBarExpandedHeight")
            }
        }

        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        // 用普通容器承载（不用 NSWindow：窗口簿记延迟块与测试裸释放竞态，曾致运行器 SIGSEGV）
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        container.addSubview(bar)
        bar.isExpanded = true

        bar.update(with: [entry])
        container.layoutSubtreeIfNeeded()

        // 多次重排，等价于分界线拖拽/高度拖拽/窗口尺寸变化的触发路径
        bar.rearrangeFlow()
        bar.rearrangeFlow()

        // 6 常规行 + ≥1 专属行 + 3 常规行：专属行必须仍在流动顺序中
        let flow = bar.flowOrderedRows
        XCTAssertTrue(flow.count > 9,
                      "专属信息行应保留在流动顺序中（6 常规 + ≥1 专属 + 3 常规），实际 \(flow.count)")

        // 且至少一个类型专属行仍被某一列持有（不在 infoRows/multiRows 中的行）
        let attached = bar.infoColumns.flatMap { $0.arrangedSubviews }
        XCTAssertTrue(
            attached.contains { !bar.infoRows.contains($0) && !bar.multiRows.contains($0) },
            "至少一个类型专属行应被列持有")
    }

    /// 终审建议 3 回归（验收 4 接线）：栏变矮时溢出行被摘除（可见行数由
    /// FFDetailsFlowLayout 按 availableHeight 分配），栏变高后重新挂回，行不丢失。
    ///
    /// 驱动方式说明：host 窗口直接缩放 contentView 会与栏的 required 高度约束打架
    /// （contentView frame 由窗口接管，heightConstraint 无法跟随），故走真实的远端同步
    /// 接线驱动高度：写记忆 key + 广播 FFDetailsBarLayoutChanged → layoutChangedRemotely
    /// 应用 clamp 后高度并重排（与「另一栏拖拽同步」同一条路径）。
    @MainActor
    func testOverflowRowsDetachAndReturnWithHeight() throws {
        // 写一个真实 PNG 到临时目录（与类型专属行测试同构，保证有 ≥1 条专属信息行）
        let ctx = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        let cgImage = try XCTUnwrap(ctx?.makeImage(), "应能生成 8×8 位图")
        let pngData = try XCTUnwrap(
            NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]),
            "应能编码为 PNG")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowfinder-overflow-\(UUID().uuidString).png")
        try pngData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let entry = FileEntry(path: url.path, name: url.lastPathComponent, isDirectory: false)

        // 测试不依赖用户机器上的记忆值，保持布局日志干净
        barDefaultsSnapshot = UserDefaults.standard.object(forKey: "FFDetailsBarExpandedHeight")
        UserDefaults.standard.removeObject(forKey: "FFDetailsBarExpandedHeight")
        defer {
            // 快照恢复（复核 Minor 2：不在测试域留下删除痕迹）
            if let snapshot = barDefaultsSnapshot {
                UserDefaults.standard.set(snapshot, forKey: "FFDetailsBarExpandedHeight")
            } else {
                UserDefaults.standard.removeObject(forKey: "FFDetailsBarExpandedHeight")
        defer {
            // 快照恢复（复核 Minor 2 补全：不在测试域留下删除痕迹）
            if let snapshot = barDefaultsSnapshot {
                UserDefaults.standard.set(snapshot, forKey: "FFDetailsBarExpandedHeight")
            } else {
                UserDefaults.standard.removeObject(forKey: "FFDetailsBarExpandedHeight")
            }
        }
            }
        }

        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 210))
        // 用普通容器承载（不用 NSWindow：窗口簿记延迟块与测试裸释放竞态，曾致运行器 SIGSEGV）
        // 底边贴容器、高度由栏自身高度约束驱动；面板高 480（> 记忆值 210 + 让位 120），初始不触发 clamp
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        bar.isExpanded = true
        bar.update(with: [entry])
        container.layoutSubtreeIfNeeded()

        func attachedCount() -> Int {
            // D-06：列数随高度变化，须统计全部列而非前两列
            bar.infoColumns.reduce(0) { $0 + $1.arrangedSubviews.count }
        }

        // 初始：栏高 210，行按可用高度分配（放不下的已摘除隐藏）
        let count1 = attachedCount()
        let flowCount = bar.flowOrderedRows.count
        XCTAssertGreaterThan(count1, 0, "展开态应有可见行")

        // 栏变矮（记忆 100，面板 480 不截断 clamp）：溢出行被摘除
        UserDefaults.standard.set(CGFloat(100), forKey: "FFDetailsBarExpandedHeight")
        NotificationCenter.default.post(name: .FFDetailsBarLayoutChanged, object: nil)
        container.layoutSubtreeIfNeeded()
        let count2 = attachedCount()
        XCTAssertLessThan(count2, count1, "栏变矮后可见行数应减少（溢出行被摘除）")

        // 栏变高回 210：行重新挂回
        UserDefaults.standard.set(CGFloat(210), forKey: "FFDetailsBarExpandedHeight")
        NotificationCenter.default.post(name: .FFDetailsBarLayoutChanged, object: nil)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(attachedCount(), count1, "栏变高后可见行应恢复原数量（行回归）")
        // 全程行不得丢失：流动顺序注册表数量恒定
        XCTAssertEqual(bar.flowOrderedRows.count, flowCount, "行不得丢失（流动顺序注册表数量恒定）")
    }

    // MARK: - 活体验收缺陷修复（列表重复行 + ⌘2 焦点漂移）

    /// 构造 n 个测试文件条目
    private func makeFileEntries(_ n: Int) -> [FileEntry] {
        return (0..<n).map { i in
            FileEntry(path: "/tmp/ff-dup-test/file-\(i).txt", name: "file-\(i).txt", isDirectory: false)
        }
    }

    /// 等待 Combine .receive(on: DispatchQueue.main) 的投递与主队列派发块执行完毕
    /// （主队列 FIFO：本方法的 fulfill 块排在所有已入队投递之后执行）
    private func drainMainQueue() {
        let exp = expectation(description: "drain main queue")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 5.0)
    }

    /// 回归 pin（活体验收缺陷1：列表重复行）。
    /// 根因：reloadData / viewModel didSet 按「当前完整 state」全量重建 displayRows，
    /// 但 lastFilesCount 追加检测基准未同步。复刻生产时序：空列表先建立基准(0) →
    /// state 变为 9 条且重赋 viewModel（didSet 全量重建 9 行）→ sink 投递 count=9。
    /// 修复前 lastFilesCount 仍为 0，被误判为「纯追加」走 appendDisplayRows 把整表
    /// 再拼一遍（9 项显示 18 行、9 条目恰好重复两遍，状态栏仍按 state.files 显示「9 项」）。
    func testListViewReloadedViewMustNotDuplicateRowsOnNextEmission() {
        let vm = PaneViewModel()
        vm.state.path = "/tmp/ff-dup-test"
        let listView = FileListView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        listView.viewModel = vm
        drainMainQueue()  // 基准随空列表建立（lastFilesCount → 0）

        vm.state.files = makeFileEntries(9)
        listView.viewModel = vm  // 复刻 updatePaneUI 的重赋：didSet 全量重建 displayRows=9
        drainMainQueue()  // sink 投递 count=9：不得叠加行

        XCTAssertEqual(listView.numberOfDisplayedRows, 9,
                       "9 项必须恰好显示 9 行（修复前为 18 行整表重复）")
    }

    /// 回归 pin（缺陷1修复不得破坏合法分页追加路径）：
    /// 真实的「数量增加」发射仍走增量插入，且每行恰好插入一次。
    func testListViewAppendEmissionStillInsertsExactlyOnce() {
        let vm = PaneViewModel()
        vm.state.path = "/tmp/ff-dup-test"
        let listView = FileListView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        listView.viewModel = vm
        drainMainQueue()

        vm.state.files = makeFileEntries(3)
        drainMainQueue()
        XCTAssertEqual(listView.numberOfDisplayedRows, 3, "初始 3 项应显示 3 行")

        vm.state.files = makeFileEntries(6)  // 分页/刷新追加 3 条
        drainMainQueue()
        XCTAssertEqual(listView.numberOfDisplayedRows, 6, "追加 3 条后应恰好 6 行（不得重复或丢失）")
    }

    /// 回归 pin（活体验收缺陷2：⌘2 焦点漂移）。
    /// 根因：视图模式切换直接隐藏 firstResponder 所在的旧文件视图，AppKit 沿
    /// keyViewLoop 把焦点漂到「下一个」可见控件（左列表的 nextKeyView = 右面板搜索框，
    /// 即截图中的右搜索框蓝圈）。修复：先把焦点转移到同面板新视图，再隐藏旧视图。
    /// 本测试 pin 转移判定：焦点在旧视图（含子视图）内需要转移；焦点在别处
    /// （另一面板控件/搜索框 field editor）不转移。
    /// 注：不创建 NSWindow——测试运行器的内存检查器会在用例结束后释放作用域对象，
    /// 与窗口簿记延迟块竞态曾致运行器 SIGSEGV（见 PaneStateDeleteFilterTests 既有注释）。
    func testShouldTransferFocusOnlyWhenInsideOldView() {
        final class FocusableView: NSView {
            override var acceptsFirstResponder: Bool { true }
        }
        let oldView = FocusableView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let child = FocusableView(frame: NSRect(x: 10, y: 10, width: 50, height: 50))
        oldView.addSubview(child)
        let unrelated = FocusableView(frame: NSRect(x: 200, y: 0, width: 100, height: 100))
        let fieldEditor = NSTextView(frame: NSRect(x: 0, y: 200, width: 50, height: 20))

        // 焦点在旧视图自身 → 需要转移
        XCTAssertTrue(MainWindowController.shouldTransferFocus(firstResponder: oldView, from: oldView))
        // 焦点在旧视图的子视图内 → 需要转移
        XCTAssertTrue(MainWindowController.shouldTransferFocus(firstResponder: child, from: oldView))
        // 焦点在旧视图外（另一面板的文件视图/搜索框等）→ 不转移
        XCTAssertFalse(MainWindowController.shouldTransferFocus(firstResponder: unrelated, from: oldView))
        // 文本编辑中（field editor）→ 不打断
        XCTAssertFalse(MainWindowController.shouldTransferFocus(firstResponder: fieldEditor, from: oldView))
        // 非视图 firstResponder（窗口自身）→ 不转移
        XCTAssertFalse(MainWindowController.shouldTransferFocus(firstResponder: NSObject(), from: oldView))
        // 旧视图为 nil → 不转移
        XCTAssertFalse(MainWindowController.shouldTransferFocus(firstResponder: oldView, from: nil))
    }
}

// MARK: - FFErrorText（错误人话化，核心旅程 J5）

final class FFErrorTextTests: XCTestCase {

    func testPermissionDeniedIsRecognized() {
        let m = FFErrorText.humanize("Permission denied (os error 13)")
        XCTAssertTrue(m.isPermission)
        XCTAssertTrue(m.title.contains("权限"))
        XCTAssertTrue(m.detail.contains("系统设置"))
    }

    func testOperationNotPermittedIsPermission() {
        XCTAssertTrue(FFErrorText.humanize("Operation not permitted").isPermission)
    }

    func testMissingFile() {
        let m = FFErrorText.humanize("No such file or directory (os error 2)")
        XCTAssertFalse(m.isPermission)
        XCTAssertTrue(m.title.contains("找不到"))
    }

    func testReadOnlyVolume() {
        let m = FFErrorText.humanize("Read-only file system (os error 30)")
        XCTAssertTrue(m.title.contains("只读"))
    }

    func testNoSpace() {
        XCTAssertTrue(FFErrorText.humanize("No space left on device (os error 28)").title.contains("空间"))
    }

    func testUnknownEnglishIsNotShownRaw() {
        let m = FFErrorText.humanize("something completely unexpected")
        XCTAssertFalse(m.title.contains("something"))
        XCTAssertTrue(m.title.contains("没有成功"))
        // 原始串保留在 detail 末行供排查，但不作为主标题
        XCTAssertTrue(m.detail.contains("something completely unexpected"))
    }

    func testAlreadyChinesePassesThrough() {
        let m = FFErrorText.humanize("目标文件夹已存在")
        XCTAssertEqual(m.title, "目标文件夹已存在")
        XCTAssertFalse(m.isPermission)
    }
}

// MARK: - FFStartupPath（J1：首开必须能落到一个真实存在的目录）

final class FFStartupPathTests: XCTestCase {

    private let home = "/Users/tester"
    private let desktop = "/Users/tester/Desktop"
    private let documents = "/Users/tester/Documents"

    private func exists(_ set: Set<String>) -> (String) -> Bool {
        { set.contains($0) }
    }

    func testPrefersLastLocationWhenItStillExists() {
        let p = FFStartupPath.resolve(
            choice: 0, lastLocation: "/Users/tester/work", home: home,
            isDirectory: exists(["/Users/tester/work", home, desktop])
        )
        XCTAssertEqual(p, "/Users/tester/work")
    }

    func testFallsBackToDesktopWhenLastLocationIsGone() {
        let p = FFStartupPath.resolve(
            choice: 0, lastLocation: "/Users/tester/gone", home: home,
            isDirectory: exists([home, desktop])
        )
        XCTAssertEqual(p, desktop)
    }

    /// 真实场景：~/Desktop 被删除（或从未创建）时不能把空路径交给面板，
    /// 否则首开是一屏「无法加载此文件夹」。
    func testFallsBackToHomeWhenDesktopMissing() {
        let p = FFStartupPath.resolve(
            choice: 2, lastLocation: nil, home: home,
            isDirectory: exists([home])
        )
        XCTAssertEqual(p, home)
    }

    func testHomeChoiceIgnoresLastLocation() {
        let p = FFStartupPath.resolve(
            choice: 1, lastLocation: "/Users/tester/work", home: home,
            isDirectory: exists(["/Users/tester/work", home])
        )
        XCTAssertEqual(p, home)
    }

    func testSecondaryPrefersLastThenDocuments() {
        XCTAssertEqual(
            FFStartupPath.resolveSecondary(
                lastLocation: "/Users/tester/a", home: home, subdirectory: "Documents",
                isDirectory: exists(["/Users/tester/a", documents, home])
            ),
            "/Users/tester/a"
        )
        XCTAssertEqual(
            FFStartupPath.resolveSecondary(
                lastLocation: nil, home: home, subdirectory: "Documents",
                isDirectory: exists([documents, home])
            ),
            documents
        )
        XCTAssertEqual(
            FFStartupPath.resolveSecondary(
                lastLocation: nil, home: home, subdirectory: "Documents",
                isDirectory: exists([home])
            ),
            home
        )
    }
}

// MARK: - 路径栏分段

/// 首段必须是「路径所属的卷」：挂载卷不能拼成「根卷 > Volumes > 卷名」
final class FFBreadcrumbSegmentsTests: XCTestCase {

    private func make(_ path: String, rootName: String = "Macintosh HD") -> [(String, String)] {
        FFBreadcrumbSegments
            .make(for: path, volumeName: { $0 == "/" ? rootName : ($0 as NSString).lastPathComponent })
            .map { ($0.name, $0.path) }
    }

    func testVolumeRootDetection() {
        XCTAssertEqual(FFBreadcrumbSegments.volumeRoot(of: "/"), "/")
        XCTAssertEqual(FFBreadcrumbSegments.volumeRoot(of: "/Users/tester"), "/")
        XCTAssertEqual(FFBreadcrumbSegments.volumeRoot(of: "/Volumes/Studio"), "/Volumes/Studio")
        XCTAssertEqual(FFBreadcrumbSegments.volumeRoot(of: "/Volumes/Studio/Documents"), "/Volumes/Studio")
        XCTAssertEqual(FFBreadcrumbSegments.volumeRoot(of: "/Volumes"), "/")
    }

    func testMountedVolumeDoesNotShowVolumesComponent() {
        let segs = make("/Volumes/Studio/Documents")
        XCTAssertEqual(segs.map { $0.0 }, ["Studio", "Documents"])
        XCTAssertEqual(segs.map { $0.1 }, ["/Volumes/Studio", "/Volumes/Studio/Documents"])
    }

    func testMountedVolumeRootOnly() {
        let segs = make("/Volumes/Studio")
        XCTAssertEqual(segs.map { $0.0 }, ["Studio"])
        XCTAssertEqual(segs.first?.1, "/Volumes/Studio")
    }

    func testBootVolumePathKeepsRootName() {
        let segs = make("/Users/tester/Documents")
        XCTAssertEqual(segs.map { $0.0 }, ["Macintosh HD", "Users", "tester", "Documents"])
        XCTAssertEqual(segs.map { $0.1 }, ["/", "/Users", "/Users/tester", "/Users/tester/Documents"])
    }

    func testRootPathSingleSegment() {
        let segs = make("/")
        XCTAssertEqual(segs.map { $0.0 }, ["Macintosh HD"])
        XCTAssertEqual(segs.map { $0.1 }, ["/"])
    }

    func testEmptyPathYieldsNoSegments() {
        XCTAssertTrue(FFBreadcrumbSegments.make(for: "", volumeName: { _ in "x" }).isEmpty)
    }

    func testTrailingSlashIsStandardized() {
        XCTAssertEqual(make("/Volumes/Studio/Documents/").map { $0.0 }, ["Studio", "Documents"])
    }
}
