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
