# flowfinder-v074-complete-fix - Work Plan

## TL;DR (For humans)
<!-- Fill this LAST, after the detailed plan below is written, so it summarizes the REAL plan. -->
<!-- Plain English for a non-engineer: NO file paths, NO todo numbers, NO wave/agent/tool names. -->

**What you'll get:** A safer, testable FlowFinder with protected batch file operations, cancellable indexed content search, reliable FFI/task/cache behavior, visible AppKit states, primary-flow accessibility, and a responsive Pages site. It also produces a reproducible, CI-gated v0.7.5 release without changing v0.7.4.

**Why this approach:** Security and data correctness are fixed before UX polish; the content index uses a separate versioned store so it cannot destroy the existing directory cache or break downgrade behavior. Every wave adds executable tests and manual/browser evidence before the next wave.

**What it will NOT do:** It will not mutate v0.7.4, migrate the app to SwiftUI, implement unrelated AI features, or rewrite the entire UI visual language. Secondary legacy accessibility surfaces remain explicitly outside the first primary-flow accessibility wave.

**Effort:** XL
**Risk:** High - content indexing, FFI changes, Xcode test-target wiring, and notarized release automation cross several boundaries.
**Decisions to sanity-check:** Separate FTS5 content index; primary-flow accessibility scope; v0.7.5 notarized release gate.

Your next move: start execution in a separate worker session with `$start-work flowfinder-v074-complete-fix`. Full execution detail follows below.

---

> TL;DR (machine): XL/high-risk five-wave remediation: Rust/FFI safety, separate FTS5 content index, AppKit UX/accessibility, Pages/docs, CI and notarized v0.7.5 release.

## Scope
### Must have
- Protect every user-controlled filename/path at Rust boundaries, including batch rename and organize conflict behavior.
- Make file operations, search, indexing, and cache access cancellable or non-blocking where they touch the UI.
- Add a separate, versioned SQLite FTS5 content index with incremental invalidation and explicit rebuilding/error/empty states.
- Make Swift FFI ownership/layout contracts testable and reconcile orphan exports/declarations.
- Wire Swift XCTest to a real Xcode test target and make Rust, Swift, Pages, and packaging checks executable in CI.
- Cover primary AppKit flows with VoiceOver metadata, keyboard focus, visible focus, reduced motion, large-text checks, and empty/loading/error states.
- Fix Pages mobile architecture overflow/navigation, semantic landmarks, metadata, contrast, and content/version drift.
- Produce reproducible v0.7.5 DMG/ZIP/checksum artifacts, Developer ID signing, notarization, stapling, and GitHub Release gates.
### Must NOT have (guardrails, anti-slop, scope boundaries)
- Do not mutate the v0.7.4 tag, Release assets, or published history.
- Do not migrate from AppKit to SwiftUI or introduce a UI framework.
- Do not implement AI/LLM tagging; correct documentation to match actual capability.
- Do not hide content, remove search, weaken accessibility, or disable UX states to make tests pass.
- Do not include legacy projects outside `flowfinder-native`.

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: Rust security/correctness tests first; Swift tests-after after adding an Xcode XCTest target; Playwright Pages QA; AppKit manual smoke QA; packaging verification in CI.
- Evidence: `.omo/evidence/flowfinder-v074-complete-fix/task-<N>/` with command logs, test reports, screenshots, DOM measurements, package checksums, and notarization receipts.
- Required commands: `cargo fmt --check`, `cargo clippy --all-targets --all-features -- -D warnings` (or documented pre-existing exceptions), `cargo test --all-features`; `/Applications/Xcode*.app/Contents/Developer/usr/bin/xcodebuild test`; Playwright Chromium at 375/768/1280; package `codesign --verify`, `spctl`, `xcrun notarytool`, `xcrun stapler`; `shasum -a 256`.

