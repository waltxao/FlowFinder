//! Thumbnail generation and caching.
//!
//! Provides thumbnail generation for images (JPEG, PNG, HEIC, RAW)
//! with disk caching support.

use std::io;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use parking_lot::Mutex;

/// Supported image formats for thumbnail generation.
pub const SUPPORTED_FORMATS: &[&str] = &[
    "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "raw",
];

/// Default interval between automatic full-directory thumbnail cleanups.
const DEFAULT_CLEANUP_INTERVAL: Duration = Duration::from_secs(300);

/// Number of days after which an untouched thumbnail is evicted.
const THUMBNAIL_MAX_AGE_DAYS: u64 = 30;

/// Check if a file extension is supported for thumbnail generation.
pub fn is_supported_format(ext: &str) -> bool {
    let ext_lower = ext.to_lowercase();
    SUPPORTED_FORMATS.contains(&ext_lower.as_str())
}

/// Generate a thumbnail for an image file.
///
/// A fresh, existing thumbnail is served from the cache. When no thumbnail
/// exists yet the function fails with `ErrorKind::Unsupported` instead of
/// fabricating a placeholder file, so callers can fall back to a generic
/// icon rather than rendering an empty image.
///
/// # Arguments
/// - `path` — Path to the image file.
/// - `max_size` — Maximum width/height of the thumbnail.
///
/// # Returns
/// - Path to the cached thumbnail on success.
/// - Error if the file cannot be processed or generation is unavailable.
pub fn generate_thumbnail(_path: &str, _max_size: u32) -> io::Result<PathBuf> {
    let thumb_path = get_thumbnail_cache_path(_path)?;

    // Serve a fresh cached thumbnail as-is.
    if thumb_path.exists() {
        let thumb_modified = std::fs::metadata(&thumb_path)?.modified()?;
        let original_modified = std::fs::metadata(_path)?.modified()?;
        if thumb_modified >= original_modified {
            return Ok(thumb_path);
        }
    }

    // Real thumbnail generation is not implemented yet. Fail loudly instead
    // of writing an empty placeholder that UI code (`thumb_path.exists()`)
    // would mistake for a genuine thumbnail and render as a blank image.
    Err(io::Error::new(
        io::ErrorKind::Unsupported,
        "thumbnail generation is not implemented (refusing to write an empty placeholder)",
    ))
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

    // P2-14 修复：清理超过 30 天的旧缩略图。节流执行——上次清理在
    // `DEFAULT_CLEANUP_INTERVAL` 内时直接跳过，避免每次取缓存路径都做 O(n) 全扫。
    maybe_cleanup_old_thumbnails(&cache_dir);

    let hash = blake3::hash(path.as_bytes());
    let thumb_name = format!("{}.jpg", hash.to_hex());
    Ok(cache_dir.join(thumb_name))
}

/// Override the full-directory cleanup interval (seconds) used by the global
/// throttle. Production keeps `DEFAULT_CLEANUP_INTERVAL`; tests lower it to
/// observe cleanup behavior without waiting 300s.
pub fn set_cleanup_interval(secs: u64) {
    global_throttle().lock().interval = Duration::from_secs(secs);
}

/// Throttles full-directory thumbnail scans so the hot path
/// (`get_thumbnail_cache_path`) does not re-scan on every call.
struct CleanupThrottle {
    interval: Duration,
    last_run: Option<Instant>,
}

impl CleanupThrottle {
    fn new(interval: Duration) -> Self {
        CleanupThrottle {
            interval,
            last_run: None,
        }
    }

    /// True only when enough time has passed since the previous run; records
    /// `now` as the new last-run time on success so subsequent calls within
    /// `interval` return false.
    fn should_run(&mut self, now: Instant) -> bool {
        match self.last_run {
            None => {
                self.last_run = Some(now);
                true
            }
            Some(last) if now.duration_since(last) >= self.interval => {
                self.last_run = Some(now);
                true
            }
            Some(_) => false,
        }
    }
}

static CLEANUP_THROTTLE: OnceLock<Mutex<CleanupThrottle>> = OnceLock::new();

fn global_throttle() -> &'static Mutex<CleanupThrottle> {
    CLEANUP_THROTTLE.get_or_init(|| Mutex::new(CleanupThrottle::new(DEFAULT_CLEANUP_INTERVAL)))
}

/// Run the age-based cleanup if the throttle allows it.
fn throttled_cleanup(cache_dir: &Path, throttle: &mut CleanupThrottle, now: Instant) {
    if throttle.should_run(now) {
        cleanup_old_thumbnails(cache_dir);
    }
}

/// Throttled entry point used by the hot path.
fn maybe_cleanup_old_thumbnails(cache_dir: &Path) {
    throttled_cleanup(cache_dir, &mut global_throttle().lock(), Instant::now());
}

