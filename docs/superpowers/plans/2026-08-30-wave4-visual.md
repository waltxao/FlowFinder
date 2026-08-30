# Wave 4 实现计划 — 视觉材质与密度

> **执行方式：** 单实现子代理 + 独立审查；控制器在构建后做截图视觉验收。审计依据：`.superpowers/audit/materials-toolbar-visual.md`（含 file:line 与量级评估）；补充实测观察：深色模式下详情栏玻璃偏重（近黑），见任务 4.2。
> **设计依据：** 蓝图 `docs/superpowers/specs/2026-08-30-native-experience-blueprint.md` §4。

## Global Constraints

- 简体中文注释；不新增文件；pbxproj 不碰；Libraries/* 不提交。
- 每任务后 `make swift-test > /tmp/ff-w4-tN.log 2>&1` 落盘判读 94/94。已知抖动：DuplicateScanBrowseRegressionTests（重跑一次）。
- **视觉红线：深浅色两套都必须成立**（改完每个视觉任务自查 FFDesign 令牌双值 + 刷新链）；不改窗口结构（fullSizeContentView/透明标题栏/红绿灯位置不动）。
- 用户偏好红线：侧边栏"我的收藏"彩色真实图标、收藏不折叠、操作区日间 #F5F5F5/夜间 #2D2D2D 基调**不变**（Wave 4 只做层级与一致性，不推翻 v0.6.7 决策）。

## Task 1: 材质去冲突（审计 §1.1）

**Files:** `UI/PaneToolbar.swift:72`（工具栏 FFGlassView(.panel,.headerView)）
**要求：** 工具栏背景由玻璃改**实体**：日间 = 操作区同色 #F5F5F5 上浅一档（如 #FAFAFA）/夜间 = #2D2D2D 上浅一档（如 #333333）——加入 FFDesign 令牌（见 Task 3）双值。搜索框若同样叠玻璃（审计点名的 PaneToolbar 搜索框）一并实体化（浅一档灰度）。详情栏保留玻璃浮层（层级对比锚点）。
**验收：** 工具栏与列表交界处无模糊/清晰突变；深浅色均协调。

## Task 2: 阴影/圆角收敛（审计 §1.3）

**Files:** `UI/MainWindowController.swift:736-740`（详情栏 MWC 侧阴影）、`DesignTokens.swift:54-55`、`UI/ExpandableDetailsBar.swift:325`、`UI/MainWindowController.swift:816`、`UI/ToolOverlayView.swift:240`
**要求：**
1. 删除 MainWindowController 侧的详情栏阴影（保留 FFGlassView 分级阴影，消除双投与反向 offset）。
2. 圆角收敛两档：容器级 16（操作区 squircle 保持）/ 浮层级 10（FFGlassView panel 14→10、详情栏 12→10、设备/工具面板 8→10、component 10 保持）。
**验收：** 浮层投影不再发灰发厚；同窗圆角只余两档。

## Task 3: 颜色令牌统一（审计 §1.2）

**Files:** `DesignTokens.swift`（FFDesign 扩展）、`UI/MainWindowController.swift:783-788`、`UI/SettingsSectionView.swift:254`
**要求：**
1. FFDesign 新增 `operationAreaBackground`（Light #F5F5F5 / Dark #2D2D2D）与 `operationAreaElevated`（Task 1 的浅一档，Light #FAFAFA / Dark #333333）双值令牌；MainWindowController 的硬编码改读令牌；SettingsSectionView 的 calibratedWhite 改读令牌（设置卡片与主窗色调统一）。
2. SettingsSectionView.swift:185 过时注释（FFGlassView→solidBackground）顺带修正。
**验收：** 主窗与设置窗口并排时灰度一致（截图验证）。

## Task 4: 密度三档 + 网格缩放（审计 §4）

**Files:** `UI/FileListView.swift:798,1636-1643`（行高）、`UI/FileGridView.swift:707`（itemSize）、`UI/SettingsWindowController.swift`/`AppearanceSettingsView.swift`（外观页新增分区）、`DesignTokens.swift`（可选常量）
**要求：**
1. 列表密度三档：紧凑 22 / 标准 26 / 宽松 32（UserDefaults key `list_density`，默认标准）；rowHeight 与带标签行高（48→随档位 42/48/56）联动；设置→外观新增"列表密度"分段控件，切换广播刷新（参照 .appearanceChanged 或专用通知）。
2. 网格缩放：itemSize 由状态驱动（UserDefaults `grid_icon_size`，默认 120；范围 80–200），⌘+滚轮（scrollWheel 带 magnifier？用 `magnify(with:)` 手势 + ⌘滚轮双入口）实时调整 + invalidateLayout；设置→外观加"图标大小"滑杆（可选，手势优先）。缩略图尺寸随 itemSize 联动（64pt 基准按比例 0.5x itemSize）。
3. 缩放状态跨会话记忆。
**验收：** 三档密度切换立即生效且行内元素不错位；网格 ⌘滚轮/捏合平滑缩放（80–200 夹紧）；重启后记忆。

## Task 5: 字体令牌 + 详情栏解耦（审计 §3）

**Files:** `DesignTokens.swift`（FFDesign.Typography）、`UI/ExpandableDetailsBar.swift:928-934`、逐文件字号替换（列表/网格/面包屑/工具面板——以审计盘点为准）
**要求：**
1. FFDesign.Typography：caption=10 / body=11 / emphasis=11 semibold / title=13 semibold（static let，便于后续统一调档）。
2. 详情栏标签/值 10pt→11pt（body），44pt 固定标签宽改 `greaterThanOrEqualToConstant: 44`（弹性）。
3. 替换范围控制：本任务只统一**跨文件同一信息档不一致**的点（分组标题、详情栏、子窗口正文字号），全量令牌化列后续（避免大范围回归）。
**验收：** 详情栏换字号不破版；同档字号跨文件一致。

## Task 6: 工具栏 overflow + 装饰降噪（审计 §2 折中 + §3）

**Files:** `UI/PaneToolbar.swift:235`（Row2 stack）、`UI/MainWindowController.swift:634`（1px 边框）、`UI/FFGlassView.swift:295-324`（三层装饰）
**要求：**
1. Row2 控件设 compression resistance 分级：搜索框(1) > 排序/分组(先并入菜单按钮的能力可后续，本任务先保证优先级排序：排序 740/分组 730/视图切换 720/新建 710/选项 700)——窗口缩窄时按序压缩/截断不破版。
2. 删操作区 1px 边框（:634-635）——卡片已有阴影与边距分层。
3. FFGlassView 的磨边亮线/顶部高光/内阴影三层装饰：叠加在实体背景上时降级（仅保留单层描边）；玻璃浮层（详情栏）保持现状。
**验收：** 窗口缩到最小宽工具栏不破版；操作区边框消失后层次仍清晰。

## Task 7: 全量验证 + 视觉自检清单输出

- `make swift-test` 94/94；分任务提交（`style(ui): …`/`feat(ui): …`）。
- 报告末尾输出「视觉验收清单」（深浅色 × 主窗/设置/浮层 × 每任务的观察点），供控制器截图验收。

## 审查要点（审查者用）

- 所有 FFDesign 新令牌必须 Light/Dark 双值 + 走既有刷新链（.appearanceChanged/refreshAppearance）；深浅色切换后新旧值正确。
- 密度/缩放切换的 UserDefaults 键命名与既有风格一致；行高联动不错位（标签药丸行）。
- 圆角/阴影收敛后浮层层次仍分明（详情栏浮层 vs 操作区）。
- 任务 4 网格缩放不破坏 prepareForReuse 缩略图取消逻辑。
- 全局：无新文件；测试基线 94；简体中文注释；用户偏好红线（收藏/操作区基调/窗口结构）未触碰。