## Execution strategy
### Parallel execution waves
> Target 5-8 todos per wave. Fewer than 3 (except the final) means you under-split.
- Wave 1: todos 1-4. Security and data-loss prevention; no UI polish starts before this wave passes.
- Wave 2: todos 5-8. Content index, search cancellation, cache/thumbnail reliability; todo 5 defines the separate index contract before todo 6 wires it.
- Wave 3: todos 9-11. FFI/Swift testability, PaneState/background operations, and CI test execution.
- Wave 4: todos 12-15. AppKit states, destructive-flow parity, primary-flow accessibility, and Pages UX/SEO.
- Wave 5: todos 16-18. Documentation/version reconciliation, reproducible package/notarization, and v0.7.5 release workflow.

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| 1 | none | 2,3,4 | none |
| 2 | 1 | 5,10 | 3,4 |
| 3 | 1 | 10,18 | 2,4 |
| 4 | 1 | 5,7 | 2,3 |
| 5 | 1,4 | 6,7,10 | 8 |
| 6 | 5 | 7,10,18 | 8,9 |
| 7 | 6,9 | 10,12 | 8,11 |
| 8 | 1 | 10,18 | 5,6,9 |
| 9 | 1 | 7,10,11 | 5,6,8 |
| 10 | 2,4,7,9 | 11,12 | 8,9 |
| 11 | 10 | 12,13 | 9 |
| 12 | 10,11 | 13,14 | 15 |
| 13 | 11,12 | 15 | 14 |
| 14 | none | 17 | 12,13 |
| 15 | 12 | 17 | 13,14 |
| 16 | none | 17,18 | 14,15 |
| 17 | 1,3,6,9,11,14,15,16 | 18 | none |
| 18 | 17 | final wave | none |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->
- [ ] 1. Add red regression tests and a baseline matrix before production fixes
  What to do / Must NOT do: Add Rust tests for unsafe batch filenames, collisions, FSEvents startup failure, dedup cancellation isolation, and task-history clearing; add failing tests before production changes. Record current Swift test-target and package failures. Do not alter product behavior in this task.
  Parallelization: Wave 1 | Blocked by: none | Blocks: 2,3,4
  References (executor has NO interview context - be exhaustive): `rust-core/src/ffi/mod.rs:1659-1703, 756-890, 1580-1630, 2330+`; `rust-core/src/core/{batch_ops,fsevents,dedup_engine,task_scheduler}.rs`; `FlowFinderNative/Tests/FlowFinderNativeTests/FlowFinderNativeTests.swift`; `FlowFinderNative.xcodeproj/project.pbxproj`.
  Acceptance criteria (agent-executable): New tests fail for the pre-fix traversal/collision/false-success/global-cancel behavior; baseline command logs are saved under `.omo/evidence/flowfinder-v074-complete-fix/task-1/`.
  QA scenarios (name the exact tool + invocation): happy: `cargo test --all-features`; failure: each regression test is proven red on the pre-fix revision or with a temporary controlled assertion; Evidence `.omo/evidence/flowfinder-v074-complete-fix/task-1/`.
  Commit: Y | `test(core): add v0.7.5 regression baseline`

- [ ] 2. Enforce safe filenames and explicit collision policy for all batch/organize operations
  What to do / Must NOT do: Add a Rust filename validator separate from `path_guard` that rejects empty names, `/`, `\\`, `.`, `..`, absolute paths, control characters, and path components; apply it to batch rename. Add explicit no-overwrite default and a typed conflict result for batch rename, organize-by-date, and organize-by-type. Do not silently delete/replace existing files.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 5,10
  References (executor has NO interview context - be exhaustive): `rust-core/src/ffi/mod.rs:1659-1703`; `rust-core/src/core/batch_ops.rs:94-240`; `rust-core/src/core/path_guard.rs`; Swift batch rename callers and conflict UI.
  Acceptance criteria (agent-executable): traversal inputs return `FF_ERR_INVALID_PATH`; existing destination returns a conflict result without modifying either file; valid Unicode names continue to work; tests from todo 1 pass.
  QA scenarios (name the exact tool + invocation): happy: Unicode filename and non-conflicting batch rename; failure: `../escape`, `/tmp/escape`, `..`, duplicate destination, organize collision; `cargo test --all-features`; Evidence task-2.
  Commit: Y | `fix(core): harden batch filenames and conflicts`

