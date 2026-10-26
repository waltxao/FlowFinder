# SPEC · 详情栏重做（2026-10-23）

> 状态：**已实现（2026-10-24，最终 Debug 0.8.0-26102407；折叠药丸 / 展开卡片）**；10 项决策锁定，真机取证完成，全量回归与人工项见文末。
> 关联：`DESIGN-SPEC.md §10`（D-01…D-13）、`ExpandableDetailsBar.swift`、`FFDetailsLayout.swift`、`SPEC-2026-10-24-TOOLSBAR.md`。
> 对比稿快照：`detailsbar-layout-q1` / `drag-q2` / `click-q3` / `overflow-q4` / `iconsize-q5` / `iconmax-q6` / `wrap-q7` / `glass-q8` / `keyboard-q9` / `threshold-q10`（会话可视化目录）。
> 证据：`docs/images/audit-2026-10-24-detailsbar/`（首轮 54/132/240）、`docs/images/audit-2026-10-24-pilltools/`（第二轮药丸/工具簇，窗口 25814 @ 260,30 1400×900）。

## 决策台账

| ID | 日期 | 问题 | 现状证据 | 选项 | 用户选择 | 原话约束 | 状态 |
|---|---|---|---|---|---|---|---|
| D-01 | 2026-10-23 | 详情栏与操作区的空间关系 | 浮层覆盖；`contentInsets.bottom = 栏高+8`，滚到底末行可见（实机 0.8.0-26102308 双栏/列表/网格复核）；滚动条与中段被覆盖 | 现状 / A 止于栏顶 / B 贴底底栏 / C 浮层+滚动条内缩 | **C** | 「操作区内容需要对详情栏进行避让，确保滚动条最底处的内容不被详情栏遮挡」 | 已定 |
| D-02 | 2026-10-23 | 小白条拉手与拖动模型 | 收起态拖上边缘无反应（`applyHeightDrag` guard `isExpanded`，ExpandableDetailsBar.swift:1215-1216）；仅 6pt 隐形热区；展开 132–300pt | 现状 / A 两段吸附 / B 连续自由 / C 三段吸附 | **C + 修改** | 「C，但可以点击小白条直接切换折叠展开模式，不要箭头按钮，同时小白条直接接管详情栏高度控制」 | 已定 |
| D-02a | 2026-10-23 | 三档模型下「点击小白条」切换语义 | 箭头按钮将被移除；⌘I 仍是 54 ↔ 记忆高度的键盘入口 | A 折叠↔上次展开档 / B 折叠↔标准 132 / C 三档循环 | **A** | 「A」 | 已定 |
| D-03 | 2026-10-23 | 展开态内容溢出策略（完整显示 vs 隐藏末行） | 最多 4 列，装不下隐藏末行（D-06b）；`infoScrollView.hasVerticalScroller = false` | 现状 / A 栏内滚动 / B 自动增高+滚动 / C 提示+大档 | **A** | 「栏内滚动」 | 已定 |
| D-04 | 2026-10-23 | 展开态图标大小调节入口 | 仅设置页 48–96（`FFDetailsLayoutPolicy.storedIconSize`）；图标区宽度可拖 96–200，`capacity = iconWidth − 32` 会二次限制图标 | 现状设置页 / A 拖右下角手柄 / B 右键预设 / C 触控板捏合 | **A+B+C 组合** | 「ABC 都要，图标可以更大」 | 已定 |
| D-04a | 2026-10-23 | 图标最大尺寸与栏高约束 | 图标区宽 96–200；`updateIconEdge` 仅按 `iconWidth − 32` 限制，未按内容高度限制；132 档内容区约 92pt | 96 / 120 / 160 / 200 | **C（上限 200pt，图标区上限 232pt，信息区可单列）** | 「C」 | 已定 |
| D-05 | 2026-10-23 | 文件名 / 路径换行规则 | `maximumNumberOfLines = 2`、固定 `preferredMaxLayoutWidth = 320`；地址 `byCharWrapping` 2 行 | 现状 / A 2+3 行 / B 不限行 / C 1+2 行+点击全文 | **B（不限行，完整换行；信息区滚动）** | 「B」 | 已定 |
| D-06 | 2026-10-23 | 液态玻璃材质规格 | 当前实色 `SquircleView` + `operationAreaBackground`；窗口背景已是 macOS 26 `NSGlassEffectView(.regular)` | A .regular / B .clear / C 厚玻璃+分隔线+tint | **A（.regular 厚玻璃）** | 「A」 | 已定 |
| D-07 | 2026-10-23 | ⌘I 键盘切换语义与动画 | 现状 ⌘I 为 54 ↔ 记忆高度，0.25s easeInOut（MenuActions:92-99；ExpandableDetailsBar:1324-1329） | A 与点击一致 / B 三档循环 / C 折叠↔标准 132 | **A（与点击一致）** | 「A」 | 已定 |
| D-08 | 2026-10-23 | 三档吸附阈值 | 档位 54 / 132 / 240；自然中点为 93 / 186 | 中点 93/186 / 偏下 96/170 / 偏上 96/200 | **A（93 / 186）** | 「A」 | 已定 |

