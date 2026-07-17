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

// MARK: - Entry Collector Context

/// Context structure for collecting entries from FFI callback
private struct EntryCollectorContext {
    var entries: [FileEntry] = []
}

// MARK: - FFI Callback

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
