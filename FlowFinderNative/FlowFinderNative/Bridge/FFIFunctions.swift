import Foundation

/// FFI entry reference structure, corresponding to Rust's ff_entry_t
public struct FFEntryRef {
    public let path: UnsafePointer<CChar>
    public let name: UnsafePointer<CChar>
    public let isDir: Bool
    public let size: UInt64
    public let modified: UInt64
}

// MARK: - Duplicate Scan Types

/// C-compatible duplicate file info
public struct FFDuplicateFile {
    public let id: String
    public let path: String
    public let name: String
    public let size: UInt64
    public let modified: Int64
}

/// C-compatible duplicate group info
public struct FFDuplicateGroup {
    public let id: String
    public let hash: String
    public let size: UInt64
    public let files: [FFDuplicateFile]
}

// MARK: - Search Types

/// C-compatible search result
public struct FFSearchResult {
    public let path: String
    public let name: String
    public let size: UInt64
    public let modified: Int64
    public let isDir: Bool
}

/// Search filter criteria
public struct FFSearchFilters {
    public var fileTypes: String?
    public var minSize: UInt64?
    public var maxSize: UInt64?
    public var modifiedAfter: Int64?
    public var modifiedBefore: Int64?

    public init(
        fileTypes: String? = nil,
        minSize: UInt64? = nil,
        maxSize: UInt64? = nil,
        modifiedAfter: Int64? = nil,
        modifiedBefore: Int64? = nil
    ) {
        self.fileTypes = fileTypes
        self.minSize = minSize
        self.maxSize = maxSize
        self.modifiedAfter = modifiedAfter
        self.modifiedBefore = modifiedBefore
    }
}

// MARK: - FFI Function Declarations

/// List contents of a directory
/// - Parameters:
///   - path: Target directory path (C string)
///   - callback: Callback function called for each discovered entry
///   - userData: User data pointer passed to the callback
/// - Returns: 0 on success, non-zero error code on failure
@_silgen_name("ff_list_dir")
public func ff_list_dir(
    _ path: UnsafePointer<CChar>,
    _ callback: @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void,
    _ userData: UnsafeMutableRawPointer?
) -> Int32

/// Get the last error message
/// - Returns: Pointer to error description C string (caller must free with ff_free_string)
@_silgen_name("ff_last_error")
public func ff_last_error() -> UnsafePointer<CChar>?

/// Free a string allocated by the Rust side
/// - Parameter string: C string pointer to free
@_silgen_name("ff_free_string")
public func ff_free_string(_ string: UnsafeMutablePointer<CChar>?)

// MARK: - File Operations FFI Declarations

/// Copy a file from src to dst
/// - Parameters:
///   - src: Source file path (C string)
///   - dst: Destination file path (C string)
/// - Returns: 0 on success, non-zero error code on failure
@_silgen_name("ff_copy_file")
public func ff_copy_file(
    _ src: UnsafePointer<CChar>,
    _ dst: UnsafePointer<CChar>
) -> Int32

/// Move a file or directory from src to dst
/// - Parameters:
///   - src: Source path (C string)
///   - dst: Destination path (C string)
/// - Returns: 0 on success, non-zero error code on failure
@_silgen_name("ff_move_file")
public func ff_move_file(
    _ src: UnsafePointer<CChar>,
    _ dst: UnsafePointer<CChar>
) -> Int32

/// Delete a file at path
/// - Parameter path: File path to delete (C string)
/// - Returns: 0 on success, non-zero error code on failure
@_silgen_name("ff_delete_file")
public func ff_delete_file(_ path: UnsafePointer<CChar>) -> Int32

/// Delete a directory and all its contents at path
/// - Parameter path: Directory path to delete (C string)
/// - Returns: 0 on success, non-zero error code on failure
@_silgen_name("ff_delete_dir")
public func ff_delete_dir(_ path: UnsafePointer<CChar>) -> Int32

/// Create a directory and all parent directories at path
/// - Parameter path: Directory path to create (C string)
/// - Returns: 0 on success, non-zero error code on failure
@_silgen_name("ff_create_dir")
public func ff_create_dir(_ path: UnsafePointer<CChar>) -> Int32

