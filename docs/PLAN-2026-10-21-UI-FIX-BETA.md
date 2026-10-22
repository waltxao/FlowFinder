# PLAN · 0.8.0 Beta 顶栏与交互修复（2026-10-21）

> 状态：**已执行（2026-10-21）**；Task 1–8 全部完成，验证见 SPEC §6。
> 测试位置：工程使用显式 `PBXFileReference`，新增测试统一追加到
> `FlowFinder/Tests/FlowFinderTests/InteractionRegressionTests.swift`，避免手工改 pbxproj。
> 规格：`SPEC-2026-10-21-UI-FIX-BETA.md`
> 纪律：每个行为先写失败测试；不批量写想象测试；全绿后再重构。
> 工作区：当前未提交工作区（106 个文件改动 + 新文档）。**不建 worktree**——HEAD 不含
> 交接后的 UI 改造，worktree 会丢当前基线；不提交、不推送，除非用户明确要求。

## Task 1 · 顶栏度量与纯几何（RED → GREEN）

文件：`FlowFinder/FlowFinder/UI/FFInteractionPolicy.swift`

- 改：`titleBandHeight 36→30`、`inactiveTabHeight 22→24`、`tabSeamFillet 8→9`、
  `titleContentInset(hidden) 106→112`；`tabTopGap` 自动变为 2。
- 新增纯函数：
  - `FFTabStripLayout.leadingOffset(contentInset:wrapperLeading:)`
  - `FFTabStripLayout.firstTabMinX(cardLeading:tabInset:seam:)`（可选）
- 测试：追加到 `InteractionRegressionTests.swift` 的 `FFTopBarLayoutTests`
  - 30/28/24/2/9/16 常量；
  - 隐藏侧栏 offset = 112，可见 offset = 0；
  - 中心线：active center / inactive center / plus center 均为 16（用常量推导）；
  - 隐藏时首标签左缘 ≥ 红绿灯右缘 + 浮动开关宽 + 肩线。
- 命令：`make swift-test` 单文件（xcodebuild `-only-testing`）先红后绿。

## Task 2 · 标签视觉重做

文件：`UI/PaneTabs.swift`、`UI/MainWindowController.swift`

- `PaneTabStripView`：
  - 恢复 `PaneTabStripBackdrop`（`isHidden = false`），填充 = 卡片色；活动标签由背板
    用 `FFTabSilhouette.tabFootprint` 绘制 A1 肩线。
  - stack `alignment = .centerY`；top gap 2；高度约束 active 28 / inactive 24。
  - + 按钮：`FFHoverIconButton` 24×24、图标 13、bottom 2、hover 6pt 圆角底色。
- `PaneTabItemView`：
  - 移除 layer 背景/边框/underline；活动标签透明，交背板绘制。
  - 新增 12pt folder 图标；active 文本 medium + accent 图标，inactive secondary + regular。
  - 关闭 ×：24 命中 / 10 图标 / hover 圆形；active 常显，inactive hover 显示（新增 tracking area）。
  - 标题/× 的 centerY = 0；leading 10，icon-label 间距 5。
- 侧栏：新建 `FFHoverIconButton`（`FFComponents.swift` 或新文件），替换
  `SidebarView.makeSidebarIconButton` 的 NSButton；保持 24×24、16pt 图标、4pt 间距。
- 自检：更新 `MainWindowController+Tabs.swift` 中硬编码 36/8/22/106 的断言，增加
  “标签中心 16 / 非活动 24 / 隐藏侧栏 112 / 首个标签不压浮动开关”。

## Task 3 · 隐藏侧栏避让重算

文件：`UI/MainWindowController.swift`

- `setSidebarVisible` 动画 completion 内调用 `updateTabStripFrames()`。
- `splitViewDidResizeSubviews` / `windowDidResize` 中调用（去重，避免布局环）。
- 测试：`FFTopBarLayoutTests` 覆盖 offset 公式；自检覆盖侧栏隐藏后的真实 frame。
- 复现：启动 → 隐藏侧栏 → 读取 `/tmp/ff-debug.log` 的 `[GEO]` 标签 frame，首标签
  minX 必须 > 浮动开关 maxX。

## Task 4 · 红绿灯关闭修复

文件：`UI/FFPaneDrag.swift`、新增 `UI/FFWindowChrome.swift`

- 新增纯函数：
  - `FFWindowChrome.contains(point:in rects:)`
  - `FFWindowChrome.standardButtonFrames(in window:)`
- `FFPaneDragController.handleDown` 首行：
  命中标准窗口按钮 → `return event`（不设 mode、不 performDrag）。
- 测试：追加 `FFWindowChromeTests`（点命中/边界/空 rects）。
- 实测：构建后启动新实例，用 AX 按 close button，确认窗口关闭且进程仍存活；
  侧栏显示/隐藏两种状态各测一次。

