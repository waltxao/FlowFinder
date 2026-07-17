import Foundation

// MARK: - CoreBridge Error Types

/// Errors that can occur during CoreBridge operations
public enum CoreBridgeError: Error, LocalizedError {
    case ffiError(String)
    case invalidPath(String)
    case unknownError
    case rustCoreNotLoaded
    case stringConversionFailed

    public var errorDescription: String? {
        switch self {
        case .ffiError(let message):
            return "FFI Error: \(message)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .unknownError:
            return "Unknown error occurred"
        case .rustCoreNotLoaded:
            return "Rust core library not loaded"
        case .stringConversionFailed:
            return "Failed to convert string to C string"
        }
    }
}

// MARK: - Thread-Safe Result Wrapper

/// Thread-safe wrapper for FFI results
private final class ThreadSafeFFIResult<T> {
    private var value: T?
    private let lock = NSLock()

    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func get() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

// MARK: - CoreBridge

/// Thread-safe bridge for communicating with the Rust core via FFI
public final class CoreBridge {

    // MARK: - Singleton

    /// Shared instance of CoreBridge
    public static let shared = CoreBridge()

    // MARK: - Properties

    /// Thread-safe access to the last error message
    private let lastErrorMessage = ThreadSafeFFIResult<String>()

    /// Serial queue for FFI operations to ensure thread safety
    private let ffiQueue = DispatchQueue(label: "com.flowfinder.ffi", qos: .userInitiated)

    // MARK: - Initialization

    private init() {}

    // MARK: - Directory Operations

    /// List directory contents via FFI
    /// - Parameter path: Directory path to list
    /// - Returns: Array of FileEntry objects
    /// - Throws: CoreBridgeError if operation fails
    public func listDirectory(path: String) throws -> [FileEntry] {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath(path)
        }

        // Verify path exists
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        guard exists else {
            throw CoreBridgeError.invalidPath("Path does not exist: \(path)")
        }

        var entries: [FileEntry] = []

        // Use a serial queue for thread-safe FFI access
        var ffiResult: Int32 = -1
        var ffiEntries: [FileEntry] = []

        // Execute FFI call on the serial queue
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            var context = EntryCollectorContext()
            context.entries = []

            let result = path.withCString { cPath in
                withUnsafeMutablePointer(to: &context) { contextPtr in
                    ff_list_dir(cPath, entryCallback, contextPtr)
                }
            }

            ffiResult = result
            ffiEntries = context.entries
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }

        entries = ffiEntries

        // Sort entries: directories first, then alphabetically
        entries.sort { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        return entries
    }

    // MARK: - File Operations

