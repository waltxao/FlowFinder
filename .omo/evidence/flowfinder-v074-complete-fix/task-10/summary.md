# Wave3 T10 — PaneState 与后台文件操作状态机

状态结论: **完成**。删除/撤销/重做文件系统 I/O 全部后台化、tag+query 组合过滤缺口修复、
typed 删除失败状态 + 通知就绪、失败项保留与多目录缓存失效复核一致。

采集日期 2026-08-13。改动仅限 `Model/PaneState.swift` + 新增独立测试文件，未触碰
`FFIFunctions.swift` / `rust-core/**`（T9/T7 并行范围）/ UI 视图 / `SearchPanelController`。

## 1. 改动文件清单

| 文件 | 改动 |
|---|---|
| `FlowFinderNative/FlowFinderNative/Model/PaneState.swift` | +254 / -114 行（后台化删除/撤销/重做 + 组合过滤 + 状态机） |
| `FlowFinderNative/Tests/FlowFinderNativeTests/PaneStateDeleteFilterTests.swift` | 新增（6 个测试） |

未修改（避免与 T7/T9 冲突）：`Bridge/FFIFunctions.swift`、`Bridge/CoreBridge.swift`、
`rust-core/**`、`UI/**`、`SearchPanelController.swift`。

## 2. 后台化方案（deliverable 1）

### 2.1 deleteSelected

```
主线程: 快照 selectedFiles → deleteOperationGeneration 自增 → state.isDeleting=true
        → DispatchQueue.global(.userInitiated) 派发
后台:   for entry in toDelete { trashItem(at:resultingItemURL:) }，收集 trashedItems / failedPaths
        → DispatchQueue.main.async 回主线程
主线程: 代次校验(deleteOperationGeneration==generation) 不符即丢弃 → finishDelete(...)
```

`finishDelete`（主线程）职责：
- 注册撤销（`undoManager?.registerUndo` **必须在主线程**，语义保持）
- 多目录缓存失效（`Self.parentDirectories(of:)` 逐目录 `invalidateCache`）
- 失败项保留选中集 / 成功项移除
- 更新 `state.error` / `state.deleteFailedPaths` / `state.isDeleting=false`
- 发 `.paneFileOperationChanged` 通知

关键点：`trashItem` 返回的 `resultingURL`（废纸篓 URL）在后台捕获、通过
`trashedItems: [(originalPath: String, trashURL: URL)]` 正确传回主线程，供撤销恢复用，
URL 传递未丢失。

### 2.2 undoTrashRestore / redoTrashRestore

```
主线程: registerUndo（注册 redo/反向 undo，必须在主线程）→ generation 自增 → isDeleting=true
后台:   moveItem（undo）或 trashItem（redo）循环，收集失败路径
主线程: 代次校验 → 失效缓存 → 更新 state → 发通知 → 按需 loadDirectory
```

- undo 恢复 `moveItem(at: trashURL, to: originalPath)` 的 URL 传递保持。
- 修复一处隐性不一致：原 undo 仅失效 `items.first` 的父目录；现改为逐目录失效
  （与 deleteSelected 一致，见 §5）。

### 2.3 取消/代次机制

新增 `private var deleteOperationGeneration: Int`。每次 `deleteSelected` /
`undoTrashRestore` / `redoTrashRestore` 发起时自增；后台完成回主线程后校验
`deleteOperationGeneration == generation`，不符即丢弃（`[DELETE-DIAG] ... 丢弃过期完成`）。
避免「删除→删除」「删除→撤销→重做」快速连续操作时旧后台完成回调覆盖新状态。

### 2.4 非阻塞证据（日志时间戳）

后台执行通过 `FFDebug.log`（写入 `/tmp/ff-debug.log`，含 `HH:mm:ss.SSS` 时间戳 + 线程标记）：
- `[DELETE-DIAG] deleteSelected 派发后台 ... isMainThread=true`
- `[DELETE-DIAG] deleteSelected 后台开始 ... isMainThread=false`（关键：I/O 在非主线程）
- `[DELETE-DIAG] deleteSelected 后台完成 ...`

测试 `testDeleteIsNonBlocking` 以确定性的方式断言：`deleteSelected()` 返回后
`state.isDeleting == true`（主线程未阻塞、I/O 尚在后台），随后等通知断言 `false`。

## 3. 组合过滤修复（deliverable 2）

原 `applyFilter` 在 `tagFilter != nil` 时**提前 return，漏掉 searchQuery 过滤**（组合过滤缺口）。
修复：抽出静态纯函数 `filterEntries(entries:tagFilter:searchQuery:)`，先标签后查询取交集：

```swift
static func filterEntries(_ entries: [FileEntry], tagFilter: Tag?, searchQuery: String) -> [FileEntry] {
    var result = entries
    if let tagFilter = tagFilter {
        result = result.filter { entry in
            entry.tags.contains(where: { $0.id == tagFilter.id || $0.name == tagFilter.name })
        }
    }
    if !searchQuery.isEmpty {
        let query = searchQuery.lowercased()
        result = result.filter { $0.name.lowercased().contains(query) }
    }
    return result
}
```

`applyFilter` 三条路径（无标签 / 标签全缓存 / 标签后台读 xattr）统一走此纯函数，
因此 tag+query 同时激活时结果 = 交集，与先后顺序无关。`applyFilterPaginated`
同步去重（tagFilter 为 nil 路径也走该纯函数）。

## 4. 可观察状态机（deliverable 3）

