---
slug: flowfinder-v074-complete-fix
status: plan-written
intent: clear
review_required: false
pending-action: ask whether to start work or run optional high-accuracy plan review
approach: five-wave remediation plan ordered by safety/correctness, data and search state, FFI/tasks, AppKit UX/accessibility, then Pages/release hygiene; every wave carries tests, manual QA, and release gates.
---

# Draft: flowfinder-v074-complete-fix

## Components (topology ledger)
<!-- Lock the SHAPE before depth. One row per top-level component that can succeed or fail independently. -->
<!-- id | outcome (one line) | status: active|deferred | evidence path -->
- A | File/path safety, batch operations, caches, and search cannot cause traversal, silent overwrite, or UI-blocking I/O | active | rust-core/src/ffi/mod.rs; rust-core/src/core/{batch_ops,file_ops,parallel_ops,search_engine,sqlite_cache,thumbnails}.rs; Model/PaneState.swift; UI/SearchPanelController.swift
- B | FFI ownership, task lifecycle, cancellation, callbacks, and ABI contracts are explicit, tested, and race-safe | active | rust-core/src/core/{fsevents,task_scheduler,dedup_engine}.rs; rust-core/src/ffi/mod.rs; Bridge/{CoreBridge,FFIFunctions,TaskSchedulerManager,SearchBridge}.swift
- C | AppKit product UI exposes errors/loading/empty states, consistent destructive flows, keyboard/accessibility support, and list/grid parity | active | FlowFinderNative/FlowFinderNative/{UI,Model}
- D | Accessibility and maintainability improve without changing the established product visual language | active | UI/*.swift; oversized controllers listed in audit
- E | Pages, README, changelog, versions, tests, CI, schemes, packaging, and release assets are reproducible and consistent | active | docs/index.html; README.md; CHANGELOG.md; docs/{HANDOVER,VERIFICATION}.md; scripts/; Package.swift; project.pbxproj; .github/

## Open assumptions (announced defaults)
<!-- Record any default you adopt instead of asking, so the user can veto it at the gate. -->
<!-- assumption | adopted default | rationale | reversible? -->
- Implementation sequencing | fix P0/P1 data-safety and main-thread blocking before UX polish; establish test/CI gates before v0.7.5 packaging | minimizes shipping regressions and makes later visual changes verifiable | yes
- Test strategy | tests-first for Rust/security invariants; tests-after plus a newly wired Swift XCTest target for AppKit behavior; browser QA for Pages | Rust tests work, Swift tests are currently unreachable, UI needs executable/manual coverage | yes
- Content search | build a dedicated content index with index state, rebuilding/error/empty states, cancellation, and bounded query work | owner selected index-backed content search rather than per-result main-thread reads | cross-cutting but explicit
- Accessibility scope | primary-flow complete coverage: browsing, dual-pane navigation, search, tasks, settings, delete/rename; secondary legacy tools remain sequenced later | near-zero AppKit accessibility metadata makes full-secondary coverage too broad for the first shippable wave | yes
- Release target | include v0.7.5 release gates: signing, notarization, DMG/ZIP/checksum, CI, Pages, and GitHub Release; never mutate v0.7.4 | owner selected a new release gate | v0.7.4 immutable

## Findings (cited - path:lines)
- P0/P1: batch rename validates only original_path, not new_name; parent.join(user input) permits ../ or absolute destinations and existing targets can be overwritten | rust-core/src/ffi/mod.rs:1659-1703; rust-core/src/core/batch_ops.rs:94-123
- P1: PaneState writes state.error and state.isLoading without a unified visible error/loading surface | FlowFinderNative/FlowFinderNative/Model/PaneState.swift; UI/FileListView.swift; UI/FileGridView.swift
- P1: content search reads up to 4MB per result synchronously from applyFiltersAndReload on main | UI/SearchPanelController.swift:fileContainsText/applyFiltersAndReload
- P1: delete/trash and restore loops perform filesystem I/O on main | Model/PaneState.swift:deleteSelected/undoTrashRestore
- P1: FSEventStream setup failure still returns success; watcher may be reported active when absent | rust-core/src/core/fsevents.rs:start_macos
- P1: global dedup cancellation flag makes concurrent scans cancel/un-cancel each other | rust-core/src/ffi/mod.rs:DEDUP_CANCEL; core/dedup_engine.rs
- P1: Rust search is synchronous, uncancellable, and walks the entire root tree | rust-core/src/core/search_engine.rs:63-163
- P1: SQLite cache opens fresh connections without busy_timeout/WAL; concurrent access can surface SQLITE_BUSY | rust-core/src/core/sqlite_cache.rs
- P1/P2: thumbnail cleanup scans the whole cache directory on every cache-path request | rust-core/src/core/thumbnails.rs:cleanup_old_thumbnails/get_thumbnail_cache_path
- P1: Swift XCTest is not wired to an Xcode test target; Package.swift has no test target and tests reference removed FileEntryViewModel | FlowFinderNative/Tests/FlowFinderNativeTests/FlowFinderNativeTests.swift; FlowFinderNative/Package.swift; FlowFinderNative.xcodeproj/project.pbxproj
- P1: no project CI workflow; only Pages deployment exists | .github/ absent; GitHub Actions inventory
- P1: package.sh codesign verification pipes into tail, allowing tail to mask codesign failure | scripts/package.sh:codesign verification block
- P2: tag-filter branch can skip searchQuery filtering when both filters are active | Model/PaneState.swift:applyFilter
- P2: destructive confirmation differs between FFPaneActionsController and MainWindowController/DeleteConfirmDialog | UI/FFPaneActionsController.swift:deleteSelected; UI/MainWindowController.swift; UI/DeleteConfirmDialog.swift
- P2: search result details prompt is never updated after selection | UI/SearchPanelController.swift:detailsLabel and missing selection callback
- P2: grid drop behavior is not equivalent to list drop-on-folder behavior | UI/FileGridView.swift; UI/FileListView.swift
- P2: search window centering defeats frame autosave | UI/SearchPanelController.swift:showPanel
- P2: AppKit UI has essentially no accessibility labels/roles/help across primary surfaces | UI/*.swift audit
- P2: Pages architecture FFI header and module grid overflow/crush at 375px; .arch-layer-ffi margin plus 200px grid minimum | docs/index.html architecture CSS/markup
- P2: Pages lacks main landmark, nav label, skip link, OG/Twitter/canonical/theme metadata; tertiary text has contrast risk | docs/index.html
- P2: Pages mobile hides navigation without replacement menu | docs/index.html mobile CSS/nav
- P2: README/Pages/Release say v0.7.4, but CHANGELOG/Cargo.toml/HANDOVER/VERIFICATION remain stale; README links missing DEVELOPMENT.md and nonexistent make run target | README.md; CHANGELOG.md; rust-core/Cargo.toml; docs/HANDOVER.md; docs/VERIFICATION.md; Makefile
- P3: oversized controllers/modules remain well over the 250-line maintainability ceiling | MainWindowController.swift; FileListView.swift; SidebarView.swift; ExpandableDetailsBar.swift; SettingsWindowController.swift; rust-core/src/ffi/mod.rs
- P3: package process creates DMG but ZIP/checksums/notarization are manual or absent; Xcode scheme is not shared; tracked binary artifacts add drift/repo weight | scripts/package.sh; FlowFinderNative.xcodeproj; Libraries/; dist/

## Decisions (with rationale)
- Preserve v0.7.4 as immutable; fixes target a new patch/minor release (default v0.7.5).
- Keep content search, but make it cancellable/background and explicitly test slow/large files.
- Validate security at Rust FFI boundaries even when Swift UI currently constrains input.
- Do not combine large structural refactors with correctness fixes; split oversized modules only after behavior is covered.

## Scope IN
- Rust path validation, batch conflict semantics, FSEvents failure reporting, dedup cancellation, search cancellation, cache concurrency/freshness, thumbnail cleanup, task-history tests.
- Swift FFI ABI/ownership tests, task lifecycle tests, PaneState filter/error/loading behavior, background filesystem work.
- AppKit error/loading/empty states, destructive-action unification, accessibility metadata/focus/keyboard/reduced-motion/dynamic-type checks, list/grid parity.
- Pages responsive architecture layout, mobile navigation, semantics/metadata/contrast/focus, README/CHANGELOG/docs/version consistency.
- CI for Rust, Swift/Xcode target, Pages validation, package/signing verification, reproducible DMG/ZIP/checksum release workflow.

## Scope OUT (Must NOT have)
- No mutation of the already-published v0.7.4 tag or Release assets.
- No migration from AppKit to SwiftUI, no framework rewrite, no new third-party UI framework.
- No implementation of AI/LLM tagging unless explicitly selected as an owner decision; documentation must reflect actual capability.
- No broad visual redesign of the macOS app beyond consistency/accessibility/state fixes; preserve current visual language.
- No deletion of user-facing content/search features merely to avoid testing or performance work.
- No unrelated legacy projects outside flowfinder-native.

## Open questions
- None blocking. Adopted test strategy: Rust security tests first; Swift XCTest target wiring plus tests-after for existing UI behavior; Playwright for Pages; manual AppKit smoke QA; full build/package verification.

## Approval gate
status: awaiting-approval
approach: Five implementation waves: (1) security/filesystem/search correctness, (2) FFI/tasks/cache reliability, (3) AppKit UX/accessibility/state/parity, (4) Pages/documentation consistency, (5) CI/release gates; each wave ends with executable tests and manual/browser QA before the next wave.
<!-- When exploration is exhausted and unknowns are answered, set status: awaiting-approval. -->
<!-- That durable record is the loop guard: on a later turn read it and resume at the gate instead of re-running exploration. -->
