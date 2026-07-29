//! Thumbnail generation and caching.
//!
//! Provides thumbnail generation for images (JPEG, PNG, HEIC, RAW)
//! with disk caching support.

use std::io;
use std::path::PathBuf;

/// Supported image formats for thumbnail generation.
pub const SUPPORTED_FORMATS: &[&str] = &[
    "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "raw",
];

/// Check if a file extension is supported for thumbnail generation.
pub fn is_supported_format(ext: &str) -> bool {
    let ext_lower = ext.to_lowercase();
    SUPPORTED_FORMATS.contains(&ext_lower.as_str())
}

/// Generate a thumbnail for an image file.
///
/// # Arguments
/// - `path` — Path to the image file.
/// - `max_size` — Maximum width/height of the thumbnail.
///
/// # Returns
/// - Path to the generated thumbnail on success.
/// - Error if the file cannot be processed.
pub fn generate_thumbnail(path: &str, max_size: u32) -> io::Result<PathBuf> {
    let thumb_path = get_thumbnail_cache_path(path)?;

    // Check if thumbnail already exists and is fresh
    if thumb_path.exists() {
        let metadata = std::fs::metadata(&thumb_path)?;
        let original_metadata = std::fs::metadata(path)?;
        if metadata.modified()? >= original_metadata.modified()? {
            return Ok(thumb_path);
        }
    }

    // Placeholder: In production, this would use the image crate or system APIs
    // to generate a resized thumbnail and save it to thumb_path.
    // For now, we just create an empty file as a placeholder.
    std::fs::write(&thumb_path, b"")?;

    Ok(thumb_path)
}

/// Generate thumbnails for multiple image files.
///
/// # Arguments
/// - `paths` — Array of paths to image files.
/// - `max_size` — Maximum width/height of each thumbnail.
///
/// # Returns
/// - Array of paths to generated thumbnails.
pub fn generate_thumbnails(paths: &[String], max_size: u32) -> io::Result<Vec<PathBuf>> {
    let mut results = Vec::with_capacity(paths.len());
    for path in paths {
        let thumb_path = generate_thumbnail(path, max_size)?;
        results.push(thumb_path);
    }
    Ok(results)
}

/// Get the cache path for a thumbnail.
fn get_thumbnail_cache_path(path: &str) -> io::Result<PathBuf> {
    let cache_dir = std::env::temp_dir()
        .join("FlowFinder")
        .join("Thumbnails");

    std::fs::create_dir_all(&cache_dir)?;

    // P2-14 修复：启动时清理超过 30 天的旧缩略图
    cleanup_old_thumbnails(&cache_dir);

    let hash = blake3::hash(path.as_bytes());
    let thumb_name = format!("{}.jpg", hash.to_hex());
    Ok(cache_dir.join(thumb_name))
}

/// P2-14 修复：清理超过 30 天的旧缩略图缓存文件。
///
/// 该函数在每次获取缩略图缓存路径时被调用（惰性清理）。
/// 清理操作是尽力而为的——如果遍历目录失败或删除单个文件失败，
/// 不会影响正常的缩略图生成流程。
fn cleanup_old_thumbnails(cache_dir: &std::path::Path) {
    const MAX_AGE_DAYS: u64 = 30;
    let max_age = std::time::Duration::from_secs(MAX_AGE_DAYS * 24 * 60 * 60);

    let entries = match std::fs::read_dir(cache_dir) {
        Ok(e) => e,
        Err(_) => return, // 目录读取失败，静默跳过清理
    };

    let now = std::time::SystemTime::now();
    for entry in entries.flatten() {
        let path = entry.path();
        // 仅清理 .jpg 缩略图文件
        if path.extension().and_then(|e| e.to_str()) != Some("jpg") {
            continue;
        }
        if let Ok(metadata) = entry.metadata() {
            if let Ok(modified) = metadata.modified() {
                if let Ok(age) = now.duration_since(modified) {
                    if age > max_age {
                        // 删除过期的缩略图文件，忽略错误
                        let _ = std::fs::remove_file(&path);
                    }
                }
            }
        }
    }
}

// ── Tests ───────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_thumbnail_cache_path() {
        let path = "/test/image.jpg";
        let cache_path = get_thumbnail_cache_path(path).unwrap();
        assert!(cache_path.to_string_lossy().contains("FlowFinder"));
        assert!(cache_path.to_string_lossy().ends_with(".jpg"));
    }

    #[test]
    fn test_is_supported_format() {
        assert!(is_supported_format("jpg"));
        assert!(is_supported_format("JPG"));
        assert!(is_supported_format("png"));
        assert!(is_supported_format("heic"));
        assert!(!is_supported_format("txt"));
        assert!(!is_supported_format(""));
    }

    #[test]
    fn test_generate_thumbnail_creates_file() {
        let tmp = tempfile::TempDir::new().unwrap();
        let test_file = tmp.path().join("test.png");
        std::fs::write(&test_file, b"fake image data").unwrap();

        let thumb_path = generate_thumbnail(test_file.to_str().unwrap(), 256).unwrap();
        assert!(thumb_path.exists());
    }
}
