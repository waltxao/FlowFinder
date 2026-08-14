# T7 Deliverable — Content Index Swift FFI + App 接线 + SearchPanel 状态集成 (Wave2)

**Status:** ✅ Complete
**Design authority:** `.omo/evidence/flowfinder-v074-complete-fix/task-5/content-index-contract.md`
**FFI authority:** `rust-core/include/ff_ffi.h` + `rust-core/src/ffi/mod.rs`（实际签名，未猜）

## 交付文件清单

| 文件 | 改动 |
|---|---|
| `FlowFinderNative/FlowFinderNative/Bridge/FFIFunctions.swift` | 新增 `ContentIndexStatus`/`ContentIndexMode` 枚举（raw value 对齐 header #define）+ 9 个 `ff_content_index_*` `@_silgen_name` 声明（加在 FSEvents 段之后，与 header 段位一致）。**修复**：删除与 bridging-header C import 冲突的 `ff_cancel_scan_by_id`/`ff_cancel_search_by_id` 两处重复 `@_silgen_name` 声明（ambiguous 归零）。 |
| `FlowFinderNative/FlowFinderNative/Bridge/SearchBridge.swift` | 未改动（调用点与 C import `ff_error_t` 返回天然兼容）。 |
| `FlowFinderNative/FlowFinderNative/Bridge/ContentIndexBridge.swift` | **新建**。`ContentIndexBridge` 单例封装 9 个 FFI（init/status/start/cancel/pause/resume/markDirty/query/stats）+ `ContentIndexStats` JSON 解析。 |
| `FlowFinderNative/FlowFinderNative/App/AppDelegate.swift` | 新增 `initContentIndex()`（解析 `content_index.sqlite` 路径并调用 `ContentIndexBridge.shared.initialize`，失败仅 NSLog 不阻断启动），在 `initPersistentDirectoryCache()` 之后调用。 |
| `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift` | `handleFileSystemChange` 增加一行 `ContentIndexBridge.shared.markDirty(path: changedPath)` 转发（复用单一全局 FSEvents watcher）。 |
| `FlowFinderNative/FlowFinderNative/UI/SearchPanelController.swift` | 删除 `fileContainsText`（主线程 `Data(contentsOf:)`）；`applyFiltersAndReload` 改为「异步一次索引查询 → 匹配路径 `Set<String>` → O(1) 成员过滤」；新增内容索引状态栏 UI（6 状态 + 构建/取消/继续/重试/重建入口）+ 0.5s 轮询。 |
| `FlowFinderNative/Tests/FlowFinderNativeTests/ContentIndexBridgeTests.swift` | **新建**。枚举 raw value、stats JSON 解码、单例测试（T11 接入 target）。 |

未改：`rust-core/**`、`project.pbxproj`、`Package.swift`、`SearchFilterSidebar.swift` 及其它 UI 视觉文件。

## FFI 对比结果（9/9 无差异）

`FFI-signature-check.log`：header 9 个 `ff_content_index_*` 与 Swift `@_silgen_name` 符号集合 `diff` 为空，逐一签名对齐：

| header | Swift | 说明 |
|---|---|---|
| `ff_error_t init(const char*)` | `(_ dbPath: UnsafePointer<CChar>) -> Int32` | `const char*` 借用；ff_error_t↔Int32 ABI 等价 |
| `int status(void)` | `() -> Int32` | 返回 `int`，非 ff_error_t |
| `ff_error_t start(const char*, int, uint64_t*)` | `(_ rootPath: UnsafePointer<CChar>, _ mode: Int32, _ outHandle: UnsafeMutablePointer<UInt64>?) -> Int32` | out_handle 可空 |
| `ff_error_t cancel/pause/resume(uint64_t)` | `(_ handle: UInt64) -> ff_error_t` | **返回 ff_error_t（见下）** |
| `ff_error_t mark_dirty(const char*)` | `(_ path: UnsafePointer<CChar>) -> Int32` | 借用 |
| `ff_error_t query(const char*, size_t, FFSearchCallback, void*)` | `(_ query: UnsafePointer<CChar>, _ maxResults: Int, _ callback: @convention(c)(UnsafeRawPointer?, UnsafeMutableRawPointer?)->Void, _ userData: UnsafeMutableRawPointer?) -> Int32` | 回调借用 |
| `char *stats(void)` | `() -> UnsafeMutablePointer<CChar>?` | 出参所有权，`ff_free_string` 释放 |

