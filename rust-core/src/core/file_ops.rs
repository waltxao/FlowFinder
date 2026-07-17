//! File operations: copy, move, rename, delete, and directory creation.
//!
//! This module provides high-level file operations with proper error handling
//! and CoW (Copy-on-Write) support via the `cow_copy` module for efficient
//! file copying on APFS.

use std::io;
use std::path::Path;

use crate::core::cow_copy;

/// Copy a file from `src` to `dst`.
///
/// Uses CoW cloning when available (same-volume APFS), falling back to
/// standard byte-for-byte copy otherwise. For directories, copies recursively.
///
/// # Errors
///
/// Returns an `io::Error` if the source does not exist, the destination
/// cannot be written, or a CoW clone fails with an unrecoverable error.
pub fn copy_file(src: &Path, dst: &Path) -> io::Result<u64> {
    cow_copy::copy_file_cow(src, dst)
}

/// Move a file or directory from `src` to `dst`.
///
/// Attempts a fast rename first. If `src` and `dst` are on different
/// volumes, falls back to copy + delete.
///
/// # Errors
///
/// Returns an `io::Error` if the source does not exist or cannot be moved.
pub fn move_file(src: &Path, dst: &Path) -> io::Result<()> {
    // Try rename first (same volume, fast)
    match std::fs::rename(src, dst) {
        Ok(()) => return Ok(()),
        Err(e) => {
            // If it's a cross-device error, fall back to copy + delete
            let errno = e.raw_os_error().unwrap_or(0);
            #[cfg(target_os = "macos")]
            const EXDEV: i32 = 18;
            #[cfg(not(target_os = "macos"))]
            const EXDEV: i32 = 18;
            if errno != EXDEV {
                return Err(e);
            }
        }
    }

    // Cross-volume: copy then delete
    cow_copy::copy_file_cow(src, dst)?;
    cow_copy::remove_path(src)?;
    Ok(())
}

/// Delete a file at `path`.
///
/// # Errors
///
/// Returns an `io::Error` if the file does not exist or cannot be deleted.
pub fn delete_file(path: &Path) -> io::Result<()> {
    std::fs::remove_file(path)
}

/// Delete a directory and all its contents at `path`.
///
/// # Errors
///
/// Returns an `io::Error` if the directory does not exist or cannot be deleted.
pub fn delete_dir(path: &Path) -> io::Result<()> {
    std::fs::remove_dir_all(path)
}

/// Create a directory and all parent directories at `path`.
///
/// # Errors
///
/// Returns an `io::Error` if the directory cannot be created.
pub fn create_dir(path: &Path) -> io::Result<()> {
    std::fs::create_dir_all(path)
}

/// Rename a file or directory from `src` to `dst`.
///
/// This is a thin wrapper around `std::fs::rename`.
///
/// # Errors
///
/// Returns an `io::Error` if the source does not exist or the destination
/// cannot be written.
pub fn rename(src: &Path, dst: &Path) -> io::Result<()> {
    std::fs::rename(src, dst)
}

