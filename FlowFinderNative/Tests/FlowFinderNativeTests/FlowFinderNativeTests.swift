import XCTest
@testable import FlowFinderNative

final class FlowFinderNativeTests: XCTestCase {

    // MARK: - FFI Loading Tests

    func testLibraryCanBeLoaded() {
        let dylibPath = Bundle.main.bundlePath + "/../Frameworks/libflowfinder_core.dylib"
        let fileManager = FileManager.default

        var libraryExists = fileManager.fileExists(atPath: dylibPath)

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

    func testCopyFileAsync() throws {
        let bridge = CoreBridge.shared
        let tmpDir = FileManager.default.temporaryDirectory
        let srcPath = tmpDir.appendingPathComponent("test_async_src.txt").path
        let dstPath = tmpDir.appendingPathComponent("test_async_dst.txt").path

        try? FileManager.default.removeItem(atPath: srcPath)
        try? FileManager.default.removeItem(atPath: dstPath)

        try "async copy".write(toFile: srcPath, atomically: true, encoding: .utf8)

        let expectation = self.expectation(description: "Async copy completes")
        var copyError: CoreBridgeError?

        bridge.copyFileAsync(src: srcPath, dst: dstPath) { error in
            copyError = error
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0, handler: nil)

        XCTAssertNil(copyError, "Async copy should not produce an error")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstPath), "Destination file should exist after async copy")

        try? FileManager.default.removeItem(atPath: srcPath)
        try? FileManager.default.removeItem(atPath: dstPath)
    }

    func testDeleteFileAsync() throws {
        let bridge = CoreBridge.shared
        let tmpDir = FileManager.default.temporaryDirectory
        let filePath = tmpDir.appendingPathComponent("test_async_delete.txt").path

        try? FileManager.default.removeItem(atPath: filePath)

        try "async delete".write(toFile: filePath, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath), "File should exist before async delete")

        let expectation = self.expectation(description: "Async delete completes")
        var deleteError: CoreBridgeError?

        bridge.deleteFileAsync(path: filePath) { error in
            deleteError = error
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0, handler: nil)

        XCTAssertNil(deleteError, "Async delete should not produce an error")
        XCTAssertFalse(FileManager.default.fileExists(atPath: filePath), "File should not exist after async delete")
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

    func testFileEntryMimeType() {
        let jpgEntry = FileEntry(path: "/test.jpg", name: "test.jpg", isDirectory: false, size: 100, modificationDate: Date())
        XCTAssertEqual(jpgEntry.mimeType, "image/jpeg")

        let pdfEntry = FileEntry(path: "/test.pdf", name: "test.pdf", isDirectory: false, size: 100, modificationDate: Date())
        XCTAssertEqual(pdfEntry.mimeType, "application/pdf")

        let unknownEntry = FileEntry(path: "/test.xyz", name: "test.xyz", isDirectory: false, size: 100, modificationDate: Date())
        XCTAssertEqual(unknownEntry.mimeType, "application/octet-stream")
    }

    func testFileEntryFormattedSize() {
        let smallFile = FileEntry(path: "/small.txt", name: "small.txt", isDirectory: false, size: 512, modificationDate: Date())
        let sizeString = smallFile.formattedSize
        XCTAssertFalse(sizeString.isEmpty, "Formatted size should not be empty")
    }

    // MARK: - FileEntryViewModel Tests

    func testViewModelInitialState() {
        let viewModel = FileEntryViewModel()
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(viewModel.currentPath)
    }

    func testViewModelNavigateToHome() {
        let viewModel = FileEntryViewModel()
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        viewModel.navigateToHome()

        XCTAssertEqual(viewModel.currentPath, homePath)
    }

    // MARK: - Error Tests

    func testCoreBridgeErrorDescriptions() {
        let ffiError = CoreBridgeError.ffiError("test error")
        XCTAssertEqual(ffiError.errorDescription, "FFI Error: test error")

        let invalidPath = CoreBridgeError.invalidPath("/bad/path")
        XCTAssertEqual(invalidPath.errorDescription, "Invalid path: /bad/path")

        let unknown = CoreBridgeError.unknownError
        XCTAssertEqual(unknown.errorDescription, "Unknown error occurred")

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

    func testSearchBridgeGetFileType() {
        let bridge = QuickLookBridge.shared
        let fileType = bridge.getFileType(path: "/test/document.pdf")
        XCTAssertEqual(fileType, "pdf", "Should extract PDF extension")
    }

    func testSearchBridgeGetFileTypeNoExtension() {
        let bridge = QuickLookBridge.shared
        let fileType = bridge.getFileType(path: "/test/README")
        XCTAssertEqual(fileType, "", "Should return empty string for no extension")
    }

    func testSearchBridgeCanPreview() {
        let bridge = QuickLookBridge.shared
        XCTAssertTrue(bridge.canPreview(path: "/test/image.jpg"), "Should support image preview")
        XCTAssertTrue(bridge.canPreview(path: "/test/doc.pdf"), "Should support PDF preview")
        XCTAssertFalse(bridge.canPreview(path: "/test/unknown.xyz"), "Should not support unknown type")
    }

    func testSearchBridgeCanPreviewText() {
        let bridge = QuickLookBridge.shared
        XCTAssertTrue(bridge.canPreview(path: "/test/readme.txt"), "Should support text preview")
        XCTAssertTrue(bridge.canPreview(path: "/test/notes.md"), "Should support markdown preview")
    }

    // MARK: - QuickLook Bridge Tests

    func testQuickLookBridgeSingleton() {
        let bridge1 = QuickLookBridge.shared
        let bridge2 = QuickLookBridge.shared
        XCTAssertTrue(bridge1 === bridge2, "QuickLookBridge.shared should return the same instance")
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
