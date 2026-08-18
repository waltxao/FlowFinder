//! Independent FTS5 full-text content index (Wave2 T5/T6).
//!
//! Owns a *separate* SQLite database (`content_index.sqlite`) — never the
//! directory-cache DB — and exposes a cancellable, pause-aware, resumable
//! background build over a sorted walk of the filesystem, plus a one-shot
//! FTS5 content query. Design authority: `.omo/evidence/flowfinder-v074-
//! complete-fix/task-5/content-index-contract.md`.
// allow: SIZE_OK — contract §11 mandates a single-file module owning an
// indivisible state machine (schema, FTS sync, encoding, identity, state,
// checkpoint, transactions, temp-replace, dirty set, migration, corruption).

use std::collections::HashSet;
use std::io;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use parking_lot::Mutex;
use rusqlite::{params, Connection, OptionalExtension};

use crate::core::search_engine::SearchResult;

// ── Constants ────────────────────────────────────────────────────────

/// Schema version persisted via `PRAGMA user_version`. Only ever grows;
/// migrations are additive-only (§9 of the contract).
pub const SCHEMA_VERSION: i32 = 1;

/// Maximum indexed file size (4 MiB), matching the legacy `fileContainsText`
/// cap of `4 * 1024 * 1024`.
pub const MAX_FILE_SIZE: u64 = 4 * 1024 * 1024;

/// Documents per committed batch (§10.1).
pub const BATCH_SIZE: usize = 500;

/// Lock retry window, matching `sqlite_cache::open_configured_connection`.
const BUSY_TIMEOUT: Duration = Duration::from_millis(5000);

/// Bytes sniffed for the NUL-byte binary probe (§3.3).
const SNIFF_LEN: usize = 8 * 1024;

/// Version-1 schema (§2.2). External-content FTS5 + identity table + meta.
const SCHEMA_SQL: &str = "
CREATE TABLE IF NOT EXISTS documents (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    path       TEXT    NOT NULL UNIQUE,
    mtime      INTEGER NOT NULL,
    size       INTEGER NOT NULL,
    body       TEXT    NOT NULL,
    indexed_at INTEGER NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS content_fts USING fts5(
    body,
    content='documents',
    content_rowid='id'
);
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
";

/// Indexed extensions (all compared lower-case, §3.1).
const INDEXED_EXTENSIONS: &[&str] = &[
    "txt", "md", "rtf", "json", "xml", "log", "csv", "s", "h", "c", "cpp", "hpp", "py", "rs",
    "swift", "js", "ts", "mjs", "cjs", "html", "htm", "css", "yaml", "yml", "toml", "ini", "cfg",
    "conf", "plist", "sh", "zsh", "bash", "sql", "java", "kt", "go", "rb", "php", "lua", "m", "mm",
    "pl", "tex", "rst", "adoc", "org", "env", "properties", "gradle",
];

/// Extension-less known text basenames (lower-case, §3.1).
const KNOWN_TEXT_BASENAMES: &[&str] = &[
    "readme", "license", "makefile", "dockerfile", "gitignore", "gitattributes", "editorconfig",
];

// ── State machine ────────────────────────────────────────────────────

/// Content-index lifecycle status (§6).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    /// No indexed data (first launch / pre-rebuild / after clear).
    Empty = 0,
    /// Build in progress (paused builds stay here; see stats `paused`).
    Indexing = 1,
    /// Ready: queryable.
    Ready = 2,
    /// Build / init failed (generic).
    Error = 3,
    /// Build cancelled by the user; checkpoint retained.
    Cancelled = 4,
    /// Terminal: FTS5 not compiled into the SQLite build.
    Unavailable = 5,
}

impl Status {
    pub fn as_c_int(self) -> i32 {
        self as i32
    }
}

/// Build mode for `ff_content_index_start` (§8.1).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Incremental = 0,
    Rebuild = 1,
}

impl Mode {
    pub fn from_int(v: i32) -> Option<Mode> {
        match v {
            0 => Some(Mode::Incremental),
            1 => Some(Mode::Rebuild),
            _ => None,
        }
    }
}

/// Outcome of a finished build.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BuildOutcome {
    Completed,
    Cancelled,
    Failed,
}

/// Typed error for the module.
#[derive(Debug)]
pub enum ContentIndexError {
    Sqlite(rusqlite::Error),
    Io(io::Error),
    BuildInProgress,
    Unavailable,
    NotReady,
}

impl std::fmt::Display for ContentIndexError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ContentIndexError::Sqlite(e) => write!(f, "sqlite: {}", e),
            ContentIndexError::Io(e) => write!(f, "io: {}", e),
            ContentIndexError::BuildInProgress => write!(f, "build already in progress"),
            ContentIndexError::Unavailable => write!(f, "content search unavailable (FTS5 missing)"),
            ContentIndexError::NotReady => write!(f, "content index not ready"),
        }
    }
}

impl std::error::Error for ContentIndexError {}

impl From<rusqlite::Error> for ContentIndexError {
    fn from(e: rusqlite::Error) -> Self {
        ContentIndexError::Sqlite(e)
    }
}

impl From<io::Error> for ContentIndexError {
    fn from(e: io::Error) -> Self {
        ContentIndexError::Io(e)
    }
}

// ── Global state ─────────────────────────────────────────────────────

static STATUS: Mutex<Status> = Mutex::new(Status::Empty);
static DIRTY: std::sync::LazyLock<Mutex<HashSet<String>>> =
    std::sync::LazyLock::new(|| Mutex::new(HashSet::new()));
static ERROR_MSG: Mutex<Option<String>> = Mutex::new(None);

/// Progress / persistence snapshot exposed by `stats_json` (§7.3). Kept in
/// sync with the `meta` table so `stats` needs no DB access.
#[derive(Debug, Clone, Default)]
struct BuildState {
    paused: bool,
    processed: u64,
    total_candidates: u64,
    document_count: u64,
    checkpoint_path: Option<String>,
    last_build_at: Option<i64>,
    root_path: Option<String>,
}

static BUILD_STATE: Mutex<BuildState> = Mutex::new(BuildState {
    paused: false,
    processed: 0,
    total_candidates: 0,
    document_count: 0,
    checkpoint_path: None,
    last_build_at: None,
    root_path: None,
});

// ── Document operations ──────────────────────────────────────────────

/// A pending write to `documents` + `content_fts`.
enum DocOp {
    /// Insert or update (update = delete-then-insert, preserving FTS link).
    Upsert {
        path: String,
        mtime: i64,
        size: u64,
        body: String,
        old: Option<(i64, String)>,
    },
    /// Remove a document (file deleted).
    Delete { id: i64, body: String },
}

/// A candidate file discovered during the walk.
struct Candidate {
    path: String,
    mtime: i64,
    size: u64,
}

// ── Public API ───────────────────────────────────────────────────────

/// Initialize (or re-assert) the content index at `db_path`.
///
/// Handles FTS5 runtime detection (§2.5), corruption backup + rebuild
/// (§9.3), version migration (§9.2) and leftover temp-file cleanup
/// (§10.3). On success the status is set to `Empty`, `Ready`, or
/// `Unavailable`; a fatal failure sets `Error` and returns `Err`.
pub fn init(db_path: &str) -> Result<(), ContentIndexError> {
    cleanup_tmp_files(db_path);
    match open_and_init(db_path) {
        Ok(()) => Ok(()),
        Err(InitFailure::Corrupt) => {
            recover_corrupt(db_path)?;
            // Fresh empty DB after recovery — await a full rebuild.
            set_status(Status::Empty);
            set_error_msg(None);
            Ok(())
        }
        Err(InitFailure::Fatal(e)) => {
            set_error_msg(Some(e.to_string()));
            set_status(Status::Error);
            Err(e)
        }
    }
}

