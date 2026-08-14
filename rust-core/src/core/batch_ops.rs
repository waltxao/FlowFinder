//! Batch rename and file organization operations.
//!
//! Provides:
//! - Batch rename with pattern substitution (e.g., {name}_{index}.{ext})
//! - Organize files by date (YYYY/MM/DD)
//! - Organize files by file type (Images/, Documents/, etc.)

use std::collections::HashSet;
use std::io;
use std::path::{Path, PathBuf};
use chrono::Datelike;

use crate::core::safe_filename::validate_filename;

/// A single rename operation.
#[derive(Debug, Clone)]
pub struct RenameItem {
    pub original_path: String,
    pub new_name: String,
}

/// Progress callback for batch operations.
pub type BatchProgressCallback = fn(completed: usize, total: usize, current_file: &str);

/// Parse a rename pattern and generate new names.
///
/// Supported placeholders:
/// - `{name}` — original filename without extension
/// - `{ext}` — original extension
/// - `{date}` — current date in YYYY-MM-DD format
/// - `{index}` — 1-based index
/// - `{index0}` — 0-based index
/// - `{index:3}` — zero-padded index (e.g., 001)
///
/// # Examples
///
/// ```
/// pattern = "{name}_{index}.{ext}"
/// files = ["a.txt", "b.txt"]
/// result = ["a_1.txt", "b_2.txt"]
/// ```
pub fn parse_rename_pattern(
    files: &[String],
    pattern: &str,
) -> io::Result<Vec<RenameItem>> {
    let mut items = Vec::with_capacity(files.len());
    let current_date = chrono::Local::now().format("%Y-%m-%d").to_string();

    for (i, file) in files.iter().enumerate() {
        let path = Path::new(file);
        let stem = path
            .file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_default();
        let ext = path
            .extension()
            .map(|e| e.to_string_lossy().to_string())
            .unwrap_or_default();

        let mut new_name = pattern.to_string();

        // Replace {index} with 1-based index
        new_name = new_name.replace("{index}", &(i + 1).to_string());
        // Replace {index0} with 0-based index
        new_name = new_name.replace("{index0}", &i.to_string());
        // Replace {date} with current date
        new_name = new_name.replace("{date}", &current_date);

        // Simple placeholder replacement
        new_name = new_name.replace("{name}", &stem);
        new_name = new_name.replace("{ext}", &ext);

        // Handle {index:N} with simple string replacement
        if let Some(start) = new_name.find("{index:") {
            if let Some(end) = new_name[start..].find('}') {
                let full_end = start + end + 1;
                let width_str = &new_name[start + 7..full_end - 1];
                if let Ok(width) = width_str.parse::<usize>() {
                    let padded = format!("{:0width$}", i + 1, width = width);
                    new_name.replace_range(start..full_end, &padded);
                }
            }
        }

        items.push(RenameItem {
            original_path: file.clone(),
            new_name,
        });
    }

    Ok(items)
}

/// Execute batch rename operations.
///
/// Returns the number of successful renames.
///
/// # Safety contract
///
/// Every `new_name` is validated as a single bare file name (see
/// [`validate_filename`]) and every target is pre-flighted before any rename
/// runs. An invalid name (empty, separators, traversal, control characters)
/// rejects the batch with [`io::ErrorKind::InvalidInput`]; an occupied or
/// duplicated target rejects it with [`io::ErrorKind::AlreadyExists`]. In
/// both cases **no file is renamed and no existing file is overwritten**.
/// For a batch that passes validation the returned count equals the number
/// of files actually renamed (per-file I/O failures are logged and skipped).
pub fn batch_rename(
    items: &[RenameItem],
    progress: Option<BatchProgressCallback>,
) -> io::Result<usize> {
    // Phase 1 — validate every name and target up front so a bad item rejects
    // the whole batch before any file is touched.
    let mut plans = Vec::with_capacity(items.len());
    let mut claimed: HashSet<PathBuf> = HashSet::new();
    for item in items {
        if let Err(msg) = validate_filename(&item.new_name) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("new_name {:?} is not a valid file name: {}", item.new_name, msg),
            ));
        }
        let parent = Path::new(&item.original_path)
            .parent()
            .unwrap_or(Path::new(""));
        let new_path = parent.join(&item.new_name);
        // Renaming a file onto its own current name is a no-op on the target
        // OS and must stay allowed.
        if new_path != Path::new(&item.original_path) {
            if new_path.exists() {
                return Err(io::Error::new(
                    io::ErrorKind::AlreadyExists,
                    format!("target already exists: {}", new_path.display()),
                ));
            }
            if !claimed.insert(new_path.clone()) {
                return Err(io::Error::new(
                    io::ErrorKind::AlreadyExists,
                    format!("duplicate target within batch: {}", new_path.display()),
                ));
            }
        }
        plans.push(new_path);
    }

    // Phase 2 — execute; all names are legal and all targets are free, so a
    // rename can only fail on a genuine I/O condition.
    let total = items.len();
    let mut succeeded = 0usize;

    for (i, item) in items.iter().enumerate() {
        let new_path = &plans[i];

        match std::fs::rename(&item.original_path, new_path) {
            Ok(()) => {
                succeeded += 1;
            }
            Err(e) => {
                // P2-19 修复：使用 log::error! 替代 eprintln!，集成日志框架
                log::error!(
                    "rename {} -> {} failed: {}",
                    item.original_path,
                    new_path.display(),
                    e
                );
            }
        }

        if let Some(cb) = progress {
            cb(i + 1, total, &item.new_name);
        }
    }

    Ok(succeeded)
}

