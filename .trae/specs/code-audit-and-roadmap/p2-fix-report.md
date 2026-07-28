# P2 Review Fixes — Report

日期: 2026-07-23
提交信息: `fix: P2 review findings — 部分失败错误细节、parallel_move 测试、选中保留、文档措辞`

## 修复总览

### Fix 1 — PaneState.deleteSelected 在全部删除失败时保留选中
- 文件: `FlowFinderNative/FlowFinderNative/Model/PaneState.swift` (lines 188-208)
- 变更: `deleteSelected()` 现在按 `success` 计数分支处理：
  - `success == 0`（全部失败）: 保留 `state.selectedFiles` 不清空，不调用 `loadDirectory()`，仅设置错误信息，便于用户重试。
  - `success > 0`（至少一个成功）: 清空选中并 `loadDirectory()`；若 `success < paths.count` 仍提示部分失败。
- 说明: `parallelDelete` 仅返回成功计数，无法映射到具体存活的条目，因此只要有任意成功就清空全部选中（与旧版“至少删一个就刷新”行为一致）。

### Fix 2 — 补充 ff_parallel_move / parallel_move_files 测试
- 文件: `rust-core/src/core/parallel_ops.rs` (lines 138-168) — 新增 `test_parallel_move_files`
  - 创建 3 个源文件，调用 `parallel_move_files` 移到目标 tempdir。
  - 校验结果数、全部 `is_ok`、进度回调触发 3 次、目标文件存在且内容匹配、源文件已消失。
- 文件: `rust-core/src/ffi/mod.rs` (tests, `test_ff_parallel_move`) — 新增 FFI 层测试
  - 创建 3 个源文件，经 `ff_parallel_move` 移到目标 tempdir。
  - 校验返回值 = 3、目标文件存在且内容匹配、源文件不存在。
- 注: 两个 tempdir 同卷，走 `rename` 快速路径；跨卷 fallback 由已测的 `copy_single` + `remove_file` 覆盖。

### Fix 3 — 部分失败保留错误细节
- 文件: `rust-core/src/ffi/mod.rs`
  - 新增 import `use std::io;` (line 19)
  - 新增辅助函数 `summarize_parallel_failures(results, max_entries)` (lines 67-101): 汇总失败条目为 `"N/M failed: /path/a (err), /path/b (err)"`，超过 `max_entries` 则尾部追加 `", … and X more"`。
  - 三个函数 `ff_parallel_copy` / `ff_parallel_move` / `ff_parallel_delete` 末尾改为: 若 `success < results.len()` 调用 `set_last_error(summarize_parallel_failures(&results, 5))`；否则 `clear_last_error()`。返回值语义不变（仍为 `success as c_int`）。
- 效果: Swift 侧在部分失败时可通过 `ff_last_error` 拿到具体失败路径与错误原因，不再只有“X 项失败”的笼统提示。

### Fix 4 — ff_cache_init 文档措辞
- 文件: `rust-core/src/ffi/mod.rs` (lines 1075-1080)
- 变更: 原文档 “Subsequent calls are idempotent … without re-initializing” 与实现（每次调用 `init_cache` 即 `CREATE TABLE IF NOT EXISTS`）不符。改为: “Subsequent calls re-assert the schema idempotently (`CREATE TABLE IF NOT EXISTS`) but do not change the stored database path — the path is set once via a `OnceLock` …”，准确反映“路径仅设置一次、schema 每次幂等重断言”的实际行为。

## 验证结果

### cargo check
```
Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.98s
```
退出码 0，无错误（仅保留既有 14 条与本次改动无关的 warning）。

### cargo test (输出尾部)
```
test core::parallel_ops::tests::test_parallel_delete_files ... ok
test core::parallel_ops::tests::test_parallel_copy_files ... ok
test core::parallel_ops::tests::test_parallel_move_files ... ok
...
test ffi::tests::test_ff_parallel_copy_null_inputs ... ok
test ffi::tests::test_ff_parallel_delete_null_inputs ... ok
test ffi::tests::test_ff_parallel_copy_empty ... ok
test ffi::tests::test_ff_parallel_delete ... ok
test ffi::tests::test_ff_parallel_move ... ok
test ffi::tests::test_ff_parallel_copy ... ok
...
test result: ok. 86 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.15s
```
退出码 0。新增的两个测试 `test_parallel_move_files` 与 `test_ff_parallel_move` 均已运行并通过。总计 86 通过 / 0 失败。

## 关注点 / Concerns

1. **跨卷 move fallback 未直接测试**: 同卷测试走 `rename` 快速路径；跨卷 copy+delete fallback 依赖已测试的 `copy_single`/`remove_file`，未单独构造跨挂载点场景（测试环境中难以可靠创建）。如需端到端覆盖需引入第二个挂载点。
2. **Swift 侧错误细节消费未联调**: Fix 3 让 `ff_last_error` 在部分失败时携带汇总字符串，但本次未运行 xcodebuild，未验证 Swift `CoreBridge` 是否已将 `lastError` 透传到 `PaneState.error`。属后续 Swift 侧联调事项，不影响本次 Rust 侧正确性。
3. **Fix 1 选中清理策略**: 当部分成功时仍清空全部选中（API 仅返回计数）。若未来 `parallelDelete` 能返回逐条结果，可改为只移除成功项以保留失败项选中。
4. **提交范围**: 严格按要求仅 stage 3 个源文件（PaneState.swift、parallel_ops.rs、ffi/mod.rs），未包含本报告 .md 与任何 .build 产物。Rust 静态库 `.a`/`.dylib` 二进制变化未提交（按要求无需重建/拷贝）。
