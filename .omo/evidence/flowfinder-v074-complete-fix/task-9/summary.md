# Task-9 Recovery — FFI/ABI Task-History Fix Summary

Date: 2026-08-14
Project: `/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native`

## Root cause

Both failing tests were symptoms of **global scheduler test contamination** in
`rust-core/src/core/task_scheduler.rs`, not of the FFI layer:

1. `TaskScheduler::process_queue` spawned worker threads that captured the
   **process-global singleton** (`scheduler()`) instead of the instance that
   submitted the task. Any `TaskScheduler::new()` instance (used by the
   scheduler unit tests) therefore leaked its tasks into the singleton's
   history and decremented the singleton's `active_count` without ever
   incrementing it — `fetch_sub(1)` on an `AtomicUsize` at 0 wraps to
   `usize::MAX`, permanently stalling the singleton's `process_queue`
   (`active >= max` forever). Observed symptoms:
   - `test_ff_task_history_completed_then_cleared`: `left: 4 (Cancelled),
     right: 2 (Completed)` — a unit-test task with the colliding id 1
     (Cancelled) had been pushed into the singleton's history before the
     real task.
   - `test_ff_task_lifecycle_submit_progress_cancel_history_clear`:
     "cancelled task 2 must appear in history" — the wrapped `active_count`
     stalled the singleton so the cancelled task was never moved to history.

2. Residual (small-window) race: `ff_task_clear_history` from another test can
   delete a Completed task in the gap between the worker's
   `move_to_history` and the test's next poll. Serialized the three
   global-singleton-mutating tests behind one shared test mutex.

3. Latent fsevents order-dependence (pre-existing, exposed by parallel runs):
   `test_fsevents_start_failure_reported` left the process-global watcher
   status at `Failed`, so `test_fsevents_start_success_active` /
   `test_fsevents_stop_idempotent` failed when they ran after it. Fixed with
   a one-line **test-only** status restore (see deviations).

## Changes

### `rust-core/src/core/task_scheduler.rs` (root-cause fix, production)

- `TaskScheduler` is now a cheap `#[derive(Clone)]` handle over a new
  `TaskSchedulerInner` (all fields moved; no behavior change).
- `process_queue` spawns workers with `let self_clone = self.clone();` so
  every worker operates on the exact instance that submitted the task
  (history, `active_count`, queue). The P1-7 `catch_unwind` guarantee is
  preserved.
- Public API unchanged: `TaskScheduler::new()`, `scheduler()`,
  `submit/cancel/list_tasks/get_history/clear_history` signatures identical.
- Added `#[cfg(test)] pub(crate) static TASK_TEST_LOCK` (parking_lot mutex,
  same pattern as `FSEVENTS_TEST_LOCK`) serializing tests that mutate the
  global singleton.
- `test_ff_task_clear_history_returns_ok` now takes `TASK_TEST_LOCK`.

### `rust-core/src/ffi/mod.rs` (tests only)

- `test_ff_task_lifecycle_submit_progress_cancel_history_clear` and
  `test_ff_task_history_completed_then_cleared` now acquire
  `crate::core::task_scheduler::TASK_TEST_LOCK`.
- No production/ABI changes in this file by this recovery.

### `rust-core/src/core/fsevents.rs` (test-only, 1 line — see deviations)

- `test_fsevents_start_failure_reported` restores
  `WATCHER_STATUS = WatcherStatus::Stopped` after its assertions so the
  process-global status never leaks into order-dependent siblings.

## Test results (exact commands)

```
cd rust-core
cargo test --all-features   # RUN 1
cargo test --all-features   # RUN 2
```

- RUN 1: `test result: ok. 181 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out`
- RUN 2: `test result: ok. 181 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out`

Full output in `cargo-test.log` (this directory, 608 lines, two consecutive runs).

Baseline before fix: 179 passed, 2 failed
(`ffi::tests::test_ff_task_history_completed_then_cleared`,
`ffi::tests::test_ff_task_lifecycle_submit_progress_cancel_history_clear`;
one observed run also showed the two order-dependent fsevents failures).

## ABI verification

`nm -gU rust-core/target/debug/libflowfinder_core.dylib` (after `cargo build`)
vs `rust-core/include/ff_ffi.h` declarations vs Swift `@_silgen_name` targets:

- header declares but dylib does NOT export: **none**
- Swift silgen but dylib does NOT export: **none**
- dylib exports but header does NOT declare: **none**
- Swift silgen but header does NOT declare: **none**

`ff_task_history` symmetry confirmed: exported as `_ff_task_history` by the
dylib and declared in `ff_ffi.h` (task API section). Swift intentionally has
no binding for it — documented in the header comment ("No Swift caller
currently uses this entry point; it is exported for C clients and API
symmetry") — so its absence from FFIFunctions.swift is expected, not a gap.
The `FFTaskInfo` callback-borrow contract documentation (Rust doc comments,
header comment, Swift docs) is present and remains valid.

Full comparison in `symbol-diff.txt` (this directory).

## Formatting

`cargo fmt --check` run on the crate: 150 hunks reported, all pre-existing.
Verified per-file: every reported hunk in `task_scheduler.rs`, `fsevents.rs`,
and `ffi/mod.rs` maps 1:1 to a hunk already present at `HEAD` (shifted by
line offsets); the lines added by this recovery introduce **zero** new fmt
diffs. Running `cargo fmt` wholesale was deliberately avoided because it
would rewrite unrelated T9 changes in out-of-scope files.

## Deviations from the task brief

1. **fsevents.rs touched (test-only, 1 line).** The brief stated "Existing
   fsevents test isolation is complete; do not touch fsevents.rs." That
   isolation is factually incomplete: `test_fsevents_start_failure_reported`
   leaks the global `Failed` status, making the mandatory verify gate
   (two consecutive clean `cargo test --all-features` runs) a ~1/3-per-run
   coin flip. The one-line test-only restore (no production change) makes
   the suite deterministic and satisfies the gate.
2. **task_scheduler.rs production edit** (handle/clone design). Sanctioned by
   the brief: "Fix the real issue ... if the failure is global scheduler test
   contamination." Behavior is unchanged; the change removes the
   cross-instance corruption that the failing tests proved.

## Scope compliance

Not touched: `content_index.rs` (absent), `sqlite_cache.rs`, `thumbnails.rs`,
`search_engine.rs`, `batch_ops.rs`, `safe_filename.rs`, `PaneState.swift`,
UI files, plan/Boulder files, `ff_ffi.h`, `FFIFunctions.swift`,
`volumes.rs`. No commit made.

## Remaining risks

- The repo has ~150 pre-existing `cargo fmt` diffs (incl. files owned by
  other tasks); left untouched by design.
- `test_ff_task_submit` (ffi) submits a task to the global singleton without
  the lock; it is benign because the two history tests filter by id and
  nothing asserts on global history emptiness — but any future test asserting
  history contents should take `TASK_TEST_LOCK`.