    /// Copy a file from src to dst
    /// - Parameters:
    ///   - src: Source file path
    ///   - dst: Destination file path
    /// - Throws: CoreBridgeError if operation fails
    public func copyFile(src: String, dst: String) throws {
        guard !src.isEmpty, !dst.isEmpty else {
            throw CoreBridgeError.invalidPath("Source or destination path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = src.withCString { cSrc in
                dst.withCString { cDst in
                    ff_copy_file(cSrc, cDst)
                }
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// Move a file or directory from src to dst
    /// - Parameters:
    ///   - src: Source path
    ///   - dst: Destination path
    /// - Throws: CoreBridgeError if operation fails
    public func moveFile(src: String, dst: String) throws {
        guard !src.isEmpty, !dst.isEmpty else {
            throw CoreBridgeError.invalidPath("Source or destination path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = src.withCString { cSrc in
                dst.withCString { cDst in
                    ff_move_file(cSrc, cDst)
                }
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// Delete a file at path
    /// - Parameter path: File path to delete
    /// - Throws: CoreBridgeError if operation fails
    public func deleteFile(path: String) throws {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath("Path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = path.withCString { cPath in
                ff_delete_file(cPath)
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// Delete a directory and all its contents at path
    /// - Parameter path: Directory path to delete
    /// - Throws: CoreBridgeError if operation fails
    public func deleteDirectory(path: String) throws {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath("Path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = path.withCString { cPath in
                ff_delete_dir(cPath)
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// Create a directory and all parent directories at path
    /// - Parameter path: Directory path to create
    /// - Throws: CoreBridgeError if operation fails
    public func createDirectory(path: String) throws {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath("Path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = path.withCString { cPath in
                ff_create_dir(cPath)
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// Rename a file or directory from src to dst
    /// - Parameters:
    ///   - src: Source path
    ///   - dst: Destination path
    /// - Throws: CoreBridgeError if operation fails
    public func renameFile(src: String, dst: String) throws {
        guard !src.isEmpty, !dst.isEmpty else {
            throw CoreBridgeError.invalidPath("Source or destination path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = src.withCString { cSrc in
                dst.withCString { cDst in
                    ff_rename(cSrc, cDst)
                }
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    // MARK: - Async File Operations

    /// Copy a file asynchronously
    /// - Parameters:
    ///   - src: Source file path
    ///   - dst: Destination file path
    ///   - completion: Completion handler with optional error
    public func copyFileAsync(src: String, dst: String, completion: @escaping (CoreBridgeError?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.copyFile(src: src, dst: dst)
                completion(nil)
            } catch let error as CoreBridgeError {
                completion(error)
            } catch {
                completion(CoreBridgeError.unknownError)
            }
        }
    }

    /// Move a file asynchronously
    /// - Parameters:
    ///   - src: Source path
    ///   - dst: Destination path
    ///   - completion: Completion handler with optional error
    public func moveFileAsync(src: String, dst: String, completion: @escaping (CoreBridgeError?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.moveFile(src: src, dst: dst)
                completion(nil)
            } catch let error as CoreBridgeError {
                completion(error)
            } catch {
                completion(CoreBridgeError.unknownError)
            }
        }
    }

    /// Delete a file asynchronously
    /// - Parameters:
    ///   - path: File path to delete
    ///   - completion: Completion handler with optional error
    public func deleteFileAsync(path: String, completion: @escaping (CoreBridgeError?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.deleteFile(path: path)
                completion(nil)
            } catch let error as CoreBridgeError {
                completion(error)
            } catch {
                completion(CoreBridgeError.unknownError)
            }
        }
    }

    /// Delete a directory asynchronously
    /// - Parameters:
    ///   - path: Directory path to delete
    ///   - completion: Completion handler with optional error
    public func deleteDirectoryAsync(path: String, completion: @escaping (CoreBridgeError?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.deleteDirectory(path: path)
                completion(nil)
            } catch let error as CoreBridgeError {
                completion(error)
            } catch {
                completion(CoreBridgeError.unknownError)
            }
        }
    }

    /// Create a directory asynchronously
    /// - Parameters:
    ///   - path: Directory path to create
    ///   - completion: Completion handler with optional error
    public func createDirectoryAsync(path: String, completion: @escaping (CoreBridgeError?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.createDirectory(path: path)
                completion(nil)
            } catch let error as CoreBridgeError {
                completion(error)
            } catch {
                completion(CoreBridgeError.unknownError)
            }
        }
    }

    /// Rename a file or directory asynchronously
    /// - Parameters:
    ///   - src: Source path
    ///   - dst: Destination path
    ///   - completion: Completion handler with optional error
    public func renameFileAsync(src: String, dst: String, completion: @escaping (CoreBridgeError?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.renameFile(src: src, dst: dst)
                completion(nil)
            } catch let error as CoreBridgeError {
                completion(error)
            } catch {
                completion(CoreBridgeError.unknownError)
            }
        }
    }

    // MARK: - Cache Operations

    /// Invalidate the directory cache for a specific path
    /// - Parameter path: Directory path to invalidate
    /// - Throws: CoreBridgeError if operation fails
    public func invalidateCache(path: String) throws {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath("Path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }
            let result = path.withCString { cPath in
                ff_cache_invalidate(cPath)
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// Clear all directory caches (invalidate all)
    /// - Throws: CoreBridgeError if operation fails
    public func clearAllCache() throws {
        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }
            ffiResult = ff_dir_cache_clear()
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    // MARK: - FSEvents Watcher (Sub-project 5)

    /// Start watching a path for filesystem changes
    /// - Parameters:
    ///   - path: Directory path to watch
    ///   - changeHandler: Called when a change is detected
    /// - Throws: CoreBridgeError if operation fails
    public func startFSEventsWatcher(path: String, changeHandler: @escaping (String) -> Void) throws {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath("Path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = path.withCString { cPath in
                ff_fsevents_start(cPath, fseventsCallback, nil)
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    /// Stop the FSEvents watcher
    /// - Throws: CoreBridgeError if operation fails
    public func stopFSEventsWatcher() throws {
        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }
            ffiResult = ff_fsevents_stop(0)
        }

        semaphore.wait()

        guard ffiResult == 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }
    }

    // MARK: - Batch Rename & Organize (Sub-project 6)

    /// Batch rename files
    /// - Parameters:
    ///   - items: Array of (originalPath, newName) tuples
    /// - Returns: Number of successful renames
    /// - Throws: CoreBridgeError if operation fails
    public func batchRename(items: [(String, String)]) throws -> Int {
        guard !items.isEmpty else {
            throw CoreBridgeError.invalidPath("Items array is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        // Convert items to C-compatible format
        var cItems: [FFRenameItem] = []
        for (original, newName) in items {
            let originalPtr = strdup(original)
            let newNamePtr = strdup(newName)
            cItems.append(FFRenameItem(originalPath: originalPtr!, newName: newNamePtr!))
        }

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = cItems.withUnsafeBufferPointer { buffer in
                ff_batch_rename(buffer.baseAddress!, cItems.count)
            }
            ffiResult = result
        }

        semaphore.wait()

        // Free allocated strings
        for item in cItems {
            free(item.originalPath)
            free(item.newName)
        }

        guard ffiResult >= 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }

        return Int(ffiResult)
    }

    /// Organize files by date into folders
    /// - Parameters:
    ///   - path: Directory path
    ///   - format: Date format string (e.g., "YYYY/MM/DD")
    /// - Returns: Number of files moved
    /// - Throws: CoreBridgeError if operation fails
    public func organizeByDate(path: String, format: String = "YYYY/MM/DD") throws -> Int {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath("Path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = path.withCString { cPath in
                format.withCString { cFormat in
                    ff_organize_by_date(cPath, cFormat)
                }
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult >= 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }

        return Int(ffiResult)
    }

    /// Organize files by file type into category folders
    /// - Parameter path: Directory path
    /// - Returns: Number of files moved
    /// - Throws: CoreBridgeError if operation fails
    public func organizeByType(path: String) throws -> Int {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath("Path is empty")
        }

        var ffiResult: Int32 = -1
        let semaphore = DispatchSemaphore(value: 0)

        ffiQueue.async {
            defer { semaphore.signal() }

            let result = path.withCString { cPath in
                ff_organize_by_type(cPath)
            }
            ffiResult = result
        }

        semaphore.wait()

        guard ffiResult >= 0 else {
            let errorMessage = getLastError()
            throw CoreBridgeError.ffiError(errorMessage)
        }

        return Int(ffiResult)
    }

    // MARK: - Thumbnail Generation (Sub-project 7)

    /// Generate a thumbnail for an image file
    /// - Parameters:
    ///   - path: Image file path
    ///   - maxSize: Maximum width/height of the thumbnail
    ///   - completion: Called with the thumbnail path on success
    /// - Throws: CoreBridgeError if operation fails
    public func generateThumbnail(path: String, maxSize: UInt32, completion: @escaping (String?) -> Void) throws {
        guard !path.isEmpty else {
            throw CoreBridgeError.invalidPath("Path is empty")
        }

        ffiQueue.async {
            var context = ThumbnailContext(completion: completion)

            let result = path.withCString { cPath in
                ff_generate_thumbnail(cPath, maxSize, thumbnailCallback, &context)
            }

            if result != 0 {
                let errorMessage = self.getLastError()
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    /// Generate thumbnails for multiple image files
    /// - Parameters:
    ///   - paths: Array of image file paths
    ///   - maxSize: Maximum width/height of each thumbnail
    ///   - completion: Called with array of thumbnail paths on success
    /// - Throws: CoreBridgeError if operation fails
    public func generateThumbnails(paths: [String], maxSize: UInt32, completion: @escaping ([String]) -> Void) throws {
        guard !paths.isEmpty else {
            throw CoreBridgeError.invalidPath("Paths array is empty")
        }

        ffiQueue.async {
            var thumbnailPaths: [String] = []
            var context = ThumbnailsContext(paths: &thumbnailPaths, completion: completion)

            let cPaths = paths.map { strdup($0) }
            let result = cPaths.withUnsafeBufferPointer { buffer in
                ff_generate_thumbnails(buffer.baseAddress!, paths.count, maxSize, thumbnailsCallback, &context)
            }

            // Free allocated strings
            for ptr in cPaths {
                free(ptr)
            }

            if result != 0 {
                let errorMessage = self.getLastError()
                DispatchQueue.main.async {
                    completion([])
                }
            }
        }
    }

    // MARK: - Error Handling

    /// Get the last error message from the Rust core
    /// - Returns: Error message string
    private func getLastError() -> String {
        guard let cString = ff_last_error() else {
            return "Unknown error"
        }

        // Safely convert C string to Swift String
        let message = String(cString: cString)

        // Free the C string allocated by Rust
        ff_free_string(UnsafeMutablePointer(mutating: cString))

        return message
    }

    /// Get the last error message (thread-safe)
    /// - Returns: Last error message or "Unknown error"
    public func getLastErrorMessage() -> String {
        return lastErrorMessage.get() ?? "Unknown error"
    }
}

// MARK: - Thumbnail Contexts

/// Context for thumbnail generation callback
private struct ThumbnailContext {
    let completion: (String?) -> Void
}

/// Context for multiple thumbnails generation callback
private struct ThumbnailsContext {
    let paths: UnsafeMutablePointer<[String]>
    let completion: ([String]) -> Void
}

// MARK: - FFI Callbacks

/// Callback function called by Rust for each directory entry
private func entryCallback(
    _ entryRefPtr: UnsafeRawPointer?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let entryRefPtr = entryRefPtr,
          let userData = userData else { return }

    let entryRef = entryRefPtr.assumingMemoryBound(to: FFEntryRef.self)
    let context = userData.withMemoryRebound(to: EntryCollectorContext.self, capacity: 1) { $0 }
    let entry = FileEntry(from: entryRef.pointee)
    context.pointee.entries.append(entry)
}

/// Callback for FSEvents notifications
private func fseventsCallback(
    _ path: UnsafePointer<CChar>?,
    _ userData: UnsafeMutableRawPointer?
) {
    // Handle FSEvents notification
    // In production, this would notify the UI to refresh
}

/// Callback for thumbnail generation
private func thumbnailCallback(
    _ thumbnailPath: UnsafePointer<CChar>?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let thumbnailPath = thumbnailPath,
          let userData = userData else { return }

    let context = userData.withMemoryRebound(to: ThumbnailContext.self, capacity: 1) { $0 }
    let path = String(cString: thumbnailPath)
    context.pointee.completion(path)
}

/// Callback for multiple thumbnails generation
private func thumbnailsCallback(
    _ thumbnailPath: UnsafePointer<CChar>?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let thumbnailPath = thumbnailPath,
          let userData = userData else { return }

    let path = String(cString: thumbnailPath)
    let context = userData.withMemoryRebound(to: ThumbnailsContext.self, capacity: 1) { $0 }
    context.pointee.paths.pointee.append(path)
}