/// Current lifecycle status.
pub fn status() -> Status {
    *STATUS.lock()
}

/// Mark a path dirty (O(1), no I/O). Cleared by the next build.
pub fn mark_dirty(path: &str) {
    DIRTY.lock().insert(path.to_string());
}

/// Begin a build synchronously: validate the current status and flip to
/// `Indexing`. Returns the *prior* status so the caller (or `run_build`)
/// can branch on it (e.g. resume-from-cancelled vs fresh walk).
pub fn begin_build() -> Result<Status, ContentIndexError> {
    let mut s = STATUS.lock();
    match *s {
        Status::Unavailable => Err(ContentIndexError::Unavailable),
        Status::Indexing => Err(ContentIndexError::BuildInProgress),
        prior => {
            *s = Status::Indexing;
            Ok(prior)
        }
    }
}

/// Run a build to completion and finalize the status. `prior` is the status
/// captured by `begin_build` before it flipped to `Indexing`.
pub fn run_build(
    db_path: &str,
    root: &str,
    mode: Mode,
    prior: Status,
    cancel: &AtomicBool,
    pause: &AtomicBool,
) -> BuildOutcome {
    {
        let mut st = BUILD_STATE.lock();
        st.paused = false;
        st.processed = 0;
        st.total_candidates = 0;
        st.root_path = Some(root.to_string());
    }

    let result = match mode {
        Mode::Rebuild => rebuild(db_path, root, cancel, pause),
        Mode::Incremental => incremental(db_path, root, prior, cancel, pause),
    };

    let outcome = match result {
        Ok(BuildResult::Completed) => {
            finalize_success(db_path, root);
            set_status(Status::Ready);
            BuildOutcome::Completed
        }
        Ok(BuildResult::Cancelled) => {
            set_status(Status::Cancelled);
            BuildOutcome::Cancelled
        }
        Err(e) => {
            set_error_msg(Some(e.to_string()));
            set_status(Status::Error);
            BuildOutcome::Failed
        }
    };

    {
        let mut st = BUILD_STATE.lock();
        st.paused = false;
        st.processed = 0;
        st.total_candidates = 0;
    }
    outcome
}

/// Stats JSON (§7.3). The caller frees the returned string.
pub fn stats_json() -> String {
    let status = *STATUS.lock();
    let st = BUILD_STATE.lock().clone();
    let mut map = serde_json::Map::new();
    map.insert("status".to_string(), serde_json::json!(status.as_c_int()));
    map.insert("paused".to_string(), serde_json::json!(st.paused));
    map.insert("document_count".to_string(), serde_json::json!(st.document_count));
    map.insert("total_candidates".to_string(), serde_json::json!(st.total_candidates));
    map.insert("processed".to_string(), serde_json::json!(st.processed));
    map.insert(
        "checkpoint_path".to_string(),
        serde_json::json!(st.checkpoint_path),
    );
    map.insert("last_build_at".to_string(), serde_json::json!(st.last_build_at));
    map.insert("root_path".to_string(), serde_json::json!(st.root_path));
    if status == Status::Error {
        if let Some(e) = ERROR_MSG.lock().clone() {
            map.insert("error".to_string(), serde_json::json!(e));
        }
    }
    serde_json::Value::Object(map).to_string()
}

/// Run a content query (§2.4). Only valid when the index is `Ready` (the
/// FFI layer enforces this; callers should too). Results are delivered via
/// `cb` in rank order.
pub fn query(
    db_path: &str,
    query: &str,
    max_results: usize,
    cb: &mut dyn FnMut(SearchResult),
) -> Result<(), ContentIndexError> {
    let conn = open_configured(db_path)?;
    let mut stmt = conn.prepare(
        "SELECT d.path, d.mtime, d.size
         FROM content_fts
         JOIN documents d ON d.id = content_fts.rowid
         WHERE content_fts MATCH ?1
         ORDER BY rank
         LIMIT ?2",
    )?;
    let rows = stmt.query_map(params![query, max_results as i64], |r| {
        Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?))
    })?;
    for row in rows {
        let (path, mtime, size) = row?;
        let name = Path::new(&path)
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_default();
        cb(SearchResult {
            path,
            name,
            size: size as u64,
            modified: mtime,
            is_dir: false,
        });
    }
    Ok(())
}

// ── Init internals ───────────────────────────────────────────────────

enum InitFailure {
    Corrupt,
    Fatal(ContentIndexError),
}

fn open_and_init(db_path: &str) -> Result<(), InitFailure> {
    let conn = open_configured(db_path).map_err(|e| {
        if is_corruption(&e) {
            InitFailure::Corrupt
        } else {
            InitFailure::Fatal(e)
        }
    })?;

    // FTS5 runtime detection (§2.5): terminal `unavailable` if missing.
    if !has_fts5(&conn).map_err(InitFailure::Fatal)? {
        set_status(Status::Unavailable);
        set_error_msg(None);
        return Ok(());
    }

    let version = read_user_version(&conn).map_err(|_| InitFailure::Corrupt)?;

    if version > SCHEMA_VERSION {
        // Future version written by newer code: leave the DB untouched
        // (§9.2) and only report readiness from the surviving columns.
        let count = doc_count(&conn).unwrap_or(0);
        set_status(if count > 0 { Status::Ready } else { Status::Empty });
        set_error_msg(None);
        load_build_state(&conn);
        return Ok(());
    }

    if !integrity_ok(&conn) {
        return Err(InitFailure::Corrupt);
    }

    // version 0 (fresh) or 1 (current): create idempotently, stamp version.
    create_schema(&conn).map_err(InitFailure::Fatal)?;
    let count = doc_count(&conn).unwrap_or(0);
    set_status(if count > 0 { Status::Ready } else { Status::Empty });
    set_error_msg(None);
    load_build_state(&conn);
    Ok(())
}

/// Open a connection with WAL + busy_timeout (§10.2).
fn open_configured(db_path: &str) -> Result<Connection, ContentIndexError> {
    let conn = Connection::open(db_path)?;
    conn.busy_timeout(BUSY_TIMEOUT)?;
    let _ = conn.query_row("PRAGMA journal_mode=WAL", [], |r| r.get::<_, String>(0));
    Ok(conn)
}

fn create_schema(conn: &Connection) -> Result<(), ContentIndexError> {
    conn.execute_batch(SCHEMA_SQL)?;
    conn.execute_batch(&format!("PRAGMA user_version = {};", SCHEMA_VERSION))?;
    Ok(())
}

fn has_fts5(conn: &Connection) -> Result<bool, ContentIndexError> {
    let mut stmt = conn.prepare("PRAGMA compile_options")?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let opt: String = row.get(0)?;
        if opt == "ENABLE_FTS5" {
            return Ok(true);
        }
    }
    Ok(false)
}

fn integrity_ok(conn: &Connection) -> bool {
    conn.query_row("PRAGMA integrity_check", [], |r| r.get::<_, String>(0))
        .map(|s| s == "ok")
        .unwrap_or(false)
}

