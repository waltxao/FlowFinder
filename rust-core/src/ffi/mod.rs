//! FFI export layer — exposes Rust core functions via a C-compatible ABI.
//!
//! This module provides the bridge between Swift (frontend) and Rust (core).
//! All exported functions use the `#[no_mangle]` attribute and `extern "C"`
//! calling convention for stable C ABI compatibility.
//!
//! ## Design
//!
//! - Error codes are returned as `ff_error_t` integers.
//! - The last error message is stored in thread-local storage and can be
//!   retrieved via `ff_last_error()`.
//! - Directory entries are returned through an iterator callback pattern:
//!   Rust calls the Swift-provided callback for each entry.
//! - All heap-allocated strings returned to C must be freed with
//!   `ff_free_string()`.

// SAFETY(lint): C ABI 边界函数解引用 Swift 侧传入的裸指针是 FFI 固有模式，
// 调用方（Swift）无法表达 Rust 的 unsafe 语义，该 lint 对本模块属已知误报场景。
#![allow(clippy::not_unsafe_ptr_arg_deref)]
use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::io;
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, LazyLock, Mutex, OnceLock};

// ── L2 persistent cache db path ────────────────────────────────────
//
// Path to the SQLite database used as the L2 persistent directory cache.
// Set once via `ff_cache_init` at app startup. When unset, only the L1
// in-memory cache (`dir_cache`) is used — preserving backward compatibility.

static CACHE_DB_PATH: OnceLock<String> = OnceLock::new();

// ── Content index db path ────────────────────────────────────────────
//
// Path to the independent `content_index.sqlite` database (§1 of the
// content-index contract). Set once via `ff_content_index_init`; resolved by
// Swift, never by Rust.

static CONTENT_INDEX_DB_PATH: OnceLock<String> = OnceLock::new();

// ── Error codes ─────────────────────────────────────────────────────

/// Operation succeeded.
pub const FF_OK: c_int = 0;
/// Generic error.
pub const FF_ERR_GENERIC: c_int = -1;
/// Invalid path argument.
pub const FF_ERR_INVALID_PATH: c_int = -2;
/// I/O error during operation.
pub const FF_ERR_IO: c_int = -3;
/// Resource not found.
pub const FF_ERR_NOT_FOUND: c_int = -4;
/// Duplicate resource.
pub const FF_ERR_DUPLICATE: c_int = -5;
/// Permission denied.
pub const FF_ERR_PERMISSION_DENIED: c_int = -6;

// ── Thread-local error storage ────────────────────────────────────────

// P1-6 修复：thread_local 保证单线程访问，使用 RefCell 替代 Mutex，
// 避免 .lock().unwrap() 的开销和潜在死锁。
thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
}

fn set_last_error(msg: String) {
    LAST_ERROR.with(|e| {
        *e.borrow_mut() = Some(msg);
    });
}

fn clear_last_error() {
    LAST_ERROR.with(|e| {
        *e.borrow_mut() = None;
    });
}

/// Build a summary error string for partial failures of a parallel batch
/// operation (copy/move/delete).
///
/// Produces a string like `"3/5 failed: /path/a (Permission denied), /path/b
/// (Not found)"`. To bound the string size, at most `max_entries` failed
/// `(path, error)` pairs are listed; any extra failures are summarised as
/// `", … and N more"`. The total/failed counts always reflect every result.
fn summarize_parallel_failures(
    results: &[(String, io::Result<()>)],
    max_entries: usize,
) -> String {
    let total = results.len();
    let failures: Vec<(&String, &io::Error)> = results
        .iter()
        .filter_map(|(p, r)| r.as_ref().err().map(|e| (p, e)))
        .collect();
    let failed = failures.len();
    let detail: Vec<String> = failures
        .iter()
        .take(max_entries)
        .map(|(p, e)| format!("{} ({})", p, e))
        .collect();
    let suffix = if failures.len() > max_entries {
        format!(", … and {} more", failures.len() - max_entries)
    } else {
        String::new()
    };
    format!(
        "{}/{} failed: {}{}",
        failed,
        total,
        detail.join(", "),
        suffix
    )
}

// ── C-compatible directory entry ────────────────────────────────────

/// A single directory entry exposed to C.
///
/// All string fields are heap-allocated and must be freed with
/// `ff_free_string()` by the caller.
#[repr(C)]
pub struct FFEntryRef {
    pub name: *mut c_char,
    pub path: *mut c_char,
    pub extension: *mut c_char,
    pub is_dir: bool,
    pub is_file: bool,
    pub is_symlink: bool,
    pub is_hidden: bool,
    pub is_system_protected: bool,
    pub size: u64,
    pub modified: i64,
    pub created: i64,
}

/// Callback type for directory entry iteration.
///
/// The callback receives a pointer to an `FFEntryRef` for each entry.
/// The `user_data` pointer is passed through from the caller.
///
/// # Safety
///
/// The callback must not retain the `FFEntryRef` pointer beyond the call.
/// All string fields are valid only for the duration of the callback.
pub type FFEntryCallback = extern "C" fn(entry: *const FFEntryRef, user_data: *mut c_void);

// ── Duplicate scan callback types ───────────────────────────────────

/// C-compatible duplicate file info.
#[repr(C)]
pub struct FFDuplicateFile {
    pub id: *mut c_char,
    pub path: *mut c_char,
    pub name: *mut c_char,
    pub size: u64,
    pub modified: i64,
}

/// C-compatible duplicate group info.
#[repr(C)]
pub struct FFDuplicateGroup {
    pub id: *mut c_char,
    pub hash: *mut c_char,
    pub size: u64,
    pub files: *const FFDuplicateFile,
    pub file_count: usize,
}

/// Callback for duplicate scan progress.
pub type FFDedupProgressCallback = extern "C" fn(scanned: usize, total: usize, user_data: *mut c_void);

/// Callback for duplicate group found.
pub type FFDedupGroupCallback = extern "C" fn(group: *const FFDuplicateGroup, user_data: *mut c_void);

// ── Search callback types ─────────────────────────────────────────

/// C-compatible search result.
#[repr(C)]
pub struct FFSearchResult {
    pub path: *mut c_char,
    pub name: *mut c_char,
    pub size: u64,
    pub modified: i64,
    pub is_dir: bool,
}

/// Callback for search results.
pub type FFSearchCallback = extern "C" fn(result: *const FFSearchResult, user_data: *mut c_void);

// ── Helper: convert Rust string to C string ─────────────────────────

// P2-16 修复：签名改为接受 impl AsRef<str>，避免调用方不必要的 String 克隆。
// CString::new 直接接受 &[u8]（实现了 Into<Vec<u8>>），由 CString 内部完成唯一一次拷贝。
fn rust_string_to_c(s: impl AsRef<str>) -> *mut c_char {
    match CString::new(s.as_ref().as_bytes()) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

// ── FFI panic-safety wrappers ───────────────────────────────────────
//
// Crossing the FFI boundary with an unwinding panic is undefined
// behaviour in Rust (the C side has no landing pad, so the runtime
// aborts or corrupts state). Every `#[no_mangle] pub extern "C" fn`
// in this file wraps its body in one of these helpers so that a panic
// is caught at the boundary and translated into a safe error code /
// null pointer. `AssertUnwindSafe` is acceptable here because we are
// about to return an error anyway — we don't need to preserve any
// internal invariants across the panic.

/// Wrap an FFI body returning `c_int`. On panic, records a generic
/// "FFI function panicked" message via `set_last_error` and returns
/// `FF_ERR_GENERIC`.
fn ffi_catch_int<F: FnOnce() -> c_int>(f: F) -> c_int {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(v) => v,
        Err(_) => {
            set_last_error("FFI function panicked".to_string());
            FF_ERR_GENERIC
        }
    }
}

/// Wrap an FFI body returning `*mut c_char`. On panic, records the
/// panic via `set_last_error` and returns a null pointer.
fn ffi_catch_ptr<F: FnOnce() -> *mut c_char>(f: F) -> *mut c_char {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(v) => v,
        Err(_) => {
            set_last_error("FFI function panicked".to_string());
            ptr::null_mut()
        }
    }
}

/// Wrap an FFI body returning `()`. On panic, the panic is swallowed
/// (recorded via `set_last_error` for diagnostics).
fn ffi_catch_void<F: FnOnce()>(f: F) {
    if std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)).is_err() {
        set_last_error("FFI function panicked".to_string());
    }
}

/// Wrap an FFI body returning `u64`. On panic, returns `0`.
fn ffi_catch_u64<F: FnOnce() -> u64>(f: F) -> u64 {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(v) => v,
        Err(_) => {
            set_last_error("FFI function panicked".to_string());
            0
        }
    }
}

// ── Exported functions ──────────────────────────────────────────────

/// List all entries in a directory, calling `callback` for each entry.
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 path string.
/// - `callback` — Function called for each directory entry.
/// - `user_data` — Opaque pointer passed to the callback.
///
/// # Callback borrow contract
///
/// The `FFEntryRef` pointer (and every string field inside it) is valid only
/// for the duration of the callback invocation. The Rust side owns the
/// backing `CString`s and drops them immediately after the callback returns.
/// The callback must **not** retain the pointer or copy it for later use.
///
/// # Returns
///
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if the path is invalid.
/// - `FF_ERR_IO` if a filesystem error occurs.
///
/// # Safety
///
/// - `path` must be a valid, NUL-terminated UTF-8 string.
/// - `callback` must be a valid function pointer.
#[no_mangle]
pub extern "C" fn ff_list_dir(
    path: *const c_char,
    callback: FFEntryCallback,
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        if path.is_null() {
            set_last_error("path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        match crate::core::bulk_read::list_dir_bulk(path_str) {
            Ok(entries) => {
                for entry in entries {
                    // P0-3 修复：使用 RAII CString 保持所有权，仅借用裸指针给回调。
                    // 回调返回后 CString 自动 drop，即使回调 panic 也不会泄漏内存。
                    let name_c = CString::new(entry.name.as_bytes()).ok();
                    let path_c = CString::new(entry.path.as_bytes()).ok();
                    let ext_c = CString::new(entry.extension.as_bytes()).ok();

                    let ff_entry = FFEntryRef {
                        name: name_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
                        path: path_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
                        extension: ext_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
                        is_dir: entry.is_dir,
                        is_file: entry.is_file,
                        is_symlink: entry.is_symlink,
                        is_hidden: entry.is_hidden,
                        is_system_protected: entry.is_system_protected,
                        size: entry.size,
                        modified: entry.modified,
                        created: entry.created,
                    };

                    callback(&ff_entry, user_data);
                    // name_c, path_c, ext_c 在此自动 drop，无需手动释放
                }
                clear_last_error();
                FF_OK
            }
            Err(e) => {
                let msg = format!("list_dir failed: {}", e);
                set_last_error(msg);
                FF_ERR_IO
            }
        }
    })
}

/// Get the last error message as a heap-allocated C string.
///
/// Returns `NULL` if no error has occurred.
/// The returned string must be freed with `ff_free_string()`.
///
/// # Safety
///
/// The returned pointer must be freed with `ff_free_string()` or
/// `ff_free_string()` to avoid memory leaks.
#[no_mangle]
pub extern "C" fn ff_last_error() -> *mut c_char {
    ffi_catch_ptr(|| {
        LAST_ERROR.with(|e| {
            let guard = e.borrow();
            match guard.as_ref() {
                Some(msg) => rust_string_to_c(msg.clone()),
                None => ptr::null_mut(),
            }
        })
    })
}

