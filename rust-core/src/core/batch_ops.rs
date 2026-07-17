//! Batch rename and file organization operations.
//!
//! Provides:
//! - Batch rename with pattern substitution (e.g., {name}_{index}.{ext})
//! - Organize files by date (YYYY/MM/DD)
//! - Organize files by file type (Images/, Documents/, etc.)

use std::io;
use std::path::{Path, PathBuf};
use chrono::Datelike;

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
pub fn batch_rename(
    items: &[RenameItem],
    progress: Option<BatchProgressCallback>,
) -> io::Result<usize> {
    let total = items.len();
    let mut succeeded = 0usize;

    for (i, item) in items.iter().enumerate() {
        let parent = Path::new(&item.original_path)
            .parent()
            .unwrap_or(Path::new(""));
        let new_path = parent.join(&item.new_name);

        match std::fs::rename(&item.original_path, &new_path) {
            Ok(()) => {
                succeeded += 1;
            }
            Err(e) => {
                eprintln!("rename {} -> {} failed: {}", item.original_path, item.new_name, e);
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

        match std::fs::rename(&file_path, &target_path) {
            Ok(()) => {
                moved += 1;
            }
            Err(e) => {
                eprintln!("move {} -> {} failed: {}", file_path.display(), target_path.display(), e);
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

        match std::fs::rename(&file_path, &target_path) {
            Ok(()) => {
                moved += 1;
            }
            Err(e) => {
                eprintln!("move {} -> {} failed: {}", file_path.display(), target_path.display(), e);
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
}