fn read_user_version(conn: &Connection) -> Result<i32, ContentIndexError> {
    Ok(conn.query_row("PRAGMA user_version", [], |r| r.get(0))?)
}

fn doc_count(conn: &Connection) -> Result<u64, ContentIndexError> {
    Ok(conn.query_row("SELECT COUNT(*) FROM documents", [], |r| r.get::<_, i64>(0))? as u64)
}

fn is_corruption(e: &ContentIndexError) -> bool {
    match e {
        ContentIndexError::Sqlite(rusqlite::Error::SqliteFailure(ffi, _)) => matches!(
            ffi.code,
            rusqlite::ErrorCode::NotADatabase | rusqlite::ErrorCode::DatabaseCorrupt
        ),
        _ => false,
    }
}

/// Backup the corrupt DB and recreate a fresh schema at the same path (§9.3).
fn recover_corrupt(db_path: &str) -> Result<(), ContentIndexError> {
    let path = Path::new(db_path);
    if path.exists() {
        let backup = format!("{}.corrupt-{}", db_path, chrono::Utc::now().timestamp());
        std::fs::rename(db_path, &backup)?;
        // Stale WAL/SHM sidecars reference the old main file.
        let _ = std::fs::remove_file(format!("{}-wal", db_path));
        let _ = std::fs::remove_file(format!("{}-shm", db_path));
    }
    let conn = open_configured(db_path)?;
    create_schema(&conn)?;
    Ok(())
}

/// Remove leftover `*.tmp-*` files from a previous crashed build (§10.3).
fn cleanup_tmp_files(db_path: &str) {
    let path = Path::new(db_path);
    let fname = path
        .file_name()
        .map(|f| f.to_string_lossy().to_string())
        .unwrap_or_default();
    let prefix = format!("{}.tmp-", fname);
    if let Some(dir) = path.parent() {
        if let Ok(entries) = std::fs::read_dir(dir) {
            for e in entries.flatten() {
                if e.file_name().to_string_lossy().starts_with(&prefix) {
                    let _ = std::fs::remove_file(e.path());
                }
            }
        }
    }
}

fn tmp_path(db_path: &str) -> String {
    format!("{}.tmp-{}", db_path, std::process::id())
}

fn load_build_state(conn: &Connection) {
    let mut st = BUILD_STATE.lock();
    st.document_count = read_meta(conn, "document_count")
        .ok()
        .flatten()
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(0);
    st.checkpoint_path = read_meta(conn, "checkpoint_path").ok().flatten();
    st.last_build_at = read_meta(conn, "last_build_at")
        .ok()
        .flatten()
        .and_then(|v| v.parse::<i64>().ok());
    st.root_path = read_meta(conn, "root_path").ok().flatten();
}

fn read_meta(conn: &Connection, key: &str) -> Result<Option<String>, ContentIndexError> {
    Ok(conn
        .query_row("SELECT value FROM meta WHERE key = ?1", params![key], |r| {
            r.get::<_, String>(0)
        })
        .optional()?)
}

fn upsert_meta(conn: &Connection, key: &str, value: &str) -> Result<(), ContentIndexError> {
    conn.execute(
        "INSERT INTO meta(key, value) VALUES(?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![key, value],
    )?;
    Ok(())
}

// ── Build internals ──────────────────────────────────────────────────

enum BuildResult {
    Completed,
    Cancelled,
}

/// Full rebuild: temp DB + atomic rename (§10.3).
fn rebuild(
    db_path: &str,
    root: &str,
    cancel: &AtomicBool,
    pause: &AtomicBool,
) -> Result<BuildResult, ContentIndexError> {
    ensure_root_dir(root)?;
    let tmp = tmp_path(db_path);
    let _ = std::fs::remove_file(&tmp);
    let mut conn = open_configured(&tmp)?;
    create_schema(&conn)?;
    BUILD_STATE.lock().document_count = 0;

    let result = index_tree(&mut conn, root, cancel, pause, None);

    match result {
        Ok(BuildResult::Completed) => {
            drop(conn);
            std::fs::rename(&tmp, db_path)?;
            Ok(BuildResult::Completed)
        }
        Ok(BuildResult::Cancelled) => {
            drop(conn);
            // Delete the temp file; the live DB stays at the old version
            // (§10.3).
            let _ = std::fs::remove_file(&tmp);
            Ok(BuildResult::Cancelled)
        }
        Err(e) => {
            drop(conn);
            let _ = std::fs::remove_file(&tmp);
            Err(e)
        }
    }
}

/// Incremental / resume / degrade build on the live DB (§5.3, §5.4, §7.2).
fn incremental(
    db_path: &str,
    root: &str,
    prior: Status,
    cancel: &AtomicBool,
    pause: &AtomicBool,
) -> Result<BuildResult, ContentIndexError> {
    let dirty: Vec<String> = DIRTY.lock().drain().collect();

    match prior {
        Status::Cancelled => {
            // Resume from the checkpoint cursor on the live DB (§7.2).
            ensure_root_dir(root)?;
            let mut conn = open_configured(db_path)?;
            BUILD_STATE.lock().document_count = doc_count(&conn)?;
            let checkpoint = read_meta(&conn, "checkpoint_path")?.and_then(|v| {
                if v.is_empty() {
                    None
                } else {
                    Some(v)
                }
            });
            index_tree(&mut conn, root, cancel, pause, checkpoint.as_deref())
        }
        Status::Ready | Status::Empty if !dirty.is_empty() => {
            // Process only the dirty paths (§5.3).
            let mut conn = open_configured(db_path)?;
            BUILD_STATE.lock().document_count = doc_count(&conn)?;
            process_dirty(&mut conn, &dirty, cancel, pause)
        }
        Status::Ready => {
            // Already complete. Without an active watcher we cannot know what
            // changed, so degrade to a full rebuild (§5.4); otherwise no-op.
            if watcher_active() {
                Ok(BuildResult::Completed)
            } else {
                rebuild(db_path, root, cancel, pause)
            }
        }
        Status::Empty => {
            // First build: full walk on the live DB (cancellable, resumable).
            ensure_root_dir(root)?;
            let mut conn = open_configured(db_path)?;
            BUILD_STATE.lock().document_count = doc_count(&conn)?;
            index_tree(&mut conn, root, cancel, pause, None)
        }
        Status::Error => {
            // Retry (§6.1): a fresh temp DB naturally recovers corruption.
            rebuild(db_path, root, cancel, pause)
        }
        Status::Indexing | Status::Unavailable => {
            // Unreachable: begin_build rejects these before run_build.
            Ok(BuildResult::Completed)
        }
    }
}