/// Free a string previously returned by the FFI layer.
///
/// # Safety
///
/// - `s` must be a string returned by the FFI layer (e.g. `ff_last_error()`).
/// - `s` may be `NULL` (no-op).
/// - After calling this function, `s` must not be used again.
#[no_mangle]
pub extern "C" fn ff_free_string(s: *mut c_char) {
    ffi_catch_void(|| {
        if !s.is_null() {
            unsafe {
                let _ = CString::from_raw(s);
            }
        }
    })
}

// ── Additional exported functions (placeholders for future use) ────

/// Get the library version string.
///
/// Returns a heap-allocated C string. Must be freed with `ff_free_string()`.
#[no_mangle]
pub extern "C" fn ff_version_string() -> *mut c_char {
    ffi_catch_ptr(|| rust_string_to_c(env!("CARGO_PKG_VERSION")))
}

/// Get the system memory size in bytes.
#[no_mangle]
pub extern "C" fn ff_get_system_memory() -> u64 {
    ffi_catch_u64(|| {
        // Return 0 as a placeholder; platform-specific implementation
        // can use sysinfo or similar on macOS.
        0
    })
}

// ── File Operations ─────────────────────────────────────────────────

/// Copy a file from `src` to `dst`.
///
/// Uses CoW cloning when available (same-volume APFS), falling back to
/// standard byte-for-byte copy otherwise.
///
/// # Arguments
///
/// - `src` — NUL-terminated UTF-8 source path string.
/// - `dst` — NUL-terminated UTF-8 destination path string.
///
/// # Returns
///
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if a path is invalid.
/// - `FF_ERR_IO` if a filesystem error occurs.
///
/// # Safety
///
/// - `src` and `dst` must be valid, NUL-terminated UTF-8 strings.
#[no_mangle]
pub extern "C" fn ff_copy_file(src: *const c_char, dst: *const c_char) -> c_int {
    ffi_catch_int(|| {
        if src.is_null() || dst.is_null() {
            set_last_error("src or dst is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let src_str = unsafe {
            match CStr::from_ptr(src).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("src is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        let dst_str = unsafe {
            match CStr::from_ptr(dst).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("dst is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        if let Err(msg) = crate::core::path_guard::path_guard(src_str) {
            set_last_error(msg);
            return FF_ERR_INVALID_PATH;
        }
        if let Err(msg) = crate::core::path_guard::path_guard(dst_str) {
            set_last_error(msg);
            return FF_ERR_INVALID_PATH;
        }

        match crate::core::file_ops::copy_file(std::path::Path::new(src_str), std::path::Path::new(dst_str)) {
            Ok(_) => {
                clear_last_error();
                FF_OK
            }
            Err(e) => {
                let msg = format!("copy_file failed: {}", e);
                set_last_error(msg);
                FF_ERR_IO
            }
        }
    })
}

/// Move a file or directory from `src` to `dst`.
///
/// Attempts a fast rename first. If `src` and `dst` are on different
/// volumes, falls back to copy + delete.
///
/// # Arguments
///
/// - `src` — NUL-terminated UTF-8 source path string.
/// - `dst` — NUL-terminated UTF-8 destination path string.
///
/// # Returns
///
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if a path is invalid.
/// - `FF_ERR_IO` if a filesystem error occurs.
///
/// # Safety
///
/// - `src` and `dst` must be valid, NUL-terminated UTF-8 strings.
#[no_mangle]
pub extern "C" fn ff_move_file(src: *const c_char, dst: *const c_char) -> c_int {
    ffi_catch_int(|| {
        if src.is_null() || dst.is_null() {
            set_last_error("src or dst is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let src_str = unsafe {
            match CStr::from_ptr(src).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("src is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        let dst_str = unsafe {
            match CStr::from_ptr(dst).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("dst is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        if let Err(msg) = crate::core::path_guard::path_guard(src_str) {
            set_last_error(msg);
            return FF_ERR_INVALID_PATH;
        }
        if let Err(msg) = crate::core::path_guard::path_guard(dst_str) {
            set_last_error(msg);
            return FF_ERR_INVALID_PATH;
        }

        match crate::core::file_ops::move_file(std::path::Path::new(src_str), std::path::Path::new(dst_str)) {
            Ok(()) => {
                clear_last_error();
                FF_OK
            }
            Err(e) => {
                let msg = format!("move_file failed: {}", e);
                set_last_error(msg);
                FF_ERR_IO
            }
        }
    })
}

/// Delete a file at `path`.
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 path string.
///
/// # Returns
///
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if the path is invalid.
/// - `FF_ERR_IO` if a filesystem error occurs.
///
/// # Safety
///
/// - `path` must be a valid, NUL-terminated UTF-8 string.
#[no_mangle]
pub extern "C" fn ff_delete_file(path: *const c_char) -> c_int {
    ffi_catch_int(|| {
        if path.is_null() {
            set_last_error("path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        if let Err(msg) = crate::core::path_guard::path_guard(path_str) {
            set_last_error(msg);
            return FF_ERR_INVALID_PATH;
        }

        match crate::core::file_ops::delete_file(std::path::Path::new(path_str)) {
            Ok(()) => {
                clear_last_error();
                FF_OK
            }
            Err(e) => {
                let msg = format!("delete_file failed: {}", e);
                set_last_error(msg);
                FF_ERR_IO
            }
        }
    })
}

/// Delete a directory and all its contents at `path`.
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 path string.
///
/// # Returns
///
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if the path is invalid.
/// - `FF_ERR_IO` if a filesystem error occurs.
///
/// # Safety
///
/// - `path` must be a valid, NUL-terminated UTF-8 string.
#[no_mangle]
pub extern "C" fn ff_delete_dir(path: *const c_char) -> c_int {
    ffi_catch_int(|| {
        if path.is_null() {
            set_last_error("path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        if let Err(msg) = crate::core::path_guard::path_guard(path_str) {
            set_last_error(msg);
            return FF_ERR_INVALID_PATH;
        }

        match crate::core::file_ops::delete_dir(std::path::Path::new(path_str)) {
            Ok(()) => {
                clear_last_error();
                FF_OK
            }
            Err(e) => {
                let msg = format!("delete_dir failed: {}", e);
                set_last_error(msg);
                FF_ERR_IO
            }
        }
    })
}

/// Create a directory and all parent directories at `path`.
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 path string.
///
/// # Returns
///
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if the path is invalid.
/// - `FF_ERR_IO` if a filesystem error occurs.
///
/// # Safety
///
/// - `path` must be a valid, NUL-terminated UTF-8 string.
#[no_mangle]
pub extern "C" fn ff_create_dir(path: *const c_char) -> c_int {
    ffi_catch_int(|| {
        if path.is_null() {
            set_last_error("path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        if let Err(msg) = crate::core::path_guard::path_guard(path_str) {
            set_last_error(msg);
            return FF_ERR_INVALID_PATH;
        }

        match crate::core::file_ops::create_dir(std::path::Path::new(path_str)) {
            Ok(()) => {
                clear_last_error();
                FF_OK
            }
            Err(e) => {
                let msg = format!("create_dir failed: {}", e);
                set_last_error(msg);
                FF_ERR_IO
            }
        }
    })
}

/// Rename a file or directory from `src` to `dst`.
///
/// # Arguments
///
/// - `src` — NUL-terminated UTF-8 source path string.
/// - `dst` — NUL-terminated UTF-8 destination path string.
///
/// # Returns
///
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if a path is invalid.
/// - `FF_ERR_IO` if a filesystem error occurs.
///
/// # Safety
///
/// - `src` and `dst` must be valid, NUL-terminated UTF-8 strings.
#[no_mangle]
pub extern "C" fn ff_rename(src: *const c_char, dst: *const c_char) -> c_int {
    ffi_catch_int(|| {
        if src.is_null() || dst.is_null() {
            set_last_error("src or dst is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let src_str = unsafe {
            match CStr::from_ptr(src).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("src is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        let dst_str = unsafe {
            match CStr::from_ptr(dst).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("dst is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        if let Err(msg) = crate::core::path_guard::path_guard(src_str) {
            set_last_error(msg);
            return FF_ERR_INVALID_PATH;
        }
        if let Err(msg) = crate::core::path_guard::path_guard(dst_str) {
            set_last_error(msg);
            return FF_ERR_INVALID_PATH;
        }

        match crate::core::file_ops::rename(std::path::Path::new(src_str), std::path::Path::new(dst_str)) {
            Ok(()) => {
                clear_last_error();
                FF_OK
            }
            Err(e) => {
                let msg = format!("rename failed: {}", e);
                set_last_error(msg);
                FF_ERR_IO
            }
        }
    })
}

// ── Cooperative cancellation registry ───────────────────────────────
//
// Every long-running FFI operation (duplicate scan or search) is registered
// under a process-unique handle with its own *private* `Arc<AtomicBool>`
// cancel flag. `ff_cancel_scan()` / `ff_cancel_scan_by_id()` /
// `ff_cancel_search_by_id()` set the flag of the targeted operation only, so
// cancelling one scan never affects another — and starting a new scan cannot
// reset a previously cancelled scan, because the flags are not shared.
//
// This replaces the old process-global `DEDUP_CANCEL`, which every scan
// reset on start and which `ff_cancel_scan()` cleared globally.
//
// The registry is a plain `Mutex<HashMap>`: the critical sections are only
// the register/query/deregister points, never the scan itself.

#[derive(Clone, Copy, PartialEq, Eq)]
enum OpKind {
    Scan,
    Search,
    Index,
}

struct ActiveOp {
    kind: OpKind,
    cancel: Arc<AtomicBool>,
    pause: Arc<AtomicBool>,
}

static NEXT_OP_ID: AtomicU64 = AtomicU64::new(1);
static ACTIVE_OPS: LazyLock<Mutex<HashMap<u64, ActiveOp>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// RAII guard that deregisters an operation from [`ACTIVE_OPS`] when dropped.
struct OpGuard {
    id: u64,
}

impl OpGuard {
    /// Allocate a fresh, isolated cancel flag and register it as an active
    /// operation of `kind`. Returns the guard (deregisters on drop) and the
    /// operation's private cancel flag.
    fn register(kind: OpKind) -> (Self, Arc<AtomicBool>) {
        let (guard, cancel, _pause) = Self::register_full(kind);
        (guard, cancel)
    }

    /// Like [`register`](Self::register), but also returns a private pause
    /// flag (used by cancellable/pause-aware content-index builds).
    fn register_full(kind: OpKind) -> (Self, Arc<AtomicBool>, Arc<AtomicBool>) {
        let id = NEXT_OP_ID.fetch_add(1, Ordering::Relaxed);
        let cancel = Arc::new(AtomicBool::new(false));
        let pause = Arc::new(AtomicBool::new(false));
        ACTIVE_OPS
            .lock()
            .unwrap()
            .insert(id, ActiveOp {
                kind,
                cancel: Arc::clone(&cancel),
                pause: Arc::clone(&pause),
            });
        (OpGuard { id }, cancel, pause)
    }
}

impl Drop for OpGuard {
    fn drop(&mut self) {
        ACTIVE_OPS.lock().unwrap().remove(&self.id);
    }
}

/// Set the cancel flag of the active operation with `id` if it is of `kind`.
/// Returns `FF_OK` when found, `FF_ERR_NOT_FOUND` when no such operation is
/// registered (it already finished, or never existed).
fn cancel_op(id: u64, kind: OpKind) -> c_int {
    let ops = ACTIVE_OPS.lock().unwrap();
    match ops.get(&id) {
        Some(op) if op.kind == kind => {
            op.cancel.store(true, Ordering::Relaxed);
            FF_OK
        }
        _ => {
            set_last_error("no active operation with the given handle".to_string());
            FF_ERR_NOT_FOUND
        }
    }
}

fn pause_op(id: u64, kind: OpKind) -> c_int {
    let ops = ACTIVE_OPS.lock().unwrap();
    match ops.get(&id) {
        Some(op) if op.kind == kind => {
            op.pause.store(true, Ordering::Relaxed);
            FF_OK
        }
        _ => {
            set_last_error("no active operation with the given handle".to_string());
            FF_ERR_NOT_FOUND
        }
    }
}

fn resume_op(id: u64, kind: OpKind) -> c_int {
    let ops = ACTIVE_OPS.lock().unwrap();
    match ops.get(&id) {
        Some(op) if op.kind == kind => {
            op.pause.store(false, Ordering::Relaxed);
            FF_OK
        }
        _ => {
            set_last_error("no active operation with the given handle".to_string());
            FF_ERR_NOT_FOUND
        }
    }
}

// ── Duplicate File Detection ──────────────────────────────────────

/// Scan for duplicate files under `path`.
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 root path string.
/// - `progress_callback` — Called with (scanned, total) progress updates.
/// - `group_callback` — Called for each duplicate group found.
/// - `user_data` — Opaque pointer passed to callbacks.
///
/// # Callback borrow contract
///
/// The `FFDuplicateGroup` pointer (and every string field inside it,
/// including the `files` array) is valid only for the duration of the
/// callback invocation; the Rust side drops the backing `CString`s
/// immediately after the callback returns. The callback must **not** retain
/// the pointer or any field for later use.
///
/// # Returns
///
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if the path is invalid.
/// - `FF_ERR_IO` if a filesystem error occurs.
///
/// # Safety
///
/// - `path` must be a valid, NUL-terminated UTF-8 string.
/// - Callbacks must be valid function pointers.
#[no_mangle]
pub extern "C" fn ff_scan_duplicates(
    path: *const c_char,
    progress_callback: FFDedupProgressCallback,
    group_callback: FFDedupGroupCallback,
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        scan_duplicates_impl(path, progress_callback, group_callback, user_data, ptr::null_mut())
    })
}

/// Scan for duplicate files, exposing a per-scan cancellation handle.
///
/// Identical to [`ff_scan_duplicates`], except that the freshly allocated
/// handle is written to `*out_handle` *before* the scan starts, so a caller
/// on another thread can cancel this specific scan via
/// [`ff_cancel_scan_by_id`] while it is running. Passing `NULL` for
/// `out_handle` behaves exactly like [`ff_scan_duplicates`].
#[no_mangle]
pub extern "C" fn ff_scan_duplicates_ex(
    path: *const c_char,
    progress_callback: FFDedupProgressCallback,
    group_callback: FFDedupGroupCallback,
    user_data: *mut c_void,
    out_handle: *mut u64,
) -> c_int {
    ffi_catch_int(|| {
        scan_duplicates_impl(path, progress_callback, group_callback, user_data, out_handle)
    })
}

/// Shared body for [`ff_scan_duplicates`] / [`ff_scan_duplicates_ex`].
fn scan_duplicates_impl(
    path: *const c_char,
    progress_callback: FFDedupProgressCallback,
    group_callback: FFDedupGroupCallback,
    user_data: *mut c_void,
    out_handle: *mut u64,
) -> c_int {
    if path.is_null() {
        set_last_error("path is null".to_string());
        return FF_ERR_INVALID_PATH;
    }

    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s,
            Err(_) => {
                set_last_error("path is not valid UTF-8".to_string());
                return FF_ERR_INVALID_PATH;
            }
        }
    };

    // Each scan owns an isolated cancel flag; the guard deregisters it as
    // soon as the scan returns, so a cancel request issued afterwards is a
    // clean no-op (`FF_ERR_NOT_FOUND`) rather than hitting a stale flag.
    let (_guard, cancel) = OpGuard::register(OpKind::Scan);
    if !out_handle.is_null() {
        // Write the handle before scanning so another thread can cancel us.
        unsafe {
            *out_handle = _guard.id;
        }
    }

    struct CallbackEmitter {
        progress: FFDedupProgressCallback,
        group: FFDedupGroupCallback,
        user_data: *mut c_void,
    }

    impl crate::core::dedup_engine::EventEmitter for CallbackEmitter {
        fn emit(&self, event: crate::core::dedup_engine::DedupEvent) {
            match event {
                crate::core::dedup_engine::DedupEvent::Progress { scanned, total } => {
                    let total_val = total.unwrap_or(0);
                    (self.progress)(scanned, total_val, self.user_data);
                }
                crate::core::dedup_engine::DedupEvent::GroupFound { group } => {
                    // P0-3 修复：使用 RAII Vec<CString> 保持所有权，
                    // 仅借用裸指针给回调。回调返回后（即使 panic）所有 CString 自动释放。
                    let mut id_cstrings: Vec<CString> = Vec::with_capacity(group.files.len());
                    let mut path_cstrings: Vec<CString> = Vec::with_capacity(group.files.len());
                    let mut name_cstrings: Vec<CString> = Vec::with_capacity(group.files.len());

                    let files: Vec<FFDuplicateFile> = group
                        .files
                        .iter()
                        .map(|f| {
                            let id_c = CString::new(f.id.as_bytes()).ok();
                            let path_c = CString::new(f.path.as_bytes()).ok();
                            let name_c = CString::new(f.name.as_bytes()).ok();
                            let file = FFDuplicateFile {
                                id: id_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
                                path: path_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
                                name: name_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
                                size: f.size,
                                modified: f.modified,
                            };
                            // 将 CString 推入 Vec 保持所有权
                            if let Some(c) = id_c { id_cstrings.push(c); }
                            if let Some(c) = path_c { path_cstrings.push(c); }
                            if let Some(c) = name_c { name_cstrings.push(c); }
                            file
                        })
                        .collect();

                    let group_id_c = CString::new(group.id.as_bytes()).ok();
                    let group_hash_c = CString::new(group.hash.as_bytes()).ok();

                    let group_c = FFDuplicateGroup {
                        id: group_id_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
                        hash: group_hash_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
                        size: group.size,
                        files: files.as_ptr(),
                        file_count: files.len(),
                    };

                    (self.group)(&group_c, self.user_data);
                    // files, *_cstrings, group_id_c, group_hash_c 在此自动 drop
                }
                _ => {}
            }
        }
    }

    let emitter = CallbackEmitter {
        progress: progress_callback,
        group: group_callback,
        user_data,
    };

    // The per-scan `cancel` flag is passed to `run_scan`, which polls it
    // cooperatively. It is private to this scan, so `ff_cancel_scan_by_id`
    // (and only that) can interrupt it.
    let _groups = crate::core::dedup_engine::run_scan(
        vec![path_str.to_string()],
        &emitter,
        &cancel,
    );

    clear_last_error();
    FF_OK
}

/// Cancel an ongoing duplicate scan.
///
/// Backward-compatible form that cancels the "current" scan: the one that
/// started first and is still running. Each scan owns an independent cancel
/// flag, so this never affects any other in-flight scan. Prefer
/// [`ff_cancel_scan_by_id`] when the target scan's handle is known.
#[no_mangle]
pub extern "C" fn ff_cancel_scan() {
    ffi_catch_void(|| {
        let ops = ACTIVE_OPS.lock().unwrap();
        let oldest = ops
            .iter()
            .filter(|(_, op)| op.kind == OpKind::Scan)
            .map(|(id, _)| *id)
            .min();
        if let Some(id) = oldest {
            ops.get(&id).unwrap().cancel.store(true, Ordering::Relaxed);
        }
    })
}

/// Cancel a specific duplicate scan by its handle.
///
/// Returns `FF_OK` when the scan was found and cancelled, and
/// `FF_ERR_NOT_FOUND` when no running scan with `handle` exists (it already
/// completed or the handle is invalid).
#[no_mangle]
pub extern "C" fn ff_cancel_scan_by_id(handle: u64) -> c_int {
    ffi_catch_int(|| cancel_op(handle, OpKind::Scan))
}

// ── File Search ─────────────────────────────────────────────────────

/// C-compatible search execution options.
///
/// `max_results` caps the number of delivered results (`0` = unlimited);
/// `max_depth` caps directory recursion (`0` = unlimited).
#[repr(C)]
pub struct FFSearchOptions {
    pub max_results: usize,
    pub max_depth: usize,
}

fn parse_search_options(options: *const FFSearchOptions) -> crate::core::search_engine::SearchConfig {
    if options.is_null() {
        crate::core::search_engine::SearchConfig::default()
    } else {
        let o = unsafe { &*options };
        crate::core::search_engine::SearchConfig {
            max_results: o.max_results,
            max_depth: if o.max_depth == 0 { None } else { Some(o.max_depth) },
        }
    }
}

fn parse_ff_search_filters(filters: *const FFSearchFilters) -> crate::core::search_engine::SearchFilters {
    if filters.is_null() {
        return crate::core::search_engine::SearchFilters::default();
    }
    let f = unsafe { &*filters };
    crate::core::search_engine::SearchFilters {
        file_types: if f.has_file_types && !f.file_types.is_null() {
            Some(unsafe { CStr::from_ptr(f.file_types).to_string_lossy().to_string() })
        } else {
            None
        },
        min_size: if f.has_min_size { Some(f.min_size) } else { None },
        max_size: if f.has_max_size { Some(f.max_size) } else { None },
        modified_after: if f.has_modified_after { Some(f.modified_after) } else { None },
        modified_before: if f.has_modified_before { Some(f.modified_before) } else { None },
    }
}

/// Shared body for the four search entry points.
///
/// Registers a per-search cancel flag (handle written to `*out_handle`
/// before the walk starts, when non-null) and runs the walk with the
/// configured limits. Cancellation is cooperative: the walk polls the flag
/// at every entry and returns early.
fn search_impl(
    path: *const c_char,
    query: *const c_char,
    options: *const FFSearchOptions,
    filters: Option<&crate::core::search_engine::SearchFilters>,
    out_handle: *mut u64,
    callback: FFSearchCallback,
    user_data: *mut c_void,
) -> c_int {
    if path.is_null() || query.is_null() {
        set_last_error("path or query is null".to_string());
        return FF_ERR_INVALID_PATH;
    }

    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s,
            Err(_) => {
                set_last_error("path is not valid UTF-8".to_string());
                return FF_ERR_INVALID_PATH;
            }
        }
    };

    let query_str = unsafe {
        match CStr::from_ptr(query).to_str() {
            Ok(s) => s,
            Err(_) => {
                set_last_error("query is not valid UTF-8".to_string());
                return FF_ERR_INVALID_PATH;
            }
        }
    };

    let config = parse_search_options(options);

    let (_guard, cancel) = OpGuard::register(OpKind::Search);
    if !out_handle.is_null() {
        unsafe {
            *out_handle = _guard.id;
        }
    }

    let mut cb = |result: crate::core::search_engine::SearchResult| {
        // P0-3 修复：使用 RAII CString 保持所有权，回调 panic 时自动释放
        let path_c = CString::new(result.path.as_bytes()).ok();
        let name_c = CString::new(result.name.as_bytes()).ok();
        let result_c = FFSearchResult {
            path: path_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
            name: name_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
            size: result.size,
            modified: result.modified,
            is_dir: result.is_dir,
        };
        callback(&result_c, user_data);
        // path_c, name_c 在此自动 drop
    };

    let outcome = match filters {
        Some(f) => crate::core::search_engine::search_with_filters(
            path_str,
            query_str,
            f,
            &config,
            &cancel,
            &mut cb,
        ),
        None => crate::core::search_engine::search_files(
            path_str,
            query_str,
            &config,
            &cancel,
            &mut cb,
        ),
    };

    match outcome {
        Ok(_) => {
            clear_last_error();
            FF_OK
        }
        Err(e) => {
            let msg = format!("search failed: {}", e);
            set_last_error(msg);
            FF_ERR_IO
        }
    }
}

/// Search for files matching `query` under `path`.
///
/// Backward-compatible form of [`ff_search_ex`] with default options
/// (max 500 results, unlimited depth, no cancellation handle).
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 root path string.
/// - `query` — NUL-terminated UTF-8 search query.
/// - `callback` — Called for each matching result.
/// - `user_data` — Opaque pointer passed to the callback.
///
/// # Callback borrow contract
///
/// The `FFSearchResult` pointer (and its string fields) is valid only for
/// the duration of the callback invocation; the Rust side drops the backing
/// `CString`s immediately after the callback returns. The callback must
/// **not** retain the pointer for later use.
///
/// # Returns
///
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if the path is invalid.
/// - `FF_ERR_IO` if a filesystem error occurs.
///
/// # Safety
///
/// - `path` and `query` must be valid, NUL-terminated UTF-8 strings.
/// - `callback` must be a valid function pointer.
#[no_mangle]
pub extern "C" fn ff_search(
    path: *const c_char,
    query: *const c_char,
    callback: FFSearchCallback,
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| search_impl(path, query, ptr::null(), None, ptr::null_mut(), callback, user_data))
}

/// Search for files matching `query` under `path`, with execution options
/// and a per-search cancellation handle.
///
/// The freshly allocated handle is written to `*out_handle` *before* the
/// walk starts, so a caller on another thread can cancel this specific
/// search via [`ff_cancel_search_by_id`] while it is running. Passing
/// `NULL` for `options` uses the defaults (max 500 results, unlimited
/// depth); passing `NULL` for `out_handle` skips handle reporting.
#[no_mangle]
pub extern "C" fn ff_search_ex(
    path: *const c_char,
    query: *const c_char,
    options: *const FFSearchOptions,
    out_handle: *mut u64,
    callback: FFSearchCallback,
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| search_impl(path, query, options, None, out_handle, callback, user_data))
}

/// C-compatible search filters.
#[repr(C)]
pub struct FFSearchFilters {
    pub file_types: *const c_char,
    pub min_size: u64,
    pub max_size: u64,
    pub modified_after: i64,
    pub modified_before: i64,
    pub has_file_types: bool,
    pub has_min_size: bool,
    pub has_max_size: bool,
    pub has_modified_after: bool,
    pub has_modified_before: bool,
}

/// Search for files with advanced filters.
///
/// Backward-compatible form of [`ff_search_with_filters_ex`] with default
/// options (max 500 results, unlimited depth, no cancellation handle).
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 root path string.
/// - `query` — NUL-terminated UTF-8 search query.
/// - `filters` — Pointer to filter criteria.
/// - `callback` — Called for each matching result.
/// - `user_data` — Opaque pointer passed to the callback.
///
/// # Returns
///
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if the path is invalid.
/// - `FF_ERR_IO` if a filesystem error occurs.
///
/// # Safety
///
/// - `path`, `query`, and `filters` must be valid pointers.
/// - `callback` must be a valid function pointer.
#[no_mangle]
pub extern "C" fn ff_search_with_filters(
    path: *const c_char,
    query: *const c_char,
    filters: *const FFSearchFilters,
    callback: FFSearchCallback,
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        let rust_filters = parse_ff_search_filters(filters);
        search_impl(path, query, ptr::null(), Some(&rust_filters), ptr::null_mut(), callback, user_data)
    })
}

/// Search for files with advanced filters, with execution options and a
/// per-search cancellation handle.
///
/// The freshly allocated handle is written to `*out_handle` *before* the
/// walk starts, so a caller on another thread can cancel this specific
/// search via [`ff_cancel_search_by_id`] while it is running. Passing
/// `NULL` for `options` uses the defaults (max 500 results, unlimited
/// depth); passing `NULL` for `out_handle` skips handle reporting.
#[no_mangle]
pub extern "C" fn ff_search_with_filters_ex(
    path: *const c_char,
    query: *const c_char,
    filters: *const FFSearchFilters,
    options: *const FFSearchOptions,
    out_handle: *mut u64,
    callback: FFSearchCallback,
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        let rust_filters = parse_ff_search_filters(filters);
        search_impl(path, query, options, Some(&rust_filters), out_handle, callback, user_data)
    })
}

