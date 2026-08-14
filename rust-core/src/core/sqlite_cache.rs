use rusqlite::{params, Connection};
use std::collections::HashMap;
use std::io;
use std::sync::Arc;
use std::time::Duration;

use parking_lot::Mutex;
use crate::core::scanner::FileEntrySkeleton;

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS dir_cache (
    dir_path TEXT NOT NULL,
    file_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    is_dir INTEGER NOT NULL,
    is_file INTEGER NOT NULL,
    is_symlink INTEGER NOT NULL,
    is_hidden INTEGER NOT NULL,
    extension TEXT NOT NULL,
    size INTEGER NOT NULL,
    modified INTEGER NOT NULL,
    created INTEGER NOT NULL,
    is_system_protected INTEGER NOT NULL,
    cached_at INTEGER NOT NULL,
    PRIMARY KEY (dir_path, file_path)
);
CREATE INDEX IF NOT EXISTS idx_dir_cache_dir ON dir_cache(dir_path);
";

/// Schema version tracked via `PRAGMA user_version`. Bump this whenever the
/// `dir_cache` schema changes — `init_cache` will drop and recreate the
/// table when the on-disk version does not match.
const SCHEMA_VERSION: i32 = 1;

/// Sentinel `file_path` for the "directory has been cached" marker row.
///
/// An empty directory has zero real entries, so without a marker the
/// `dir_cache` table cannot distinguish "never cached" (no rows) from
/// "cached but empty" (also no rows). `cache_put` always inserts one marker
/// row per `dir_path` (with `file_path = ""`), and `cache_get` filters it
/// out of the returned entries. Real file paths are never empty, so the
/// sentinel cannot collide with genuine entries.
const CACHED_DIR_MARKER_FILE_PATH: &str = "";

/// How long a statement waits for a contended lock before failing with
/// `SQLITE_BUSY`. Combined with WAL journal mode this makes concurrent
/// access from other processes/threads retry instead of erroring.
const BUSY_TIMEOUT: Duration = Duration::from_millis(5000);

/// Per-database connection pool.
///
/// Every operation used to open a fresh `Connection` per call, which meant
/// no `busy_timeout` and no WAL — under multi-threaded access SQLite could
/// return `SQLITE_BUSY`. We now keep one shared connection per `db_path`,
/// serialized through a `Mutex`. Within the process only one statement runs
/// at a time per database, so `SQLITE_BUSY` is structurally impossible;
/// WAL + `busy_timeout` additionally protect against cross-process access.
struct CachePool {
    conns: Mutex<HashMap<String, Arc<Mutex<Connection>>>>,
}

static POOL: std::sync::OnceLock<CachePool> = std::sync::OnceLock::new();

fn rget<T: rusqlite::types::FromSql>(row: &rusqlite::Row<'_>, idx: usize) -> io::Result<T> {
    row.get(idx)
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))
}

/// Open a connection with the production pragmas applied.
///
/// - `busy_timeout = 5000ms`: a contended lock is retried for up to 5s
///   instead of failing immediately with `SQLITE_BUSY`.
/// - `journal_mode = WAL`: concurrent readers never block the writer and
///   writes are crash-safe. WAL is a persistent journal mode stored in the
///   database file, so it survives across connections.
///
/// WAL sidecar files (`<db>-wal`, `<db>-shm`) are transient: SQLite
/// auto-checkpoints committed pages back into the main file (default
/// `wal_autocheckpoint = 1000` pages) and removes the sidecars when the
/// last connection to the database closes. The pool keeps connections for
/// the process lifetime, so the sidecars persist during the run — that is
/// normal and safe; no manual cleanup is required.
fn open_configured_connection(db_path: &str) -> io::Result<Connection> {
    let conn = Connection::open(db_path)
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
    conn.busy_timeout(BUSY_TIMEOUT)
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
    // Best-effort: if WAL is unavailable (e.g. network filesystem) SQLite
    // falls back to the default journal mode and we continue with the
    // busy_timeout safety net.
    let _ = conn.query_row("PRAGMA journal_mode=WAL", [], |r| r.get::<_, String>(0));
    Ok(conn)
}