/// Get the file type category for organization.
fn file_type_category(ext: &str) -> &'static str {
    let ext_lower = ext.to_lowercase();
    match ext_lower.as_str() {
        "jpg" | "jpeg" | "png" | "gif" | "bmp" | "tiff" | "tif" | "webp" | "heic" | "svg"
            => "Images",
        "pdf" | "doc" | "docx" | "txt" | "md" | "rtf" | "odt" | "pages"
            => "Documents",
        "xls" | "xlsx" | "csv" | "ods" | "numbers"
            => "Spreadsheets",
        "ppt" | "pptx" | "odp" | "key"
            => "Presentations",
        "mp3" | "aac" | "wav" | "flac" | "m4a" | "ogg"
            => "Audio",
        "mp4" | "mov" | "avi" | "mkv" | "wmv" | "flv" | "m4v"
            => "Videos",
        "zip" | "rar" | "7z" | "tar" | "gz" | "bz2"
            => "Archives",
        "app" | "exe" | "dmg" | "pkg"
            => "Applications",
        _ => "Other",
    }
}

/// Organize files by modification date into YYYY/MM/DD folders.
///
/// `format` can be:
/// - `"YYYY/MM/DD"` — year/month/day hierarchy
/// - `"YYYY/MM"` — year/month hierarchy
/// - `"YYYY"` — year only
///
/// Returns the number of files moved.
pub fn organize_by_date(
    path: &str,
    format: &str,
    progress: Option<BatchProgressCallback>,
) -> io::Result<usize> {
    let dir = Path::new(path);
    let mut entries = Vec::new();

    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let meta = entry.metadata()?;
        if meta.is_file() {
            entries.push((entry.path(), meta));
        }
    }

    let total = entries.len();
    let mut moved = 0usize;

    for (i, (file_path, meta)) in entries.iter().enumerate() {
        let modified = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        let dt = chrono::DateTime::from_timestamp(modified, 0)
            .unwrap_or_else(|| chrono::DateTime::UNIX_EPOCH);

        let subdir = match format {
            "YYYY/MM/DD" => format!("{:04}/{:02}/{:02}", dt.year(), dt.month(), dt.day()),
            "YYYY/MM" => format!("{:04}/{:02}", dt.year(), dt.month()),
            "YYYY" => format!("{:04}", dt.year()),
            _ => format!("{:04}/{:02}/{:02}", dt.year(), dt.month(), dt.day()),
        };

        let target_dir = dir.join(&subdir);
        std::fs::create_dir_all(&target_dir)?;

        let file_name = file_path.file_name().unwrap_or_default();
        let target_path = target_dir.join(file_name);

        // Conflict protection: never overwrite an existing file in the target
        // subdirectory — skip it and report via the log instead.
        if target_path.exists() {
            log::error!(
                "move {} -> {} skipped: target already exists",
                file_path.display(),
                target_path.display()
            );
            if let Some(cb) = progress {
                cb(i + 1, total, &file_name.to_string_lossy());
            }
            continue;
        }

        match std::fs::rename(&file_path, &target_path) {
            Ok(()) => {
                moved += 1;
            }
            Err(e) => {
                // P2-19 修复：使用 log::error! 替代 eprintln!，集成日志框架
                log::error!("move {} -> {} failed: {}", file_path.display(), target_path.display(), e);
            }
        }

        if let Some(cb) = progress {
            cb(i + 1, total, &file_name.to_string_lossy());
        }
    }

    Ok(moved)
}