- [ ] 3. Make FSEvents startup stateful and failure-observable
  What to do / Must NOT do: Change the watcher lifecycle so Swift receives `starting/active/failed/stopped`, and `ff_fsevents_start` cannot return success before worker setup succeeds. Preserve the current safe callback lifetime and `SendPtr` proof; do not weaken unsafe boundaries. Add deterministic setup-failure tests/stubs and stop idempotency tests.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 10,18
  References (executor has NO interview context - be exhaustive): `rust-core/src/core/fsevents.rs:194-438`; `rust-core/src/ffi/mod.rs:1580-1630`; `Bridge/CoreBridge.swift` FSEvents watcher methods; `rust-core/include/ff_ffi.h`.
  Acceptance criteria (agent-executable): invalid/setup-failure path returns non-zero and UI exposes failed state; successful watcher reaches active before caller continues; stop joins without hang; `cargo test --all-features` and FFI integration test pass.
  QA scenarios (name the exact tool + invocation): happy: start watcher, create/rename a file, receive copied path callback, stop; failure: forced stream-create failure reports error and no active watcher; Evidence task-3.
  Commit: Y | `fix(core): expose FSEvents lifecycle failures`

- [ ] 4. Isolate cancellation and make long-running scans/searches cancellable
  What to do / Must NOT do: Replace global `DEDUP_CANCEL` with per-operation cancellation context; add cancellation tokens to Rust search and bridge them through Swift. Bound traversal/results and preserve callback ownership. Do not cancel unrelated operations.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 5,7
  References (executor has NO interview context - be exhaustive): `rust-core/src/ffi/mod.rs:756-890`; `core/dedup_engine.rs`; `core/search_engine.rs:63-163`; `Bridge/SearchBridge.swift`; `UI/SearchPanelController.swift`.
  Acceptance criteria (agent-executable): cancelling operation A leaves B running; starting B does not reset A; search completion reports cancelled distinctly; no callback after context release; concurrency tests pass under repeated runs.
  QA scenarios (name the exact tool + invocation): happy: two concurrent scans/searches complete independently; failure: cancel A during hashing/walk and verify B results remain intact; `cargo test --all-features`; Evidence task-4.
  Commit: Y | `fix(core): isolate scan and search cancellation`

- [ ] 5. Design and document a separate content-index contract
  What to do / Must NOT do: Define an independent Application Support index store, FTS5 schema, indexed file-type/size policy, path+mtime+size identity, incremental invalidation via FSEvents, rebuilding/error/empty states, cancellation/resume semantics, and FFI ownership contract. Do not reuse the directory-cache DB without migration; do not let schema mismatch drop user index data.
  Parallelization: Wave 2 | Blocked by: 1,4 | Blocks: 6,7,10
  References (executor has NO interview context - be exhaustive): `rust-core/src/core/sqlite_cache.rs:30-50`; `core/fsevents.rs`; `core/search_engine.rs`; `FlowFinderNative/Package.swift`; `rust-core/Cargo.toml`; `docs/`.
  Acceptance criteria (agent-executable): schema and migration document exists; FTS5 capability is asserted; a fresh index, interrupted build, stale entry, permission error, and downgrade/read-only old DB have deterministic outcomes; index path is separate from dir cache.
  QA scenarios (name the exact tool + invocation): happy: index text files and query them; failure: corrupt DB, cancelled build, unsupported/binary file, stale mtime; evidence includes schema/migration tests in task-5.
  Commit: Y | `feat(search): specify separate content index contract`

- [ ] 6. Implement the Rust content index and migration-safe persistence
  What to do / Must NOT do: Implement the separate FTS5 store, incremental builder, cancellation, bounded text extraction, file identity checks, and safe migration/version handling. Never drop the existing directory cache or index on version mismatch; use atomic replacement/transactional updates.
  Parallelization: Wave 2 | Blocked by: 5 | Blocks: 7,10,18
  References (executor has NO interview context - be exhaustive): `rust-core/src/core/sqlite_cache.rs`; `rust-core/src/core/search_engine.rs`; new content-index module; `Cargo.toml` SQLite features; Application Support path resolver.
  Acceptance criteria (agent-executable): index build/query/cancel/restart tests pass; no main-thread work; index corruption falls back to rebuild without destroying dir cache; incremental FSEvents update changes one document only; FTS query latency/result correctness are asserted.
  QA scenarios (name the exact tool + invocation): happy: 10k-file fixture index/query; failure: locked DB, interrupted transaction, deleted file, changed mtime, 4MB+ file, binary file; `cargo test --all-features`; Evidence task-6.
  Commit: Y | `feat(search): add cancellable FTS5 content index`