## 锁定规格

### 1. 尺寸与档位

- 收起 `54pt`（药丸，内容垂直居中；收起态隐藏底部项目计数）；标准 `132pt`；大档 `240pt`。
- 大档按 `min(240, 面板高 × 45%)` 再收敛；`300pt` 仅保留为绝对安全上限。
- 浮层：左右/底各 `8pt`；**折叠为药丸（半径 27），展开为卡片（12pt 圆角）**——展开态不能沿用高度/2 的药丸半径，否则半圆端会裁掉内容；阴影沿用 `opacity 0.14 / radius 12 / offset (0,-2)`。
- 横向内容内边距：收起 20；标准 30；大档 52。
- 默认折叠时右侧让出 `8 + 54 + 8` 给工具圆钮；展开时工具圆钮隐藏，卡片铺到右侧 8pt。

### 2. 小白条与高度控制

- 拉手：白色胶囊 `38 × 4pt`，圆角 `3pt`，水平居中，位于栏顶 `12pt` 区域；浅/深色自适应（白 98% / 浅灰 92%），带 0.5pt 描边与 1pt 阴影。
- 命中区：以拉手为中心 `120 × 24pt`；悬停光标 `resizeUpDown`；悬停时拉手轻提亮。
- **移除** `chevronButton`（箭头按钮）与顶部 6pt 隐形热区；高度控制只由拉手接管。
- 点击 vs 拖动：按下到松开位移 `< 4pt` = 点击；`≥ 4pt` = 拖动。
  - 点击：`折叠 ↔ 上次展开档`（D-02a A）；上次档跨会话持久化（`FFDetailsBarLastExpandedTier`，默认 132）。
  - **点击药丸/展开卡片空白区域同样切换**：收起态内容层穿透命中，由 `FFMouseInterceptorView.onClick` 接管；展开态空白区域同入口。
  - 拖动：高度 1:1 跟随指针（`deltaY` 反向：上拖增高），实时 `clamp(54…min(240, 面板高45%))`，不加动画。
  - 松手：按中点吸附（D-08 A）：`h < 93 → 54`；`93 ≤ h < 186 → 132`；`h ≥ 186 → 240`；吸附动画 `0.28s cubic-bezier(.32,.72,.28,1)`。
- ⌘I：与点击完全一致（D-07 A），同一吸附动画。
- 动画降级：`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == true` 时改为 `0.12s` 线性或直接跳变。
- 左右栏：沿用 `.FFDetailsBarLayoutChanged` 同步本档高度与图标大小。

### 3. 内容避让（D-01 C）

- 保持浮层覆盖布局（列表/网格延伸到底）。
- 列表与网格：`scrollView.contentInsets.bottom = 栏高 + 8`（沿用 `setBottomOverlayInset`）。
- **新增**：`scrollView.scrollerInsets.bottom = 栏高 + 8`，让滚动条轨道在详情栏上缘结束，不再被浮层压住。
- 栏高变化（点击/拖动/⌘I/远端同步）时同时更新 `contentInsets` 与 `scrollerInsets`。

### 4. 展开布局

- 玻璃：macOS 26+ 用 `NSGlassEffectView(.regular)`，`cornerRadius = 10`；**玻璃作为底层兄弟视图，内容视图置于其上**（沿用 Bug 1 容器模式，禁止玻璃直接作为 `contentView`/拦截命中）。macOS < 26 回退 `NSVisualEffectView`（`.underWindowBackground` + `.withinWindow`）。
- 图标区：
  - 图标边长 `edge = clamp(min(设定值, 200), 48, 内容高 − 8, 图标区宽 − 32)`。
  - 图标区宽 `= edge + 32`，上限 `232pt`；不再要求用户先拖分界线才能放大图标。
  - 分界线仍可拖（96–232），拖窄时图标跟随缩小。
- 信息区：
  - 列数按**信息区实际宽度**推导（`< 340pt` 单列，否则双列；最多 4 列仅在极宽时启用）。
  - **不再隐藏溢出末行**：所有行按顺序均衡分配进各列，文档视图高度随内容增长，`infoScrollView.hasVerticalScroller = true`、`scrollerStyle = .overlay`。
  - 滚动条仅在需要时出现；滚轮落在信息区只滚信息区，落在列表只滚列表。
