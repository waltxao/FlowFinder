# Wave 1 实现计划 — 主线程卡顿根治

> **执行方式：** 子代理实现 + 独立审查（控制器协调）。审计依据：`.superpowers/audit/async-performance.md`；设计依据：`docs/superpowers/specs/2026-08-30-native-experience-blueprint.md` §1。
> **For agentic workers:** 按任务顺序实现，每任务一提交。

## Global Constraints

- 简体中文注释；不新增文件；pbxproj 不碰。
- FFI 线程纪律：所有 CoreBridge 调用走全局 `ffiQueue`（串行）；后台化时用 `DispatchQueue.global` 包裹 + 主线程回调刷新 UI；禁止在 ffiQueue 上再 sync 嵌套。
- 进度回调模式参考既有粘贴路径（MainWindowController+MenuActions.swift:101-102 → TaskProgressBar.swift:162-210）。
- 撤销/重做语义必须保留（undo 注册时点、串行队列 MainWindowController.undoRedoQueue 不动）。
- 每步 `make swift-test`（落盘判读）；Rust 无改动则不需 rust-test。
- 收起态/失败态行为不变；watcher 失败时的旧行为（状态机 failed）保持可观察。

## Task 1: ff_fsevents_start 异步化（审计 P0-1）

**Files:** Modify `Bridge/CoreBridge.swift:763-830`、`UI/MainWindowController.swift:309`、`UI/MainWindowController.swift:1349-1368`（handleFileSystemChange 缓冲）

**要求：**
- `startFSEventsWatcher(path:changeHandler:completion:)` 新签名：内部把「stop 旧 watcher + start 新 watcher + 等握手」整体放后台队列，completion(main queue) 回调 active/failed；保留旧签名处编译适配（唯一调用点 MainWindowController.swift:309）。
- `fseventsWatcherStatus()` 的 `ffiQueue.sync` 改为后台缓存原子值（watcher 启动回调时记录），主线程读缓存。
- `handleFileSystemChange`（:1349-1368）：watcher 未 active 期间的事件不丢弃——放入 pendingPaths 合帧集合（与 Task 4 合帧可一并实现，本任务先做简单缓冲：未 active 时 markDirty 已是异步即可，重点是删掉每事件 2 次 invalidateCache 的 semaphore 往返→改为后台队列批量失效）。
- 验收：启动路径无主线程同步等待（代码审查）；watcher 启动失败仍可见（状态机日志/浮层既有链路不回退）。

## Task 2: createFolderFromSelection 后台化 + 进度（审计 P0-2）

**Files:** Modify `Model/PaneState.swift:743-782`、`UI/FFPaneActionsController.swift:452-455`

**要求：**
- createDirectory + parallelMove + 逐项 moveFile 整体移 `DispatchQueue.global`；parallelMove 接 progress 回调（CoreBridge.swift:549 已支持）→ 走 TaskProgressBar 直连模式（参考 MenuActions.swift:101-102 模式）。
- 完成后主线程：invalidateCache + refresh + 选择恢复；失败：主线程弹窗（复用既有错误呈现）。
- 撤销注册语义不变（undo 闭包仍在主线程 UI 层注册，I/O 后台化不影响 undoManager 时序）。
- `FFPaneActionsController.swift:452-455` 调用点适配（无阻塞）。
- 验收：对大文件执行该操作期间 UI 可交互、进度条可见、完成后列表刷新且可撤销。

## Task 3: loadDevices 后台化（审计 P0-3）

**Files:** Modify `UI/SidebarView.swift:1092`（loadDevices 及其调用点 DeviceSidebarDataSource.init :1042、MainWindowController.swift:950 卷挂载/卸载通知）

**要求：**
- listVolumes 调用移 `DispatchQueue.global`，主线程回调更新设备浮层数据源；挂载/卸载通知路径同样异步。
- 首次加载期间设备浮层显示既有空态（不闪烁即可，允许先显示上次缓存数据）。
- 验收：代码审查无主线程 listVolumes；模拟挂载事件（diskutil 触发或重启应用）浮层正常刷新。

## Task 4: 全量验证 + 提交整理

- `make swift-test` 全绿（94）；回归重点：FFDetailsBar 系列、PaneState 系列不回退。
- 手动冒烟：启动应用（切目录/新建文件夹/看侧边栏）无冻结。
- 分任务提交（每 Task 一提交，消息格式 `perf(ui/core): …`）。

## 审查要点（审查者用）

- Task 1：确认无任何路径在主线程等待 fsevents 握手（grep semaphore/recv_timeout 的 Swift 调用方）；completion 是否 main queue；失败路径可观察。
- Task 2：undo 语义保留；进度回调线程正确（ffi 线程→主线程）；错误弹窗不丢路径信息。
- Task 3：无主线程 listVolumes；通知路径不再同步。
- 全局：FFI 串行队列纪律未被破坏（无嵌套 sync）；简体中文注释。
