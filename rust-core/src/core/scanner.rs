//! Filesystem scanning primitives and the [`FileEntrySkeleton`] model.

use std::path::Path;

/// Stream a file through BLAKE3 and return its hex digest.
///
/// Uses a fixed-size stack buffer so even very large files do not need to be
/// loaded fully into memory.
pub fn hash_file(path: &str) -> std::io::Result<String> {
    use std::io::Read;

    let mut hasher = blake3::Hasher::new();
    let mut file = std::fs::File::open(path)?;
    let mut buf = [0u8; 65_536];
    loop {
        let n = file.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hasher.finalize().to_hex().to_string())
}

/// A lightweight directory entry returned for fast directory listing.
///
/// In FlowFinder ≥ 0.5.0 the skeleton is populated by
/// [`crate::core::bulk_read::list_dir_bulk`] (macOS `getattrlistbulk`),
/// so it **already includes full metadata** (size, dates, system-protected).
/// The `metadata_loaded` field is therefore `true` for entries coming from
/// the bulk path.  The legacy `from_dir_entry` constructor also fills in
/// metadata via `stat()` for backward compatibility.
#[derive(Debug, Clone)]
pub struct FileEntrySkeleton {
    pub id: String,
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub is_file: bool,
    pub is_symlink: bool,
    pub is_hidden: bool,
    pub extension: String,
    // ── Metadata fields (populated by getattrlistbulk or stat) ──────
    pub size: u64,
    pub modified: i64,
    pub created: i64,
    pub is_system_protected: bool,
    /// Whether metadata (size, dates, system-protected) has been loaded.
    /// Always `true` when the entry comes from `getattrlistbulk` or
    /// `from_dir_entry`.
    pub metadata_loaded: bool,
}

impl FileEntrySkeleton {
    /// Build a skeleton from a DirEntry, including metadata via `stat()`.
    ///
    /// This is the fallback constructor used when `getattrlistbulk` is
    /// unavailable.  It calls `metadata()` (one `stat` per entry).
    pub fn from_dir_entry(entry: &std::fs::DirEntry) -> std::io::Result<Self> {
        let path = entry.path();
        let path_str = path.to_string_lossy().to_string();
        let file_type = entry.file_type()?;
        let name = entry.file_name().to_string_lossy().to_string();
        let extension = Path::new(&name)
            .extension()
            .map(|e| e.to_string_lossy().to_string())
            .unwrap_or_default();

        let meta = entry.metadata()?;
        let modified = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        let created = meta
            .created()
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        let is_system_protected = crate::core::utils::is_system_protected_path(&path.to_string_lossy());

        Ok(Self {
            id: path_str.clone(),
            is_dir: file_type.is_dir(),
            is_file: file_type.is_file(),
            is_symlink: file_type.is_symlink(),
            is_hidden: name.starts_with('.'),
            name,
            path: path_str,
            extension,
            size: if file_type.is_file() { meta.len() } else { 0 },
            modified,
            created,
            is_system_protected,
            metadata_loaded: true,
        })
    }

    /// Build a skeleton from a [`BulkEntry`] obtained via `getattrlistbulk`.
    ///
    /// This is the preferred fast path — all metadata is already present,
    /// so no additional `stat()` calls are needed.
    pub fn from_bulk_entry(entry: &crate::core::bulk_read::BulkEntry) -> Self {
        Self {
            id: entry.path.clone(),
            name: entry.name.clone(),
            path: entry.path.clone(),
            is_dir: entry.is_dir,
            is_file: entry.is_file,
            is_symlink: entry.is_symlink,
            is_hidden: entry.is_hidden,
            extension: entry.extension.clone(),
            size: entry.size,
            modified: entry.modified,
            created: entry.created,
            is_system_protected: entry.is_system_protected,
            metadata_loaded: true,
        }
    }
}

/// A batch of file metadata.
#[derive(Debug, Clone)]
pub struct FileMetadataItem {
    pub path: String,
    pub size: u64,
    pub modified: i64,
    pub created: i64,
    pub is_system_protected: bool,
}

/// Batch of metadata items.
#[derive(Debug, Clone)]
pub struct MetadataBatch {
    pub items: Vec<FileMetadataItem>,
    pub done: bool,
}

/// Progress event for batch file operations.
#[derive(Debug, Clone)]
pub enum CopyEvent {
    /// Progress update — one file completed.
    Progress {
        completed: usize,
        total: usize,
        current_file: String,
    },
    /// All operations done.
    Done {
        succeeded: usize,
        failed: usize,
    },
    /// Error on a specific file (operation continues).
    FileError {
        path: String,
        error: String,
    },
}