/// Sort-canonical walk + batched, checkpointed indexing (§7.2, §10.1).
fn index_tree(
    conn: &mut Connection,
    root: &str,
    cancel: &AtomicBool,
    pause: &AtomicBool,
    skip_up_to: Option<&str>,
) -> Result<BuildResult, ContentIndexError> {
    let mut candidates = collect_candidates(root);
    candidates.sort_by(|a, b| a.path.cmp(&b.path));
    BUILD_STATE.lock().total_candidates = candidates.len() as u64;

    let mut batch: Vec<DocOp> = Vec::new();
    let mut processed = 0u64;
    let mut last_path: Option<String> = None;

    for cand in &candidates {
        // Skip files already committed at-or-before the checkpoint (§7.2).
        if skip_up_to.is_some_and(|ck| cand.path.as_str() <= ck) {
            processed += 1;
            BUILD_STATE.lock().processed = processed;
            continue;
        }

        pause_wait(cancel, pause);

        if cancel.load(Ordering::Relaxed) {
            if !batch.is_empty() {
                let cp = last_path.clone().unwrap_or_else(|| cand.path.clone());
                commit_docs(conn, &batch, &cp)?;
            }
            return Ok(BuildResult::Cancelled);
        }

        if let Some(op) = prepare_doc(conn, &cand.path, cand.mtime, cand.size)? {
            batch.push(op);
        }
        processed += 1;
        last_path = Some(cand.path.clone());
        BUILD_STATE.lock().processed = processed;

        // Cooperative cancel between files and before the batch commit (§7.1).
        if cancel.load(Ordering::Relaxed) {
            if !batch.is_empty() {
                commit_docs(conn, &batch, &cand.path)?;
            }
            return Ok(BuildResult::Cancelled);
        }

        if batch.len() >= BATCH_SIZE {
            commit_docs(conn, &batch, &cand.path)?;
            batch.clear();
        }
    }

    if !batch.is_empty() {
        let cp = last_path.unwrap_or_default();
        commit_docs(conn, &batch, &cp)?;
    }

    Ok(BuildResult::Completed)
}

/// Incremental dirty-path processing on the live DB (§5.3, §10.4).
fn process_dirty(
    conn: &mut Connection,
    dirty: &[String],
    cancel: &AtomicBool,
    pause: &AtomicBool,
) -> Result<BuildResult, ContentIndexError> {
    BUILD_STATE.lock().total_candidates = dirty.len() as u64;
    let mut ops: Vec<DocOp> = Vec::new();
    let mut processed = 0u64;

    for path in dirty {
        pause_wait(cancel, pause);
        if cancel.load(Ordering::Relaxed) {
            if !ops.is_empty() {
                commit_docs(conn, &ops, path)?;
            }
            return Ok(BuildResult::Cancelled);
        }

        match std::fs::metadata(path) {
            Ok(m) if m.is_file() => {
                let mtime = mtime_secs(&m);
                let size = m.len();
                if size <= MAX_FILE_SIZE && is_indexable_path(path) {
                    if let Some(op) = prepare_doc(conn, path, mtime, size)? {
                        ops.push(op);
                    }
                } else if let Some((id, body)) = existing_doc(conn, path)? {
                    // File became non-indexable (oversize/binary/other ext):
                    // drop its stale entry.
                    ops.push(DocOp::Delete { id, body });
                }
            }
            Ok(_) => {
                // Directory or symlink: nothing to index.
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                if let Some((id, body)) = existing_doc(conn, path)? {
                    ops.push(DocOp::Delete { id, body });
                }
            }
            Err(_) => {
                // Unreadable: skip, don't fail the whole build (§12).
            }
        }

        processed += 1;
        BUILD_STATE.lock().processed = processed;

        if cancel.load(Ordering::Relaxed) {
            if !ops.is_empty() {
                commit_docs(conn, &ops, path)?;
            }
            return Ok(BuildResult::Cancelled);
        }

        if ops.len() >= BATCH_SIZE {
            commit_docs(conn, &ops, path)?;
            ops.clear();
        }
    }

    if !ops.is_empty() {
        let last = dirty.last().cloned().unwrap_or_default();
        commit_docs(conn, &ops, &last)?;
    }

    Ok(BuildResult::Completed)
}

/// Identity check (§4) + body extraction. Returns the write op, or `None`
/// when the file is up-to-date or unreadable (skip).
fn prepare_doc(
    conn: &Connection,
    path: &str,
    mtime: i64,
    size: u64,
) -> Result<Option<DocOp>, ContentIndexError> {
    let existing = conn
        .query_row(
            "SELECT id, mtime, size, body FROM documents WHERE path = ?1",
            params![path],
            |r| {
                Ok((
                    r.get::<_, i64>(0)?,
                    r.get::<_, i64>(1)?,
                    r.get::<_, i64>(2)?,
                    r.get::<_, String>(3)?,
                ))
            },
        )
        .optional()?;

    match existing {
        Some((_id, dm, ds, _body)) if dm == mtime && ds == size as i64 => Ok(None),
        Some((id, _, _, body)) => Ok(read_body(path, size).map(|new_body| DocOp::Upsert {
            path: path.to_string(),
            mtime,
            size,
            body: new_body,
            old: Some((id, body)),
        })),
        None => Ok(read_body(path, size).map(|new_body| DocOp::Upsert {
            path: path.to_string(),
            mtime,
            size,
            body: new_body,
            old: None,
        })),
    }
}

fn existing_doc(conn: &Connection, path: &str) -> Result<Option<(i64, String)>, ContentIndexError> {
    Ok(conn
        .query_row(
            "SELECT id, body FROM documents WHERE path = ?1",
            params![path],
            |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)),
        )
        .optional()?)
}

/// Commit a batch in one transaction, keeping `documents` + `content_fts`
/// in sync (§2.3) and advancing `checkpoint_path` (§10.1).
fn commit_docs(
    conn: &mut Connection,
    ops: &[DocOp],
    checkpoint: &str,
) -> Result<(), ContentIndexError> {
    let tx = conn.transaction()?;
    let mut delta: i64 = 0;

    for op in ops {
        match op {
            DocOp::Upsert {
                path,
                mtime,
                size,
                body,
                old,
            } => {
                if let Some((id, old_body)) = old {
                    tx.execute(
                        "INSERT INTO content_fts(content_fts, rowid, body) VALUES('delete', ?1, ?2)",
                        params![id, old_body],
                    )?;
                    tx.execute("DELETE FROM documents WHERE id = ?1", params![id])?;
                } else {
                    delta += 1;
                }
                tx.execute(
                    "INSERT INTO documents(path, mtime, size, body, indexed_at) VALUES(?1, ?2, ?3, ?4, ?5)",
                    params![path, mtime, *size as i64, body, chrono::Utc::now().timestamp()],
                )?;
                let id = tx.last_insert_rowid();
                tx.execute(
                    "INSERT INTO content_fts(rowid, body) VALUES(?1, ?2)",
                    params![id, body],
                )?;
            }
            DocOp::Delete { id, body } => {
                tx.execute(
                    "INSERT INTO content_fts(content_fts, rowid, body) VALUES('delete', ?1, ?2)",
                    params![id, body],
                )?;
                tx.execute("DELETE FROM documents WHERE id = ?1", params![id])?;
                delta -= 1;
            }
        }
    }

    tx.execute(
        "INSERT INTO meta(key, value) VALUES('checkpoint_path', ?1)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![checkpoint],
    )?;

    tx.commit()?;

    let mut st = BUILD_STATE.lock();
    st.document_count = (st.document_count as i64 + delta).max(0) as u64;
    st.checkpoint_path = Some(checkpoint.to_string());
    drop(st);
    Ok(())
}

/// Persist the final build snapshot into `meta` (§7.3).
fn finalize_success(db_path: &str, root: &str) {
    if let Ok(conn) = open_configured(db_path) {
        let now = chrono::Utc::now().timestamp();
        let _ = upsert_meta(&conn, "last_build_at", &now.to_string());
        let _ = upsert_meta(
            &conn,
            "document_count",
            &BUILD_STATE.lock().document_count.to_string(),
        );
        let _ = upsert_meta(&conn, "root_path", root);
    }
    let mut st = BUILD_STATE.lock();
    st.last_build_at = Some(chrono::Utc::now().timestamp());
    st.root_path = Some(root.to_string());
    drop(st);
}