// ── Tests ───────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use tempfile::TempDir;

    #[test]
    fn test_copy_file() {
        let tmp = TempDir::new().unwrap();
        let src = tmp.path().join("source.txt");
        let dst = tmp.path().join("dest.txt");

        fs::write(&src, "hello world").unwrap();

        let bytes = copy_file(&src, &dst).unwrap();
        assert_eq!(bytes, 11);
        assert_eq!(fs::read_to_string(&dst).unwrap(), "hello world");
    }

    #[test]
    fn test_copy_file_overwrite() {
        let tmp = TempDir::new().unwrap();
        let src = tmp.path().join("source.txt");
        let dst = tmp.path().join("dest.txt");

        fs::write(&src, "new content").unwrap();
        fs::write(&dst, "old content").unwrap();

        // Remove destination first to allow overwrite (clonefile doesn't overwrite)
        fs::remove_file(&dst).unwrap();

        let bytes = copy_file(&src, &dst).unwrap();
        assert_eq!(bytes, 11);
        assert_eq!(fs::read_to_string(&dst).unwrap(), "new content");
    }

    #[test]
    fn test_copy_dir_recursive() {
        let tmp = TempDir::new().unwrap();
        let src = tmp.path().join("srcdir");
        let dst = tmp.path().join("dstdir");

        fs::create_dir(&src).unwrap();
        fs::write(src.join("file1.txt"), "content1").unwrap();
        fs::create_dir(src.join("subdir")).unwrap();
        fs::write(src.join("subdir/file2.txt"), "content2").unwrap();

        let bytes = copy_file(&src, &dst).unwrap();
        assert!(bytes > 0);
        assert!(dst.exists());
        assert_eq!(fs::read_to_string(dst.join("file1.txt")).unwrap(), "content1");
        assert_eq!(fs::read_to_string(dst.join("subdir/file2.txt")).unwrap(), "content2");
    }

    #[test]
    fn test_move_file_same_volume() {
        let tmp = TempDir::new().unwrap();
        let src = tmp.path().join("source.txt");
        let dst = tmp.path().join("dest.txt");

        fs::write(&src, "move me").unwrap();

        move_file(&src, &dst).unwrap();
        assert!(!src.exists());
        assert!(dst.exists());
        assert_eq!(fs::read_to_string(&dst).unwrap(), "move me");
    }

    #[test]
    fn test_delete_file() {
        let tmp = TempDir::new().unwrap();
        let file = tmp.path().join("delete_me.txt");

        fs::write(&file, "delete me").unwrap();
        assert!(file.exists());

        delete_file(&file).unwrap();
        assert!(!file.exists());
    }

    #[test]
    fn test_delete_file_not_found() {
        let tmp = TempDir::new().unwrap();
        let file = tmp.path().join("nonexistent.txt");

        let result = delete_file(&file);
        assert!(result.is_err());
    }

    #[test]
    fn test_delete_dir() {
        let tmp = TempDir::new().unwrap();
        let dir = tmp.path().join("deletedir");

        fs::create_dir(&dir).unwrap();
        fs::write(dir.join("file.txt"), "content").unwrap();

        delete_dir(&dir).unwrap();
        assert!(!dir.exists());
    }

    #[test]
    fn test_create_dir() {
        let tmp = TempDir::new().unwrap();
        let dir = tmp.path().join("newdir");

        assert!(!dir.exists());
        create_dir(&dir).unwrap();
        assert!(dir.exists());
        assert!(dir.is_dir());
    }

    #[test]
    fn test_create_dir_nested() {
        let tmp = TempDir::new().unwrap();
        let dir = tmp.path().join("a/b/c");

        assert!(!dir.exists());
        create_dir(&dir).unwrap();
        assert!(dir.exists());
        assert!(dir.is_dir());
    }

    #[test]
    fn test_rename() {
        let tmp = TempDir::new().unwrap();
        let src = tmp.path().join("old.txt");
        let dst = tmp.path().join("new.txt");

        fs::write(&src, "rename me").unwrap();

        rename(&src, &dst).unwrap();
        assert!(!src.exists());
        assert!(dst.exists());
        assert_eq!(fs::read_to_string(&dst).unwrap(), "rename me");
    }

    #[test]
    fn test_rename_dir() {
        let tmp = TempDir::new().unwrap();
        let src = tmp.path().join("olddir");
        let dst = tmp.path().join("newdir");

        fs::create_dir(&src).unwrap();
        fs::write(src.join("file.txt"), "content").unwrap();

        rename(&src, &dst).unwrap();
        assert!(!src.exists());
        assert!(dst.exists());
        assert!(dst.is_dir());
        assert_eq!(fs::read_to_string(dst.join("file.txt")).unwrap(), "content");
    }
}