/// Organize files by file type into category folders.
///
/// Categories: Images, Documents, Spreadsheets, Presentations, Audio,
/// Videos, Archives, Applications, Other.
///
/// Returns the number of files moved.
pub fn organize_by_type(
    path: &str,
    progress: Option<BatchProgressCallback>,
) -> io::Result<usize> {
    let dir = Path::new(path);
    let mut entries = Vec::new();

    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let meta = entry.metadata()?;
        if meta.is_file() {
            entries.push((entry.path(), meta));
        }
    }

    let total = entries.len();
    let mut moved = 0usize;

    for (i, (file_path, _meta)) in entries.iter().enumerate() {
        let ext = file_path
            .extension()
            .map(|e| e.to_string_lossy().to_string())
            .unwrap_or_default();
        let category = file_type_category(&ext);

        let target_dir = dir.join(category);
        std::fs::create_dir_all(&target_dir)?;

        let file_name = file_path.file_name().unwrap_or_default();
        let target_path = target_dir.join(file_name);

        // Conflict protection: never overwrite an existing file in the target
        // subdirectory — skip it and report via the log instead.
        if target_path.exists() {
            log::error!(
                "move {} -> {} skipped: target already exists",
                file_path.display(),
                target_path.display()
            );
            if let Some(cb) = progress {
                cb(i + 1, total, &file_name.to_string_lossy());
            }
            continue;
        }

        match std::fs::rename(&file_path, &target_path) {
            Ok(()) => {
                moved += 1;
            }
            Err(e) => {
                // P2-19 修复：使用 log::error! 替代 eprintln!，集成日志框架
                log::error!("move {} -> {} failed: {}", file_path.display(), target_path.display(), e);
            }
        }

        if let Some(cb) = progress {
            cb(i + 1, total, &file_name.to_string_lossy());
        }
    }

    Ok(moved)
}