fn ensure_root_dir(root: &str) -> Result<(), ContentIndexError> {
    match std::fs::metadata(root) {
        Ok(m) if m.is_dir() => Ok(()),
        Ok(_) => Err(ContentIndexError::Io(io::Error::new(
            io::ErrorKind::InvalidInput,
            "root is not a directory",
        ))),
        Err(e) => Err(ContentIndexError::Io(e)),
    }
}

fn watcher_active() -> bool {
    crate::core::fsevents::status() == crate::core::fsevents::WatcherStatus::Active
}

/// Block while the pause flag is set (checked at batch boundaries §6.3).
/// Breaks early if cancelled while paused so the caller's cancel check runs.
fn pause_wait(cancel: &AtomicBool, pause: &AtomicBool) {
    while pause.load(Ordering::Relaxed) {
        BUILD_STATE.lock().paused = true;
        std::thread::sleep(Duration::from_millis(10));
        if cancel.load(Ordering::Relaxed) {
            break;
        }
    }
    BUILD_STATE.lock().paused = false;
}

// ── Walk & candidates ────────────────────────────────────────────────

fn collect_candidates(root: &str) -> Vec<Candidate> {
    let mut out = Vec::new();
    for entry in walkdir::WalkDir::new(root)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        let ft = entry.file_type();
        if !ft.is_file() || ft.is_symlink() {
            continue;
        }
        if entry.file_name().to_string_lossy().starts_with('.') {
            continue;
        }
        let path = entry.path().to_string_lossy().to_string();
        if crate::core::utils::is_system_protected_path(&path) {
            continue;
        }
        if !is_indexable_path(&path) {
            continue;
        }
        let meta = match entry.metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };
        let size = meta.len();
        if size > MAX_FILE_SIZE {
            continue;
        }
        out.push(Candidate {
            path,
            mtime: mtime_secs(&meta),
            size,
        });
    }
    out
}

