//! Search engine for file discovery with filtering and fuzzy matching.
//!
//! Provides two main entry points:
//! - [`search_files`] — simple text search across file names
//! - [`search_with_filters`] — advanced search with file type, size, and date filters

use std::collections::HashMap;
use std::path::Path;
use walkdir::WalkDir;

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
/// Returns results through the callback as they are found.
pub fn search_files<F>(
    root_path: &str,
    query: &str,
    callback: &mut F,
) -> Result<Vec<SearchResult>, std::io::Error>
where
    F: FnMut(SearchResult),
{
    let mut results = Vec::new();

    for entry in WalkDir::new(root_path)
        .into_iter()
        .filter_map(|e| e.ok())
    {
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
                path: path.clone(),
                name: name.clone(),
                size,
                modified,
                is_dir,
            };
            callback(result.clone());
            results.push(result);
        }
    }

    Ok(results)
}

/// Search for files with advanced filters.
///
/// Returns results through the callback as they are found.
pub fn search_with_filters<F>(
    root_path: &str,
    query: &str,
    filters: &SearchFilters,
    callback: &mut F,
) -> Result<Vec<SearchResult>, std::io::Error>
where
    F: FnMut(SearchResult),
{
    let mut results = Vec::new();

    // Parse file type filter
    let allowed_extensions: Option<Vec<String>> = filters.file_types.as_ref().map(|types| {
        types
            .split(',')
            .map(|s| s.trim().to_lowercase())
            .collect()
    });

    for entry in WalkDir::new(root_path)
        .into_iter()
        .filter_map(|e| e.ok())
    {
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
            path: path.clone(),
            name: name.clone(),
            size,
            modified,
            is_dir,
        };
        callback(result.clone());
        results.push(result);
    }

    Ok(results)
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
        let _ = search_files(
            &tmp.to_string_lossy(),
            "nonexistent_file_xyz_123",
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
        let _ = search_with_filters(
            &tmp.path().to_string_lossy(),
            "test",
            &filters,
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
        let _ = search_with_filters(
            &tmp.path().to_string_lossy(),
            "",
            &filters,
            &mut |r| results.push(r),
        );

        assert_eq!(results.len(), 1, "Should find only .txt file");
        assert!(results[0].name.ends_with(".txt"));
    }
}
