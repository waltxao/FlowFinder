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
}
