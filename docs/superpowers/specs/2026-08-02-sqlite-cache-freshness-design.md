# FlowFinder L2 SQLite 目录缓存新鲜度校验设计

> 日期：2026-08-02
> 版本：v0.6.9+（未发版）
> 状态：已批准

## 背景

FlowFinder 的目录缓存为两级结构：

- **L1 内存缓存**（`rust-core/src/core/dir_cache.rs`）：LRU + 5 秒 TTL，过期自动失效。
- **L2 持久化缓存**（`rust-core/src/core/sqlite_cache.rs`）：SQLite 持久化，跨会话保留。

L1 有 TTL 兜底，但 **L2 SQLite 缓存命中时不做任何新鲜度校验**——目录被外部工具（Finder / 终端）修改后，只要没有显式 `invalidateCache` 调用，L2 命中仍会返回陈旧数据。`sqlite_cache::is_cache_fresh`（按目录 mtime 校验）已实现但全项目无调用方（`ffi/mod.rs` 未接线，仅 `sqlite_cache.rs` 内有单测）。

> 备注：交接文档将"sqlite_cache 接入 FFI"列为高优先级待办，但核查代码（提交 `6290983` / `3463490`）后确认 FFI 接线已全部完成（`ff_cache_init` / `ff_cache_get` / `ff_cache_put` / `ff_cache_invalidate` + AppDelegate 启动初始化 + `CoreBridge.listDirectory` 两级查找）。真实缺口仅为 L2 命中缺少新鲜度校验。本设计补齐该缺口。

## 方案

采用方案 A：**Rust 侧 FFI 内联校验**。不改 FFI 签名，在 `ff_cache_get` 的 L2 命中分支（`rust-core/src/ffi/mod.rs`）内：

1. 通过 `std::fs::metadata(path)` 获取目录 mtime（`SystemTime` → 秒级 timestamp）。
2. 调用 `sqlite_cache::is_cache_fresh(db_path, path, dir_mtime)` 判定：
   - **fresh**（`cached_at >= dir_mtime`）→ 命中，写回 L1（现行为不变），返回缓存。
   - **stale** → 调用 `cache_invalidate` 删除该目录的 L2 记录，降级为 miss（返回 `FF_ERR_NOT_FOUND`，触发 live scan 并重新缓存）。
3. **stat 失败**（目录已删除等）→ 按 stale 处理：清理 L2 记录 + 返回 `FF_ERR_NOT_FOUND`，绝不返回幽灵数据。
4. **is_cache_fresh 自身报错** → 按现有 best-effort 约定处理（L2 错误降级为 miss，记录错误，不 panic）。

## 设计细节

### 新鲜度语义

- 目录 mtime 与"直接子项列表缓存"语义匹配：子项创建 / 删除 / 重命名会更新目录 mtime；子项内容修改只更新文件自身 mtime，不影响目录 mtime。
- 秒级精度：`cached_at`（写入时 `chrono::Utc::now().timestamp()`）与目录 mtime 同为秒级，`cached_at >= dir_mtime` 语义正确（缓存写入晚于目录最后修改 → 目录未变 → fresh）。

### 边界与不变式

| 场景 | 行为 |
|---|---|
| L2 命中且 fresh | 返回缓存，写回 L1（现行为） |
| L2 命中但 stale | 删除 L2 记录 → `FF_ERR_NOT_FOUND` → live scan 重新缓存 |
| 目录已被删除（stat 失败） | 清理 L2 记录 → `FF_ERR_NOT_FOUND` |
| is_cache_fresh 查询失败 | 记录错误，降级 miss（best-effort） |
| L1 命中 | 不受影响，L1 5 秒 TTL 保留 |
| 显式 `invalidateCache` | 走原 `ff_cache_invalidate`，不受影响 |

### 改动范围

| 文件 | 改动 |
|---|---|
| `rust-core/src/ffi/mod.rs` | L2 命中分支（约 1354-1373 行）插入 mtime 校验；新增 FFI 级测试 |
| `rust-core/src/core/sqlite_cache.rs` | 无需改动（`is_cache_fresh` 已存在） |

Swift 层（`CoreBridge.swift` / `FFIFunctions.swift`）**零改动**——FFI 签名不变。

### 测试

- 新增 FFI 级测试：构造过期缓存场景（先 put，再 mock 目录 mtime 晚于 cached_at），断言 `ff_cache_get` 返回 `FF_ERR_NOT_FOUND` 且 L2 记录被清除。
- 现有 `is_cache_fresh` 单测（fresh / stale / 幂等 init）保持不动。

## 验证方式

1. `cargo test`（rust-core 全量，含新增测试）。
2. `cargo build --release`，复制新构建的 `libflowfinder_core.dylib` / `.a` 到 `FlowFinderNative/FlowFinderNative/Libraries/`。
3. `xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Debug build` 确认无回归（FFI 签名未变）。

## 非目标（YAGNI）

- 不改 L1 缓存策略（5 秒 TTL 保留）。
- 不引入目录 mtime 的额外存储（直接 stat，避免 schema 变更）。
- 不做缩略图 / 标签等其它 SQLite 持久化的新鲜度校验（`sqlite_cache.rs` 仅服务目录缓存）。