- 文件名/路径（D-05 B）：
  - `maximumNumberOfLines = 0`，`lineBreakMode = .byWordWrapping`（名称）/ `.byCharWrapping`（路径），`cell?.wraps = true`，`truncatesLastVisibleLine = false`。
  - **移除固定 `preferredMaxLayoutWidth = 320`**；每次布局按当前列宽回填 `preferredMaxLayoutWidth`，保证窄栏正确换行。
  - 名称单击进入改名、路径单击复制，行为不变。
- 状态栏：保留「N 项」；磁盘可用空间维持现状（本轮不改）。
- 多选/空态：沿用现有内容；多选汇总行同样进入流动列并可滚动。

### 5. 图标大小入口（D-04 A+B+C）

- 入口一：图标右下角 `16pt` 圆形手柄（悬停出现），拖动连续缩放；范围 `48–200`，松开持久化 `detailsPreviewSize`。
- 入口二：右键（或 `control+单击`）图标 → 菜单：`默认 64 / 小 48 / 中 96 / 大 200`；点选立即生效并持久化。
- 入口三：指针在图标上时触控板捏合（`magnify` 手势）连续缩放；范围同上；松开持久化。
- 保留设置页滑杆作为默认值来源；其范围同步从 `48–96` 调到 `48–200`。
- 当前档位放不下设定值时按第 4 节公式截断（例如 132 档最多约 `84pt`），不自动升档。

### 6. 非目标

- 不改窗口级玻璃背景、不改侧边栏/工具栏。
- 不改状态栏内容项（磁盘空间）。
- 不做详情栏内容的分页/分节折叠。
- 不改文件类型元数据的采集逻辑（`gather*Info`），只改展示与滚动。

## 验收标准

### 自动化（先红后绿）

1. `FFDetailsLayoutPolicyTests`
   - `testTierSnappingUsesMidpoints`：92→54、93→132、185→132、186→240。
   - `testLargeTierClampedByPaneHeight`：面板 400pt 时大档 = `min(240, 180) = 180`。
   - `testIconEdgeClampedByTierHeightAndWidth`：132 档 ≤ 84；240 档允许 200；图标区宽 = edge + 32 ≤ 232。
   - `testClickToggleReturnsToLastExpandedTier`：54→132、132→54、54→132；在大档收起后点击回到 240。
   - `testColumnsDependOnInfoAreaWidth`：338→1 列，340→2 列。
2. `FFDetailsScrollTests`
   - `testAllRowsReachableWhenContentOverflows`：14 行内容在 132 档全部存在且文档高度 > 可视高度。
   - `testInfoScrollViewShowsOverlayScroller`：`hasVerticalScroller = true`、`scrollerStyle == .overlay`。
   - `testOverflowRowsAreNotHidden`：构造超量行后无 `isHidden == true` 的信息行。
3. `FFDetailsWrappingTests`
   - `testNameWrapsWithoutFixedMaxWidth`：窄列宽下名称高度 > 单行。
   - `testLocationWrapsByChar`：深路径在窄列宽下多行且不截断。
4. `FFDetailsAvoidanceTests`
   - `testListBottomInsetMatchesBarHeight` / `testScrollerBottomInsetMatchesBarHeight`：54→62、132→140、240→248。
5. `FFDetailsGripGestureTests`
   - `testClickUnderFourPointsToggles` / `testDragOverFourPointsResizes`。
6. 既有 `FFDetailsLayoutTests` / `FFDetailsIntegrationTests` 全量回归。

### 真机（独立 Bundle ID 副本）

- 收起/标准/大档三态截图；点击拉手往返；拖动上/下跨阈值吸附。
- 132 档下 14 行图片详情可滚动到底，最后一行完整可见。
- 列表/网格滚到底，最后一行与滚动条都在栏上方（避让）。
- 浅/深色玻璃 `NSGlassEffectView` 截图；深色下文字对比度。
- 图标：拖拽手柄、右键预设、捏合三条路径各一次，尺寸持久化。
- ⌘I 与点击一致；开启「减弱动态效果」后无长动画。
- 记录窗口号、截图路径、AX 状态。

### 人工确认

- 玻璃观感是否接近音乐/照片底栏；拉手悬停手感；捏合灵敏度。

## 验证边界

- 本轮不改元数据采集，故「信息完整」指已有行全部可达，不新增字段。
- 触控板捏合依赖真实硬件；自动化只验 `magnify` 回调与夹紧。
- 玻璃 CSS 对比稿为近似，最终以真机截图为准。