// ── Tests ───────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    #[test]
    fn test_parse_rename_pattern_basic() {
        let files = vec![
            "/tmp/test/file1.txt".to_string(),
            "/tmp/test/file2.txt".to_string(),
        ];
        let items = parse_rename_pattern(&files, "{name}_{index}.{ext}").unwrap();

        assert_eq!(items[0].new_name, "file1_1.txt");
        assert_eq!(items[1].new_name, "file2_2.txt");
    }

    #[test]
    fn test_parse_rename_pattern_zero_index() {
        let files = vec!["a.txt".to_string()];
        let items = parse_rename_pattern(&files, "{name}_{index0}.{ext}").unwrap();

        assert_eq!(items[0].new_name, "a_0.txt");
    }

    #[test]
    fn test_parse_rename_pattern_padded_index() {
        let files = vec!["a.txt".to_string(), "b.txt".to_string()];
        let items = parse_rename_pattern(&files, "file_{index:3}.{ext}").unwrap();

        assert_eq!(items[0].new_name, "file_001.txt");
        assert_eq!(items[1].new_name, "file_002.txt");
    }

    #[test]
    fn test_file_type_category() {
        assert_eq!(file_type_category("jpg"), "Images");
        assert_eq!(file_type_category("pdf"), "Documents");
        assert_eq!(file_type_category("mp3"), "Audio");
        assert_eq!(file_type_category("mp4"), "Videos");
        assert_eq!(file_type_category("zip"), "Archives");
        assert_eq!(file_type_category("unknown"), "Other");
    }

    #[test]
    fn test_organize_by_type() {
        let tmp = TempDir::new().unwrap();
        fs::write(tmp.path().join("photo.jpg"), "fake image").unwrap();
        fs::write(tmp.path().join("doc.pdf"), "fake pdf").unwrap();
        fs::write(tmp.path().join("song.mp3"), "fake audio").unwrap();

        let moved = organize_by_type(&tmp.path().to_string_lossy(), None).unwrap();
        assert_eq!(moved, 3);

        assert!(tmp.path().join("Images/photo.jpg").exists());
        assert!(tmp.path().join("Documents/doc.pdf").exists());
        assert!(tmp.path().join("Audio/song.mp3").exists());
    }

    #[test]
    fn test_parse_rename_pattern_with_date() {
        let files = vec!["a.txt".to_string()];
        let items = parse_rename_pattern(&files, "{name}_{date}.{ext}").unwrap();

        let today = chrono::Local::now().format("%Y-%m-%d").to_string();
        assert_eq!(items[0].new_name, format!("a_{}.txt", today));
    }

    // ── Wave1 regression tests (v0.7.5 fix plan, red before the fix) ──
    //
    // `batch_rename` joins `parent.join(new_name)` without validating
    // `new_name`. These tests encode the CORRECT behavior (reject escapes,
    // refuse to overwrite) and fail on the current code.

    #[test]
    fn test_batch_rename_traversal_rejected() {
        let tmp = TempDir::new().unwrap();
        // Source lives one level down so "../escaped.txt" resolves *inside*
        // the TempDir — the test never writes outside its own sandbox.
        let sub = tmp.path().join("sub");
        fs::create_dir_all(&sub).unwrap();
        let src = sub.join("victim.txt");

        for (case, new_name) in [
            ("dotdot-escape", "../escaped.txt"),
            ("absolute-escape", "/ff_abs_escape_wave1.txt"),
            ("empty-name", ""),
        ] {
            fs::write(&src, "payload").unwrap();
            let items = vec![RenameItem {
                original_path: src.to_string_lossy().into_owned(),
                new_name: new_name.to_string(),
            }];
            // CORRECT: traversal / empty names are rejected.
            let result = batch_rename(&items, None);
            assert!(
                result.is_err(),
                "case {}: new_name {:?} must be rejected (path traversal), got {:?}",
                case, new_name, result
            );
            // CORRECT: the source file must remain in place.
            assert!(src.exists(), "case {}: source must not be moved by traversal", case);
        }
    }

    #[test]
    fn test_batch_rename_conflict_not_overwritten() {
        let tmp = TempDir::new().unwrap();
        let a = tmp.path().join("a.txt");
        let b = tmp.path().join("b.txt");
        fs::write(&a, "alpha-payload").unwrap();
        fs::write(&b, "beta-payload").unwrap();

        let items = vec![RenameItem {
            original_path: a.to_string_lossy().into_owned(),
            new_name: "b.txt".to_string(),
        }];
        // CORRECT: a rename onto an existing target must be refused.
        let result = batch_rename(&items, None);
        assert!(
            result.is_err(),
            "rename onto existing target must be rejected, got {:?}",
            result
        );
        // CORRECT: the existing target's content must be preserved.
        assert_eq!(
            fs::read_to_string(&b).unwrap(),
            "beta-payload",
            "existing target must not be silently overwritten"
        );
        // CORRECT: the source must not be consumed.
        assert!(a.exists(), "source must remain in place when rename is rejected");
    }

    // ── Wave1 T2 additions: validator-driven batch safety ─────────────

    #[test]
    fn test_batch_rename_valid_names_still_work() {
        let tmp = TempDir::new().unwrap();
        let a = tmp.path().join("a.txt");
        let b = tmp.path().join("b.txt");
        fs::write(&a, "alpha").unwrap();

        let items = vec![RenameItem {
            original_path: a.to_string_lossy().into_owned(),
            new_name: "b.txt".to_string(),
        }];
        let result = batch_rename(&items, None);
        assert_eq!(result.unwrap(), 1, "legal rename must succeed and count 1");
        assert!(b.exists(), "target must exist after legal rename");
        assert!(!a.exists(), "source must be consumed by legal rename");
    }

    #[test]
    fn test_batch_rename_unicode_names_work() {
        let tmp = TempDir::new().unwrap();
        let src = tmp.path().join("old.txt");
        fs::write(&src, "payload").unwrap();

        let items = vec![RenameItem {
            original_path: src.to_string_lossy().into_owned(),
            new_name: "照片 2024 🚀.txt".to_string(),
        }];
        let result = batch_rename(&items, None);
        assert_eq!(result.unwrap(), 1, "Unicode new_name must be accepted");
        assert!(tmp.path().join("照片 2024 🚀.txt").exists());
    }

    #[test]
    fn test_batch_rename_conflict_rejects_whole_batch() {
        // One conflicting item must reject the whole batch: the other item's
        // rename must NOT be executed either.
        let tmp = TempDir::new().unwrap();
        let a = tmp.path().join("a.txt");
        let b = tmp.path().join("b.txt");
        let c = tmp.path().join("c.txt");
        fs::write(&a, "alpha").unwrap();
        fs::write(&b, "beta").unwrap();

        let items = vec![
            RenameItem {
                original_path: a.to_string_lossy().into_owned(),
                new_name: "c.txt".to_string(),
            },
            RenameItem {
                original_path: b.to_string_lossy().into_owned(),
                new_name: "a.txt".to_string(), // conflicts with existing a.txt
            },
        ];
        let result = batch_rename(&items, None);
        assert!(result.is_err(), "conflict must reject the whole batch");
        assert!(a.exists(), "a.txt must not be overwritten");
        assert!(b.exists(), "b.txt must not be consumed");
        assert!(!c.exists(), "c.txt must not be created by a rejected batch");
    }

    #[test]
    fn test_batch_rename_duplicate_target_rejected() {
        // Two items resolving to the same (currently free) target must be
        // rejected up front — otherwise the second rename would overwrite the
        // first one's result.
        let tmp = TempDir::new().unwrap();
        let a = tmp.path().join("a.txt");
        let b = tmp.path().join("b.txt");
        fs::write(&a, "alpha").unwrap();
        fs::write(&b, "beta").unwrap();

        let items = vec![
            RenameItem {
                original_path: a.to_string_lossy().into_owned(),
                new_name: "same.txt".to_string(),
            },
            RenameItem {
                original_path: b.to_string_lossy().into_owned(),
                new_name: "same.txt".to_string(),
            },
        ];
        let result = batch_rename(&items, None);
        assert!(result.is_err(), "duplicate target must be rejected");
        assert!(a.exists() && b.exists(), "no source may be consumed");
    }

    #[test]
    fn test_batch_rename_full_traversal_matrix_rejected() {
        // Beyond the T1 cases, every path-tampering shape must be rejected at
        // the batch level with the source left untouched.
        let tmp = TempDir::new().unwrap();
        let src = tmp.path().join("victim.txt");
        for (case, new_name) in [
            ("current-dir", "."),
            ("parent-dir", ".."),
            ("dotdot-slash", "../x"),
            ("nested", "a/b.txt"),
            ("backslash", "a\\b.txt"),
            ("absolute", "/abs/x.txt"),
            ("empty", ""),
            ("control-char", "a\u{0000}b"),
        ] {
            fs::write(&src, "payload").unwrap();
            let items = vec![RenameItem {
                original_path: src.to_string_lossy().into_owned(),
                new_name: new_name.to_string(),
            }];
            let result = batch_rename(&items, None);
            assert!(
                result.is_err(),
                "case {}: new_name {:?} must be rejected, got {:?}",
                case, new_name, result
            );
            assert!(src.exists(), "case {}: source must not be moved", case);
        }
    }

    #[test]
    fn test_batch_rename_same_name_is_noop() {
        // Renaming a file onto its own current name is a no-op and must not
        // be reported as a conflict.
        let tmp = TempDir::new().unwrap();
        let a = tmp.path().join("a.txt");
        fs::write(&a, "alpha").unwrap();

        let items = vec![RenameItem {
            original_path: a.to_string_lossy().into_owned(),
            new_name: "a.txt".to_string(),
        }];
        let result = batch_rename(&items, None);
        assert_eq!(result.unwrap(), 1, "same-name rename must succeed");
        assert!(a.exists(), "file must still exist after no-op rename");
    }

    #[test]
    fn test_organize_by_date_skips_existing_target() {
        let tmp = TempDir::new().unwrap();
        // A file whose date subdir already contains a same-named file.
        let src = tmp.path().join("photo.jpg");
        fs::write(&src, "new payload").unwrap();
        // Compute the exact subdir organize_by_date will derive from the
        // file's modification time, then pre-seed a conflicting target there.
        let modified = fs::metadata(&src)
            .unwrap()
            .modified()
            .unwrap()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;
        let dt = chrono::DateTime::from_timestamp(modified, 0).unwrap();
        let subdir = format!("{:04}/{:02}/{:02}", dt.year(), dt.month(), dt.day());
        let target_dir = tmp.path().join(&subdir);
        fs::create_dir_all(&target_dir).unwrap();
        fs::write(target_dir.join("photo.jpg"), "existing payload").unwrap();

        let moved = organize_by_date(&tmp.path().to_string_lossy(), "YYYY/MM/DD", None).unwrap();
        assert_eq!(moved, 0, "conflicting file must be skipped, not moved");
        assert_eq!(
            fs::read_to_string(target_dir.join("photo.jpg")).unwrap(),
            "existing payload",
            "existing target must not be overwritten"
        );
        assert!(
            src.exists(),
            "source must remain in place when target exists"
        );
    }

    #[test]
    fn test_organize_by_type_skips_existing_target() {
        let tmp = TempDir::new().unwrap();
        fs::write(tmp.path().join("photo.jpg"), "new payload").unwrap();
        let target_dir = tmp.path().join("Images");
        fs::create_dir_all(&target_dir).unwrap();
        fs::write(target_dir.join("photo.jpg"), "existing payload").unwrap();

        let moved = organize_by_type(&tmp.path().to_string_lossy(), None).unwrap();
        assert_eq!(moved, 0, "conflicting file must be skipped, not moved");
        assert_eq!(
            fs::read_to_string(target_dir.join("photo.jpg")).unwrap(),
            "existing payload",
            "existing target must not be overwritten"
        );
        assert!(
            tmp.path().join("photo.jpg").exists(),
            "source must remain in place when target exists"
        );
    }
}
