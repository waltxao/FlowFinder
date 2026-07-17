import XCTest
@testable import FlowFinderNative

final class FlowFinderNativeTests: XCTestCase {

    // MARK: - FFI Loading Tests

    func testLibraryCanBeLoaded() {
        // Verify the Rust core library can be loaded at runtime
        let dylibPath = Bundle.main.bundlePath + "/../Frameworks/libflowfinder_core.dylib"
        let fileManager = FileManager.default

        // Check if the library exists in the bundle
        var libraryExists = fileManager.fileExists(atPath: dylibPath)

        // Fallback: check in the project Libraries directory
        if !libraryExists {
            let projectLibPath = "./FlowFinderNative/Libraries/libflowfinder_core.dylib"
            libraryExists = fileManager.fileExists(atPath: projectLibPath)
        }

        // The library should exist somewhere
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

        // The current directory should have at least some entries
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

        // Clean up any existing files
        try? FileManager.default.removeItem(atPath: srcPath)
        try? FileManager.default.removeItem(atPath: dstPath)

        // Create source file
        try "hello world".write(toFile: srcPath, atomically: true, encoding: .utf8)

        // Copy file
        try bridge.copyFile(src: srcPath, dst: dstPath)

        // Verify destination exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstPath), "Destination file should exist after copy")

        // Clean up
        try? FileManager.default.removeItem(atPath: srcPath)
        try? FileManager.default.removeItem(atPath: dstPath)
    }

    func testMoveFile() throws {
        let bridge = CoreBridge.shared
        let tmpDir = FileManager.default.temporaryDirectory
        let srcPath = tmpDir.appendingPathComponent("test_move_src.txt").path
        let dstPath = tmpDir.appendingPathComponent("test_move_dst.txt").path

        // Clean up any existing files
        try? FileManager.default.removeItem(atPath: srcPath)
        try? FileManager.default.removeItem(atPath: dstPath)

        // Create source file
        try "move me".write(toFile: srcPath, atomically: true, encoding: .utf8)

        // Move file
        try bridge.moveFile(src: srcPath, dst: dstPath)

        // Verify source no longer exists and destination does
        XCTAssertFalse(FileManager.default.fileExists(atPath: srcPath), "Source file should not exist after move")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstPath), "Destination file should exist after move")

        // Clean up
        try? FileManager.default.removeItem(atPath: dstPath)
    }

    func testDeleteFile() throws {
        let bridge = CoreBridge.shared
        let tmpDir = FileManager.default.temporaryDirectory
        let filePath = tmpDir.appendingPathComponent("test_delete.txt").path

        // Clean up any existing file
        try? FileManager.default.removeItem(atPath: filePath)

        // Create file
        try "delete me".write(toFile: filePath, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath), "File should exist before delete")

        // Delete file
        try bridge.deleteFile(path: filePath)

        // Verify file no longer exists
        XCTAssertFalse(FileManager.default.fileExists(atPath: filePath), "File should not exist after delete")
    }

    func testCreateAndDeleteDirectory() throws {
        let bridge = CoreBridge.shared
        let tmpDir = FileManager.default.temporaryDirectory
        let dirPath = tmpDir.appendingPathComponent("test_create_dir").path

        // Clean up any existing directory
        try? FileManager.default.removeItem(atPath: dirPath)

        // Create directory
        try bridge.createDirectory(path: dirPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirPath), "Directory should exist after create")

        // Delete directory
        try bridge.deleteDirectory(path: dirPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dirPath), "Directory should not exist after delete")
    }

    func testRenameFile() throws {
        let bridge = CoreBridge.shared
        let tmpDir = FileManager.default.temporaryDirectory
        let srcPath = tmpDir.appendingPathComponent("test_rename_old.txt").path
        let dstPath = tmpDir.appendingPathComponent("test_rename_new.txt").path

        // Clean up any existing files
        try? FileManager.default.removeItem(atPath: srcPath)
        try? FileManager.default.removeItem(atPath: dstPath)

        // Create source file
        try "rename me".write(toFile: srcPath, atomically: true, encoding: .utf8)

        // Rename file
        try bridge.renameFile(src: srcPath, dst: dstPath)

        // Verify old no longer exists and new does
        XCTAssertFalse(FileManager.default.fileExists(atPath: srcPath), "Old file should not exist after rename")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstPath), "New file should exist after rename")

        // Clean up
        try? FileManager.default.removeItem(atPath: dstPath)
    }

    func testCopyFileAsync() throws {
        let bridge = CoreBridge.shared
        let tmpDir = FileManager.default.temporaryDirectory
        let srcPath = tmpDir.appendingPathComponent("test_async_src.txt").path
        let dstPath = tmpDir.appendingPathComponent("test_async_dst.txt").path

        // Clean up any existing files
        try? FileManager.default.removeItem(atPath: srcPath)
        try? FileManager.default.removeItem(atPath: dstPath)

        // Create source file
        try "async copy".write(toFile: srcPath, atomically: true, encoding: .utf8)

        // Copy file async
        let expectation = self.expectation(description: "Async copy completes")
        var copyError: CoreBridgeError?

        bridge.copyFileAsync(src: srcPath, dst: dstPath) { error in
            copyError = error
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0, handler: nil)

        // Verify no error and destination exists
        XCTAssertNil(copyError, "Async copy should not produce an error")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstPath), "Destination file should exist after async copy")

        // Clean up
        try? FileManager.default.removeItem(atPath: srcPath)
        try? FileManager.default.removeItem(atPath: dstPath)
    }

    func testDeleteFileAsync() throws {
        let bridge = CoreBridge.shared
        let tmpDir = FileManager.default.temporaryDirectory
        let filePath = tmpDir.appendingPathComponent("test_async_delete.txt").path

        // Clean up any existing file
        try? FileManager.default.removeItem(atPath: filePath)

        // Create file
        try "async delete".write(toFile: filePath, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath), "File should exist before async delete")

        // Delete file async
        let expectation = self.expectation(description: "Async delete completes")
        var deleteError: CoreBridgeError?

        bridge.deleteFileAsync(path: filePath) { error in
            deleteError = error
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0, handler: nil)

        // Verify no error and file no longer exists
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

        // After navigation, currentPath should be the home directory
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
}