- [ ] 7. Add content-index FFI and integrate SearchPanel states
  What to do / Must NOT do: Add header/Swift/Rust FFI for status/start/cancel/query with explicit borrowed-vs-owned string rules and `ff_free_string` where applicable. Replace main-thread `fileContainsText` calls with index queries; render idle/indexing/ready/error/empty/cancelled states. Do not retain raw callback pointers beyond callback lifetime.
  Parallelization: Wave 2 | Blocked by: 6,9 | Blocks: 10,12
  References (executor has NO interview context - be exhaustive): `rust-core/include/ff_ffi.h`; `rust-core/src/ffi/mod.rs`; `Bridge/FFIFunctions.swift`; `Bridge/SearchBridge.swift`; `UI/SearchPanelController.swift:applyFiltersAndReload/fileContainsText/detailsLabel`.
  Acceptance criteria (agent-executable): Swift/Rust struct layout tests pass; content queries never call `Data(contentsOf:)` on main; cancellation prevents stale callbacks; UI renders every index state; old query cannot update new results.
  QA scenarios (name the exact tool + invocation): happy: build index, search exact content, select result; failure: index unavailable/rebuilding/cancelled/permission denied; `xcodebuild test`; Evidence task-7.
  Commit: Y | `feat(search): wire indexed content search through FFI`

- [ ] 8. Repair cache concurrency and thumbnail maintenance
  What to do / Must NOT do: Add SQLite busy timeout/WAL or serialized connection strategy, make empty-directory cache hits representable, and move thumbnail cleanup to scheduled/bounded maintenance. Replace or explicitly scope the current empty thumbnail placeholder behavior; do not silently present fake thumbnails as real.
  Parallelization: Wave 2 | Blocked by: 1 | Blocks: 10,18
  References (executor has NO interview context - be exhaustive): `rust-core/src/core/sqlite_cache.rs`; `core/dir_cache.rs`; `core/thumbnails.rs:44,75`; `Bridge/ThumbnailManager.swift`.
  Acceptance criteria (agent-executable): concurrent cache reads/writes do not return SQLITE_BUSY under stress; empty directory is cached/retrieved; cleanup is not O(n) per thumbnail request; generated thumbnail status is distinguishable from placeholder.
  QA scenarios (name the exact tool + invocation): happy: concurrent 32-reader/8-writer cache stress; failure: locked DB, empty dir, thousands of thumbnails, missing QuickLook output; `cargo test --all-features`; Evidence task-8.
  Commit: Y | `fix(core): harden cache and thumbnail maintenance`

- [ ] 9. Reconcile FFI ABI, ownership, exports, and task lifecycle tests
  What to do / Must NOT do: Remove or formalize dead Swift value structs, fix `FFSearchFilters` C layout mismatch, document callback-borrow lifetimes, add missing `ff_task_history` header declaration or remove the export, and test `ff_task_clear_history`. Preserve public symbols used by the app.
  Parallelization: Wave 3 | Blocked by: 1 | Blocks: 7,10,11
  References (executor has NO interview context - be exhaustive): `Bridge/FFIFunctions.swift`; `Bridge/CoreBridge.swift`; `rust-core/include/ff_ffi.h`; `rust-core/src/ffi/mod.rs`; `core/task_scheduler.rs`; `FlowFinderNative/Tests/`.
  Acceptance criteria (agent-executable): generated/checked ABI layout assertions pass for FFEntryRef, FFVolumeInfo, FFSearchFilters, FFTaskInfo; every exported public symbol is either declared and tested or explicitly private; task history clear has a regression test; `nm`/header/Swift symbol comparison is clean.
  QA scenarios (name the exact tool + invocation): happy: list/search/task/volume callbacks copy data safely; failure: null callback, invalid UTF-8, callback after release, malformed filter layout; `cargo test`, Swift XCTest; Evidence task-9.
  Commit: Y | `test(ffi): lock ABI ownership and task contracts`

