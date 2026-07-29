//! In-memory directory listing cache with TTL and LRU eviction.
//! Speeds up repeated navigation (back/forward) especially over SMB.
//!
//! Uses `lru::LruCache` for automatic eviction: when the cache reaches its
//! capacity (500 entries) the least-recently-used entry is pushed out. A
//! 5-second TTL on top ensures stale listings are not served after a
//! filesystem change slips in between FSEvents notifications.

use lru::LruCache;
use parking_lot::Mutex;
use std::num::NonZeroUsize;
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

/// Maximum number of cached directory listings.
const CACHE_CAP: usize = 500;
/// TTL: entries older than this are treated as stale.
const TTL: Duration = Duration::from_secs(5);

// P2-15 修复：CachedEntry 使用 Arc<Vec<...>> 存储，
// get() 返回 Arc 克隆（仅增加引用计数，避免深拷贝整个 Vec）。
struct CachedEntry {
    skeletons: Arc<Vec<crate::core::scanner::FileEntrySkeleton>>,
    fetched_at: Instant,
}

static CACHE: OnceLock<Mutex<LruCache<String, CachedEntry>>> = OnceLock::new();

fn cache() -> &'static Mutex<LruCache<String, CachedEntry>> {
    CACHE.get_or_init(|| {
        Mutex::new(LruCache::new(
            NonZeroUsize::new(CACHE_CAP).expect("CACHE_CAP > 0"),
        ))
    })
}

/// Get a cached directory listing if fresh (< TTL old).
///
/// A successful get promotes the entry to the most-recently-used position,
/// so frequently-visited directories stay in cache.
///
/// P2-15 修复：返回 Arc<Vec<...>> 而非克隆整个 Vec，
/// 调用方通过 Arc 引用计数共享数据，避免大目录的深拷贝。
pub fn get(path: &str) -> Option<Arc<Vec<crate::core::scanner::FileEntrySkeleton>>> {
    let mut guard = cache().lock();
    let entry = guard.get(path)?;
    if entry.fetched_at.elapsed() < TTL {
        Some(Arc::clone(&entry.skeletons))
    } else {
        // TTL expired — evict and report a miss.
        guard.pop(path);
        None
    }
}

/// Store a directory listing in cache.
///
/// If the cache is at capacity the least-recently-used entry is evicted
/// automatically by `LruCache::put`.
pub fn put(path: String, skeletons: Vec<crate::core::scanner::FileEntrySkeleton>) {
    let mut guard = cache().lock();
    guard.put(
        path,
        CachedEntry {
            skeletons: Arc::new(skeletons),
            fetched_at: Instant::now(),
        },
    );
}

/// Invalidate a specific path (call on refresh).
pub fn invalidate(path: &str) {
    let mut guard = cache().lock();
    guard.pop(path);
}

/// Clear all entries from the cache.
pub fn clear() {
    let mut guard = cache().lock();
    guard.clear();
}
