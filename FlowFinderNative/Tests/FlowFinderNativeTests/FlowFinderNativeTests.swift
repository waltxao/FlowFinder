import XCTest
@testable import FlowFinderNative

final class FlowFinderNativeTests: XCTestCase {

    // MARK: - FFI Loading Tests

    func testLibraryCanBeLoaded() {
        // The dylib is bundled at Contents/Frameworks and loaded via @rpath by
        // the "Copy Dylib to Bundle" build phase, so that is the authoritative
        // location to assert against.
        let bundledPath = Bundle.main.bundlePath + "/Contents/Frameworks/libflowfinder_core.dylib"
        let fileManager = FileManager.default

        var libraryExists = fileManager.fileExists(atPath: bundledPath)

        if !libraryExists {
            let projectLibPath = "./FlowFinderNative/Libraries/libflowfinder_core.dylib"
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
}