/// Rename a file or directory from src to dst
/// - Parameters:
///   - src: Source path (C string)
///   - dst: Destination path (C string)
/// - Returns: 0 on success, non-zero error code on failure
@_silgen_name("ff_rename")
public func ff_rename(
    _ src: UnsafePointer<CChar>,
    _ dst: UnsafePointer<CChar>
) -> Int32

// MARK: - Duplicate File Detection FFI Declarations

/// Scan for duplicate files under a path
/// - Parameters:
///   - path: Root directory path (C string)
///   - progressCallback: Called with (scanned, total) progress updates
///   - groupCallback: Called for each duplicate group found
///   - userData: User data pointer passed to callbacks
/// - Returns: 0 on success, non-zero error code on failure
@_silgen_name("ff_scan_duplicates")
public func ff_scan_duplicates(
    _ path: UnsafePointer<CChar>,
    _ progressCallback: @convention(c) (Int, Int, UnsafeMutableRawPointer?) -> Void,
    _ groupCallback: @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void,
    _ userData: UnsafeMutableRawPointer?
) -> Int32

/// Cancel an ongoing duplicate scan
@_silgen_name("ff_cancel_scan")
public func ff_cancel_scan()

// MARK: - File Search FFI Declarations

/// Search for files matching query under path
/// - Parameters:
///   - path: Root directory path (C string)
///   - query: Search query (C string)
///   - callback: Called for each matching result
///   - userData: User data pointer passed to callback
/// - Returns: 0 on success, non-zero error code on failure
@_silgen_name("ff_search")
public func ff_search(
    _ path: UnsafePointer<CChar>,
    _ query: UnsafePointer<CChar>,
    _ callback: @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void,
    _ userData: UnsafeMutableRawPointer?
) -> Int32

/// Search for files with advanced filters
/// - Parameters:
///   - path: Root directory path (C string)
///   - query: Search query (C string)
///   - filters: Pointer to filter criteria struct
///   - callback: Called for each matching result
///   - userData: User data pointer passed to callback
/// - Returns: 0 on success, non-zero error code on failure
@_silgen_name("ff_search_with_filters")
public func ff_search_with_filters(
    _ path: UnsafePointer<CChar>,
    _ query: UnsafePointer<CChar>,
    _ filters: UnsafeRawPointer?,
    _ callback: @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void,
    _ userData: UnsafeMutableRawPointer?
) -> Int32

// MARK: - QuickLook Preview FFI Declarations

/// Get a preview-friendly path for a file
/// - Parameters:
///   - path: File path (C string)
///   - callback: Called with the preview path
///   - userData: User data pointer passed to callback
/// - Returns: 0 on success, non-zero error code on failure
@_silgen_name("ff_get_preview_path")
public func ff_get_preview_path(
    _ path: UnsafePointer<CChar>,
    _ callback: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void,
    _ userData: UnsafeMutableRawPointer?
) -> Int32

/// Get the file type/extension as a C string
/// - Parameter path: File path (C string)
/// - Returns: Pointer to file extension string (caller must free with ff_free_string)
@_silgen_name("ff_get_file_type")
public func ff_get_file_type(_ path: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

// MARK: - Directory Cache FFI Declarations

/// Invalidate the directory cache for a specific path
/// - Parameter path: Directory path (C string)
/// - Returns: 0 on success, non-zero error code on failure
@_silgen_name("ff_cache_invalidate")
public func ff_cache_invalidate(_ path: UnsafePointer<CChar>) -> Int32

/// Get cached directory entries for a path
/// - Parameters:
///   - path: Directory path (C string)
///   - callback: Called for each cached entry
///   - userData: User data pointer passed to callback
/// - Returns: 0 on success, non-zero error code on failure
@_silgen_name("ff_cache_get")
public func ff_cache_get(
    _ path: UnsafePointer<CChar>,
    _ callback: @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void,
    _ userData: UnsafeMutableRawPointer?
) -> Int32

/// Store directory entries in the cache
/// - Parameters:
///   - path: Directory path (C string)
///   - entries: Array of FFEntryRef to cache
///   - entryCount: Number of entries in the array
/// - Returns: 0 on success, non-zero error code on failure
@_silgen_name("ff_cache_put")
public func ff_cache_put(
    _ path: UnsafePointer<CChar>,
    _ entries: UnsafePointer<FFEntryRef>,
    _ entryCount: Int
) -> Int32
