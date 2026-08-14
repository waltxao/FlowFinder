//! Search engine for file discovery with filtering and fuzzy matching.
//!
//! Provides two main entry points:
//! - [`search_files`] — simple text search across file names
//! - [`search_with_filters`] — advanced search with file type, size, and date filters

use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use walkdir::WalkDir;

/// Execution limits and cooperative-cancellation configuration for a search.
#[derive(Debug, Clone)]
pub struct SearchConfig {
    /// Stop after delivering this many results. `0` means unlimited.
    pub max_results: usize,
    /// Maximum directory recursion depth (`None` = unlimited). A depth of
    /// `1` visits only the root's immediate children.
    pub max_depth: Option<usize>,
}

impl Default for SearchConfig {
    fn default() -> Self {
        Self {
            max_results: 500,
            max_depth: None,
        }
    }
}

/// Filter criteria for advanced file search.
#[derive(Debug, Clone, Default)]
pub struct SearchFilters {
    /// Comma-separated file extensions (e.g., "jpg,png,gif").
    pub file_types: Option<String>,
    /// Minimum file size in bytes.
    pub min_size: Option<u64>,
    /// Maximum file size in bytes.
    pub max_size: Option<u64>,
    /// Modified after this UNIX timestamp.
    pub modified_after: Option<i64>,
    /// Modified before this UNIX timestamp.
    pub modified_before: Option<i64>,
}

/// A single search result entry.
#[derive(Debug, Clone)]
pub struct SearchResult {
    pub path: String,
    pub name: String,
    pub size: u64,
    pub modified: i64,
    pub is_dir: bool,
}

/// Simple fuzzy matching: checks if query characters appear in order.
pub fn fuzzy_match(haystack: &str, needle: &str) -> bool {
    if needle.is_empty() {
        return true;
    }
    let haystack_lower = haystack.to_lowercase();
    let needle_lower = needle.to_lowercase();
    let mut haystack_chars = haystack_lower.chars();
    let mut needle_chars = needle_lower.chars();

    if let Some(mut nc) = needle_chars.next() {
        for hc in haystack_chars {
            if hc == nc {
                nc = match needle_chars.next() {
                    Some(c) => c,
                    None => return true,
                };
            }
        }
    }
    false
}

/// Search for files matching `query` under `root_path`.
///
/// Results are delivered through the callback as they are found. The walk
/// polls `cancel_token` at every entry and stops early when it is set; it
/// also stops after `config.max_results` results and never descends deeper
/// than `config.max_depth`.
// P2-17 修复：改为回调消费结果模式，不返回 Vec，避免双重克隆。
pub fn search_files<F>(
    root_path: &str,
    query: &str,
    config: &SearchConfig,
    cancel_token: &AtomicBool,
    callback: &mut F,
) -> Result<(), std::io::Error>
where
    F: FnMut(SearchResult),
{
    let mut walker = WalkDir::new(root_path);
    if let Some(depth) = config.max_depth {
        walker = walker.max_depth(depth);
    }

    let mut delivered = 0usize;
    for entry in walker.into_iter().filter_map(|e| e.ok()) {
        if cancel_token.load(Ordering::Relaxed) {
            return Ok(());
        }
        if config.max_results != 0 && delivered >= config.max_results {
            break;
        }
        let name = entry.file_name().to_string_lossy().to_string();
        if fuzzy_match(&name, query) {
            let meta = entry.metadata().ok();
            let modified = meta
                .as_ref()
                .and_then(|m| m.modified().ok())
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_secs() as i64)
                .unwrap_or(0);
            let size = meta.as_ref().map(|m| m.len()).unwrap_or(0);
            let is_dir = entry.file_type().is_dir();
            let path = entry.path().to_string_lossy().to_string();

            let result = SearchResult {
                path,
                name,
                size,
                modified,
                is_dir,
            };
            // 回调直接消费 result，无需克隆
            callback(result);
            delivered += 1;
        }
    }

    Ok(())
}

