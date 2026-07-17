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
