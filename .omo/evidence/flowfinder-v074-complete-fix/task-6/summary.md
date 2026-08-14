# T6 Deliverable — Independent FTS5 Content Index (Wave2)

**Status:** ✅ Complete — code + tests + evidence
**Design authority:** `.omo/evidence/flowfinder-v074-complete-fix/task-5/content-index-contract.md`

## Deliverables

| File | Change |
|---|---|
| `rust-core/src/core/content_index.rs` | **New.** Full content-index engine (§2–§10). |
| `rust-core/src/core/mod.rs` | Register `pub mod content_index;`. |
| `rust-core/src/ffi/mod.rs` | 9 `ff_content_index_*` exports + status/mode constants + `OpKind::Index` + pause flag on `ActiveOp` + `pause_op`/`resume_op` + `CONTENT_INDEX_DB_PATH: OnceLock<String>`. |
| `rust-core/include/ff_ffi.h` | 9 prototypes + 6 status `#define` + 2 mode `#define` (after FSEvents section). |

## Contract coverage

- **§1 independent DB**: `content_index.sqlite` via `CONTENT_INDEX_DB_PATH` OnceLock; never touches `dir_cache.db` (no reference to `sqlite_cache`).
- **§2 FTS5 external content**: `documents` + `content_fts(content='documents', content_rowid='id')` + `meta`; runtime `PRAGMA compile_options` → `unavailable` terminal state; delete/insert/update sync per §2.3; query SQL per §2.4.
- **§3 allowlist + 4 MiB + NUL sniff + BOM→UTF-8→UTF-16→Latin-1**: `MAX_FILE_SIZE`, `INDEXED_EXTENSIONS`, `KNOWN_TEXT_BASENAMES`, `read_body`/`decode_text`.
- **§4 identity `(path,mtime,size)`**: `prepare_doc` skip/reindex/new/delete.
- **§5 dirty set + degrade**: `DIRTY: LazyLock<Mutex<HashSet>>`, `mark_dirty` O(1), watcher-unavailable → full rebuild.
- **§6 state machine**: `Status` empty/indexing/ready/error/cancelled/unavailable; exact transition table.
- **§7 checkpoint + pause/resume**: sorted walk, `checkpoint_path` per batch (same tx), resume skips `<= checkpoint`, `Arc<AtomicBool>` cancel+pause.
- **§8 FFI**: signatures byte-for-byte per §8.2.
- **§9 migration/corruption**: `user_version` additive-only, future-version untouched, corrupt → `.corrupt-<ts>` backup + fresh DB.
- **§10 transactions**: 500-doc batches in one tx, WAL + busy_timeout 5000ms, temp-file `*.tmp-<pid>` + atomic `rename`, temp cleanup on init.

## Test results

**Command:** `cargo test --all-features` (run twice)

```
test result: ok. 202 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 3.84s
test result: ok. 202 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 3.81s
```

Baseline was 181 passed; **+21 new content-index tests** (20 core + 1 FFI integration). Full log: `cargo-test.log`.

New tests cover: schema/user_version, FTS5 availability, 5 encoding cases, allowlist, 4 MiB cap + NUL binary skip, full build+query, identity skip, dirty update/delete, cancel→checkpoint→resume, deterministic checkpoint-skip resume, corruption backup, future-version untouched, pause/resume, root-unreadable→error, stats document_count, and the full FFI init→status→start→query→stats→mark_dirty→cancel flow.

## Note: fsevents test-isolation fix (in scope, `ffi/mod.rs`)

`test_ff_fsevents_start_failure_reported` left the process-global `WATCHER_STATUS = Failed`, making the sibling `test_ff_fsevents_status_transitions` order-dependent (flaky: fails when it runs after the failure test). This is a pre-existing T9 test-hygiene issue, not content-index logic. Fixed in `ffi/mod.rs` (allowed; `fsevents.rs` is off-limits) by restoring a stopped watcher at the end of the failure test. No product code in `fsevents.rs` was touched.

## SIZE_OK note

`content_index.rs` is 1352 pure LOC (1728 total incl. tests). This is a documented `// allow: SIZE_OK` exception: contract §11 mandates a single-file module owning an indivisible state machine (schema, FTS sync, encoding, identity, state, checkpoint, transactions, temp-replace, dirty set, migration, corruption).

## Not done (deferred to T7 per contract §11)

Swift integration (`AppDelegate.initContentIndex`, `ContentIndexBridge`, `SearchPanelController`, `MainWindowController.markDirty`), and FFIFunctions.swift declarations — explicitly out of T6 scope.