/// Search for files with advanced filters.
///
/// Results are delivered through the callback as they are found. The walk
/// polls `cancel_token` at every entry and stops early when it is set; it
/// also stops after `config.max_results` results and never descends deeper
/// than `config.max_depth`.
// P2-17 修复：改为回调消费结果模式，不返回 Vec，避免双重克隆。
pub fn search_with_filters<F>(
    root_path: &str,
    query: &str,
    filters: &SearchFilters,
    config: &SearchConfig,
    cancel_token: &AtomicBool,
    callback: &mut F,
) -> Result<(), std::io::Error>
where
    F: FnMut(SearchResult),
{
    // Parse file type filter
    let allowed_extensions: Option<Vec<String>> = filters.file_types.as_ref().map(|types| {
        types
            .split(',')
            .map(|s| s.trim().to_lowercase())
            .collect()
    });

    let mut walker = WalkDir::new(root_path);
    if let Some(depth) = config.max_depth {
        walker = walker.max_depth(depth);
    }

    let mut delivered = 0usize;
    for entry in walker.into_iter().filter_map(|e| e.ok()) {
        if cancel_token.load(Ordering::Relaxed) {
            return Ok(());
        }
        if config.max_results != 0 && delivered >= config.max_results {
            break;
        }
        let name = entry.file_name().to_string_lossy().to_string();

        // Name filter (fuzzy match)
        if !query.is_empty() && !fuzzy_match(&name, query) {
            continue;
        }

        let meta = entry.metadata().ok();
        let modified = meta
            .as_ref()
            .and_then(|m| m.modified().ok())
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        let size = meta.as_ref().map(|m| m.len()).unwrap_or(0);
        let is_dir = entry.file_type().is_dir();
        let path = entry.path().to_string_lossy().to_string();

        // File type filter
        if let Some(ref extensions) = allowed_extensions {
            let ext = Path::new(&name)
                .extension()
                .map(|e| e.to_string_lossy().to_string())
                .unwrap_or_default();
            if !extensions.contains(&ext) {
                continue;
            }
        }

        // Size filter
        if let Some(min) = filters.min_size {
            if size < min {
                continue;
            }
        }
        if let Some(max) = filters.max_size {
            if size > max {
                continue;
            }
        }

        // Date filter
        if let Some(after) = filters.modified_after {
            if modified < after {
                continue;
            }
        }
        if let Some(before) = filters.modified_before {
            if modified > before {
                continue;
            }
        }

        let result = SearchResult {
            path,
            name,
            size,
            modified,
            is_dir,
        };
        // 回调直接消费 result，无需克隆
        callback(result);
        delivered += 1;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fuzzy_match_basic() {
        assert!(fuzzy_match("hello world", "hw"));
        assert!(fuzzy_match("hello world", "hello"));
        assert!(fuzzy_match("Document.pdf", "doc"));
        assert!(!fuzzy_match("hello world", "xyz"));
        assert!(fuzzy_match("TestFile.txt", "tf"));
    }

    #[test]
    fn test_fuzzy_match_case_insensitive() {
        assert!(fuzzy_match("HelloWorld", "hw"));
        assert!(fuzzy_match("UPPERCASE", "upper"));
        assert!(fuzzy_match("MixedCase", "mixed"));
    }

    #[test]
    fn test_fuzzy_match_empty() {
        assert!(fuzzy_match("anything", ""));
    }

    #[test]
    fn test_search_files_empty_dir() {
        let tmp = std::env::temp_dir();
        let mut results: Vec<SearchResult> = Vec::new();
        let cancel = AtomicBool::new(false);
        let _ = search_files(
            &tmp.to_string_lossy(),
            "nonexistent_file_xyz_123",
            &SearchConfig::default(),
            &cancel,
            &mut |r| results.push(r),
        );
        // Should return empty results for non-matching query
        assert!(results.is_empty());
    }

    #[test]
    fn test_search_with_filters_size() {
        let tmp = tempfile::TempDir::new().unwrap();
        let file_path = tmp.path().join("test.txt");
        std::fs::write(&file_path, "hello world").unwrap();

        let filters = SearchFilters {
            file_types: None,
            min_size: Some(5),
            max_size: Some(20),
            modified_after: None,
            modified_before: None,
        };

        let mut results: Vec<SearchResult> = Vec::new();
        let cancel = AtomicBool::new(false);
        let _ = search_with_filters(
            &tmp.path().to_string_lossy(),
            "test",
            &filters,
            &SearchConfig::default(),
            &cancel,
            &mut |r| results.push(r),
        );

        assert!(!results.is_empty(), "Should find test.txt with size filter");
    }

    #[test]
    fn test_search_with_filters_file_type() {
        let tmp = tempfile::TempDir::new().unwrap();
        std::fs::write(tmp.path().join("test.txt"), "hello").unwrap();
        std::fs::write(tmp.path().join("image.jpg"), "fake image").unwrap();

        let filters = SearchFilters {
            file_types: Some("txt".to_string()),
            min_size: None,
            max_size: None,
            modified_after: None,
            modified_before: None,
        };

        let mut results: Vec<SearchResult> = Vec::new();
        let cancel = AtomicBool::new(false);
        let _ = search_with_filters(
            &tmp.path().to_string_lossy(),
            "",
            &filters,
            &SearchConfig::default(),
            &cancel,
            &mut |r| results.push(r),
        );

        assert_eq!(results.len(), 1, "Should find only .txt file");
        assert!(results[0].name.ends_with(".txt"));
    }

    #[test]
    fn test_search_max_results_boundary() {
        let tmp = tempfile::TempDir::new().unwrap();
        for i in 0..10 {
            std::fs::write(tmp.path().join(format!("data_{}.txt", i)), "x").unwrap();
        }
        let cancel = AtomicBool::new(false);

        // Cap of 3 → exactly 3 results, even though 10 match.
        let capped = SearchConfig {
            max_results: 3,
            max_depth: None,
        };
        let mut results: Vec<SearchResult> = Vec::new();
        let _ = search_files(
            &tmp.path().to_string_lossy(),
            "data",
            &capped,
            &cancel,
            &mut |r| results.push(r),
        );
        assert_eq!(results.len(), 3, "max_results cap must be respected");

        // max_results = 0 → unlimited.
        let unlimited = SearchConfig {
            max_results: 0,
            max_depth: None,
        };
        let mut all: Vec<SearchResult> = Vec::new();
        let _ = search_files(
            &tmp.path().to_string_lossy(),
            "data",
            &unlimited,
            &cancel,
            &mut |r| all.push(r),
        );
        assert_eq!(all.len(), 10, "max_results=0 must not cap results");
    }

    #[test]
    fn test_search_max_depth() {
        let tmp = tempfile::TempDir::new().unwrap();
        let deep = tmp.path().join("sub").join("deep");
        std::fs::create_dir_all(&deep).unwrap();
        std::fs::write(tmp.path().join("top.txt"), "x").unwrap();
        std::fs::write(tmp.path().join("sub").join("mid.txt"), "x").unwrap();
        std::fs::write(deep.join("deep.txt"), "x").unwrap();

        let config = SearchConfig {
            max_results: 0,
            max_depth: Some(1),
        };
        let cancel = AtomicBool::new(false);
        let mut results: Vec<SearchResult> = Vec::new();
        let _ = search_with_filters(
            &tmp.path().to_string_lossy(),
            "",
            &SearchFilters::default(),
            &config,
            &cancel,
            &mut |r| results.push(r),
        );

        assert!(
            results.iter().any(|r| r.name == "top.txt"),
            "depth-1 search must include the root's direct children"
        );
        assert!(
            !results.iter().any(|r| r.name == "mid.txt"),
            "depth-1 search must not descend into sub/"
        );
        assert!(
            !results.iter().any(|r| r.name == "deep.txt"),
            "depth-1 search must not reach depth 2"
        );
    }

    #[test]
    fn test_search_cancel_mid_walk() {
        use std::sync::atomic::{AtomicBool as AB, AtomicUsize, Ordering as Ord};
        use std::sync::Arc;
        use std::time::{Duration, Instant};

        // A large flat directory so the walk outlasts the cancel request.
        let tmp = tempfile::TempDir::new().unwrap();
        let total = 8000;
        for i in 0..total {
            std::fs::write(tmp.path().join(format!("file_{:05}.txt", i)), "x").unwrap();
        }

        let cancel = Arc::new(AB::new(false));
        let cancel_in_thread = Arc::clone(&cancel);
        let count = Arc::new(AtomicUsize::new(0));
        let count_in_thread = Arc::clone(&count);
        let first_result = Arc::new(AB::new(false));
        let first_in_thread = Arc::clone(&first_result);

        let config = SearchConfig {
            max_results: 0,
            max_depth: None,
        };
        let filters = SearchFilters::default();

        let handle = std::thread::spawn(move || {
            let _ = search_with_filters(
                &tmp.path().to_string_lossy(),
                "",
                &filters,
                &config,
                &cancel_in_thread,
                &mut |_| {
                    count_in_thread.fetch_add(1, Ord::Relaxed);
                    first_in_thread.store(true, Ord::Relaxed);
                },
            );
        });

        // Wait for the walk to start delivering results, then cancel mid-walk.
        let deadline = Instant::now() + Duration::from_secs(30);
        while !first_result.load(Ord::Relaxed) && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(5));
        }
        assert!(first_result.load(Ord::Relaxed), "walk should have started");
        cancel.store(true, Ord::Relaxed);

        handle.join().unwrap();

        let delivered = count.load(Ord::Relaxed);
        assert!(
            delivered < total,
            "cancelled walk must stop early: delivered {} of {}",
            delivered,
            total
        );
        // Callbacks are synchronous: once the search returns, no more can
        // arrive, so the count is stable.
        assert_eq!(delivered, count.load(Ord::Relaxed), "no late callbacks");
    }

    #[test]
    fn test_search_pre_cancelled_emits_nothing() {
        let tmp = tempfile::TempDir::new().unwrap();
        for i in 0..20 {
            std::fs::write(tmp.path().join(format!("file_{}.txt", i)), "x").unwrap();
        }

        let cancel = AtomicBool::new(true);
        let mut results: Vec<SearchResult> = Vec::new();
        let _ = search_files(
            &tmp.path().to_string_lossy(),
            "",
            &SearchConfig::default(),
            &cancel,
            &mut |r| results.push(r),
        );
        assert!(results.is_empty(), "pre-cancelled search must emit nothing");
    }
}
