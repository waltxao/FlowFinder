# Wave 3 实现计划 — 交互反馈补全（拖拽/手势/进度/合帧）

> **执行方式：** 单实现子代理 + 独立审查。审计依据：`.superpowers/audit/drag-gestures-scroll.md`（拖拽/手势/菜单）、`.superpowers/audit/async-performance.md`（P1-4 xattr 预热 / P1-5 风暴合帧 / 进度缺口）。
> **设计依据：** 蓝图 `docs/superpowers/specs/2026-08-30-native-experience-blueprint.md` §3。

## Global Constraints

- 简体中文注释；不新增文件；pbxproj 不碰；Libraries/* 不提交。
- 每任务后 `make swift-test > /tmp/ff-w3-tN.log 2>&1` 落盘判读 94/94。已知抖动：DuplicateScanBrowseRegressionTests（重跑一次）。
- 用户偏好红线：拖拽/手势行为与 Finder 对齐；不破坏既有拖拽移动/复制/⌘ 反转/冲突/撤销闭环（审计确认质量很高，只增不破）。
- 主线程纪律（Wave 1 后仍有效）：新引入的 I/O 一律后台 + 主线程回调。

## Task 1: Drop 目标高亮（drag P0-1）

**Files:** `UI/FileListView.swift`（draggingUpdated ~:1700 区域 / draggingExited）、`UI/FileGridView.swift`（draggingUpdated ~:1186-1200 / draggingExited）、`UI/FFCommon.swift`（如需共享高亮样式）
**要求：**
1. 列表：draggingUpdated 命中文件夹行（drop 提案 `.on`）时高亮该行（accent 色 8% 底 + 1.5pt accent 圆角描边，行级 overlay 或自定义 rowView 状态位 + invalidateRow）；落行间（`.above`）保持系统插入线；draggingExited / drop 完成后复位。用 NSDraggingInfo 的 destination 概念只保留当前目标行（换行先清旧）。
2. 网格：拖到文件夹 item 上高亮该 item（同语言）；拖到空白区高亮整个容器边框（表示落入当前目录）；draggingExited 复位。
3. 高亮实现走视图状态 + setNeedsDisplay/invalidate，不做动画堆叠；拖拽结束（concludeDragOperation/exit）必须清全部状态。
**验收：** 拖拽悬停文件夹有清晰高亮；移开复位；松手后无残留。

## Task 2: Spring Loading 驻留展开（drag P0-2）

**Files:** 同上两文件
**要求：**
1. draggingUpdated 悬停在文件夹上时启动 1.0s 驻留计时（DispatchWorkItem 可取消）；到期且仍在同一文件夹 → navigate(to: folder)（复用既有打开逻辑）并结束拖拽会话视觉状态（拖拽中途换目录后 drop 落新目录——与 Finder 一致）。
2. 目标变化（换行/换 item/退出）立即取消计时。拖拽结束取消。防重入：同文件夹只触发一次。
**验收：** 拖文件悬停文件夹 1 秒自动进入该文件夹。

## Task 3: 拖拽复制/移动接进度条（async 进度缺口）

**Files:** `UI/FileListView.swift:1760-1806`、`UI/FileGridView.swift:1225-1274`
**要求：**
1. 拖拽 acceptDrop 的后台 copy/move 接 progress 回调 → TaskProgressBar 直连模式（照抄粘贴路径 MenuActions.swift:101-102 的接线）。
2. 完成/失败主线程提示（失败复用既有错误弹窗；成功后列表刷新已有则保留）。
**验收：** 拖拽复制大文件出现进度条，完成后列表更新。

## Task 4: 网格拖入文件夹对齐列表（drag §1.2）

**Files:** `UI/FileGridView.swift:1218` 附近
**要求：** draggingUpdated 命中文件夹 item 时记录目标文件夹（drop 提案 `.on`），acceptDrop 用该文件夹作为目标目录（替代恒 currentPath）；空白区仍落 currentPath。与 Task 1 的网格高亮同源状态。
**验收：** 网格里拖文件到文件夹上松手 = 移入该文件夹。

## Task 5: 两指轻扫前进后退（drag P1）

**Files:** `UI/MainWindowController.swift`（面板容器层）或 FileListView/FileGridView 共同宿主
**要求：**
1. `swipeWithEvent`（面板容器 NSView 覆写）：右滑（isDirectionInvertedFromDevice 判定自然方向）→ goBack；左滑 → goForward。两面板各自响应。
2. 防抖：动画进行中忽略重复轻扫（500ms 节流即可）。
**验收：** 触控板两指左右轻扫 = 后退/前进（有历史时）。

## Task 6: FSEvents 风暴合帧 + invalidate 后台化（async P1-5）

**Files:** `UI/MainWindowController.swift:1349-1397`（Wave 1 改后的 handleFileSystemChange）
**要求：**
1. 0.3s 合帧：事件路径进 `Set<String>`（锁保护或主队列串行）+ 0.3s Timer flush；flush 时对去重后的路径集批量 invalidate（一次后台调用）+ 每面板一次 refresh（只刷受影响面板）。
2. invalidateCache 调用移后台（Wave 1 已部分完成——确认路径批量版不再有主线程 semaphore 往返）。
**验收：** 代码审查（风暴场景难以自动化）；单事件延迟 ≤0.3s 可接受（文档注明取舍）。

## Task 7: tags 批量后台预热（async P1-4）

**Files:** `Model/PaneState.swift`（loadDirectory 完成回调处）、`Bridge/TagBridge.swift`（新增批量预热方法，内部循环读但整体在后台）
**要求：**
1. TagBridge 增加 `warmCache(paths: [String])`：后台队列循环 getTags（填充缓存），完成后如主线程在展示同目录则发一次轻量刷新通知（可选，若渲染已读缓存则无需）。
2. loadDirectory 成功后（主线程收到结果时）取 allFiles 前 500 条路径调用预热（后台）。
**验收：** 首次进入大目录后滚动不再有逐条 xattr 卡顿（代码审查 + 逻辑推演）。

## Task 8: 全量验证

- `make swift-test` 94/94；分任务提交（`feat(ui): …`/`perf(ui): …`）。

## 审查要点（审查者用）

- Task 1/2/4：拖拽状态机复位完备（换目标/退出/松手/取消四路）；Spring Loading 与 Drop 高亮共存不冲突；不破坏既有 acceptDrop 语义（⌘ 反转/冲突/撤销）。
- Task 3：进度回调线程 ffi→main；失败路径不吞错。
- Task 5：轻扫方向判定与自然滚动一致；节流防抖。
- Task 6：合帧后单事件延迟与去重正确性；无主线程 semaphore 往返残留。
- Task 7：预热不阻塞主线程；与既有 tagFilter 异步路径不打架。
- 全局：简体中文；无新文件；测试基线 94。
