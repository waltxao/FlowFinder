import AppKit
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

// MARK: - FFDetailsBarLayoutTests（详情栏三模块布局回归）

final class FFDetailsBarLayoutTests: XCTestCase {

    @MainActor
    func testExpandedDividerStripsHaveFullHeight() {
        // modules 高度确定链回归：展开后两条分界线热区必须有完整高度（曾因
        // modules.bottom 为 lessThanOrEqual 而无高度来源，布局歧义塌缩为 0）
        // 测试不依赖用户机器上的记忆值，保持布局日志干净
        UserDefaults.standard.removeObject(forKey: "FFDetailsBarExpandedHeight")
        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 210))
        bar.isExpanded = true
        bar.layoutSubtreeIfNeeded()

        // 期望值由栏自身尺寸推导，不依赖默认展开高度记忆值
        let expected = bar.frame.height - 6 - 18
        XCTAssertEqual(bar.dividerIconToCol1.bounds.height, expected, accuracy: 1.0)
        XCTAssertEqual(bar.dividerCol1ToCol2.bounds.height, expected, accuracy: 1.0)
    }
}

// MARK: - 类型专属行注册表 × 流动填充 回归（审查 Critical 修复）

final class FFDetailsBarTypeRowsFlowTests: XCTestCase {

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
        UserDefaults.standard.removeObject(forKey: "FFDetailsBarExpandedHeight")

        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let host = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        host.contentView = bar // rearrangeFlow 需 window != nil 才生效
        bar.isExpanded = true

        bar.update(with: [entry])
        bar.layoutSubtreeIfNeeded()

        // 多次重排，等价于分界线拖拽/高度拖拽/窗口尺寸变化的触发路径
        bar.rearrangeFlow()
        bar.rearrangeFlow()

        // 6 常规行 + ≥1 专属行 + 3 常规行：专属行必须仍在流动顺序中
        let flow = bar.flowOrderedRows
        XCTAssertTrue(flow.count > 9,
                      "专属信息行应保留在流动顺序中（6 常规 + ≥1 专属 + 3 常规），实际 \(flow.count)")

        // 且至少一个类型专属行仍被某一列持有（不在 infoRows/multiRows 中的行）
        let attached = bar.mainColumn1.arrangedSubviews + bar.mainColumn2.arrangedSubviews
        XCTAssertTrue(
            attached.contains { !bar.infoRows.contains($0) && !bar.multiRows.contains($0) },
            "至少一个类型专属行应被列持有")
        host.close()
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
        UserDefaults.standard.removeObject(forKey: "FFDetailsBarExpandedHeight")
        defer { UserDefaults.standard.removeObject(forKey: "FFDetailsBarExpandedHeight") }

        let bar = ExpandableDetailsBar(frame: NSRect(x: 0, y: 0, width: 600, height: 210))
        let host = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        // 托管与应用内浮层一致：底边贴容器、高度由栏自身高度约束驱动；
        // 面板高 480（> 记忆值 210 + 让位 120），初始不触发 clamp
        let container = NSView()
        host.contentView = container
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
            bar.mainColumn1.arrangedSubviews.count + bar.mainColumn2.arrangedSubviews.count
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
        // 程序化创建的窗口默认 isReleasedWhenClosed = true，close() 会立即释放窗口，
        // 测试结束时的局部强引用再释放即成 over-release（XCTest 内存检查段错误）——关掉该行为
        host.isReleasedWhenClosed = false
        host.close()
    }
}