- [ ] 10. Repair PaneState and background file-operation state transitions
  What to do / Must NOT do: Apply searchQuery after tag filtering, move delete/trash/restore I/O into cancellable task execution while keeping UndoManager mutations on main, preserve failed selection and cache invalidation, and surface typed errors/loading progress. Do not change destructive semantics without the unified confirmation policy in todo 11.
  Parallelization: Wave 3 | Blocked by: 2,4,7,9 | Blocks: 11,12
  References (executor has NO interview context - be exhaustive): `Model/PaneState.swift:deleteSelected, undoTrashRestore, applyFilter, loadDirectory`; `Bridge/CoreBridge.swift`; `Bridge/TaskSchedulerManager.swift`; UI list/grid state sinks.
  Acceptance criteria (agent-executable): combined tag+query filtering returns intersection; large delete leaves UI responsive and reports per-item failures; cancellation/partial failure leaves correct selection; error/loading states are observable and testable; no file I/O occurs on main in profiled operation path.
  QA scenarios (name the exact tool + invocation): happy: delete/undo 1 and 100 files; failure: permission denied, slow volume, cancelled batch, restore collision, tag+query combination; XCTest + manual AppKit smoke evidence task-10.
  Commit: Y | `fix(model): make file operations cancellable and stateful`

- [ ] 11. Wire executable Swift XCTest target and correct stale tests
  What to do / Must NOT do: Add an Xcode XCTest target and shared test scheme; update stale `FileEntryViewModel` tests to current PaneViewModel/PaneState contracts; add fixtures for error/loading/destructive/search/task/FFI behavior. Do not rely on `swift test` with no test target.
  Parallelization: Wave 3 | Blocked by: 9,10 | Blocks: 12,13,17
  References (executor has NO interview context - be exhaustive): `FlowFinderNative/Tests/FlowFinderNativeTests/FlowFinderNativeTests.swift`; `FlowFinderNative.xcodeproj/project.pbxproj`; `FlowFinderNative/Package.swift`; Makefile test targets.
  Acceptance criteria (agent-executable): `xcodebuild test -project ... -scheme FlowFinderNativeTests` discovers and runs tests; no reference to removed types; test target links the same Rust ABI used by the app; failure tests assert user-visible error/state contracts.
  QA scenarios (name the exact tool + invocation): happy: clean clone test discovery; failure: missing Rust library, invalid FFI pointer fixture, permission denied fixture; save test result bundle under task-11 evidence.
  Commit: Y | `test(swift): wire executable XCTest target`

- [ ] 12. Unify AppKit states and destructive-operation UX
  What to do / Must NOT do: Add reusable primary-flow error banner, loading/skeleton, empty-folder, retry, and progress states; unify all delete entry points on DeleteConfirmDialog/undo semantics; connect SearchPanel result selection/details; preserve existing AppKit visual tokens and no SwiftUI migration.
  Parallelization: Wave 4 | Blocked by: 10,11 | Blocks: 13,14
  References (executor has NO interview context - be exhaustive): `UI/FileListView.swift`; `UI/FileGridView.swift`; `UI/SidebarView.swift`; `UI/SearchPanelController.swift`; `UI/FFPaneActionsController.swift`; `UI/MainWindowController.swift`; `UI/DeleteConfirmDialog.swift`; `UI/FFModalSheet.swift`.
  Acceptance criteria (agent-executable): every primary async operation shows loading/success/error/empty state; every delete path uses one confirmation policy; selected search result updates details or removes misleading prompt; keyboard and mouse paths produce identical destructive behavior.
  QA scenarios (name the exact tool + invocation): happy: empty/loading/error folder, delete via menu/context/Delete key, search select result; failure: permission denied, cancelled operation, empty result; AppKit manual smoke + XCTest evidence task-12.
  Commit: Y | `fix(ui): unify states and destructive workflows`

- [ ] 13. Implement primary-flow AppKit accessibility and interaction parity
  What to do / Must NOT do: Add VoiceOver labels/roles/help, keyboard focus order, visible focus, full keyboard operation for browsing/search/tasks/settings/delete/rename, reduced-motion handling, large-text/dynamic-type resilience, and list/grid drop/selection parity. Do not claim full accessibility for secondary legacy tools in this wave.
  Parallelization: Wave 4 | Blocked by: 11,12 | Blocks: 15
  References (executor has NO interview context - be exhaustive): `UI/FileListView.swift`; `UI/FileGridView.swift`; `UI/SidebarView.swift`; `UI/PaneToolbar.swift`; `UI/SearchPanelController.swift`; `UI/SettingsWindowController.swift`; dialogs; `ThemeManager.swift`.
  Acceptance criteria (agent-executable): VoiceOver can identify and operate primary controls; Tab/Shift-Tab order is deterministic; focus remains visible; 125%/200% text does not clip primary controls; reduce-motion disables nonessential animation; list/grid keyboard and drag/drop parity tests pass.
  QA scenarios (name the exact tool + invocation): happy: VoiceOver/keyboard walkthrough of each primary flow; failure: disabled controls, empty states, modal Escape/Return, narrow/large text; AppKit manual QA checklist task-13.
  Commit: Y | `fix(ui): add primary-flow accessibility and parity`

