# Wave1 T2 — Batch rename/organize safety (v0.7.5 fix plan)

Date: 2026-08-13

## Scope
- `rust-core/src/core/safe_filename.rs` — NEW: dedicated file-name validator
- `rust-core/src/core/batch_ops.rs` — batch_rename validation + conflict policy; organize_by_date / organize_by_type conflict skip
- `rust-core/src/ffi/mod.rs` — ff_batch_rename error mapping only (InvalidInput → FF_ERR_INVALID_PATH)

## Evidence
- `cargo-test.log` — final full `cargo test --all-features` run:
  **155 passed / 0 failed (fully green)**.
- `task-2-tests.log` — isolated run of every T2-relevant test:
  26 passed / 0 failed (T1 red `test_batch_rename_traversal_rejected`,
  `test_batch_rename_conflict_not_overwritten` now green, plus all new validator,
  batch, organize and FFI-mapping tests).

## Concurrent-work note
T3 was editing `core/fsevents.rs` (and ffi tests) during this task; their
in-flight edits intermittently broke the build. Once stabilized, the full
suite is green including all fsevents / dedup-cancel tests.

## T2 count reconciliation
Baseline (T1 log): 118 passed, 4 red (2 batch_rename + fsevents + dedup_cancel).
T2 deliverables: the 2 batch_rename reds are green + 18 new tests (7 validator,
8 batch_ops, 3 FFI). Final suite: 155 passed, 0 failed.