**关键 ABI 决策（cancel/pause/resume 返回 `ff_error_t` 而非 `Int32`）**：`ff_ffi.h` 已通过 bridging header 把全部 9 个函数导入 Swift。cancel/pause/resume 的唯一入参是标量 `UInt64`（silgen 与 C import 参数类型完全相同），若 silgen 用 `Int32` 返回、C import 用 `ff_error_t` 返回，构成「同名同参、仅返回类型不同」的**歧义重载**（swiftc 报 `ambiguous use`）。改为 `ff_error_t` 与 header 逐字一致后与 C import 合并，无歧义。其余 6 个函数因含指针/回调参数（silgen 非可选 vs C import `!` 可选）天然可区分，沿用 `Int32` 返回与现有代码库一致。ABI 均未变（C enum = int = 32 位）。

## 内容索引状态行 UI（契约 §6.2 逐状态唯一映射）

| 状态 | 状态行文案 | 动作按钮 | 进度条 |
|---|---|---|---|
| empty | 内容索引尚未构建 | 构建索引（start incremental） | 隐藏 |
| indexing | 正在构建内容索引… / 已暂停 | 取消 / 继续（paused 时 resume） | 显示（total>0 确定进度，否则转圈） |
| ready | 内容索引就绪（N 个文件） | 重建（start rebuild） | 隐藏 |
| error | 内容索引错误：<msg> | 重试（start incremental；Rust 端损坏自动备份重建） | 隐藏 |
| cancelled | 内容索引构建已取消 | 继续构建（start incremental，从 checkpoint 恢复） | 隐藏 |
| unavailable | 内容搜索不可用 | 无（隐藏） | 隐藏 |

内容筛选逻辑（`SearchPanelController`）：
- `matchContent && 索引 ready`：`ensureContentMatches` 在 `ffiQueue` 上**一次** `ff_content_index_query`（转义后 phrase 查询，maxResults 500），结果缓存为 `Set<String>`；`reloadFilteredResults` 用 `matches.contains(result.path)` O(1) 过滤，**不再逐文件读**。
- `matchContent && 索引非 ready`：`contentMatches = nil`，内容筛选禁用（不过滤、不降级到 `Data(contentsOf:)`），状态行提示当前状态与构建入口。
- 竞态防护：`searchGeneration` 代次校验 + `contentQueryInFlight` 去重；迟到查询结果在代次不匹配时直接丢弃，不影响新查询。

## 验证结果

1. **swiftc -parse（语法）**：`swift-parse.log` —— 6 个新增/修改文件全部 exit 0，无语法错误。
2. **FFI 签名对比**：`FFI-signature-check.log` —— 9/9 符号 `diff` 为空，无差异。
3. **全模块 swiftc -typecheck**（`typecheck.log`，xcodebuild 不可用——本机仅 CommandLineTools，故 typecheck 是可用最强编译检查）：**0 errors**（ambiguous 修复后；108 条既有 warning 已记录）。
4. **不变量核查**：`Data(contentsOf:)` / `fileContainsText` 在 SearchPanelController 中已零残留；FSEvents watcher 仅 1 个（MainWindowController 既有 `startFSEventsWatcher`，未新增）；`markDirty` 转发已就位。
5. **LOC**：ContentIndexBridge.swift 154（健康）；AppDelegate 126；SearchPanelController 为既有大文件（非本次新增规模，任务明确禁止大规模视觉重构，未拆分）。

## 给 T11 的 pbxproj/工程文件清单

