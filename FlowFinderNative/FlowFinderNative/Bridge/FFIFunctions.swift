import Foundation

/// FFI entry reference structure, corresponding to Rust's ff_entry_t
public struct FFEntryRef {
    public let path: UnsafePointer<CChar>
    public let name: UnsafePointer<CChar>
    public let isDir: Bool
    public let size: UInt64
    public let modified: UInt64
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