/// Cancel a specific search by its handle.
///
/// Returns `FF_OK` when the search was found and cancelled, and
/// `FF_ERR_NOT_FOUND` when no running search with `handle` exists (it
/// already completed or the handle is invalid).
#[no_mangle]
pub extern "C" fn ff_cancel_search_by_id(handle: u64) -> c_int {
    ffi_catch_int(|| cancel_op(handle, OpKind::Search))
}

// ── QuickLook Preview ─────────────────────────────────────────────

/// Get a preview-friendly path for a file.
///
/// For most files this returns the original path. For files that may need
/// temporary conversion, it returns the converted path.
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 path string.
/// - `callback` — Called with the preview path (may be the same as input).
/// - `user_data` — Opaque pointer passed to the callback.
///
/// # Returns
///
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if the path is invalid.
///
/// # Safety
///
/// - `path` must be a valid, NUL-terminated UTF-8 string.
#[no_mangle]
pub extern "C" fn ff_get_preview_path(
    path: *const c_char,
    callback: extern "C" fn(preview_path: *const c_char, user_data: *mut c_void),
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        if path.is_null() {
            set_last_error("path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        // For now, just return the original path
        // P0-3 修复：使用 RAII CString 保持所有权，回调 panic 时自动释放
        let path_c = CString::new(path_str.as_bytes()).ok();
        let ptr = path_c.as_ref().map(|c| c.as_ptr()).unwrap_or(std::ptr::null());
        callback(ptr, user_data);
        // path_c 在此自动 drop

        clear_last_error();
        FF_OK
    })
}

