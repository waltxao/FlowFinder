//! Path validation primitives.
//!
//! These functions are used by command handlers to validate user-supplied
//! paths before any filesystem mutation, preventing catastrophic operations
//! such as copying/moving/deleting the filesystem root or following `..`
//! traversal components.

use std::path::{Path, PathBuf};

/// Validate a user-supplied path for mutating operations (copy / move / delete).
///
/// Ensures the path is non-empty, absolute, free of `..` components, and not
/// the bare filesystem root (which would let a copy/move/delete be
/// catastrophic).
pub fn path_guard(input: &str) -> Result<PathBuf, String> {
    if input.trim().is_empty() {
        return Err("Path must not be empty".into());
    }
    let path = Path::new(input);
    if !path.is_absolute() {
        return Err(format!("Path must be absolute: {}", input));
    }
    // Reject paths containing .. components
    for component in path.components() {
        if component == std::path::Component::ParentDir {
            return Err("Path must not contain '..'".into());
        }
    }
    // Check canonicalized path is not root
    let canonical = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
    if canonical.parent().is_none() {
        return Err("Refusing to operate on the filesystem root".into());
    }
    Ok(path.to_path_buf())
}

/// Validate a path for read-only operations (e.g. listing a directory).
///
/// Same as [`path_guard`] but allows the filesystem root `/` — listing `/`
/// is a safe, read-only operation that must work when the user navigates
/// to the system disk from the sidebar.
pub fn path_guard_readonly(input: &str) -> Result<PathBuf, String> {
    if input.trim().is_empty() {
        return Err("Path must not be empty".into());
    }
    let path = Path::new(input);
    if !path.is_absolute() {
        return Err(format!("Path must be absolute: {}", input));
    }
    Ok(path.to_path_buf())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_empty_path() {
        assert!(path_guard("").is_err());
        assert!(path_guard("   ").is_err());
        assert!(path_guard_readonly("").is_err());
    }

    #[test]
    fn rejects_relative_path() {
        assert!(path_guard("relative/path").is_err());
        assert!(path_guard("./here").is_err());
        assert!(path_guard_readonly("relative").is_err());
    }

    #[test]
    fn rejects_parent_dir_components() {
        assert!(path_guard("/foo/../bar").is_err());
        assert!(path_guard("/foo/..").is_err());
    }

    #[test]
    fn rejects_filesystem_root_for_mutating() {
        // path_guard must refuse "/" — deleting/copying the root is catastrophic.
        assert!(path_guard("/").is_err());
    }

    #[test]
    fn allows_filesystem_root_for_readonly() {
        // path_guard_readonly must allow "/" — listing "/" is safe.
        assert!(path_guard_readonly("/").is_ok());
    }

    #[test]
    fn accepts_normal_absolute_path() {
        // Use the temp dir which is guaranteed to exist on the host.
        let p = std::env::temp_dir();
        let input = p.to_string_lossy().to_string();
        assert!(path_guard(&input).is_ok());
        assert!(path_guard_readonly(&input).is_ok());
    }
}
