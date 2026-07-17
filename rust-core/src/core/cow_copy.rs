//! Copy-on-Write file copy via macOS `clonefile(2)`.
//!
//! On APFS, `clonefile()` creates a new file that shares all of its data
//! extents with the source file — the copy is effectively instantaneous and
//! consumes no extra space until one of the two files is modified
//! (Copy-on-Write).  This module wraps the syscall and transparently falls
//! back to `std::fs::copy` whenever CoW is not available:
//!
//! - different volumes (`EXDEV`)
//! - filesystem without clonefile support (`ENOTSUP` / `EOPNOTSUPP`)
//! - non-APFS / unsupported filesystems (reported as `ENOTSUP` by clonefile
//!   and handled via the `std::fs::copy` fallback, not an up-front `statfs`
//!   check)
//!
//! `clonefile()` is part of libSystem on macOS 10.12+ and is linked directly
//! via an `extern "C"` block — no extra build flags are required.

use std::io;
use std::path::Path;

// errno values we react to.  These are the raw `errno` numbers as documented
// in `errno(3)` on macOS — we compare against `io::Error::raw_os_error()`
// rather than the `libc::EXDEV` constants because the latter are not all
// exported on every target and the numeric values are stable ABI.
//
// - `EXDEV`        (18)  : cross-device link — the two paths live on
//                          different volumes, clonefile cannot work.
// - `ENOTSUP`      (102) : operation not supported — the filesystem does not
//                          implement clonefile (e.g. HFS+, SMB, NFS).
// - `EOPNOTSUPP`   (102) : same numeric value as ENOTSUP on macOS; kept for
//                          documentation.
#[cfg(target_os = "macos")]
const EXDEV: i32 = 18;
#[cfg(target_os = "macos")]
const ENOTSUP: i32 = 102;

#[cfg(target_os = "macos")]
mod native {
    use std::ffi::CString;
    use std::os::raw::c_char;
    use std::os::unix::ffi::OsStrExt;
    use std::os::unix::fs::MetadataExt;
    use std::path::Path;
    use std::io;

    extern "C" {
        /// `clonefile(src, dst, flags)` — create a Copy-on-Write clone of `src`
        /// at path `dst`.  Returns 0 on success, -1 on error (errno set).
        ///
        /// Declared in `<sys/clonefile.h>` and exported by libSystem.
        pub fn clonefile(src: *const c_char, dst: *const c_char, flags: u32) -> std::os::raw::c_int;
    }

    /// Return the device id (`st_dev`) of the file at `path`.
    pub fn get_device_id(path: &Path) -> io::Result<u64> {
        let metadata = std::fs::metadata(path)?;
        Ok(metadata.dev())
    }

    /// Attempt a CoW clone via `clonefile()`. Returns the bytes copied on
    /// success, or an `io::Error` (which may carry `EXDEV`/`ENOTSUP` so the
    /// caller can fall back).
    pub fn try_clonefile(src: &Path, dst: &Path) -> io::Result<u64> {
        let src_c = CString::new(src.as_os_str().as_bytes())
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
        let dst_c = CString::new(dst.as_os_str().as_bytes())
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;

        // Safety: both pointers are valid NUL-terminated C strings backed by
        // the owning `CString`s which outlive the call.  `flags == 0` means
        // "no special behaviour".
        let ret = unsafe { clonefile(src_c.as_ptr(), dst_c.as_ptr(), 0) };

        if ret == 0 {
            let metadata = std::fs::metadata(dst)?;
            Ok(metadata.len())
        } else {
            Err(io::Error::last_os_error())
        }
    }
}

/// Copy a file, using `clonefile()` on same-volume APFS, `std::fs::copy`
/// otherwise.
///
/// The decision tree is:
///
/// 1. Stat both paths and compare `st_dev`.  If they differ, skip straight to
///    `std::fs::copy` (clonefile would return `EXDEV` anyway).
/// 2. On the same volume, call `clonefile()`.
/// 3. If `clonefile()` fails with `EXDEV` or `ENOTSUP`, fall back to
///    `std::fs::copy` so that callers always get a usable copy.
/// 4. Any other error (`EEXIST`, `EACCES`, `ENOSPC`, …) is returned as-is.
///
/// On success returns the number of bytes "copied" (the file size reported by
/// the destination metadata — for a CoW clone this is the logical size, not
/// the zero physical bytes that were actually written).
pub fn copy_file_cow(src: &Path, dst: &Path) -> io::Result<u64> {
    // Handle directories recursively — clonefile can clone an empty directory
    // but not a populated one, and std::fs::copy does not work on directories.
    let src_meta = std::fs::metadata(src)?;
    if src_meta.is_dir() {
        return copy_dir_recursive(src, dst);
    }

    #[cfg(target_os = "macos")]
    {
        // Determine device IDs up-front so we can short-circuit the
        // cross-volume case without even invoking clonefile().  `metadata()`
        // follows symlinks, which is the behaviour we want for the source.
        let src_dev = native::get_device_id(src)?;

        // The destination may not exist yet.  Try the path itself first; if
        // that fails, fall back to its parent directory so we still get a
        // meaningful device comparison.
        let dst_dev = match native::get_device_id(dst) {
            Ok(dev) => dev,
            Err(_) => {
                let parent = dst.parent().ok_or_else(|| {
                    io::Error::new(io::ErrorKind::InvalidInput, "destination has no parent")
                })?;
                native::get_device_id(parent)?
            }
        };

        if src_dev == dst_dev {
            // Same volume — attempt a CoW clone.
            match native::try_clonefile(src, dst) {
                Ok(bytes) => return Ok(bytes),
                Err(err) => {
                    let errno = err.raw_os_error().unwrap_or(0);
                    // EXDEV / ENOTSUP → the filesystem cannot honour
                    // clonefile, so fall back to a plain byte-for-byte copy.
                    // Everything else is a real error and is surfaced.
                    if errno == EXDEV || errno == ENOTSUP {
                        return std::fs::copy(src, dst);
                    }
                    return Err(err);
                }
            }
        }
    }

    // Different volumes (or non-macOS) — clonefile is impossible, use
    // standard copy.
    std::fs::copy(src, dst)
}

/// Recursively copy a directory tree.
///
/// Creates the destination directory and copies all contents recursively,
/// using `copy_file_cow` for each entry so that individual files still
/// benefit from CoW cloning on APFS.
fn copy_dir_recursive(src: &Path, dst: &Path) -> io::Result<u64> {
    std::fs::create_dir_all(dst)?;

    let mut total_bytes: u64 = 0;

    for entry in std::fs::read_dir(src)? {
        let entry = entry?;
        let src_path = entry.path();
        let file_name = entry.file_name();
        let dst_path = dst.join(&file_name);

        let file_type = entry.file_type()?;
        if file_type.is_dir() {
            total_bytes += copy_dir_recursive(&src_path, &dst_path)?;
        } else if file_type.is_symlink() {
            let target = std::fs::read_link(&src_path)?;
            std::os::unix::fs::symlink(&target, &dst_path)?;
        } else {
            total_bytes += copy_file_cow(&src_path, &dst_path)?;
        }
    }

    Ok(total_bytes)
}

/// Remove a path, whether it is a file or directory.
///
/// Used by `task_submit_move` for the cross-volume copy+delete path:
/// `std::fs::remove_file` fails on directories, so this helper picks
/// the right removal function based on the file type.
pub fn remove_path(path: &Path) -> io::Result<()> {
    let meta = std::fs::symlink_metadata(path)?;
    if meta.is_dir() {
        std::fs::remove_dir_all(path)
    } else {
        std::fs::remove_file(path)
    }
}