## Task 5 · 同目录拖放无操作

文件：新增 `UI/FFFileDropPolicy.swift`、`UI/FileListView.swift`、`UI/FileGridView.swift`

- 纯函数 `validSources(_:destination:)`：
  - 过滤父目录 == dest；
  - 过滤 src == dest 或 dest 在 src 之下（文件夹拖进自身/子目录）；
  - standardized path；大小写敏感按当前卷。
- 列表 `validateDrop`：先过滤；全空返回 `[]`，混合批次只保留有效源。
- 列表 `acceptDrop`：再次过滤；空返回 `false`（不进入 ConflictResolver）。
- 网格 `handleGridDragging`：全空返回 `[]`；`performDragOperation` 过滤后空返回 `false`。
- 测试：追加 `FFFileDropPolicyTests`：同目录文件、不同目录、文件夹自身、
  子目录、混合、空、尾斜杠。
- 实测：用 `/tmp/ff-drop-test` 构造目录，拖拽由用户人工复验（合成拖拽不可靠）。

## Task 6 · 0.8.0 Beta 与版本治理

文件：`FlowFinder/FlowFinder.xcodeproj/project.pbxproj`、`UI/SidebarView.swift`、
`UI/SettingsWindowController.swift`、`App/AppDelegate.swift`、`Makefile`

- pbxproj：`MARKETING_VERSION 0.7.9→0.8.0`、`CURRENT_PROJECT_VERSION 7901→8001`（两处配置）。
- 新增 `Bridge/FFBuildInfo.swift`：
  - `displayVersion`（`0.8.0 (8001) Beta`）；
  - `buildDate` 读 executable mtime；
  - `bundlePath`；
  - 纯格式化函数供测试。
- 侧栏版本行用 `FFBuildInfo.displayVersion`；关于页增加构建时间与路径。
- 新增 `FFInstanceGuard.swift`：
  - 纯逻辑 `otherInstances(currentPID:instances:)` + `warningText(for:)`；
  - AppDelegate 启动后（非测试/非 selftest）检测并弹 NSAlert（继续打开 / 退出这个实例）。
- `Makefile swift-test` 增加 `-derivedDataPath /tmp/flowfinder-xctest-derived`。
- 测试：追加 `FFBuildInfoTests`、`FFInstanceGuardTests`。

## Task 7 · 构建、测试、自检、AX 实测

1. `make build` → BUILD SUCCEEDED。
2. `make swift-test` → 全绿（新增测试）。
3. `FF_SKIP_PERMISSION_GATE=1 FF_SELFTEST=1 <cache app executable>` → 自检 0 失败。
4. 退出当前旧实例 → `make demo` 部署 Desktop → 启动 0.8.0。
5. AX：
   - `+` 新建标签（日志 `[GEO]` 标签数增加）；
   - close button 关闭窗口；
   - 隐藏侧栏后标签 frame 不压红绿灯/浮动开关；
   - 侧栏版本显示 0.8.0 Beta。
6. 目测：顶栏 30pt、A1 肩线、hover 态。屏幕录制权限未授予时无法自动截图，明确告知用户。

## Task 8 · 清理 8 个旧副本

在 0.8.0 部署成功后执行；全部移到废纸篓：

- `~/Applications/FlowFinder.app`
- `~/Applications/FlowFinder-old.app`
- `~/Library/Developer/Xcode/DerivedData/FlowFinder-azgs…/Build/Products/Debug/FlowFinder.app`
- `~/Library/Developer/Xcode/DerivedData/FlowFinder-btdd…/Build/Products/Debug/FlowFinder.app`
- `repo/build/Products/Debug/FlowFinder.app`（或整个 `build/`）
- `repo/build_stale_0021/Products/Debug/FlowFinder.app`
- `/Volumes/Iris-Data/Download/测试/FlowFinder.app`
- `/Volumes/Iris-Data/Download/测试/FlowFinderNative.app`

验证：`mdfind kMDItemCFBundleIdentifier == com.flowfinder.native` 只剩
`~/Desktop/FlowFinder.app` 与缓存构建（/tmp 测试宿主不计）。

## Task 9 · 文档

- 更新 `REQUIREMENTS-LEDGER.md`（R-18，U-01..U-09 或 D-01..D-09）。
- 更新 `CHANGELOG.md` 未发版段（0.8.0 Beta）。
- 更新 `HANDOVER.md` 顶部版本/分支/验证基线，新增本轮 §1.9。
- 本 SPEC/PLAN 状态改为“已实现/已验证”。

## 回滚

- 全部改动未提交；需要回滚时按文件 `git diff` 逐项恢复。
- 旧副本已移入废纸篓，可从废纸篓恢复；不执行空废纸篓。