/// Get (or lazily create) the shared, configured connection for `db_path`.
fn pooled_connection(db_path: &str) -> io::Result<Arc<Mutex<Connection>>> {
    let pool = POOL.get_or_init(|| CachePool {
        conns: Mutex::new(HashMap::new()),
    });
    let mut guard = pool.conns.lock();
    if let Some(conn) = guard.get(db_path) {
        return Ok(Arc::clone(conn));
    }
    let conn = open_configured_connection(db_path)?;
    let arc = Arc::new(Mutex::new(conn));
    guard.insert(db_path.to_string(), Arc::clone(&arc));
    Ok(arc)
}

pub fn init_cache(db_path: &str) -> io::Result<()> {
    let conn = pooled_connection(db_path)?;
    let conn = conn.lock();

    // `PRAGMA user_version` defaults to 0 on a fresh DB. A query failure
    // (extremely unlikely for this built-in pragma) is treated as version 0
    // so we fall through to the drop+recreate path.
    let current_version: i32 = conn
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .unwrap_or(0);

    if current_version != SCHEMA_VERSION {
        // Version mismatch (including first launch on a fresh DB where
        // user_version is 0): drop any existing table and recreate with the
        // current schema, then stamp the new version.
        conn.execute_batch("DROP TABLE IF EXISTS dir_cache;")
            .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
        conn.execute_batch(SCHEMA)
            .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
        conn.execute_batch(&format!("PRAGMA user_version = {};", SCHEMA_VERSION))
            .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
    } else {
        // Same version — ensure the table exists (handles the edge case
        // where user_version was set but the table was deleted externally).
        // `CREATE TABLE IF NOT EXISTS` is a no-op when the table already
        // matches the schema.
        conn.execute_batch(SCHEMA)
            .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
    }
    Ok(())
}

/// Read cached entries for `dir_path`.
///
/// Returns:
/// - `Ok(Some(entries))` — the directory is cached. `entries` may be empty
///   for a cached-but-empty directory (distinguished from "uncached" by the
///   marker row written by `cache_put`).
/// - `Ok(None)` — the directory has never been cached.
pub fn cache_get(db_path: &str, dir_path: &str) -> io::Result<Option<Vec<FileEntrySkeleton>>> {
    let conn = pooled_connection(db_path)?;
    let conn = conn.lock();

    let mut stmt = conn.prepare(
        "SELECT file_path, file_name, is_dir, is_file, is_symlink, is_hidden, extension, size, modified, created, is_system_protected
         FROM dir_cache WHERE dir_path = ?1"
    ).map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;

    let mut rows = stmt
        .query(params![dir_path])
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;

    let mut entries: Vec<FileEntrySkeleton> = Vec::new();
    let mut has_rows = false;
    while let Some(row) = rows
        .next()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?
    {
        has_rows = true;
        let path: String = row
            .get(0)
            .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
        // Skip the empty-directory marker row.
        if path == CACHED_DIR_MARKER_FILE_PATH {
            continue;
        }
        let name: String = rget(&row, 1)?;
        entries.push(FileEntrySkeleton {
            id: format!("{}:{}", name, path),
            path,
            name,
            is_dir: rget::<i32>(&row, 2)? != 0,
            is_file: rget::<i32>(&row, 3)? != 0,
            is_symlink: rget::<i32>(&row, 4)? != 0,
            is_hidden: rget::<i32>(&row, 5)? != 0,
            extension: rget(&row, 6)?,
            size: rget::<i64>(&row, 7)? as u64,
            modified: rget(&row, 8)?,
            created: rget(&row, 9)?,
            is_system_protected: rget::<i32>(&row, 10)? != 0,
            metadata_loaded: true,
        });
    }

    if has_rows {
        Ok(Some(entries))
    } else {
        Ok(None)
    }
}