/// P2-14 修复：清理超过 30 天的旧缩略图缓存文件。
///
/// 清理操作是尽力而为的——如果遍历目录失败或删除单个文件失败，
/// 不会影响正常的缩略图生成流程。调用方负责节流（见 `CleanupThrottle`）。
fn cleanup_old_thumbnails(cache_dir: &Path) {
    let max_age = Duration::from_secs(THUMBNAIL_MAX_AGE_DAYS * 24 * 60 * 60);

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

    /// Compute the cache path the same way `get_thumbnail_cache_path` does,
    /// so tests can assert on the on-disk side effects of `generate_thumbnail`.
    fn expected_thumb_path(source: &str) -> PathBuf {
        std::env::temp_dir()
            .join("FlowFinder")
            .join("Thumbnails")
            .join(format!("{}.jpg", blake3::hash(source.as_bytes()).to_hex()))
    }

    /// Write `path` and backdate its mtime to `age` ago.
    fn write_backdated(path: &Path, age: Duration) {
        std::fs::write(path, b"stale").unwrap();
        let f = std::fs::File::open(path).unwrap();
        f.set_modified(std::time::SystemTime::now() - age).unwrap();
    }

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
    fn test_cleanup_throttle_logic() {
        let mut throttle = CleanupThrottle::new(Duration::from_secs(300));
        let t0 = Instant::now();
        // First call always runs.
        assert!(throttle.should_run(t0));
        // Immediately after: throttled.
        assert!(!throttle.should_run(t0 + Duration::from_secs(1)));
        // Still within the interval.
        assert!(!throttle.should_run(t0 + Duration::from_secs(299)));
        // Past the interval: runs again.
        assert!(throttle.should_run(t0 + Duration::from_secs(300)));
        // Throttled again right after.
        assert!(!throttle.should_run(t0 + Duration::from_secs(301)));
    }

    #[test]
    fn test_cleanup_only_scans_once_within_interval() {
        let tmp = tempfile::TempDir::new().unwrap();
        let dir = tmp.path();
        let old_file = dir.join("old.jpg");
        let age = Duration::from_secs((THUMBNAIL_MAX_AGE_DAYS + 1) * 24 * 60 * 60);

        let mut throttle = CleanupThrottle::new(Duration::from_secs(300));
        let t0 = Instant::now();

        // First call scans and evicts the stale thumbnail.
        write_backdated(&old_file, age);
        throttled_cleanup(dir, &mut throttle, t0);
        assert!(!old_file.exists(), "first cleanup must evict stale thumbnails");

        // Recreate the stale file; a second call within the interval must not
        // scan, so the stale file survives.
        write_backdated(&old_file, age);
        throttled_cleanup(dir, &mut throttle, t0 + Duration::from_secs(1));
        assert!(
            old_file.exists(),
            "a throttled second call must not rescan the directory"
        );
    }

    #[test]
    fn test_generate_thumbnail_returns_not_generated() {
        let tmp = tempfile::TempDir::new().unwrap();
        let test_file = tmp.path().join("test.png");
        std::fs::write(&test_file, b"fake image data").unwrap();

        let result = generate_thumbnail(test_file.to_str().unwrap(), 256);
        assert!(
            result.is_err(),
            "unimplemented generation must fail loudly, not fake a thumbnail"
        );
        assert_eq!(
            result.err().unwrap().kind(),
            io::ErrorKind::Unsupported,
            "failure must be a typed 'not implemented' error"
        );
        // No placeholder file may be left behind.
        let thumb_path = expected_thumb_path(test_file.to_str().unwrap());
        assert!(
            !thumb_path.exists(),
            "generate_thumbnail must not write an empty placeholder file"
        );
    }

    #[test]
    fn test_generate_thumbnail_serves_fresh_cache() {
        let tmp = tempfile::TempDir::new().unwrap();
        let test_file = tmp.path().join("test.png");
        std::fs::write(&test_file, b"fake image data").unwrap();
        // Backdate the source so the cached thumbnail is fresher than it.
        write_backdated(&test_file, Duration::from_secs(3600));

        // Pre-seed a fresh thumbnail at the cache location.
        let thumb_path = expected_thumb_path(test_file.to_str().unwrap());
        std::fs::create_dir_all(thumb_path.parent().unwrap()).unwrap();
        std::fs::write(&thumb_path, b"existing").unwrap();

        let result = generate_thumbnail(test_file.to_str().unwrap(), 256);
        assert!(result.is_ok(), "fresh cached thumbnail must be served");
        assert_eq!(result.unwrap(), thumb_path);

        std::fs::remove_file(&thumb_path).unwrap();
    }
}