fn mtime_secs(m: &std::fs::Metadata) -> i64 {
    m.modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Extension allowlist + known basenames (§3.1), all lower-case.
fn is_indexable_path(path: &str) -> bool {
    let p = Path::new(path);
    let name = p
        .file_name()
        .map(|s| s.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    if KNOWN_TEXT_BASENAMES.contains(&name.as_str()) {
        return true;
    }
    match p.extension() {
        Some(ext) => INDEXED_EXTENSIONS.contains(&ext.to_string_lossy().to_lowercase().as_str()),
        None => false,
    }
}

// ── Body extraction & decoding ───────────────────────────────────────

/// Read + decode a candidate file's body, or `None` when it is binary
/// (NUL byte in the first 8 KiB §3.3) or unreadable.
fn read_body(path: &str, size: u64) -> Option<String> {
    if size > MAX_FILE_SIZE {
        return None;
    }
    let bytes = std::fs::read(path).ok()?;
    let sniff_len = bytes.len().min(SNIFF_LEN);
    if bytes[..sniff_len].contains(&0u8) {
        return None;
    }
    Some(decode_text(&bytes))
}

/// Encoding probe order (§3.4): BOM → UTF-8 strict → UTF-16 (BOM only) →
/// Latin-1 fallback. Never panics.
fn decode_text(bytes: &[u8]) -> String {
    if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
        return decode_utf8_or_latin1(&bytes[3..]);
    }
    if bytes.starts_with(&[0xFF, 0xFE]) {
        return decode_utf16_le(&bytes[2..]);
    }
    if bytes.starts_with(&[0xFE, 0xFF]) {
        return decode_utf16_be(&bytes[2..]);
    }
    decode_utf8_or_latin1(bytes)
}

fn decode_utf8_or_latin1(bytes: &[u8]) -> String {
    match std::str::from_utf8(bytes) {
        Ok(s) => s.to_string(),
        Err(_) => bytes.iter().map(|&b| b as char).collect(),
    }
}

fn decode_utf16_le(bytes: &[u8]) -> String {
    let units: Vec<u16> = bytes
        .chunks_exact(2)
        .map(|c| u16::from_le_bytes([c[0], c[1]]))
        .collect();
    String::from_utf16_lossy(&units)
}

fn decode_utf16_be(bytes: &[u8]) -> String {
    let units: Vec<u16> = bytes
        .chunks_exact(2)
        .map(|c| u16::from_be_bytes([c[0], c[1]]))
        .collect();
    String::from_utf16_lossy(&units)
}

fn set_status(s: Status) {
    *STATUS.lock() = s;
}

fn set_error_msg(msg: Option<String>) {
    *ERROR_MSG.lock() = msg;
}

// ── Test helpers (shared lock serializes all global-state tests) ─────

#[cfg(test)]
pub(crate) static CONTENT_INDEX_TEST_LOCK: Mutex<()> = Mutex::new(());

#[cfg(test)]
pub(crate) fn reset_for_test() {
    *STATUS.lock() = Status::Empty;
    DIRTY.lock().clear();
    *ERROR_MSG.lock() = None;
    *BUILD_STATE.lock() = BuildState::default();
}

#[cfg(test)]
pub(crate) fn set_status_for_test(s: Status) {
    set_status(s);
}

#[cfg(test)]
pub(crate) fn build_for_test(
    db_path: &str,
    root: &str,
    mode: Mode,
    cancel: &AtomicBool,
    pause: &AtomicBool,
) -> BuildOutcome {
    let prior = begin_build().expect("begin_build should succeed in tests");
    run_build(db_path, root, mode, prior, cancel, pause)
}

#[cfg(test)]
pub(crate) fn is_paused_for_test() -> bool {
    BUILD_STATE.lock().paused
}

#[cfg(test)]
pub(crate) fn processed_for_test() -> u64 {
    BUILD_STATE.lock().processed
}

#[cfg(test)]
pub(crate) fn scratch_dir(prefix: &str) -> tempfile::TempDir {
    // tempfile's default macOS location (/var/folders/...) is system-
    // protected by our own filter; create under target/ instead.
    let base = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("target")
        .join("content-index-tests");
    std::fs::create_dir_all(&base).unwrap();
    tempfile::Builder::new()
        .prefix(prefix)
        .tempdir_in(&base)
        .unwrap()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicBool as TestBool, Ordering as TestOrdering};

    fn lock() -> parking_lot::MutexGuard<'static, ()> {
        CONTENT_INDEX_TEST_LOCK.lock()
    }

    fn tmp_db() -> (tempfile::TempDir, String) {
        let dir = scratch_dir("db");
        let db = dir.path().join("content_index.sqlite");
        let db_path = db.to_string_lossy().to_string();
        (dir, db_path)
    }

    fn write_file(dir: &Path, name: &str, contents: &[u8]) -> String {
        let p = dir.join(name);
        std::fs::write(&p, contents).unwrap();
        p.to_string_lossy().to_string()
    }

    fn run_query(db: &str, q: &str) -> Vec<String> {
        let mut out = Vec::new();
        query(db, q, 500, &mut |r| out.push(r.path)).unwrap();
        out
    }

    // ── Schema / FTS5 ──────────────────────────────────────────────

    #[test]
    fn test_schema_created_and_user_version_stamped() {
        let _g = lock();
        reset_for_test();
        let (_d, db) = tmp_db();
        init(&db).unwrap();
        assert_eq!(status(), Status::Empty);

        let conn = Connection::open(&db).unwrap();
        let version: i32 = conn.query_row("PRAGMA user_version", [], |r| r.get(0)).unwrap();
        assert_eq!(version, SCHEMA_VERSION);

        // Tables exist.
        for table in ["documents", "content_fts", "meta"] {
            let n: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type IN ('table','virtual table') AND name = ?1",
                    params![table],
                    |r| r.get(0),
                )
                .unwrap();
            assert_eq!(n, 1, "table {} must exist", table);
        }
    }

    #[test]
    fn test_fts5_available_in_bundled_sqlite() {
        let _g = lock();
        let (_d, db) = tmp_db();
        let conn = open_configured(&db).unwrap();
        assert!(has_fts5(&conn).unwrap(), "bundled SQLite must expose FTS5");
    }

    #[test]
    fn test_init_idempotent_preserves_data() {
        let _g = lock();
        reset_for_test();
        let (_d, db) = tmp_db();
        init(&db).unwrap();
        // Second init must not drop data or change version.
        let conn = Connection::open(&db).unwrap();
        conn.execute(
            "INSERT INTO documents(path, mtime, size, body, indexed_at) VALUES('x', 1, 1, 'hello', 1)",
            [],
        )
        .unwrap();
        drop(conn);

        init(&db).unwrap();
        let conn = Connection::open(&db).unwrap();
        let n: i64 = conn.query_row("SELECT COUNT(*) FROM documents", [], |r| r.get(0)).unwrap();
        assert_eq!(n, 1, "idempotent re-init must not drop documents");
    }

    // ── Encoding ────────────────────────────────────────────────────

    #[test]
    fn test_decode_utf8_bom() {
        let mut v = vec![0xEF, 0xBB, 0xBF];
        v.extend_from_slice("héllo".as_bytes());
        assert_eq!(decode_text(&v), "héllo");
    }

    #[test]
    fn test_decode_utf16_le_bom() {
        let mut v = vec![0xFF, 0xFE];
        for u in "hi".encode_utf16() {
            v.extend_from_slice(&u.to_le_bytes());
        }
        assert_eq!(decode_text(&v), "hi");
    }

    #[test]
    fn test_decode_utf16_be_bom() {
        let mut v = vec![0xFE, 0xFF];
        for u in "hi".encode_utf16() {
            v.extend_from_slice(&u.to_be_bytes());
        }
        assert_eq!(decode_text(&v), "hi");
    }

    #[test]
    fn test_decode_latin1_fallback() {
        let bytes = vec![0xE9, 0x20, 0xFF]; // 0xE9 alone is invalid UTF-8
        assert_eq!(decode_text(&bytes), "é ÿ");
    }

    #[test]
    fn test_decode_utf8_strict() {
        assert_eq!(decode_text("plain ascii".as_bytes()), "plain ascii");
    }

    // ── Allowlist / bounds ──────────────────────────────────────────

    #[test]
    fn test_is_indexable_allowlist() {
        assert!(is_indexable_path("/a/b/file.md"));
        assert!(is_indexable_path("/a/b/file.TXT"));
        assert!(is_indexable_path("/a/b/README"));
        assert!(is_indexable_path("/a/b/Dockerfile"));
        assert!(!is_indexable_path("/a/b/file.pdf"));
        assert!(!is_indexable_path("/a/b/file.docx"));
        assert!(!is_indexable_path("/a/b/noextension"));
    }

    #[test]
    fn test_oversize_and_binary_skipped() {
        let _g = lock();
        reset_for_test();
        let (_d, db) = tmp_db();
        let dir = scratch_dir("t");
        init(&db).unwrap();

        // > 4 MiB file.
        let big = dir.path().join("big.txt");
        std::fs::write(&big, vec![b'a'; (MAX_FILE_SIZE + 1) as usize]).unwrap();
        // Binary (NUL in first 8 KiB).
        let bin = dir.path().join("bin.txt");
        let mut binbytes = vec![b'x'; SNIFF_LEN + 10];
        binbytes[100] = 0;
        std::fs::write(&bin, binbytes).unwrap();
        // Normal text file.
        write_file(dir.path(), "ok.txt", b"hello world");

        let cancel = TestBool::new(false);
        let pause = TestBool::new(false);
        assert_eq!(
            build_for_test(&db, dir.path().to_str().unwrap(), Mode::Incremental, &cancel, &pause),
            BuildOutcome::Completed
        );
        assert_eq!(status(), Status::Ready);

        let conn = Connection::open(&db).unwrap();
        let n: i64 = conn.query_row("SELECT COUNT(*) FROM documents", [], |r| r.get(0)).unwrap();
        assert_eq!(n, 1, "only the normal text file should be indexed");
    }

    // ── Build / query ───────────────────────────────────────────────

    #[test]
    fn test_full_build_and_query() {
        let _g = lock();
        reset_for_test();
        let (_d, db) = tmp_db();
        let dir = scratch_dir("t");
        write_file(dir.path(), "a.txt", b"the quick brown fox");
        write_file(dir.path(), "b.md", b"lazy dog");

        init(&db).unwrap();
        let cancel = TestBool::new(false);
        let pause = TestBool::new(false);
        assert_eq!(
            build_for_test(&db, dir.path().to_str().unwrap(), Mode::Incremental, &cancel, &pause),
            BuildOutcome::Completed
        );
        assert_eq!(status(), Status::Ready);

        let hits = run_query(&db, "fox");
        assert_eq!(hits.len(), 1);
        assert!(hits[0].ends_with("a.txt"));

        let none = run_query(&db, "zzzznope");
        assert!(none.is_empty());
    }

    #[test]
    fn test_identity_unchanged_not_reindexed() {
        let _g = lock();
        reset_for_test();
        let (_d, db) = tmp_db();
        let dir = scratch_dir("t");
        write_file(dir.path(), "a.txt", b"content one");

        init(&db).unwrap();
        let cancel = TestBool::new(false);
        let pause = TestBool::new(false);
        build_for_test(&db, dir.path().to_str().unwrap(), Mode::Incremental, &cancel, &pause);
        // Rebuild (mode=1) into a fresh temp DB and confirm identical count.
        assert_eq!(
            build_for_test(&db, dir.path().to_str().unwrap(), Mode::Rebuild, &cancel, &pause),
            BuildOutcome::Completed
        );
        let conn = Connection::open(&db).unwrap();
        let n: i64 = conn.query_row("SELECT COUNT(*) FROM documents", [], |r| r.get(0)).unwrap();
        assert_eq!(n, 1);
    }

    #[test]
    fn test_dirty_update_and_delete() {
        let _g = lock();
        reset_for_test();
        let (_d, db) = tmp_db();
        let dir = scratch_dir("t");
        let a = write_file(dir.path(), "a.txt", b"old content");

        init(&db).unwrap();
        let cancel = TestBool::new(false);
        let pause = TestBool::new(false);
        build_for_test(&db, dir.path().to_str().unwrap(), Mode::Incremental, &cancel, &pause);
        assert_eq!(status(), Status::Ready);

        // Update: modify mtime + content, mark dirty, incremental re-index.
        std::fs::write(&a, b"new content here").unwrap();
        mark_dirty(&a);
        build_for_test(&db, dir.path().to_str().unwrap(), Mode::Incremental, &cancel, &pause);
        assert_eq!(status(), Status::Ready);
        let hits = run_query(&db, "new");
        assert_eq!(hits.len(), 1);

        // Delete: remove the file, mark dirty, incremental removes the doc.
        std::fs::remove_file(&a).unwrap();
        mark_dirty(&a);
        build_for_test(&db, dir.path().to_str().unwrap(), Mode::Incremental, &cancel, &pause);
        assert_eq!(status(), Status::Ready);
        let conn = Connection::open(&db).unwrap();
        let n: i64 = conn.query_row("SELECT COUNT(*) FROM documents", [], |r| r.get(0)).unwrap();
        assert_eq!(n, 0, "deleted file must be removed from the index");
    }

    // ── Cancel / checkpoint / resume ────────────────────────────────

    #[test]
    fn test_cancel_commits_checkpoint_then_resume() {
        let _g = lock();
        reset_for_test();
        let (_d, db) = tmp_db();
        let dir = scratch_dir("t");
        let total = 4000usize;
        for i in 0..total {
            write_file(dir.path(), &format!("file_{:05}.txt", i), b"some text");
        }

        init(&db).unwrap();

        let cancel = Arc::new(TestBool::new(false));
        let pause = Arc::new(TestBool::new(false));
        let (c2, p2, root, dbr) = (
            Arc::clone(&cancel),
            Arc::clone(&pause),
            dir.path().to_str().unwrap().to_string(),
            db.clone(),
        );
        let handle = std::thread::spawn(move || {
            build_for_test(&dbr, &root, Mode::Incremental, &c2, &p2)
        });

        // Wait until at least one batch (500 docs) is committed, then cancel
        // mid-walk so a checkpoint exists for the resume path.
        let deadline = std::time::Instant::now() + Duration::from_secs(120);
        while processed_for_test() < 600 && std::time::Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(2));
        }
        assert!(
            processed_for_test() >= 600,
            "build should have committed at least one batch"
        );
        cancel.store(true, TestOrdering::Relaxed);
        let outcome = handle.join().unwrap();
        assert_eq!(outcome, BuildOutcome::Cancelled);
        assert_eq!(status(), Status::Cancelled);

        // A checkpoint must have been committed (some documents persisted).
        let conn = Connection::open(&db).unwrap();
        let n: i64 = conn.query_row("SELECT COUNT(*) FROM documents", [], |r| r.get(0)).unwrap();
        assert!(n > 0, "cancelled build must retain committed documents");
        drop(conn);

        // Resume completes the build (clear the cancel flag first).
        cancel.store(false, TestOrdering::Relaxed);
        assert_eq!(
            build_for_test(&db, dir.path().to_str().unwrap(), Mode::Incremental, &cancel, &pause),
            BuildOutcome::Completed
        );
        assert_eq!(status(), Status::Ready);
        let conn = Connection::open(&db).unwrap();
        let n: i64 = conn.query_row("SELECT COUNT(*) FROM documents", [], |r| r.get(0)).unwrap();
        assert_eq!(n as usize, total, "resume must reach the full document count");
    }

    #[test]
    fn test_resume_skips_committed_checkpoint() {
        let _g = lock();
        reset_for_test();
        let (_d, db) = tmp_db();
        let dir = scratch_dir("t");
        write_file(dir.path(), "a.txt", b"alpha");
        let b = write_file(dir.path(), "b.txt", b"beta");

        init(&db).unwrap();
        let cancel = TestBool::new(false);
        let pause = TestBool::new(false);

        // Build a.txt + b.txt for real.
        build_for_test(&db, dir.path().to_str().unwrap(), Mode::Incremental, &cancel, &pause);
        assert_eq!(status(), Status::Ready);

        // Simulate a cancelled build with checkpoint = b.txt.
        {
            let conn = Connection::open(&db).unwrap();
            conn.execute(
                "INSERT INTO meta(key, value) VALUES('checkpoint_path', ?1)
                 ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                params![b.as_str()],
            )
            .unwrap();
        }
        set_status_for_test(Status::Cancelled);

        // A new file appears after the checkpoint.
        write_file(dir.path(), "c.txt", b"gamma");

        // Resume: only c.txt (> checkpoint) should be newly indexed.
        assert_eq!(
            build_for_test(&db, dir.path().to_str().unwrap(), Mode::Incremental, &cancel, &pause),
            BuildOutcome::Completed
        );
        assert_eq!(status(), Status::Ready);
        assert_eq!(run_query(&db, "gamma").len(), 1, "c.txt must be indexed on resume");
        let conn = Connection::open(&db).unwrap();
        let n: i64 = conn.query_row("SELECT COUNT(*) FROM documents", [], |r| r.get(0)).unwrap();
        assert_eq!(n, 3, "all three documents must be present after resume");
    }

    // ── Corruption / migration ──────────────────────────────────────

    #[test]
    fn test_corruption_backup_and_rebuild() {
        let _g = lock();
        reset_for_test();
        let (dir, db) = tmp_db();
        // Write garbage so SQLite open fails with NOTADB.
        std::fs::write(&db, b"this is not a sqlite database at all, definitely corrupt").unwrap();

        init(&db).unwrap();

        assert_eq!(status(), Status::Empty, "corruption → backup + empty rebuild");
        // A backup file must exist.
        let parent = dir.path();
        let has_backup = std::fs::read_dir(parent).unwrap().flatten().any(|e| {
            e.file_name()
                .to_string_lossy()
                .contains(".corrupt-")
        });
        assert!(has_backup, "corrupt DB must be renamed to a .corrupt-* backup");
        // The main DB is now a valid fresh SQLite file.
        let conn = Connection::open(&db).unwrap();
        let v: i32 = conn.query_row("PRAGMA user_version", [], |r| r.get(0)).unwrap();
        assert_eq!(v, SCHEMA_VERSION);
    }

    #[test]
    fn test_future_version_untouched() {
        let _g = lock();
        reset_for_test();
        let (_d, db) = tmp_db();
        // Build a v1 DB with one document, then bump user_version to 2.
        init(&db).unwrap();
        {
            let conn = Connection::open(&db).unwrap();
            conn.execute_batch(
                "INSERT INTO documents(path, mtime, size, body, indexed_at) VALUES('/future.txt', 1, 1, 'future', 1);",
            )
            .unwrap();
            conn.execute_batch("PRAGMA user_version = 99;").unwrap();
        }

        reset_for_test();
        init(&db).unwrap();

        // Future version: skip schema ops, keep data, report ready.
        assert_eq!(status(), Status::Ready, "future-version DB keeps its data");
        let conn = Connection::open(&db).unwrap();
        let v: i32 = conn.query_row("PRAGMA user_version", [], |r| r.get(0)).unwrap();
        assert_eq!(v, 99, "user_version must remain untouched for future versions");
        let n: i64 = conn.query_row("SELECT COUNT(*) FROM documents", [], |r| r.get(0)).unwrap();
        assert_eq!(n, 1, "future-version data must not be modified");
    }

    // ── Pause / resume ──────────────────────────────────────────────

    #[test]
    fn test_pause_blocks_then_resume() {
        let _g = lock();
        reset_for_test();
        let (_d, db) = tmp_db();
        let dir = scratch_dir("t");
        for i in 0..2000usize {
            write_file(dir.path(), &format!("file_{:05}.txt", i), b"pause test content");
        }
        init(&db).unwrap();

        let cancel = Arc::new(TestBool::new(false));
        let pause = Arc::new(TestBool::new(true)); // pre-paused
        let (c2, p2, root, dbr) = (
            Arc::clone(&cancel),
            Arc::clone(&pause),
            dir.path().to_str().unwrap().to_string(),
            db.clone(),
        );
        let handle = std::thread::spawn(move || {
            build_for_test(&dbr, &root, Mode::Incremental, &c2, &p2)
        });

        // Wait until the loop enters the paused wait.
        let deadline = std::time::Instant::now() + Duration::from_secs(60);
        while !is_paused_for_test() && std::time::Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(2));
        }
        assert!(is_paused_for_test(), "build must observe the pause flag");
        assert_eq!(status(), Status::Indexing, "paused build stays indexing");

        // Resume and let it finish.
        pause.store(false, TestOrdering::Relaxed);
        assert_eq!(handle.join().unwrap(), BuildOutcome::Completed);
        assert_eq!(status(), Status::Ready);
    }

    #[test]
    fn test_root_unreadable_sets_error() {
        let _g = lock();
        reset_for_test();
        let (_d, db) = tmp_db();
        init(&db).unwrap();
        let cancel = TestBool::new(false);
        let pause = TestBool::new(false);
        let outcome = build_for_test(&db, "/nonexistent/root/xyz", Mode::Incremental, &cancel, &pause);
        assert_eq!(outcome, BuildOutcome::Failed);
        assert_eq!(status(), Status::Error);
        // Error message surfaced in stats.
        let json: serde_json::Value = serde_json::from_str(&stats_json()).unwrap();
        assert!(json.get("error").is_some());
    }

    #[test]
    fn test_stats_reflects_document_count() {
        let _g = lock();
        reset_for_test();
        let (_d, db) = tmp_db();
        let dir = scratch_dir("t");
        write_file(dir.path(), "a.txt", b"one");
        write_file(dir.path(), "b.txt", b"two");
        init(&db).unwrap();
        let cancel = TestBool::new(false);
        let pause = TestBool::new(false);
        build_for_test(&db, dir.path().to_str().unwrap(), Mode::Incremental, &cancel, &pause);
        let json: serde_json::Value = serde_json::from_str(&stats_json()).unwrap();
        assert_eq!(json["status"], 2);
        assert_eq!(json["document_count"], 2);
        assert_eq!(json["paused"], false);
    }
}