pub fn cache_put(db_path: &str, dir_path: &str, entries: &[FileEntrySkeleton]) -> io::Result<()> {
    let conn = pooled_connection(db_path)?;
    let mut conn = conn.lock();

    let tx = conn
        .transaction()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;

    tx.execute("DELETE FROM dir_cache WHERE dir_path = ?1", params![dir_path])
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;

    let now = chrono::Utc::now().timestamp();

    // Marker row: records that `dir_path` has been cached even when it has
    // zero entries, so an empty directory is a cache hit rather than a miss.
    tx.execute(
        "INSERT OR REPLACE INTO dir_cache
         (dir_path, file_path, file_name, is_dir, is_file, is_symlink, is_hidden, extension, size, modified, created, is_system_protected, cached_at)
         VALUES (?1, '', '', 0, 0, 0, 0, '', 0, 0, 0, 0, ?2)",
        params![dir_path, now],
    )
    .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;

    for entry in entries {
        tx.execute(
            "INSERT OR REPLACE INTO dir_cache
             (dir_path, file_path, file_name, is_dir, is_file, is_symlink, is_hidden, extension, size, modified, created, is_system_protected, cached_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
            params![
                dir_path, entry.path, entry.name,
                entry.is_dir as i32, entry.is_file as i32, entry.is_symlink as i32,
                entry.is_hidden as i32, entry.extension, entry.size as i64,
                entry.modified, entry.created, entry.is_system_protected as i32, now
            ],
        ).map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
    }

    tx.commit()
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
    Ok(())
}

pub fn cache_invalidate(db_path: &str, dir_path: &str) -> io::Result<()> {
    let conn = pooled_connection(db_path)?;
    let conn = conn.lock();
    conn.execute("DELETE FROM dir_cache WHERE dir_path = ?1", params![dir_path])
        .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
    Ok(())
}

pub fn is_cache_fresh(db_path: &str, dir_path: &str, dir_mtime: i64) -> io::Result<bool> {
    let conn = pooled_connection(db_path)?;
    let conn = conn.lock();
    let cached_at: Option<i64> = conn.query_row(
        "SELECT MAX(cached_at) FROM dir_cache WHERE dir_path = ?1",
        params![dir_path],
        |row| row.get(0),
    ).unwrap_or(None);

    Ok(cached_at.map_or(false, |ts| ts >= dir_mtime))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    fn make_test_entry(name: &str) -> FileEntrySkeleton {
        FileEntrySkeleton {
            id: name.to_string(),
            name: name.to_string(),
            path: format!("/tmp/{}", name),
            is_dir: false,
            is_file: true,
            is_symlink: false,
            is_hidden: false,
            extension: "txt".to_string(),
            size: 100,
            modified: 1000,
            created: 900,
            is_system_protected: false,
            metadata_loaded: true,
        }
    }

    #[test]
    fn test_cache_put_and_get() {
        let tmp = NamedTempFile::new().unwrap();
        let db_path = tmp.path().to_str().unwrap();
        init_cache(db_path).unwrap();

        let entries = vec![make_test_entry("a.txt"), make_test_entry("b.txt")];
        cache_put(db_path, "/tmp", &entries).unwrap();

        let result = cache_get(db_path, "/tmp").unwrap();
        assert!(result.is_some());
        assert_eq!(result.unwrap().len(), 2);
    }

    #[test]
    fn test_cache_invalidate() {
        let tmp = NamedTempFile::new().unwrap();
        let db_path = tmp.path().to_str().unwrap();
        init_cache(db_path).unwrap();

        let entries = vec![make_test_entry("a.txt")];
        cache_put(db_path, "/tmp", &entries).unwrap();
        cache_invalidate(db_path, "/tmp").unwrap();

        let result = cache_get(db_path, "/tmp").unwrap();
        assert!(result.is_none());
    }

    #[test]
    fn test_is_cache_fresh() {
        let tmp = NamedTempFile::new().unwrap();
        let db_path = tmp.path().to_str().unwrap();
        init_cache(db_path).unwrap();

        let entries = vec![make_test_entry("a.txt")];
        cache_put(db_path, "/tmp", &entries).unwrap();

        // 缓存时间应 >= 0（1970），所以对 mtime=0 应该是 fresh
        assert!(is_cache_fresh(db_path, "/tmp", 0).unwrap());
        // mtime 远在未来，应不是 fresh
        assert!(!is_cache_fresh(db_path, "/tmp", 9999999999).unwrap());
    }

    #[test]
    fn test_init_cache_sets_user_version() {
        let tmp = NamedTempFile::new().unwrap();
        let db_path = tmp.path().to_str().unwrap();

        // First init — fresh DB (user_version defaults to 0), should drop,
        // recreate, and stamp user_version = SCHEMA_VERSION.
        init_cache(db_path).expect("first init_cache should succeed");

        let conn = Connection::open(db_path).expect("open db");
        let version: i32 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .expect("query user_version");
        assert_eq!(
            version, SCHEMA_VERSION,
            "init_cache must stamp user_version to SCHEMA_VERSION"
        );
        drop(conn);

        // Second init on the same DB — version matches, so it must be
        // idempotent (no drop, just CREATE TABLE IF NOT EXISTS) and the
        // version must remain SCHEMA_VERSION.
        init_cache(db_path).expect("second init_cache should succeed (idempotent)");

        let conn = Connection::open(db_path).expect("reopen db");
        let version: i32 = conn
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .expect("query user_version again");
        assert_eq!(
            version, SCHEMA_VERSION,
            "user_version must remain SCHEMA_VERSION after idempotent re-init"
        );

        // The table must still exist and be usable after the second init.
        let entries = vec![make_test_entry("versioned.txt")];
        cache_put(db_path, "/tmp", &entries)
            .expect("cache_put must work after idempotent re-init");
        let result = cache_get(db_path, "/tmp").expect("cache_get must work");
        assert!(result.is_some(), "entries should survive idempotent re-init");
        assert_eq!(result.unwrap().len(), 1);
    }

    #[test]
    fn test_pragma_wal_and_busy_timeout_configured() {
        let tmp = NamedTempFile::new().unwrap();
        let db_path = tmp.path().to_str().unwrap();
        init_cache(db_path).unwrap();

        let conn = pooled_connection(db_path).unwrap();
        let conn = conn.lock();

        let journal_mode: String = conn
            .query_row("PRAGMA journal_mode", [], |r| r.get(0))
            .expect("query journal_mode");
        assert_eq!(
            journal_mode, "wal",
            "pooled connections must run in WAL journal mode"
        );

        let busy_timeout_ms: i64 = conn
            .query_row("PRAGMA busy_timeout", [], |r| r.get(0))
            .expect("query busy_timeout");
        assert_eq!(
            busy_timeout_ms, 5000,
            "pooled connections must set busy_timeout = 5000ms"
        );
    }

    #[test]
    fn test_cache_empty_dir_roundtrip() {
        let tmp = NamedTempFile::new().unwrap();
        let db_path = tmp.path().to_str().unwrap();
        init_cache(db_path).unwrap();

        // A directory that has never been cached is a miss (None).
        assert!(
            cache_get(db_path, "/never_cached").unwrap().is_none(),
            "uncached directory must remain a miss"
        );

        // Caching an empty directory must be a hit with zero entries.
        cache_put(db_path, "/empty", &[]).unwrap();
        let got = cache_get(db_path, "/empty").unwrap();
        assert!(
            got.is_some(),
            "cached empty directory must be a hit, not a miss"
        );
        assert!(
            got.unwrap().is_empty(),
            "cached empty directory must yield zero entries"
        );

        // Freshness works for cached empty directories too.
        assert!(
            is_cache_fresh(db_path, "/empty", 0).unwrap(),
            "cached empty directory should be fresh for mtime=0"
        );

        // Invalidate removes the marker → back to a miss.
        cache_invalidate(db_path, "/empty").unwrap();
        assert!(
            cache_get(db_path, "/empty").unwrap().is_none(),
            "after invalidate the empty directory must be a miss again"
        );
    }

    #[test]
    fn test_concurrent_read_write_no_sqlite_busy() {
        let tmp = NamedTempFile::new().unwrap();
        let db_path = tmp.path().to_str().unwrap().to_string();
        init_cache(&db_path).unwrap();

        // 5 outer rounds × 8 threads × 10 inner rounds of mixed
        // put/get/fresh/invalidate on the same DB. Any SQLITE_BUSY would
        // surface as an Err and panic the thread.
        for _round in 0..5 {
            let db = Arc::new(db_path.clone());
            let mut handles = Vec::new();
            for t in 0..8 {
                let db = Arc::clone(&db);
                handles.push(std::thread::spawn(move || {
                    for i in 0..10 {
                        let dir = format!("/dir{}", t);
                        let entries = vec![make_test_entry(&format!("f{}-{}", t, i))];
                        cache_put(&db, &dir, &entries).expect("concurrent put must not fail");
                        let got = cache_get(&db, &dir).expect("concurrent get must not fail");
                        assert!(got.is_some(), "put entries must be readable");
                        let _ = is_cache_fresh(&db, &dir, 0).expect("fresh check must not fail");
                        cache_invalidate(&db, &dir).expect("invalidate must not fail");
                    }
                }));
            }
            for h in handles {
                h.join().expect("worker thread must not panic");
            }
        }
    }
}