- [ ] 14. Refactor oversized modules behind behavior coverage
  What to do / Must NOT do: Split MainWindowController, FileListView, SidebarView, SettingsWindowController, PaneState, ExpandableDetailsBar, and ffi/mod.rs by responsibility only after their behavior tests pass. Preserve public APIs and current visual language; do not combine refactoring with semantic changes.
  Parallelization: Wave 4 | Blocked by: 12,13 | Blocks: 17
  References (executor has NO interview context - be exhaustive): pure LOC inventory in audit; all public call sites; Xcode project membership; Rust module exports.
  Acceptance criteria (agent-executable): each resulting file has one responsibility; no public call-site changes unless documented; Xcode membership and Rust exports remain complete; tests/build pass before and after each split.
  QA scenarios (name the exact tool + invocation): happy: full Xcode test/build after each split; failure: intentionally remove a moved file/reference and ensure membership check fails; Evidence task-14.
  Commit: Y | `refactor: split oversized controllers after coverage`

- [ ] 15. Repair Pages responsive UX, accessibility, SEO, and architecture diagram
  What to do / Must NOT do: Fix 375px FFI header/grid overflow, add replacement mobile navigation, semantic `<main>`/nav label/skip link, focus-visible styling, reduced-motion CSS, contrast, image dimensions, canonical/OG/Twitter/theme metadata, and direct/clear CTA states. Preserve the three-layer architecture concept.
  Parallelization: Wave 4 | Blocked by: 12 | Blocks: 17
  References (executor has NO interview context - be exhaustive): `docs/index.html` architecture CSS/markup; mobile media query; hero/nav/download sections.
  Acceptance criteria (agent-executable): Playwright at 375/768/1280 reports no horizontal overflow, no clipped CJK/ASCII text, no layer overlap; all nav anchors resolve; keyboard focus is visible; metadata and landmarks are present; contrast checks meet WCAG AA for normal text.
  QA scenarios (name the exact tool + invocation): happy: desktop/tablet/mobile page navigation and architecture section; failure: 375px long CJK/long code tokens, reduced motion, keyboard-only navigation, broken asset; save screenshots/DOM metrics task-15.
  Commit: Y | `fix(pages): harden responsive architecture and accessibility`

- [ ] 16. Reconcile documentation, versions, and product claims
  What to do / Must NOT do: Add v0.7.4/v0.7.5-appropriate CHANGELOG entry, align Cargo.toml/Cargo.lock/HANDOVER/VERIFICATION/README/Pages/Release claims, fix broken DEVELOPMENT/make links, and correct AI-tagging claims to actual capability. Do not claim content indexing or AI support before shipped.
  Parallelization: Wave 5 | Blocked by: none | Blocks: 17,18
  References (executor has NO interview context - be exhaustive): `README.md`; `CHANGELOG.md`; `docs/{HANDOVER,VERIFICATION,MIGRATION_LOG}.md`; `docs/index.html`; `rust-core/Cargo.toml`; `Cargo.lock`; `Makefile`; Git tags/releases.
  Acceptance criteria (agent-executable): version scan has one declared release version per artifact; every README/docs link resolves; CHANGELOG matches Release notes; AI/content-index wording reflects shipped behavior; `make` help targets match README.
  QA scenarios (name the exact tool + invocation): happy: link checker and version consistency script; failure: deliberately stale version/link fixture is detected; Evidence task-16.
  Commit: Y | `docs: reconcile v0.7.5 release documentation`