/// Get the file type/extension as a C string.
///
/// Returns a heap-allocated C string containing the file extension.
/// Must be freed with `ff_free_string()`.
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 path string.
///
/// # Returns
///
/// - Pointer to file extension string on success.
/// - `NULL` on error.
///
/// # Safety
///
/// - `path` must be a valid, NUL-terminated UTF-8 string.
/// - The returned pointer must be freed with `ff_free_string()`.
#[no_mangle]
pub extern "C" fn ff_get_file_type(path: *const c_char) -> *mut c_char {
    ffi_catch_ptr(|| {
        if path.is_null() {
            set_last_error("path is null".to_string());
            return ptr::null_mut();
        }

        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("path is not valid UTF-8".to_string());
                    return ptr::null_mut();
                }
            }
        };

        let ext = std::path::Path::new(path_str)
            .extension()
            .map(|e| e.to_string_lossy().to_string())
            .unwrap_or_default();

        rust_string_to_c(ext)
    })
}

// ── Directory Cache ─────────────────────────────────────────────────

/// Initialize the L2 persistent (SQLite) directory cache.
///
/// Stores `db_path` in a module-level `OnceLock<String>` and creates the
/// `dir_cache` schema via `sqlite_cache::init_cache`. After this call
/// succeeds, `ff_cache_get`/`ff_cache_put`/`ff_cache_invalidate` will
/// additionally consult/persist to the SQLite database (best-effort).
///
/// Subsequent calls re-assert the schema idempotently (`CREATE TABLE IF
/// NOT EXISTS`) but do not change the stored database path — the path is
/// set once via a `OnceLock` and retained for the lifetime of the process.
/// Setting a different path after the first call has no effect (the
/// original path is retained); callers should call this exactly once at
/// app startup.
///
/// # Arguments
///
/// - `db_path` — NUL-terminated UTF-8 path to the SQLite database file.
///
/// # Returns
///
/// - `FF_OK` on success (or if already initialized).
/// - `FF_ERR_INVALID_PATH` if `db_path` is null or invalid UTF-8.
/// - `FF_ERR_IO` if SQLite schema creation fails.
///
/// # Safety
///
/// - `db_path` must be a valid, NUL-terminated UTF-8 string.
#[no_mangle]
pub extern "C" fn ff_cache_init(db_path: *const c_char) -> c_int {
    ffi_catch_int(|| {
        if db_path.is_null() {
            set_last_error("db_path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let db_path_str = unsafe {
            match CStr::from_ptr(db_path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("db_path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        // Create the schema on disk first so we can surface I/O errors early.
        if let Err(e) = crate::core::sqlite_cache::init_cache(db_path_str) {
            set_last_error(format!("sqlite_cache::init_cache failed: {}", e));
            return FF_ERR_IO;
        }

        // Store the path globally. If a path is already set, keep the original
        // (OnceLock semantics) — the schema was just (re-)created idempotently.
        let _ = CACHE_DB_PATH.set(db_path_str.to_string());

        clear_last_error();
        FF_OK
    })
}

/// Invalidate the directory cache for a specific path.
///
/// Invalidates both the L1 in-memory cache (`dir_cache`) and, if
/// `ff_cache_init` has been called, the L2 persistent SQLite cache.
/// L2 failures are best-effort: errors are recorded via `set_last_error`
/// but do not change the return value (L1 invalidation still succeeds).
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 path string.
///
/// # Returns
///
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if the path is invalid.
///
/// # Safety
///
/// - `path` must be a valid, NUL-terminated UTF-8 string.
#[no_mangle]
pub extern "C" fn ff_cache_invalidate(path: *const c_char) -> c_int {
    ffi_catch_int(|| {
        if path.is_null() {
            set_last_error("path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        crate::core::dir_cache::invalidate(path_str);

        // Best-effort L2 invalidation — do not mask L1 success.
        let mut l2_failed = false;
        if let Some(db_path) = CACHE_DB_PATH.get() {
            if let Err(e) = crate::core::sqlite_cache::cache_invalidate(db_path, path_str) {
                set_last_error(format!("sqlite_cache::cache_invalidate failed: {}", e));
                l2_failed = true;
            }
        }

        if !l2_failed {
            clear_last_error();
        }
        FF_OK
    })
}

/// Get cached directory entries for a path.
///
/// Two-tier lookup: L1 (in-memory `dir_cache`) → L2 (persistent SQLite
/// `sqlite_cache`, if `ff_cache_init` has been called). On an L1 miss the
/// L2 cache is consulted; if L2 hits, the entries are written back to L1
/// (so subsequent calls are served from memory) and delivered through the
/// callback. If both tiers miss (or L2 is not configured), the callback
/// is not called and `FF_ERR_NOT_FOUND` is returned.
///
/// L2 errors are best-effort: a non-NotFound error is recorded via
/// `set_last_error` and the call degrades to an L1 miss
/// (`FF_ERR_NOT_FOUND`); the function never panics on SQLite failures.
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 path string.
/// - `callback` — Function called for each cached entry.
/// - `user_data` — Opaque pointer passed to the callback.
///
/// # Returns
///
/// - `FF_OK` on success (entries found in cache).
/// - `FF_ERR_INVALID_PATH` if the path is invalid.
/// - `FF_ERR_NOT_FOUND` if the path is not in cache.
///
/// # Safety
///
/// - `path` must be a valid, NUL-terminated UTF-8 string.
/// - `callback` must be a valid function pointer.
#[no_mangle]
pub extern "C" fn ff_cache_get(
    path: *const c_char,
    callback: FFEntryCallback,
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        if path.is_null() {
            set_last_error("path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        // Inline helper: deliver a batch of skeletons through the callback.
        // P0-3 修复：使用 RAII CString 保持所有权，回调 panic 时自动释放。
        // P2-15 修复：改为接受 &[FileEntrySkeleton] 切片引用，避免 Vec 克隆。
        let deliver = |entries: &[crate::core::scanner::FileEntrySkeleton]| {
            for skeleton in entries {
                let name_c = CString::new(skeleton.name.as_bytes()).ok();
                let path_c = CString::new(skeleton.path.as_bytes()).ok();
                let ext_c = CString::new(skeleton.extension.as_bytes()).ok();

                let ff_entry = FFEntryRef {
                    name: name_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
                    path: path_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
                    extension: ext_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
                    is_dir: skeleton.is_dir,
                    is_file: skeleton.is_file,
                    is_symlink: skeleton.is_symlink,
                    is_hidden: skeleton.is_hidden,
                    is_system_protected: skeleton.is_system_protected,
                    size: skeleton.size,
                    modified: skeleton.modified,
                    created: skeleton.created,
                };

                callback(&ff_entry, user_data);
                // name_c, path_c, ext_c 在此自动 drop
            }
        };

        // ── L1 lookup ──────────────────────────────────────────────────
        // P2-15 修复：get() 返回 Arc<Vec<...>>，直接借用切片，无需克隆
        if let Some(entries) = crate::core::dir_cache::get(path_str) {
            deliver(&entries);
            clear_last_error();
            return FF_OK;
        }

        // ── L2 lookup (best-effort) ────────────────────────────────────
        if let Some(db_path) = CACHE_DB_PATH.get() {
            match crate::core::sqlite_cache::cache_get(db_path, path_str) {
                Ok(Some(entries)) => {
                    // Write back to L1 so subsequent reads hit memory.
                    crate::core::dir_cache::put(path_str.to_string(), entries.clone());
                    deliver(&entries);
                    clear_last_error();
                    return FF_OK;
                }
                Ok(None) => {
                    // Genuine L2 miss — fall through to NOT_FOUND below.
                }
                Err(e) => {
                    // L2 errored: record and degrade to L1-miss behavior.
                    set_last_error(format!("sqlite_cache::cache_get failed: {}", e));
                    return FF_ERR_NOT_FOUND;
                }
            }
        }

        set_last_error("path not found in cache".to_string());
        FF_ERR_NOT_FOUND
    })
}

/// Store directory entries in the cache.
///
/// Writes entries to both L1 (in-memory `dir_cache`) and, if
/// `ff_cache_init` has been called, L2 (persistent SQLite
/// `sqlite_cache`). L2 writes are best-effort: if the SQLite write fails,
/// the L1 write still succeeds and `FF_OK` is returned; the error is
/// recorded via `set_last_error`. When no db_path is configured, only L1
/// is written (backward-compatible behavior).
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 path string.
/// - `entries` — Array of `FFEntryRef` to cache.
/// - `entry_count` — Number of entries in the array.
///
/// # Returns
///
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if the path is invalid.
///
/// # Safety
///
/// - `path` must be a valid, NUL-terminated UTF-8 string.
/// - `entries` must be a valid pointer to an array of `FFEntryRef`.
/// - P2-11 补充说明：`entries` 数组中每个 `FFEntryRef` 的字符串字段
///   (`name`, `path`, `extension`) 必须为有效的 NUL 结尾 UTF-8 C 字符串指针，
///   或为 `NULL`（NULL 时该字段被视为空字符串）。
///   调用方需保证这些指针在 `ff_cache_put` 返回前持续有效。
///   指针有效性要求：每个非 NULL 的字符串指针必须指向以 `\0` 结尾的字节序列，
///   且不得在函数执行期间被释放或修改。
/// - `entry_count` must not exceed the actual length of the `entries` array.
#[no_mangle]
pub extern "C" fn ff_cache_put(
    path: *const c_char,
    entries: *const FFEntryRef,
    entry_count: usize,
) -> c_int {
    ffi_catch_int(|| {
        if path.is_null() {
            set_last_error("path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }
        if entries.is_null() && entry_count > 0 {
            set_last_error("entries is null but entry_count > 0".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        let mut skeletons = Vec::with_capacity(entry_count);
        for i in 0..entry_count {
            let entry = unsafe { &*entries.add(i) };
            let name = if entry.name.is_null() {
                String::new()
            } else {
                unsafe { CStr::from_ptr(entry.name).to_string_lossy().to_string() }
            };
            let path = if entry.path.is_null() {
                String::new()
            } else {
                unsafe { CStr::from_ptr(entry.path).to_string_lossy().to_string() }
            };
            let extension = if entry.extension.is_null() {
                String::new()
            } else {
                unsafe { CStr::from_ptr(entry.extension).to_string_lossy().to_string() }
            };

            skeletons.push(crate::core::scanner::FileEntrySkeleton {
                id: path.clone(),
                name,
                path,
                is_dir: entry.is_dir,
                is_file: entry.is_file,
                is_symlink: entry.is_symlink,
                is_hidden: entry.is_hidden,
                extension,
                size: entry.size,
                modified: entry.modified,
                created: entry.created,
                is_system_protected: entry.is_system_protected,
                metadata_loaded: true,
            });
        }

        // L1 write (always).
        crate::core::dir_cache::put(path_str.to_string(), skeletons.clone());

        // L2 write (best-effort) — only if db_path has been configured.
        let mut l2_failed = false;
        if let Some(db_path) = CACHE_DB_PATH.get() {
            if let Err(e) = crate::core::sqlite_cache::cache_put(db_path, path_str, &skeletons) {
                // L1 already succeeded; surface the L2 error but keep FF_OK.
                set_last_error(format!("sqlite_cache::cache_put failed: {}", e));
                l2_failed = true;
            }
        }

        if !l2_failed {
            clear_last_error();
        }
        FF_OK
    })
}

// ── Directory Cache FFI (Sub-project 5 aliases) ─────────────────────

/// Alias for ff_cache_get — get cached directory entries.
#[no_mangle]
pub extern "C" fn ff_dir_cache_get(
    path: *const c_char,
    callback: FFEntryCallback,
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| ff_cache_get(path, callback, user_data))
}

/// Alias for ff_cache_invalidate — invalidate directory cache.
#[no_mangle]
pub extern "C" fn ff_dir_cache_invalidate(path: *const c_char) -> c_int {
    ffi_catch_int(|| ff_cache_invalidate(path))
}

/// Clear all directory cache entries.
#[no_mangle]
pub extern "C" fn ff_dir_cache_clear() -> c_int {
    ffi_catch_int(|| {
        crate::core::dir_cache::clear();
        clear_last_error();
        FF_OK
    })
}

// ── FSEvents Watcher ──────────────────────────────────────────────

/// Callback type for FSEvents notifications.
/// Arguments: (path, user_data)
pub type FSEventCallback = extern "C" fn(path: *const c_char, user_data: *mut c_void);

/// Start watching a path for filesystem changes.
///
/// # Arguments
/// - `path` — NUL-terminated UTF-8 path string to watch.
/// - `callback` — Function called when a change is detected.
/// - `user_data` — Opaque pointer passed to the callback.
///
/// # Returns
/// - `0` on success.
/// - `FF_ERR_INVALID_PATH` if the path is invalid.
#[no_mangle]
pub extern "C" fn ff_fsevents_start(
    path: *const c_char,
    callback: FSEventCallback,
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        if path.is_null() {
            set_last_error("path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        match crate::core::fsevents::start(path_str, callback, user_data) {
            0 => {
                clear_last_error();
                FF_OK
            }
            _ => {
                set_last_error("fsevents_start failed".to_string());
                FF_ERR_IO
            }
        }
    })
}

/// Stop the FSEvents watcher.
///
/// # Arguments
/// - `handle` — Handle returned by ff_fsevents_start.
///
/// # Returns
/// - `0` on success.
#[no_mangle]
pub extern "C" fn ff_fsevents_stop(_handle: c_int) -> c_int {
    ffi_catch_int(|| {
        crate::core::fsevents::stop();
        clear_last_error();
        FF_OK
    })
}

/// FSEvents watcher lifecycle status codes (returned by `ff_fsevents_status`).
pub const FF_FSEVENTS_STATUS_STOPPED: c_int = 0;
pub const FF_FSEVENTS_STATUS_STARTING: c_int = 1;
pub const FF_FSEVENTS_STATUS_ACTIVE: c_int = 2;
pub const FF_FSEVENTS_STATUS_FAILED: c_int = 3;

/// Query the current FSEvents watcher lifecycle status.
///
/// # Returns
/// One of `FF_FSEVENTS_STATUS_STOPPED` (0), `FF_FSEVENTS_STATUS_STARTING`
/// (1), `FF_FSEVENTS_STATUS_ACTIVE` (2), or `FF_FSEVENTS_STATUS_FAILED` (3).
#[no_mangle]
pub extern "C" fn ff_fsevents_status() -> c_int {
    ffi_catch_int(|| {
        clear_last_error();
        crate::core::fsevents::status().as_c_int()
    })
}

// ── Content Index (FTS5) ───────────────────────────────────────────

/// Content-index lifecycle status codes (§6).
pub const FF_CONTENT_INDEX_STATUS_EMPTY: c_int = 0;
pub const FF_CONTENT_INDEX_STATUS_INDEXING: c_int = 1;
pub const FF_CONTENT_INDEX_STATUS_READY: c_int = 2;
pub const FF_CONTENT_INDEX_STATUS_ERROR: c_int = 3;
pub const FF_CONTENT_INDEX_STATUS_CANCELLED: c_int = 4;
pub const FF_CONTENT_INDEX_STATUS_UNAVAILABLE: c_int = 5;

/// Content-index build modes (§8.1).
pub const FF_CONTENT_INDEX_MODE_INCREMENTAL: c_int = 0;
pub const FF_CONTENT_INDEX_MODE_REBUILD: c_int = 1;

/// Initialize the independent content index at `db_path`.
///
/// Opens/creates `content_index.sqlite`, creates the schema, detects FTS5
/// (terminal `unavailable` if missing), and handles corruption + migration.
/// The path is set once per process (`OnceLock` semantics).
#[no_mangle]
pub extern "C" fn ff_content_index_init(db_path: *const c_char) -> c_int {
    ffi_catch_int(|| {
        if db_path.is_null() {
            set_last_error("db_path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }
        let db_path_str = unsafe {
            match CStr::from_ptr(db_path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("db_path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };
        match crate::core::content_index::init(db_path_str) {
            Ok(()) => {
                let _ = CONTENT_INDEX_DB_PATH.set(db_path_str.to_string());
                clear_last_error();
                FF_OK
            }
            Err(e) => {
                set_last_error(format!("content_index::init failed: {}", e));
                FF_ERR_IO
            }
        }
    })
}

/// Query the content-index status machine (§6).
#[no_mangle]
pub extern "C" fn ff_content_index_status() -> c_int {
    ffi_catch_int(|| {
        clear_last_error();
        crate::core::content_index::status().as_c_int()
    })
}

/// Start a content-index build on a background thread.
///
/// `mode` = `FF_CONTENT_INDEX_MODE_INCREMENTAL` (0) or `_REBUILD` (1).
/// The freshly allocated cancel handle is written to `*out_handle` before
/// the build starts; `NULL` ignores it.
#[no_mangle]
pub extern "C" fn ff_content_index_start(
    root_path: *const c_char,
    mode: c_int,
    out_handle: *mut u64,
) -> c_int {
    ffi_catch_int(|| {
        if root_path.is_null() {
            set_last_error("root_path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }
        let root = unsafe {
            match CStr::from_ptr(root_path).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => {
                    set_last_error("root_path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };
        let mode = match crate::core::content_index::Mode::from_int(mode) {
            Some(m) => m,
            None => {
                set_last_error("invalid content index mode".to_string());
                return FF_ERR_INVALID_PATH;
            }
        };
        let db_path = match CONTENT_INDEX_DB_PATH.get() {
            Some(p) => p.clone(),
            None => {
                set_last_error("content index not initialized".to_string());
                return FF_ERR_IO;
            }
        };

        let (guard, cancel, pause) = OpGuard::register_full(OpKind::Index);
        if !out_handle.is_null() {
            unsafe {
                *out_handle = guard.id;
            }
        }
        let prior = match crate::core::content_index::begin_build() {
            Ok(p) => p,
            Err(e) => {
                set_last_error(format!("cannot start build: {}", e));
                return FF_ERR_GENERIC;
            }
        };

        std::thread::spawn(move || {
            let _guard = guard;
            crate::core::content_index::run_build(&db_path, &root, mode, prior, &cancel, &pause);
        });

        clear_last_error();
        FF_OK
    })
}

/// Cancel a specific content-index build by its handle.
#[no_mangle]
pub extern "C" fn ff_content_index_cancel(handle: u64) -> c_int {
    ffi_catch_int(|| cancel_op(handle, OpKind::Index))
}

/// Pause a specific content-index build by its handle (batch-boundary).
#[no_mangle]
pub extern "C" fn ff_content_index_pause(handle: u64) -> c_int {
    ffi_catch_int(|| pause_op(handle, OpKind::Index))
}

/// Resume a specific paused content-index build by its handle.
#[no_mangle]
pub extern "C" fn ff_content_index_resume(handle: u64) -> c_int {
    ffi_catch_int(|| resume_op(handle, OpKind::Index))
}

/// Mark a path dirty for incremental processing (O(1), no I/O).
#[no_mangle]
pub extern "C" fn ff_content_index_mark_dirty(path: *const c_char) -> c_int {
    ffi_catch_int(|| {
        if path.is_null() {
            set_last_error("path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }
        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };
        crate::core::content_index::mark_dirty(path_str);
        clear_last_error();
        FF_OK
    })
}

/// Run a content query. Non-ready state returns `FF_ERR_NOT_FOUND`.
#[no_mangle]
pub extern "C" fn ff_content_index_query(
    query: *const c_char,
    max_results: usize,
    callback: FFSearchCallback,
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        if query.is_null() {
            set_last_error("query is null".to_string());
            return FF_ERR_INVALID_PATH;
        }
        if crate::core::content_index::status() != crate::core::content_index::Status::Ready {
            set_last_error("content index not ready".to_string());
            return FF_ERR_NOT_FOUND;
        }
        let query_str = unsafe {
            match CStr::from_ptr(query).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("query is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };
        let db_path = match CONTENT_INDEX_DB_PATH.get() {
            Some(p) => p.clone(),
            None => {
                set_last_error("content index not initialized".to_string());
                return FF_ERR_NOT_FOUND;
            }
        };
        let cap = if max_results == 0 { 500 } else { max_results };

        let mut cb = |result: crate::core::search_engine::SearchResult| {
            let path_c = CString::new(result.path.as_bytes()).ok();
            let name_c = CString::new(result.name.as_bytes()).ok();
            let result_c = FFSearchResult {
                path: path_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
                name: name_c.as_ref().map(|c| c.as_ptr() as *mut c_char).unwrap_or(std::ptr::null_mut()),
                size: result.size,
                modified: result.modified,
                is_dir: result.is_dir,
            };
            callback(&result_c, user_data);
        };

        match crate::core::content_index::query(&db_path, query_str, cap, &mut cb) {
            Ok(()) => {
                clear_last_error();
                FF_OK
            }
            Err(e) => {
                set_last_error(format!("content index query failed: {}", e));
                FF_ERR_IO
            }
        }
    })
}

/// Return the stats JSON (§7.3). Must be freed with `ff_free_string`.
#[no_mangle]
pub extern "C" fn ff_content_index_stats() -> *mut c_char {
    ffi_catch_ptr(|| rust_string_to_c(crate::core::content_index::stats_json()))
}

// ── Batch Rename & Organize ────────────────────────────────────────

/// C-compatible batch rename item.
#[repr(C)]
pub struct FFRenameItem {
    pub original_path: *mut c_char,
    pub new_name: *mut c_char,
}

/// Callback for batch operation progress.
pub type FFBatchProgressCallback = extern "C" fn(completed: usize, total: usize, current_file: *const c_char, user_data: *mut c_void);

/// Batch rename files.
///
/// # Arguments
///
/// - `items` — Array of `FFRenameItem`.
/// - `item_count` — Number of items.
///
/// # Returns
///
/// - Number of successful renames on success (>= 0).
/// - `FF_ERR_INVALID_PATH` if inputs are invalid.
/// - `FF_ERR_IO` if a filesystem error occurs.
///
/// # Safety
///
/// - `items` must be a valid pointer to an array of `FFRenameItem`.
#[no_mangle]
pub extern "C" fn ff_batch_rename(
    items: *const FFRenameItem,
    item_count: usize,
) -> c_int {
    ffi_catch_int(|| {
        if items.is_null() && item_count > 0 {
            set_last_error("items is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let mut rename_items = Vec::with_capacity(item_count);
        for i in 0..item_count {
            let item = unsafe { &*items.add(i) };
            let original = if item.original_path.is_null() {
                String::new()
            } else {
                unsafe { CStr::from_ptr(item.original_path).to_string_lossy().to_string() }
            };
            let new_name = if item.new_name.is_null() {
                String::new()
            } else {
                unsafe { CStr::from_ptr(item.new_name).to_string_lossy().to_string() }
            };
            if let Err(msg) = crate::core::path_guard::path_guard(&original) {
                set_last_error(msg);
                return FF_ERR_INVALID_PATH;
            }
            rename_items.push(crate::core::batch_ops::RenameItem {
                original_path: original,
                new_name,
            });
        }

        match crate::core::batch_ops::batch_rename(&rename_items, None) {
            Ok(count) => {
                clear_last_error();
                count as c_int
            }
            Err(e) => {
                set_last_error(format!("batch_rename failed: {}", e));
                // An invalid new_name (traversal / empty / control chars) is
                // an input error, not an I/O failure.
                if e.kind() == io::ErrorKind::InvalidInput {
                    FF_ERR_INVALID_PATH
                } else {
                    FF_ERR_IO
                }
            }
        }
    })
}

/// Organize files by date into folders.
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 directory path.
/// - `format` — NUL-terminated UTF-8 format string (e.g., "YYYY/MM/DD").
///
/// # Returns
///
/// - Number of files moved on success (>= 0).
/// - `FF_ERR_INVALID_PATH` if inputs are invalid.
/// - `FF_ERR_IO` if a filesystem error occurs.
///
/// # Safety
///
/// - `path` and `format` must be valid, NUL-terminated UTF-8 strings.
#[no_mangle]
pub extern "C" fn ff_organize_by_date(
    path: *const c_char,
    format: *const c_char,
) -> c_int {
    ffi_catch_int(|| {
        if path.is_null() || format.is_null() {
            set_last_error("path or format is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        let format_str = unsafe {
            match CStr::from_ptr(format).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("format is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        if let Err(msg) = crate::core::path_guard::path_guard(path_str) {
            set_last_error(msg);
            return FF_ERR_INVALID_PATH;
        }

        match crate::core::batch_ops::organize_by_date(path_str, format_str, None) {
            Ok(count) => {
                clear_last_error();
                count as c_int
            }
            Err(e) => {
                set_last_error(format!("organize_by_date failed: {}", e));
                FF_ERR_IO
            }
        }
    })
}

/// Organize files by file type into category folders.
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 directory path.
///
/// # Returns
///
/// - Number of files moved on success (>= 0).
/// - `FF_ERR_INVALID_PATH` if inputs are invalid.
/// - `FF_ERR_IO` if a filesystem error occurs.
///
/// # Safety
///
/// - `path` must be a valid, NUL-terminated UTF-8 string.
#[no_mangle]
pub extern "C" fn ff_organize_by_type(
    path: *const c_char,
) -> c_int {
    ffi_catch_int(|| {
        if path.is_null() {
            set_last_error("path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        if let Err(msg) = crate::core::path_guard::path_guard(path_str) {
            set_last_error(msg);
            return FF_ERR_INVALID_PATH;
        }

        match crate::core::batch_ops::organize_by_type(path_str, None) {
            Ok(count) => {
                clear_last_error();
                count as c_int
            }
            Err(e) => {
                set_last_error(format!("organize_by_type failed: {}", e));
                FF_ERR_IO
            }
        }
    })
}

// ── Parallel Batch Operations (rayon-backed) ──────────────────────

/// Parse a `*const *const c_char` array of NUL-terminated UTF-8 C strings
/// into a `Vec<String>`. Null pointers within the array become empty strings.
///
/// # Safety
///
/// - `ptrs` must point to an array of at least `count` valid `*const c_char`
///   entries; each non-null entry must be a NUL-terminated UTF-8 C string.
unsafe fn parse_c_string_array(ptrs: *const *const c_char, count: usize) -> Vec<String> {
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        let p = *ptrs.add(i);
        if p.is_null() {
            out.push(String::new());
        } else {
            out.push(CStr::from_ptr(p).to_string_lossy().to_string());
        }
    }
    out
}

/// Parallel copy multiple files into a destination directory using rayon.
///
/// Each source file is copied (CoW when possible) into `dst_dir` keeping its
/// basename. The progress callback is invoked from worker threads as files
/// complete.
///
/// # Arguments
///
/// - `srcs` — Array of source path C strings.
/// - `src_count` — Number of entries in `srcs`.
/// - `dst_dir` — Destination directory C string.
/// - `progress` — Callback invoked with (completed, total, current_file, user_data).
///   `current_file` is always passed as null because `parallel_ops` does not
///   report per-file names.
/// - `user_data` — Opaque pointer passed through to the callback.
///
/// # Returns
///
/// - Number of successfully copied files (>= 0). Partial failures are
///   reflected as a count less than `src_count`.
/// - `FF_ERR_INVALID_PATH` if `srcs` (when `src_count > 0`) or `dst_dir` is null.
///
/// # Safety
///
/// - `srcs` must point to `src_count` valid C string pointers.
/// - `dst_dir` must be a valid NUL-terminated UTF-8 C string.
#[no_mangle]
pub extern "C" fn ff_parallel_copy(
    srcs: *const *const c_char,
    src_count: usize,
    dst_dir: *const c_char,
    progress: FFBatchProgressCallback,
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        if srcs.is_null() && src_count > 0 {
            set_last_error("srcs is null".to_string());
            return FF_ERR_INVALID_PATH;
        }
        if dst_dir.is_null() {
            set_last_error("dst_dir is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let srcs_vec = if src_count == 0 {
            Vec::new()
        } else {
            unsafe { parse_c_string_array(srcs, src_count) }
        };
        let dst_dir_str = unsafe {
            match CStr::from_ptr(dst_dir).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => {
                    set_last_error("dst_dir is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        if let Err(msg) = crate::core::path_guard::path_guard(&dst_dir_str) {
            set_last_error(msg);
            return FF_ERR_INVALID_PATH;
        }
        for src in &srcs_vec {
            if let Err(msg) = crate::core::path_guard::path_guard(src) {
                set_last_error(msg);
                return FF_ERR_INVALID_PATH;
            }
        }

        // Cast `user_data` to `usize` so the closure captures a `Sync` value
        // (raw pointers are `!Sync` by default, which would violate the
        // `Fn(...) + Sync` bound required by rayon's `par_iter`).
        let user_data_addr = user_data as usize;
        let results = crate::core::parallel_ops::parallel_copy_files(
            &srcs_vec,
            &dst_dir_str,
            move |done, total| progress(done, total, ptr::null(), user_data_addr as *mut c_void),
        );
        let success = results.iter().filter(|(_, r)| r.is_ok()).count();
        if success < results.len() {
            set_last_error(summarize_parallel_failures(&results, 5));
        } else {
            clear_last_error();
        }
        success as c_int
    })
}

/// Parallel move multiple files into a destination directory using rayon.
///
/// Same semantics as [`ff_parallel_copy`], but moves files instead. Falls back
/// to copy-then-delete when `rename(2)` fails (e.g. cross-volume).
///
/// # Safety
///
/// See [`ff_parallel_copy`].
#[no_mangle]
pub extern "C" fn ff_parallel_move(
    srcs: *const *const c_char,
    src_count: usize,
    dst_dir: *const c_char,
    progress: FFBatchProgressCallback,
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        if srcs.is_null() && src_count > 0 {
            set_last_error("srcs is null".to_string());
            return FF_ERR_INVALID_PATH;
        }
        if dst_dir.is_null() {
            set_last_error("dst_dir is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let srcs_vec = if src_count == 0 {
            Vec::new()
        } else {
            unsafe { parse_c_string_array(srcs, src_count) }
        };
        let dst_dir_str = unsafe {
            match CStr::from_ptr(dst_dir).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => {
                    set_last_error("dst_dir is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        if let Err(msg) = crate::core::path_guard::path_guard(&dst_dir_str) {
            set_last_error(msg);
            return FF_ERR_INVALID_PATH;
        }
        for src in &srcs_vec {
            if let Err(msg) = crate::core::path_guard::path_guard(src) {
                set_last_error(msg);
                return FF_ERR_INVALID_PATH;
            }
        }

        let user_data_addr = user_data as usize;
        let results = crate::core::parallel_ops::parallel_move_files(
            &srcs_vec,
            &dst_dir_str,
            move |done, total| progress(done, total, ptr::null(), user_data_addr as *mut c_void),
        );
        let success = results.iter().filter(|(_, r)| r.is_ok()).count();
        if success < results.len() {
            set_last_error(summarize_parallel_failures(&results, 5));
        } else {
            clear_last_error();
        }
        success as c_int
    })
}

/// Parallel delete multiple files/directories using rayon.
///
/// Directories are removed recursively; files are unlinked. Partial failures
/// are reflected as a success count less than `path_count`.
///
/// # Arguments
///
/// - `paths` — Array of path C strings to delete.
/// - `path_count` — Number of entries in `paths`.
/// - `progress` — Callback invoked with (completed, total, null, user_data).
/// - `user_data` — Opaque pointer passed through to the callback.
///
/// # Returns
///
/// - Number of successfully deleted paths (>= 0).
/// - `FF_ERR_INVALID_PATH` if `paths` is null when `path_count > 0`.
///
/// # Safety
///
/// - `paths` must point to `path_count` valid C string pointers.
#[no_mangle]
pub extern "C" fn ff_parallel_delete(
    paths: *const *const c_char,
    path_count: usize,
    progress: FFBatchProgressCallback,
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        if paths.is_null() && path_count > 0 {
            set_last_error("paths is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let paths_vec = if path_count == 0 {
            Vec::new()
        } else {
            unsafe { parse_c_string_array(paths, path_count) }
        };

        for p in &paths_vec {
            if let Err(msg) = crate::core::path_guard::path_guard(p) {
                set_last_error(msg);
                return FF_ERR_INVALID_PATH;
            }
        }

        let user_data_addr = user_data as usize;
        let results = crate::core::parallel_ops::parallel_delete_files(
            &paths_vec,
            move |done, total| progress(done, total, ptr::null(), user_data_addr as *mut c_void),
        );
        let success = results.iter().filter(|(_, r)| r.is_ok()).count();
        if success < results.len() {
            set_last_error(summarize_parallel_failures(&results, 5));
        } else {
            clear_last_error();
        }
        success as c_int
    })
}

// ── Thumbnail Generation ──────────────────────────────────────────

/// Generate a thumbnail for an image file.
///
/// # Arguments
/// - `path` — NUL-terminated UTF-8 path to the image file.
/// - `max_size` — Maximum width/height of the thumbnail.
/// - `callback` — Called with the thumbnail path.
/// - `user_data` — Opaque pointer passed to the callback.
///
/// # Returns
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if the path is invalid.
#[no_mangle]
pub extern "C" fn ff_generate_thumbnail(
    path: *const c_char,
    max_size: u32,
    callback: extern "C" fn(thumbnail_path: *const c_char, user_data: *mut c_void),
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        if path.is_null() {
            set_last_error("path is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let path_str = unsafe {
            match CStr::from_ptr(path).to_str() {
                Ok(s) => s,
                Err(_) => {
                    set_last_error("path is not valid UTF-8".to_string());
                    return FF_ERR_INVALID_PATH;
                }
            }
        };

        match crate::core::thumbnails::generate_thumbnail(path_str, max_size) {
            Ok(thumb_path) => {
                let path_c = rust_string_to_c(thumb_path.to_string_lossy());
                callback(path_c, user_data);
                if !path_c.is_null() {
                    unsafe { let _ = CString::from_raw(path_c); }
                }
                clear_last_error();
                FF_OK
            }
            Err(e) => {
                set_last_error(format!("generate_thumbnail failed: {}", e));
                FF_ERR_IO
            }
        }
    })
}

/// Generate thumbnails for multiple image files.
///
/// # Arguments
/// - `paths` — Array of NUL-terminated UTF-8 paths.
/// - `path_count` — Number of paths.
/// - `max_size` — Maximum width/height of each thumbnail.
/// - `callback` — Called for each thumbnail path.
/// - `user_data` — Opaque pointer passed to the callback.
///
/// # Returns
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if inputs are invalid.
#[no_mangle]
pub extern "C" fn ff_generate_thumbnails(
    paths: *const *const c_char,
    path_count: usize,
    max_size: u32,
    callback: extern "C" fn(thumbnail_path: *const c_char, user_data: *mut c_void),
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        if paths.is_null() && path_count > 0 {
            set_last_error("paths is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let mut path_strings = Vec::with_capacity(path_count);
        for i in 0..path_count {
            let path_ptr = unsafe { *paths.add(i) };
            if path_ptr.is_null() {
                set_last_error("path in array is null".to_string());
                return FF_ERR_INVALID_PATH;
            }
            let path_str = unsafe {
                match CStr::from_ptr(path_ptr).to_str() {
                    Ok(s) => s.to_string(),
                    Err(_) => {
                        set_last_error("path is not valid UTF-8".to_string());
                        return FF_ERR_INVALID_PATH;
                    }
                }
            };
            path_strings.push(path_str);
        }

        match crate::core::thumbnails::generate_thumbnails(&path_strings, max_size) {
            Ok(thumb_paths) => {
                for thumb_path in thumb_paths {
                    let path_c = rust_string_to_c(thumb_path.to_string_lossy());
                    callback(path_c, user_data);
                    if !path_c.is_null() {
                        unsafe { let _ = CString::from_raw(path_c); }
                    }
                }
                clear_last_error();
                FF_OK
            }
            Err(e) => {
                set_last_error(format!("generate_thumbnails failed: {}", e));
                FF_ERR_IO
            }
        }
    })
}

// ── Settings API (Sub-project 8) ────────────────────────────────────

/// Load all settings as a JSON string.
///
/// Returns a heap-allocated C string. Must be freed with `ff_free_string()`.
#[no_mangle]
pub extern "C" fn ff_settings_load() -> *mut c_char {
    ffi_catch_ptr(crate::core::settings::settings_load)
}

/// Save all settings from a JSON string.
///
/// # Arguments
/// - `json` — NUL-terminated UTF-8 JSON string containing settings.
///
/// # Returns
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if json is null.
/// - `FF_ERR_GENERIC` if JSON parsing fails.
#[no_mangle]
pub extern "C" fn ff_settings_save(json: *const c_char) -> c_int {
    ffi_catch_int(|| crate::core::settings::settings_save(json))
}

/// Get a specific setting value by key.
///
/// Keys are dot-separated, e.g., "general.default_directory", "appearance.theme".
///
/// # Arguments
/// - `key` — NUL-terminated UTF-8 key string.
///
/// # Returns
/// - Pointer to value string on success.
/// - `NULL` on error or if key not found.
#[no_mangle]
pub extern "C" fn ff_settings_get(key: *const c_char) -> *mut c_char {
    ffi_catch_ptr(|| crate::core::settings::settings_get(key))
}

/// Set a specific setting value by key.
///
/// Keys are dot-separated, e.g., "general.default_directory", "appearance.theme".
///
/// # Arguments
/// - `key` — NUL-terminated UTF-8 key string.
/// - `value` — NUL-terminated UTF-8 value string.
///
/// # Returns
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if key or value is null.
/// - `FF_ERR_GENERIC` if key is invalid.
#[no_mangle]
pub extern "C" fn ff_settings_set(key: *const c_char, value: *const c_char) -> c_int {
    ffi_catch_int(|| crate::core::settings::settings_set(key, value))
}

// ── Volume Data Structures ──────────────────────────────────────────

/// C-compatible volume info structure
#[repr(C)]
pub struct FFVolumeInfo {
    pub name: *mut c_char,
    pub path: *mut c_char,
    pub fs_type: *mut c_char,
    pub total_size: u64,
    pub free_size: u64,
    pub used_size: u64,
    pub is_removable: bool,
    pub is_ejectable: bool,
    pub is_writable: bool,
}

/// Callback for volume list (passes FFVolumeInfo struct pointer, aligned with ff_ffi.h)
pub type FFVolumeCallback = extern "C" fn(
    volume: *const FFVolumeInfo,
    user_data: *mut c_void,
);

/// Callback for volume info
pub type FFVolumeInfoCallback = extern "C" fn(
    path: *const c_char,
    name: *const c_char,
    fs_type: *const c_char,
    total_size: u64,
    used_size: u64,
    free_size: u64,
    filesystem: *const c_char,
    is_removable: bool,
    is_ejectable: bool,
    is_network: bool,
    user_data: *mut c_void,
);

/// Callback for health check result
pub type FFHealthCallback = extern "C" fn(
    path: *const c_char,
    status: *const c_char,
    usage_percent: f64,
    smart_available: bool,
    smart_status: *const c_char,
    user_data: *mut c_void,
);

// ── Task Data Structures ────────────────────────────────────────────

/// C-compatible task info structure (must match FFTaskInfo in ff_ffi.h)
/// id: string pointer, status: int enum — NOT the old u64/pointer layout.
#[repr(C)]
pub struct FFTaskInfo {
    pub id: *mut c_char,
    pub name: *mut c_char,
    pub description: *mut c_char,
    pub priority: i32,
    pub status: i32,
    pub progress: f64,
    pub created_at: i64,
    pub started_at: i64,
    pub completed_at: i64,
}

/// Callback for task list / history: 2 params (FFTaskInfo pointer + user_data),
/// matching ff_ffi.h `void (*callback)(const FFTaskInfo *task, void *user_data)`.
pub type FFTaskListCallback = extern "C" fn(
    task: *const FFTaskInfo,
    user_data: *mut c_void,
);

/// List all tasks (FFI wrapper with FFTaskInfo struct).
///
/// Each `FFTaskInfo` is stack-allocated per iteration; its string fields
/// point into local `CString`s that are dropped immediately after the
/// callback returns. The callback must **not** retain the pointer or any
/// string field beyond the call.
///
/// # Arguments
/// - `callback` — Called for each task with raw task info pointer. Must be non-null.
/// - `user_data` — Opaque pointer passed to callback
///
/// # Returns
/// - `FF_OK` on success
/// - `FF_ERR_INVALID_PATH` if `callback` is null
#[no_mangle]
pub extern "C" fn ff_task_list(
    callback: extern "C" fn(*const FFTaskInfo, *mut c_void),
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        if callback as usize == 0 {
            set_last_error("callback is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let tasks = crate::core::task_scheduler::scheduler().list_tasks();

        for task in tasks {
            let id_c = rust_string_to_c(task.id.to_string());
            let name_c = rust_string_to_c(task.task_type.as_str());
            let desc_c = rust_string_to_c(task.params.get("description").cloned().unwrap_or_default());
            let status_int: i32 = match task.status.as_str() {
                "Pending" => 0,
                "Running" => 1,
                "Completed" => 2,
                "Failed" => 3,
                "Cancelled" => 4,
                _ => 0,
            };

            let ff_task = FFTaskInfo {
                id: id_c,
                name: name_c,
                description: desc_c,
                priority: match task.priority {
                    crate::core::task_scheduler::TaskPriority::Low => 0,
                    crate::core::task_scheduler::TaskPriority::Normal => 1,
                    crate::core::task_scheduler::TaskPriority::High => 2,
                    crate::core::task_scheduler::TaskPriority::Critical => 2, // clamp to High (no Critical in C enum)
                },
                status: status_int,
                progress: task.progress,
                created_at: task.created_at as i64,
                started_at: task.started_at.unwrap_or(0) as i64,
                completed_at: task.completed_at.unwrap_or(0) as i64,
            };

            callback(&ff_task, user_data);

            // 释放本次迭代分配的所有 CString（修复 description 内存泄漏）
            if !id_c.is_null() { unsafe { let _ = CString::from_raw(id_c); } }
            if !name_c.is_null() { unsafe { let _ = CString::from_raw(name_c); } }
            if !desc_c.is_null() { unsafe { let _ = CString::from_raw(desc_c); } }
        }

        FF_OK
    })
}

/// Get task history (tasks already moved out of the active map).
///
/// Uses the same `FFTaskInfo` struct callback as [`ff_task_list`], and the
/// exact same RAII string ownership contract: every C string is owned by a
/// local `CString` that is dropped immediately after the callback returns.
/// The callback must **not** retain the `FFTaskInfo` pointer or any of its
/// string fields beyond the call.
///
/// # Arguments
/// - `callback` — Called for each historical task. Must be non-null.
/// - `user_data` — Opaque pointer passed to callback.
///
/// # Returns
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if `callback` is null.
///
/// # Safety
/// - `callback` must be a valid function pointer, or null to request the
///   invalid-path error.
#[no_mangle]
pub extern "C" fn ff_task_history(
    callback: FFTaskListCallback,
    user_data: *mut c_void,
) -> c_int {
    ffi_catch_int(|| {
        if callback as usize == 0 {
            set_last_error("callback is null".to_string());
            return FF_ERR_INVALID_PATH;
        }

        let tasks = crate::core::task_scheduler::scheduler().get_history();

        for task in tasks {
            let id_c = rust_string_to_c(task.id.to_string());
            let name_c = rust_string_to_c(task.task_type.as_str());
            let desc_c = rust_string_to_c(task.params.get("description").cloned().unwrap_or_default());
            let status_int: i32 = match task.status.as_str() {
                "Pending" => 0,
                "Running" => 1,
                "Completed" => 2,
                "Failed" => 3,
                "Cancelled" => 4,
                _ => 0,
            };

            let ff_task = FFTaskInfo {
                id: id_c,
                name: name_c,
                description: desc_c,
                priority: match task.priority {
                    crate::core::task_scheduler::TaskPriority::Low => 0,
                    crate::core::task_scheduler::TaskPriority::Normal => 1,
                    crate::core::task_scheduler::TaskPriority::High => 2,
                    crate::core::task_scheduler::TaskPriority::Critical => 2, // clamp to High (no Critical in C enum)
                },
                status: status_int,
                progress: task.progress,
                created_at: task.created_at as i64,
                started_at: task.started_at.unwrap_or(0) as i64,
                completed_at: task.completed_at.unwrap_or(0) as i64,
            };

            callback(&ff_task, user_data);

            if !id_c.is_null() { unsafe { let _ = CString::from_raw(id_c); } }
            if !name_c.is_null() { unsafe { let _ = CString::from_raw(name_c); } }
            if !desc_c.is_null() { unsafe { let _ = CString::from_raw(desc_c); } }
        }

        FF_OK
    })
}

/// Get progress for a specific task
///
/// # Arguments
/// - `task_id` — NUL-terminated UTF-8 task ID string
/// - `out_progress` — Pointer to store progress value
///
/// # Returns
/// - `FF_OK` on success
/// - `FF_ERR_NOT_FOUND` if task not found
#[no_mangle]
pub extern "C" fn ff_task_progress(
    task_id: *const c_char,
    out_progress: *mut f64,
) -> c_int {
    ffi_catch_int(|| {
        if task_id.is_null() || out_progress.is_null() {
            return FF_ERR_INVALID_PATH;
        }

        let id_str = unsafe {
            match CStr::from_ptr(task_id).to_str() {
                Ok(s) => s,
                Err(_) => return FF_ERR_INVALID_PATH,
            }
        };

        let id = match id_str.parse::<u64>() {
            Ok(id) => id,
            Err(_) => return FF_ERR_INVALID_PATH,
        };

        let tasks = crate::core::task_scheduler::scheduler().list_tasks();
        if let Some(task) = tasks.iter().find(|t| t.id == id) {
            unsafe {
                *out_progress = task.progress;
            }
            FF_OK
        } else {
            FF_ERR_NOT_FOUND
        }
    })
}

/// Calculate the BLAKE3 hash of a file.
///
/// # Arguments
/// - `path` — NUL-terminated UTF-8 path to the file.
/// - `out_hash` — Pointer to receive the heap-allocated hash string (must be freed with `ff_free_string`).
///
/// # Returns
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if path or out_hash is null.
/// - `FF_ERR_IO` on I/O error.
#[no_mangle]
pub extern "C" fn ff_hash_file(
    path: *const c_char,
    out_hash: *mut *mut c_char,
) -> c_int {
    ffi_catch_int(|| {
        if path.is_null() || out_hash.is_null() {
            return FF_ERR_INVALID_PATH;
        }

        let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
            Ok(s) => s,
            Err(_) => return FF_ERR_INVALID_PATH,
        };

        match crate::core::scanner::hash_file(path_str) {
            Ok(hash) => {
                let c_string = CString::new(hash).unwrap_or_default();
                unsafe {
                    *out_hash = c_string.into_raw();
                }
                FF_OK
            }
            Err(e) => {
                set_last_error(e.to_string());
                FF_ERR_IO
            }
        }
    })
}

// ── AI Tag Generation ──────────────────────────────────────────────

/// Generate classification tags for a file based on its extension, size, and type.
///
/// Reads the file's metadata via `std::fs::metadata`, then applies rule-based
/// classification (image/video/audio/document/code/archive/large_file/folder).
/// The result is returned as a JSON array string.
///
/// # Arguments
/// - `path` — NUL-terminated UTF-8 file path.
///
/// # Returns
/// - Heap-allocated C string containing a JSON array, e.g.
///   `[{"name":"图片","color":"#FF6B35","category":"image"}]`.
///   Must be freed with `ff_free_string()`.
/// - `null` if `path` is null, not valid UTF-8, or the file does not exist.
///   In the error case, `ff_last_error()` returns a description.
#[no_mangle]
pub extern "C" fn ff_generate_tags(path: *const c_char) -> *mut c_char {
    ffi_catch_ptr(|| {
        if path.is_null() {
            set_last_error("path is null".to_string());
            return ptr::null_mut();
        }

        let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_last_error("path is not valid UTF-8".to_string());
                return ptr::null_mut();
            }
        };

        let tags = crate::core::tags::generate_tags(path_str);

        if tags.is_empty() {
            // 文件不存在或无匹配规则时，检查是否因文件不存在
            if std::fs::metadata(path_str).is_err() {
                set_last_error(format!("cannot read file metadata: {}", path_str));
                return ptr::null_mut();
            }
            // 文件存在但无匹配规则 → 返回空数组 "[]"（非错误）
        }

        let json = crate::core::tags::tags_to_json(&tags);
        rust_string_to_c(json)
    })
}

// ── Tests ───────────────────────────────────────────────────────────

#[cfg(test)]
mod tests;
