//! Plain file-name validation for batch rename operations.
//!
//! [`path_guard`](crate::core::path_guard::path_guard) validates *absolute
//! paths* handed to mutating command handlers. It is deliberately unusable for
//! a *file name* component such as `RenameItem::new_name` — a bare name is
//! relative by nature, so `path_guard` would reject every legal rename.
//!
//! [`validate_filename`] fills that gap: it checks that a value is exactly one
//! bare file name — no separators, no traversal components, no absolute
//! prefixes, no control characters — so that `parent.join(name)` can never
//! escape `parent` or address a different file than the caller intended.
//! Valid Unicode file names (including CJK, emoji, spaces and extension
//! dots) pass unchanged.

use std::path::{Component, Path};

/// Validate a value as a single file name (not a path).
///
/// Accepts exactly one `Normal` component: a bare name with no `/` or `\`
/// separators, no `.`/`..`/absolute components, and no control characters.
///
/// # Errors
///
/// Returns a human-readable message for:
/// - the empty string
/// - `.` and `..` (and any name carrying a `ParentDir`/`CurDir` component)
/// - names containing a path separator (`/` or `\`) — which make it an
///   absolute path, a parent reference, or a nested path
/// - names containing control characters
pub fn validate_filename(name: &str) -> Result<(), String> {
    if name.is_empty() {
        return Err("file name must not be empty".into());
    }
    // On Unix `\` is an ordinary file-name character, but we treat it as a
    // separator so a name crafted on another platform cannot smuggle one.
    if name.contains('\\') {
        return Err("file name must not contain '\\'".into());
    }
    // Exactly one Normal component. This rejects `a/b`, `/abs`, `.`, `..`,
    // and any name where a component is `CurDir`/`ParentDir`/`RootDir`.
    let mut components = Path::new(name).components();
    match (components.next(), components.next()) {
        (Some(Component::Normal(_)), None) => {}
        _ => {
            return Err(
                "file name must not contain path separators or traversal components".into(),
            );
        }
    }
    if name.chars().any(char::is_control) {
        return Err("file name must not contain control characters".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_empty_name() {
        assert!(validate_filename("").is_err());
    }

    #[test]
    fn rejects_current_and_parent_dir() {
        assert!(validate_filename(".").is_err());
        assert!(validate_filename("..").is_err());
        assert!(validate_filename("../").is_err());
    }

    #[test]
    fn rejects_path_separators() {
        assert!(validate_filename("a/b").is_err());
        assert!(validate_filename("a\\b").is_err());
        assert!(validate_filename("/abs").is_err());
        assert!(validate_filename("dir/name.txt").is_err());
    }

    #[test]
    fn rejects_control_characters() {
        assert!(validate_filename("a\u{0000}b").is_err());
        assert!(validate_filename("a\nb.txt").is_err());
        assert!(validate_filename("\u{0001}").is_err());
    }

    #[test]
    fn accepts_normal_unicode_names() {
        // CJK, emoji and spaces are all legal on macOS.
        assert!(validate_filename("照片 2024 🚀.txt").is_ok());
        assert!(validate_filename("报告.docx").is_ok());
        assert!(validate_filename("report final v2.txt").is_ok());
    }

    #[test]
    fn accepts_names_with_extension() {
        assert!(validate_filename("report.v1.2.txt").is_ok());
        assert!(validate_filename("archive.tar.gz").is_ok());
        assert!(validate_filename("noext").is_ok());
    }

    #[test]
    fn accepts_dotfiles() {
        assert!(validate_filename(".hidden").is_ok());
        assert!(validate_filename(".gitignore").is_ok());
    }
}
