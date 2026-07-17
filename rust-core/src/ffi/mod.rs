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

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;
use std::sync::Mutex;

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

thread_local! {
    static LAST_ERROR: Mutex<Option<String>> = Mutex::new(None);
}

fn set_last_error(msg: String) {
    LAST_ERROR.with(|e| {
        *e.lock().unwrap() = Some(msg);
    });
}

fn clear_last_error() {
    LAST_ERROR.with(|e| {
        *e.lock().unwrap() = None;
    });
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

// ── Helper: convert Rust String to C string ─────────────────────────

fn rust_string_to_c(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
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
                let name_c = rust_string_to_c(entry.name.clone());
                let path_c = rust_string_to_c(entry.path.clone());
                let ext_c = rust_string_to_c(entry.extension.clone());

                let ff_entry = FFEntryRef {
                    name: name_c,
                    path: path_c,
                    extension: ext_c,
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

                // Clean up the strings we allocated for this entry.
                if !name_c.is_null() {
                    unsafe { let _ = CString::from_raw(name_c); }
                }
                if !path_c.is_null() {
                    unsafe { let _ = CString::from_raw(path_c); }
                }
                if !ext_c.is_null() {
                    unsafe { let _ = CString::from_raw(ext_c); }
                }
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
    LAST_ERROR.with(|e| {
        let guard = e.lock().unwrap();
        match guard.as_ref() {
            Some(msg) => rust_string_to_c(msg.clone()),
            None => ptr::null_mut(),
        }
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
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

// ── Additional exported functions (placeholders for future use) ────

/// Get the library version string.
///
/// Returns a heap-allocated C string. Must be freed with `ff_free_string()`.
#[no_mangle]
pub extern "C" fn ff_version_string() -> *mut c_char {
    rust_string_to_c(env!("CARGO_PKG_VERSION").to_string())
}

/// Get the system memory size in bytes.
#[no_mangle]
pub extern "C" fn ff_get_system_memory() -> u64 {
    // Return 0 as a placeholder; platform-specific implementation
    // can use sysinfo or similar on macOS.
    0
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
}

// ── Duplicate File Detection ──────────────────────────────────────

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

static DEDUP_CANCEL: AtomicBool = AtomicBool::new(false);

/// Scan for duplicate files under `path`.
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 root path string.
/// - `progress_callback` — Called with (scanned, total) progress updates.
/// - `group_callback` — Called for each duplicate group found.
/// - `user_data` — Opaque pointer passed to callbacks.
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

    // Reset cancel flag
    DEDUP_CANCEL.store(false, Ordering::Relaxed);

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
                    let files: Vec<FFDuplicateFile> = group
                        .files
                        .iter()
                        .map(|f| FFDuplicateFile {
                            id: rust_string_to_c(f.id.clone()),
                            path: rust_string_to_c(f.path.clone()),
                            name: rust_string_to_c(f.name.clone()),
                            size: f.size,
                            modified: f.modified,
                        })
                        .collect();

                    let group_c = FFDuplicateGroup {
                        id: rust_string_to_c(group.id.clone()),
                        hash: rust_string_to_c(group.hash.clone()),
                        size: group.size,
                        files: files.as_ptr(),
                        file_count: files.len(),
                    };

                    (self.group)(&group_c, self.user_data);

                    // Clean up allocated strings
                    for f in &files {
                        if !f.id.is_null() {
                            unsafe { let _ = CString::from_raw(f.id); }
                        }
                        if !f.path.is_null() {
                            unsafe { let _ = CString::from_raw(f.path); }
                        }
                        if !f.name.is_null() {
                            unsafe { let _ = CString::from_raw(f.name); }
                        }
                    }
                    if !group_c.id.is_null() {
                        unsafe { let _ = CString::from_raw(group_c.id); }
                    }
                    if !group_c.hash.is_null() {
                        unsafe { let _ = CString::from_raw(group_c.hash); }
                    }
                }
                _ => {}
            }
        }
    }

    let cancel = Arc::new(AtomicBool::new(false));
    let emitter = CallbackEmitter {
        progress: progress_callback,
        group: group_callback,
        user_data,
    };

    let _groups = crate::core::dedup_engine::run_scan(
        vec![path_str.to_string()],
        &emitter,
        cancel,
    );

    clear_last_error();
    FF_OK
}

/// Cancel an ongoing duplicate scan.
#[no_mangle]
pub extern "C" fn ff_cancel_scan() {
    DEDUP_CANCEL.store(true, Ordering::Relaxed);
}

// ── File Search ─────────────────────────────────────────────────────