T11 需将以下文件加入 Xcode target 成员（本次按 scope 未改 pbxproj）：

1. `FlowFinderNative/FlowFinderNative/Bridge/ContentIndexBridge.swift`（新建）
2. `FlowFinderNative/Tests/FlowFinderNativeTests/ContentIndexBridgeTests.swift`（新建；测试 target 尚未接入 Package.swift，`@testable import FlowFinderNative` 依赖 T11 统一加入）

## ambiguous 修复（T9 FFI 与 `@_silgen_name` 冲突，本任务收尾）

**根因**：T9 将 `ff_cancel_scan_by_id(uint64_t)` / `ff_cancel_search_by_id(uint64_t)` 加入 `ff_ffi.h`，bridging header（`FlowFinderNative-Bridging-Header.h` → `ff_ffi.h`）自动导入为 `ff_error_t` 返回；`FFIFunctions.swift` 同时用 `@_silgen_name` 以 **`Int32` 返回** 重复声明这两个标量入参函数，构成「同名同参、仅返回类型不同」的歧义重载，`SearchBridge.swift:79` 与 `:165` 报 `ambiguous use`。

**修复（遵循项目 FFI 约定：保留一个明确来源）**：从 `FFIFunctions.swift` **删除**这两处重复 `@_silgen_name` 声明（`ff_cancel_scan_by_id(_:) -> Int32`、`ff_cancel_search_by_id(_:) -> Int32`），改为依赖 bridging header 的 C import（`ff_error_t` 返回）为唯一来源。未用别名/重命名掩盖。调用点 `SearchBridge.swift:79/165` 无需改动（结果弃用，C import 返回 `ff_error_t` 天然兼容）。

**已删除的声明**：
- `FFIFunctions.swift`（原 320-321 行）`@_silgen_name("ff_cancel_scan_by_id") public func ff_cancel_scan_by_id(_ handle: UInt64) -> Int32` → 移除，仅留文档注释说明由 header 导入。
- `FFIFunctions.swift`（原 390-391 行）`@_silgen_name("ff_cancel_search_by_id") public func ff_cancel_search_by_id(_ handle: UInt64) -> Int32` → 移除，仅留文档注释说明由 header 导入。

**保留**：`ff_cancel_scan()`（无参，`void`，与 header 一致）与全部 9 个 `ff_content_index_*` `@_silgen_name` 声明（返回类型已与 header 逐字对齐，如 cancel/pause/resume 返回 `ff_error_t`，无歧义）。

**验证**：全模块 `swiftc -typecheck`（命令见 `typecheck.log`）**0 errors**；108 条 warning 均为既有（SidebarView/SettingsSectionView/MainWindowController 等 deprecation/NoUsage，与 T7 改动无关）。

**同类潜在隐患（未触发 error，未改动，供 T11/后续参考）**：`ff_fsevents_stop`/`ff_fsevents_status`/`ff_dir_cache_clear`/`ff_task_clear_history`（标量/无参 + `ff_error_t` 返回）若未来被调用且与 silgen `Int32` 返回并存，同样会歧义。当前未被调用所以 typecheck 不报；如需清理可统一改为返回 `ff_error_t` 或删除重复 silgen 声明。

## 行为边界（文档化）

- 内容索引构建 root = `NSHomeDirectory()`（与 FSEvents watcher 范围一致）。全局 Spotlight 搜索命中 home 之外的路径时，内容筛选因索引范围不含该路径而将其排除——这是索引范围固有限制，原 `fileContainsText` 可读任意路径，行为已改变（契约意图：索引覆盖 home 目录）。
- 内容匹配为 FTS5 大小写不敏感；`caseSensitive` 开关仍作用于文件名匹配（原行为保留）。
- `swift build`（SPM 路径）本机因无 Xcode 的 `actool` 无法执行，且 SPM 无 bridging header 导致既有 `ff_last_error` 亦无法解析——属既有环境/工程配置问题，非本任务引入；权威构建为 Xcode（bridging header 导入 ff_ffi.h）。