// ── FFI-level integration tests ──────────────────────────────────────
//
// Exercised through the public FFI surface so the callback ownership and
// OnceLock path contracts are covered. Runs under the same shared lock as
// the core tests, and is the only test that sets CONTENT_INDEX_DB_PATH.

#[cfg(test)]
mod ffi_tests {
    use super::*;
    use std::ffi::{CStr, CString};

    extern "C" fn collect_path(result: *const crate::ffi::FFSearchResult, user_data: *mut std::os::raw::c_void) {
        if result.is_null() || user_data.is_null() {
            return;
        }
        let hits = unsafe { &mut *(user_data as *mut Vec<String>) };
        unsafe {
            let path = CStr::from_ptr((*result).path).to_string_lossy().to_string();
            hits.push(path);
        }
    }

    #[test]
    fn test_ffi_init_build_query_stats_cancel_flow() {
        let _g = CONTENT_INDEX_TEST_LOCK.lock();
        reset_for_test();

        let dir = scratch_dir("t");
        let db = dir.path().join("content_index.sqlite");
        let db_path = db.to_string_lossy().to_string();
        let root = scratch_dir("t");
        let a = root.path().join("alpha.txt");
        std::fs::write(&a, b"ffi needle content").unwrap();

        let db_c = CString::new(db_path.as_str()).unwrap();

        // init
        assert_eq!(crate::ffi::ff_content_index_init(db_c.as_ptr()), crate::ffi::FF_OK);
        assert_eq!(crate::ffi::ff_content_index_status(), crate::ffi::FF_CONTENT_INDEX_STATUS_EMPTY);

        // query before ready → NOT_FOUND
        let q = CString::new("needle").unwrap();
        let mut hits: Vec<String> = Vec::new();
        let rc = crate::ffi::ff_content_index_query(
            q.as_ptr(),
            500,
            collect_path,
            &mut hits as *mut Vec<String> as *mut std::os::raw::c_void,
        );
        assert_eq!(rc, crate::ffi::FF_ERR_NOT_FOUND);

        // start (mode=0)
        let root_c = CString::new(root.path().to_str().unwrap()).unwrap();
        let mut handle: u64 = 0;
        assert_eq!(
            crate::ffi::ff_content_index_start(root_c.as_ptr(), 0, &mut handle),
            crate::ffi::FF_OK
        );
        assert!(handle != 0);

        // poll until ready
        let deadline = std::time::Instant::now() + Duration::from_secs(60);
        while crate::ffi::ff_content_index_status() == crate::ffi::FF_CONTENT_INDEX_STATUS_INDEXING
            && std::time::Instant::now() < deadline
        {
            std::thread::sleep(Duration::from_millis(5));
        }
        assert_eq!(crate::ffi::ff_content_index_status(), crate::ffi::FF_CONTENT_INDEX_STATUS_READY);

        // query after ready → OK with one hit
        let mut hits: Vec<String> = Vec::new();
        let rc = crate::ffi::ff_content_index_query(
            q.as_ptr(),
            500,
            collect_path,
            &mut hits as *mut Vec<String> as *mut std::os::raw::c_void,
        );
        assert_eq!(rc, crate::ffi::FF_OK);
        assert_eq!(hits.len(), 1);
        assert!(hits[0].ends_with("alpha.txt"));

        // stats
        let stats_ptr = crate::ffi::ff_content_index_stats();
        assert!(!stats_ptr.is_null());
        let json: serde_json::Value = {
            let s = unsafe { CStr::from_ptr(stats_ptr).to_string_lossy().to_string() };
            serde_json::from_str(&s).unwrap()
        };
        assert_eq!(json["status"], 2);
        assert_eq!(json["document_count"], 1);
        crate::ffi::ff_free_string(stats_ptr);

        // mark_dirty on a deleted file, then incremental removes it
        std::fs::remove_file(&a).unwrap();
        let a_c = CString::new(a.to_string_lossy().to_string()).unwrap();
        assert_eq!(crate::ffi::ff_content_index_mark_dirty(a_c.as_ptr()), crate::ffi::FF_OK);
        let mut handle2: u64 = 0;
        assert_eq!(
            crate::ffi::ff_content_index_start(root_c.as_ptr(), 0, &mut handle2),
            crate::ffi::FF_OK
        );
        let deadline = std::time::Instant::now() + Duration::from_secs(60);
        while crate::ffi::ff_content_index_status() == crate::ffi::FF_CONTENT_INDEX_STATUS_INDEXING
            && std::time::Instant::now() < deadline
        {
            std::thread::sleep(Duration::from_millis(5));
        }
        assert_eq!(crate::ffi::ff_content_index_status(), crate::ffi::FF_CONTENT_INDEX_STATUS_READY);
        let mut hits: Vec<String> = Vec::new();
        let rc = crate::ffi::ff_content_index_query(
            q.as_ptr(),
            500,
            collect_path,
            &mut hits as *mut Vec<String> as *mut std::os::raw::c_void,
        );
        assert_eq!(rc, crate::ffi::FF_OK);
        assert!(hits.is_empty(), "deleted file must no longer match");

        // cancel an invalid handle → NOT_FOUND
        assert_eq!(
            crate::ffi::ff_content_index_cancel(u64::MAX),
            crate::ffi::FF_ERR_NOT_FOUND
        );
    }
}