/// Search for files matching `query` under `path`.
///
/// # Arguments
///
/// - `path` — NUL-terminated UTF-8 root path string.
/// - `query` — NUL-terminated UTF-8 search query.
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
/// - `path` and `query` must be valid, NUL-terminated UTF-8 strings.
/// - `callback` must be a valid function pointer.
#[no_mangle]
pub extern "C" fn ff_search(
    path: *const c_char,
    query: *const c_char,
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

    let mut cb = |result: crate::core::search_engine::SearchResult| {
        let result_c = FFSearchResult {
            path: rust_string_to_c(result.path),
            name: rust_string_to_c(result.name),
            size: result.size,
            modified: result.modified,
            is_dir: result.is_dir,
        };
        callback(&result_c, user_data);
        if !result_c.path.is_null() {
            unsafe { let _ = CString::from_raw(result_c.path); }
        }
        if !result_c.name.is_null() {
            unsafe { let _ = CString::from_raw(result_c.name); }
        }
    };

    match crate::core::search_engine::search_files(path_str, query_str, &mut cb) {
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

    let rust_filters = if filters.is_null() {
        crate::core::search_engine::SearchFilters::default()
    } else {
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
    };

    let mut cb = |result: crate::core::search_engine::SearchResult| {
        let result_c = FFSearchResult {
            path: rust_string_to_c(result.path),
            name: rust_string_to_c(result.name),
            size: result.size,
            modified: result.modified,
            is_dir: result.is_dir,
        };
        callback(&result_c, user_data);
        if !result_c.path.is_null() {
            unsafe { let _ = CString::from_raw(result_c.path); }
        }
        if !result_c.name.is_null() {
            unsafe { let _ = CString::from_raw(result_c.name); }
        }
    };

    match crate::core::search_engine::search_with_filters(path_str, query_str, &rust_filters, &mut cb) {
        Ok(_) => {
            clear_last_error();
            FF_OK
        }
        Err(e) => {
            let msg = format!("search_with_filters failed: {}", e);
            set_last_error(msg);
            FF_ERR_IO
        }
    }
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
    let path_c = rust_string_to_c(path_str.to_string());
    callback(path_c, user_data);
    if !path_c.is_null() {
        unsafe { let _ = CString::from_raw(path_c); }
    }

    clear_last_error();
    FF_OK
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
}

// ── Directory Cache ─────────────────────────────────────────────────

/// Invalidate the directory cache for a specific path.
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
    clear_last_error();
    FF_OK
}

/// Get cached directory entries for a path.
///
/// If the path is not in cache or the entry is stale, the callback
/// is not called and `FF_ERR_NOT_FOUND` is returned.
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

    match crate::core::dir_cache::get(path_str) {
        Some(entries) => {
            for skeleton in entries {
                let name_c = rust_string_to_c(skeleton.name.clone());
                let path_c = rust_string_to_c(skeleton.path.clone());
                let ext_c = rust_string_to_c(skeleton.extension.clone());

                let ff_entry = FFEntryRef {
                    name: name_c,
                    path: path_c,
                    extension: ext_c,
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

                if !name_c.is_null() {
                    unsafe { let _ = CString::from_raw(name_c); }
                }
                if !path_c.is_null() {
                    unsafe { let _ = CString::from_raw(path_c); }
                }
                if !ext_c.is_null() {
                    unsafe { let _ = CString::from_raw(ext_c); }
                }
            }
            clear_last_error();
            FF_OK
        }
        None => {
            set_last_error("path not found in cache".to_string());
            FF_ERR_NOT_FOUND
        }
    }
}

/// Store directory entries in the cache.
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
#[no_mangle]
pub extern "C" fn ff_cache_put(
    path: *const c_char,
    entries: *const FFEntryRef,
    entry_count: usize,
) -> c_int {
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

    crate::core::dir_cache::put(path_str.to_string(), skeletons);
    clear_last_error();
    FF_OK
}

// ── Tests ───────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rust_string_to_c_roundtrip() {
        let original = "hello world".to_string();
        let c_ptr = rust_string_to_c(original.clone());
        assert!(!c_ptr.is_null());
        unsafe {
            let cstr = CStr::from_ptr(c_ptr);
            assert_eq!(cstr.to_str().unwrap(), "hello world");
            let _ = CString::from_raw(c_ptr);
        }
    }

    #[test]
    fn test_ff_free_string_null() {
        // Should not panic.
        ff_free_string(ptr::null_mut());
    }

    #[test]
    fn test_ff_version_string() {
        let ptr = ff_version_string();
        assert!(!ptr.is_null());
        unsafe {
            let cstr = CStr::from_ptr(ptr);
            assert!(!cstr.to_str().unwrap().is_empty());
            let _ = CString::from_raw(ptr);
        }
    }

    #[test]
    fn test_ff_get_file_type() {
        let path = CString::new("/test/document.pdf").unwrap();
        let ptr = ff_get_file_type(path.as_ptr());
        assert!(!ptr.is_null());
        unsafe {
            let cstr = CStr::from_ptr(ptr);
            assert_eq!(cstr.to_str().unwrap(), "pdf");
            let _ = CString::from_raw(ptr);
        }
    }

    #[test]
    fn test_ff_get_file_type_no_extension() {
        let path = CString::new("/test/README").unwrap();
        let ptr = ff_get_file_type(path.as_ptr());
        assert!(!ptr.is_null());
        unsafe {
            let cstr = CStr::from_ptr(ptr);
            assert_eq!(cstr.to_str().unwrap(), "");
            let _ = CString::from_raw(ptr);
        }
    }

    #[test]
    fn test_ff_get_file_type_null() {
        let ptr = ff_get_file_type(ptr::null());
        assert!(ptr.is_null());
    }

    #[test]
    fn test_ff_cache_invalidate() {
        let path = CString::new("/tmp/test_cache").unwrap();
        let result = ff_cache_invalidate(path.as_ptr());
        assert_eq!(result, FF_OK);
    }

    #[test]
    fn test_ff_cache_invalidate_null() {
        let result = ff_cache_invalidate(ptr::null());
        assert_eq!(result, FF_ERR_INVALID_PATH);
    }

    #[test]
    fn test_ff_cache_get_miss() {
        let path = CString::new("/nonexistent/path/xyz123").unwrap();
        let result = ff_cache_get(path.as_ptr(), dummy_callback, ptr::null_mut());
        assert_eq!(result, FF_ERR_NOT_FOUND);
    }

    extern "C" fn dummy_callback(_entry: *const FFEntryRef, _user_data: *mut c_void) {}
}