- [ ] 17. Add CI, shared schemes, reproducible package, signing, notarization, and checksums
  What to do / Must NOT do: Add PR CI (Rust on Linux/macOS, Xcode tests on pinned macOS/Xcode runner, Pages validation), shared Xcode scheme, package script with fail-closed signing verification, deterministic DMG/ZIP/checksum generation, Developer ID signing, App Store Connect API-key notarization/stapling, and release-only smoke checks. Keep notarization secrets in CI secrets; fail closed if release secrets are absent.
  Parallelization: Wave 5 | Blocked by: 1,3,6,9,11,14,15,16 | Blocks: 18
  References (executor has NO interview context - be exhaustive): `.github/workflows/` absent; `scripts/package.sh`; `scripts/build-rust.sh`; `FlowFinderNative.xcodeproj`; `FlowFinderNative/Package.swift`; tracked `Libraries/`; `dist/` artifacts; GitHub Release process.
  Acceptance criteria (agent-executable): PR CI runs Rust tests/lints and Xcode tests; release CI builds pinned arm64 artifact, signs, verifies signature as a hard gate, notarizes/staples when secrets exist, emits DMG/ZIP/SHA256, and uploads only after all checks; no stale tracked generated binaries are required for a clean checkout.
  QA scenarios (name the exact tool + invocation): happy: release dry-run with test credentials and artifact verification; failure: invalid signature, missing notarization secret, failed test, missing Rust dylib all fail the job; Evidence task-17.
  Commit: Y | `ci(release): add reproducible v0.7.5 release gates`

- [ ] 18. Execute v0.7.5 release checklist without mutating v0.7.4
  What to do / Must NOT do: Build from a clean checkout, run all tests/QA, generate signed/notarized artifacts/checksums, publish a new tag/Release and Pages update only after gates pass. Do not force-push, retag, or edit v0.7.4.
  Parallelization: Wave 5 | Blocked by: 17 | Blocks: final verification wave
  References (executor has NO interview context - be exhaustive): v0.7.4 tag/Release; new CI workflow; package artifacts; README/CHANGELOG/docs; release checklist.
  Acceptance criteria (agent-executable): clean checkout reproduces the same version; `git diff` is empty before tag; v0.7.4 object unchanged; v0.7.5 assets install/open, signature/notarization/checksum validate, Pages reports built, Release notes match changelog.
  QA scenarios (name the exact tool + invocation): happy: install DMG and launch app; failure: corrupted checksum, blocked Gatekeeper/notarization, missing asset, stale Pages version; Evidence task-18.
  Commit: Y | `release: publish v0.7.5 after all gates`

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [ ] F1. Plan compliance audit: verify every Must-have, Must-NOT-have, dependency, acceptance criterion, and evidence path against the final diff and test artifacts; fail on unplanned behavior or missing task evidence.
- [ ] F2. Code quality/security review: run Rust clippy/UB review, Swift compiler diagnostics, FFI ABI comparison, oversized-file check, and targeted security review; require no unresolved P0/P1.
- [ ] F3. Real manual QA: execute AppKit primary-flow smoke matrix and Playwright Pages matrix at 375/768/1280 plus keyboard/VoiceOver/reduced-motion checks; archive screenshots/logs.
- [ ] F4. Scope fidelity/release audit: verify v0.7.4 is unchanged, v0.7.5 artifacts match source/version/docs, notarization/checksums pass, and no legacy/out-of-scope files changed.

## Commit strategy
- One commit per todo, grouped by wave; no squashing across safety, content-index, UI/accessibility, docs, and release boundaries.
- Use conventional messages shown on each todo; generated release artifacts stay out of source control unless the repository policy explicitly requires them.
- Tag only after todo 18 and final wave pass; never amend or force-push v0.7.4.

## Success criteria
- All P0/P1 findings have regression tests or explicit executable QA evidence and no unresolved failure.
- Content search is index-backed, cancellable, migration-safe, and never performs per-result main-thread file reads.
- Primary AppKit flows expose correct loading/error/empty states and pass accessibility/keyboard/manual QA.
- Rust/Swift FFI contracts are layout-checked, ownership-documented, and tested on both success and malformed-input paths.
- Pages passes mobile/tablet/desktop responsive and accessibility checks with no architecture overflow or stale claims.
- CI can build/test from a clean checkout; release packaging fails closed on signature/notarization/checksum errors.
- v0.7.4 remains byte/history immutable; v0.7.5 is published only after all gates pass.