`PaneState` 新增字段：
- `var isDeleting: Bool = false` — 进行中标志（供 T12 展示进度/禁用重复操作）
- `var deleteFailedPaths: [String] = []` — typed 结构化失败文件名列表

通知 `Notification.Name.paneFileOperationChanged`（`"PaneFileOperationChanged"`），
userInfo 键：`path`(String)、`deletedCount`(Int)、`restoredCount`(Int)、`failedPaths`([String])。
本任务只保证字段 + 通知正确，UI 外观改动归 T12。

## 5. 失败保留 + 多目录缓存失效复核结论（deliverable 4）

- **失败项保留**：`finishDelete` 中 `remaining = toDelete.filter { failedPaths.contains($0.path) }`
  → `state.selectedFiles = remaining`；成功项移除。行为与原实现一致（原实现冗余
  `loadDirectory()` 双调用已合并为单次）。
- **多目录缓存失效**：抽出 `static func parentDirectories(of paths:) -> Set<String>`
  纯函数去重父目录；deleteSelected / undo / redo 三处统一 `for dir in parentDirs { invalidateCache }`。
  修复原 undo 仅失效首个父目录的不一致。

## 6. 测试追加情况（deliverable 5）

新增 `Tests/FlowFinderNativeTests/PaneStateDeleteFilterTests.swift`（未动既有的
`FlowFinderNativeTests.swift`——该文件引用已删除的 `FileEntryViewModel`/`copyFileAsync`/
`deleteFileAsync`/`unknownError`/`mimeType`，本就不可编译，归 T11 修复）：

| 测试 | 验证点 | 是否依赖 dylib |
|---|---|---|
| `testFilterEntriesTagPlusQueryIntersection` | tag+query 交集 = { report1.txt } | 否 |
| `testFilterEntriesTagOnly` | 仅标签筛选 | 否 |
| `testFilterEntriesQueryOnlyCaseInsensitive` | 仅搜索、大小写不敏感 | 否 |
| `testFilterEntriesTagMatchByName` | 标签按 name 命中（原生标签 id 随机） | 否 |
| `testDeleteFailureRetainsSelectionAndReportsPath` | 失败项保留选中集 + typed 路径 + 错误含路径 | 否 |
| `testDeleteIsNonBlocking` | 删除非阻塞（isDeleting=true 立即断言） | 否（state.path 置空使 loadDirectory 短路） |
| `testParentDirectoriesAcrossMultipleDirectories` | 两目录父集合去重 | 否 |

运行方式说明：
- 当前 `Package.swift` **无 testTarget**、`.xcodeproj` **无测试 target**（`FlowFinderNativeTests.swift`
  为孤儿文件，未挂入任何 build phase）。本机仅 CommandLineTools（无完整 Xcode），
  `xcodebuild test` 不可用（`xcode-select: error: ... command line tools instance`）。
- 正确运行方式：在 Xcode 新建 unit test bundle（依赖已构建的 `libflowfinder_core.dylib`），
  将本文件加入该 target 后 `xcodebuild test`。其中 7 个测试除「多目录」外均不依赖 dylib
  （`deleteSelected` 测试通过 `state.path = ""` 让 `loadDirectory` 短路为 no-op）。

## 7. 语法/类型验证输出

环境限制：无完整 Xcode（仅 CommandLineTools），`xcodebuild`/`swift test` 不可用；无 test target。
故给出 `swiftc -parse`（语法）+ 纯逻辑 `swiftc -typecheck` + 运行时执行证据。

```text
$ swiftc -parse FlowFinderNative/FlowFinderNative/Model/PaneState.swift
exit=0

$ swiftc -parse FlowFinderNative/Tests/FlowFinderNativeTests/PaneStateDeleteFilterTests.swift
exit=0

$ swiftc -typecheck /tmp/t10_typecheck.swift   # filterEntries/parentDirectories/tuple 的忠实复刻
exit=0

$ /tmp/t10_typecheck                            # 运行时执行全部断言
ALL TYPE-CHECKS PASSED
run exit=0
```

纯逻辑复刻文件对 `filterEntries`/`parentDirectories`/`trashedItems` 元组做了类型检查与
运行时断言：交集={report1.txt}、大小写不敏感、按 name 命中、双目录父集合去重均通过。

## 8. 约束遵守清单

| 约束 | 遵守 |
|---|---|
| 未改 FFIFunctions.swift / rust-core/** | ✅（git status 确认其改动为 T9 既有未提交内容，我未触碰） |
| 未改 UI 外观（错误横幅/加载动画归 T12） | ✅（仅加 state 字段 + 通知，无视图改动） |
| 未引入内容索引查询逻辑（T7） | ✅ |
| 无新第三方依赖 | ✅ |
| registerUndo 保持主线程语义 | ✅（finishDelete/undo/redo 的 registerUndo 均主线程） |
| 后台完成回调回主线程更新 state/通知 | ✅（DispatchQueue.main.async + 代次校验） |

## 9. 备注

- `PaneState.swift` 现约 887 纯 LOC（改动前约 790），为既存大文件（任务语境标注「约 1100 行」）。
  拆分属结构重构，超出本任务修复范围且与并行任务冲突风险高，故未拆分，仅做定向修复。
- redo 的 `trashItem(resultingItemURL: nil)` 丢弃新废纸篓 URL 是**既有行为**（导致二次 undo
  时旧 trashURL 失配），属无限撤销/重做闭环的 URL 生命周期问题，不在本任务「后台化 + 组合过滤
  + 状态机」范围内，未改动，供后续 wave 参考。