## 实现与验证（2026-10-24）

### 实现落点

- `FFDetailsLayout.swift`：`FFDetailsTier` / `FFDetailsBarTierState`；三档高度、93/186 吸附、图标边长三角夹紧、图标区宽、滚动列数、上次展开档持久化。
- `FFCommon.swift`：`FFDetailsFlowLayout.scrollLayout`（全部行分配，不截断）。
- `ExpandableDetailsBar.swift`：
  - `FFDetailsGripHandle`（白色胶囊 38×4、命中区 120×16、点击/拖动分离、AX Increment/Decrement）；
  - `FFIconResizeHandle`（右下角拖动）+ 右键预设菜单 + `magnify` 捏合；
  - `NSGlassEffectView(.regular)` 底层兄弟视图（旧系统 `NSVisualEffectView`）；
  - 信息区 `hasVerticalScroller = true` + `scrollLayout`；名称/路径不限行、按列宽回填 `preferredMaxLayoutWidth`；
  - 三档状态机与 0.28s `cubic-bezier(.32,.72,.28,1)` 动画，减弱动态时降级。
- `FileListView.swift` / `FileGridView.swift`：`contentInsets.bottom` 与 `scrollerInsets.bottom` 同步 = 栏高 + 8。
- `SettingsWindowController.swift`：预览图标滑杆 48–200。

### 自动化

- 新增 `FFDetailsBarV2Tests` **14 条**（三档吸附、点击回上次档、大档高度夹紧、图标边长/图标区、滚动列数、全部行可达、换行、滚动条让开量）。
- `FFDetailsLayoutTests` **11 条**（既有断言按 48–200 / 232 上限更新）。
- `FFDetailsIntegrationTests` **8 条**。
- 详情三组共 **33 条，0 失败**（2026-10-24 08:19 实测）。
- Rust core **200 通过 / 0 失败**（2026-10-24 实测）。
- 全量 Swift 套件 **472 条：470 通过 / 2 条环境失败**（2026-10-24 实测）：`FFBatch2IntegrationTests.testHardcodedTokenBudget` 读取 `UI/` 目录报 POSIX EINTR（外部卷/TCC 环境，shell 读同一目录正常）；`PaneStateDeleteFilterTests.testDeleteIsNonBlocking` 等待删除通知 15s 超时（既有 flaky，本轮未改 PaneState/TaskService）。代码相关失败 **0**。

### 真机（隔离 Bundle ID `com.flowfinder.native.detailsbarverify`，证据构建 Debug 0.8.0-26102402；最终源码构建 26102403）

- 窗口 25115 @ (260,30) 1400×900；截图：
  - `01-collapsed-54.png`（收起 54，玻璃 + 白色拉手 + 紧凑摘要）；
  - `02-standard-132-image.png`（标准 132，PNG 详情双列，名称/路径不截断）；
  - `03-large-240-icon200.png`（大档 240，图标 200，信息单列）。
- AX 拉手：`调整详情栏高度` pos (715,782) size 120×16（标准档），Value 54 → 132 → 240 → 132（Increment/Decrement 各步 `err=0`）。
- 点击拉手：展开（54→132）与收起（240→54）各观察到一次。
- 右键图标菜单：默认 64 / 小 48 / 中 96 / 大 200，选「大」后标准档图标夹紧、大档显示 200。
- 列表滚到底（大档）：最后一行完整位于栏上方，滚动条止于栏顶。
- **桌面副本同步**：2026-10-24 用户授权覆盖为 **0.8.0-26102403**（旧包备份 `/tmp/ff-desktop-backup/FlowFinder-26102308.app`）；启动 PID 49203、窗口 25479，侧栏版本标签实测 26102403；重签名后 TCC 权限重置，Desktop/Documents 需用户重新授权。
- 玻璃：`NSGlassEffectView(.regular)` 真机呈现半透明底；内容置于玻璃之上，未再出现鼠标被拦截。

### 未验证 / 人工确认

- 连续拖动 1:1 手感：合成鼠标拖拽事件未稳定送达（CUA/CGEvent 环境限制）；拖拽数学与吸附已由单元测试覆盖，**物理拖拽手感待人工确认**。
- 触控板捏合：`magnify` 回调与夹紧已接线，**真机手势未触发**。
- 深色模式玻璃观感：未截深色图。
- 信息区溢出后的实际滚动：单测断言 `hasVerticalScroller` 且全部行保留；真机只观察到滚动条，未完成长内容滚动截图。
- 设置页滑杆 48–200 的真机拖动未走查。
