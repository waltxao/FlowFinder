# FlowFinder 交接文档（大改前基线）

> **整理日期：** 2026-10-18（基线）· **2026-10-20 增补**（交互大改五轮，见 §1.5）· **2026-10-21 增补**（0.8.0 Beta 顶栏修复，见 §1.9）· **2026-10-22 增补**（第二轮整改见 §1.11；AX 行虚拟化见 §1.18；批量整理见 §1.21；UI 缺陷逐条修复见 §1.25–§1.26）· **2026-10-23 增补**（第四轮 UI/UX 审计 R4 全量修复，见 §1.27；接手复跑 + 四轮真机实测见 §1.28；缺陷修复 + macOS 26 液态玻璃适配见 §1.29）· **2026-10-24 增补**（详情栏重做见 §1.30；工具模块第一版见 §1.31，已被 §1.32 取代；药丸详情栏 + 独立圆形工具簇见 §1.32）· **2026-10-25 增补**（侧栏/搜索真机审计 + 两个导航缺陷修复 + 剩余测试项收口，见 §1.34）· **2026-10-26 增补**（v0.8.0-b2 发布，见 §1.35）
> **当前版本：** **0.8.0-26102601 Beta**（版本规则 `A.B.C-yymmddxx`，见 §1.11 D-09；**2026-10-24 起 `make build` 每次构建后自动覆盖桌面副本并重启**，当前桌面副本仍为 26102501——`make beta` 不部署桌面副本；Release 打包 26102601）；**当前分支：`feat/v0.9-overhaul`（分支名沿用；产品版本按用户裁定为 0.8.0）**
> **最新 Release：** https://github.com/waltxao/FlowFinder/releases/tag/v0.8.0-b2（0.8.0 Beta · 构建 0.8.0-26102601）
> **本地路径：** `/Volumes/Iris-Data/文件管理系统/flowfinder-native`
> **代码规模：** Swift 118 文件 / 46,900+ 行（2026-10-24 工具模块后，未逐个文件复核）；Rust 24 文件 / 13,529 行（不变）
> **AI 资源快照：** `resources/ai-tools/`（2026-10-22 起；**2026-10-23 增补 `skills-2026-10-23/` 19 个 FlowFinder/macOS 工具链 Skill；2026-10-25 更新 `flowfinder-docs-sync` 与 `flowfinder-xctest-batch-verification`**），清单与运行时来源对照见 `resources/ai-tools/MCP-AND-SKILLS.md`——接手 Agent 的工具链从这里恢复
> **验证基线：** Rust 200 项全绿（2026-10-24）；**全量 Swift 542 条 0 失败**（2026-10-24 实测；跳过 2 条既有环境测试：`DuplicateScanBrowseRegressionTests.testBrowseSheetReappearsAfterDeleteAndRescan` **单独复跑 16.656s 通过**、`FFBatch2IntegrationTests.testHardcodedTokenBudget` 外部卷阻塞 **0 条执行/150s 超时**）。**2026-10-25 新增 1 条回归单测 `testSearchEnterWithEmptyQueryDoesNotOpenFirstItem` 单跑通过（0.914s），全套未重跑**。**应用内自检 `FF_SELFTEST=1` 153 / 失败 0 + 布局压力 20 轮 0 失败**（2026-10-24 在 26102406 复跑；26102407–26102601 未重跑自检）。**Release 包 `0.8.0-26102601`：CFBundleVersion 26102601、codesign 通过、DMG/ZIP sha256 校验 OK（2026-10-26）**。
> **推送状态（2026-10-26）：** 历史 §1.x 中的「未提交 / 未推送」均为当轮状态；R-25…R-39 与本轮修复已推送到 `origin/feat/v0.9-overhaul`（功能提交 `1ccba73`），并随 `v0.8.0-b2` 快进 `main`（发布提交与 tag 见 §1.35）。

本文档是大改前的**唯一交接入口**。产品定义看 `PRODUCT.md`，视觉看 `DESIGN-SPEC.md`，
验收看 `ACCEPTANCE.md`，功能清单看 `REQUIREMENTS.md`。

> **同步纪律（2026-10-21 起，强制）：** 每次代码 / 行为 / 版本修改，必须在**同一轮**更新
> `REQUIREMENTS-LEDGER.md`（ID、状态、验证证据）与本文件（当前版本、验证基线、§1.x 轮次、未验项）；
> 需要时同步 `SPEC-*.md` / `PLAN-*.md` / `CHANGELOG.md`。**没有更新这两份文档视为任务未完成。**
> 只认当次实测数字，不复用旧数字。历史章节 §1.5–§1.10 中的 190 / 258 / 282 / 135 / 335 / 164 是当轮实测值；
> **当前基线以顶部「验证基线」一行为准**（不在本段重复数字）。

---

## 1. 一句话现状

能日常使用的双面板文件管理器；当前 **0.8.0 Beta（构建 `0.8.0-26102601`，分支 `feat/v0.9-overhaul`）**，最新 Release **`v0.8.0-b2`**。
2026-10-20 完成交互层五轮重做 + 回归修复 + 标签拖拽重做；2026-10-24 完成详情栏/工具簇/任务注水；
2026-10-25 完成侧栏/搜索真机审计、修复两个导航缺陷并补齐剩余测试项；2026-10-26 打包并发布 b2。
XCTest 最后全量 **542 条 0 失败**（2026-10-24；10-25 新增 1 条回归单测通过，全套未重跑），自检 **153 + 20 轮**，Rust **200**。
结构债务（巨型文件、双真值源）仍保留。推送与发布记录见台账 §2.5 C 和 §1.35。

### 1.5 2026-10-20 交互大改（五轮，接手必读）

今天在 v0.9 分支上完成五轮重做，规格 `docs/SPEC-2026-10-20.md`（§1.1–§1.14），
**逐条台账 `docs/REQUIREMENTS-LEDGER.md`（R-01..R-14，含验证证据分级）**。
CHANGELOG「未发版」段有完整记录。六个新模块：

| 新文件 | 职责 |
|---|---|
| `UI/FFInteractionPolicy.swift` | **交互决策表**（区域 4 种 × 状态 4 维 → 意图 6 种，纯函数可穷举）——「按下去发生什么」的唯一真相源 |
| `UI/FFRegionResolver.swift` | 视图自我声明区域（`FFRegionAware`）→ 统一翻译成意图 |
| `UI/FFPaneDrag.swift` | 标签级跨窗口拖拽（窗口级 local monitor 自管；**不用 NSDraggingSession**——标签条在标题栏带内，mouseDown 会被系统先抢） |
| `UI/FFListColumns.swift` | 列表列定义 / 可见性与列宽持久化 / 三个开列入口 / Finder 说明缓存 |
| `UI/FFWindowShape.swift` | 窗口 12pt 连续曲率圆角（`cornerCurve = .continuous`；**CAShapeLayer 遮罩会让整窗空白，勿再试**） |
| `UI/FFPaneModeAnimator.swift` | 单双面板切换过渡（0.36s 弹性；面板本体无位移动画，NSSplitView 限制） |

**交互模型速记**（详见台账 R-01/R-08/R-11）：

- **拖窗口** = 侧栏空白 + 标签条空白（卡片留白已移出白名单，只做调宽把手）
- **拖标签** = 搬这个标签：条内 20pt 缓冲重排；出缓冲 1:1 标签浮层；
  落点分流（标签条=并入 / 操作区=单栏拆双栏·双栏并入 / 窗口外=新窗口）；
  源面板搬空 → 面板折叠（跨窗口则源窗口关掉）
- **新面板按落点侧**（拖右出右、拖左出左），窗口向该侧加宽并钳制到屏幕内
- 调宽把手 = 中缝/侧栏缝的卡片外沿 ±6pt（标题带以下），优先级高于一切手势

**当日修掉的三个高危 bug**（复现手法记在台账/日志，勿回归）：

1. **点击失效（含全系统）**：press 类手势绝不能消费 mouseDown——吞掉后拖出窗口外
   松手 mouseUp 回不来，系统认为鼠标还按着，**整个 OS 的点击都失灵**
2. **启动卡顿 1–2 分钟**：渲染路径禁止同步 xattr（`cachedTags` 只读缓存 +
   预热完成后广播刷新），冷启动 → 内容就绪 4 秒
3. `addGlobalMonitorForEvents` **需要辅助功能权限**，本机未授予——别指望它兜底

**遗留（台账标明）**：① 面板切换「真位移」未做（裁定走自管布局，单独一轮）；
② 跨窗口拖拽手感需人工复验（合成事件三重干扰：CGEvent y 为屏幕顶部原点 /
TCC 弹窗 / 窗口遮挡）；③ 标签重命名、AI 整理卡等旧债务不变。

### 1.6 2026-10-20 回归修复与测试护栏（第六轮）

用户实测暴露的四个回归，**先写失败测试再修**；XCTest 通道实测可用
（新增 18 条，修前 19 处失败，修后 162 条全绿）。

| 回归 | 根因 | 修法 | 护栏 |
|---|---|---|---|
| 单标签拖回自己的标签条 → 出现「占位 + 标签」两个 | `PaneTabsStore.add/insert` 不清理只剩占位的列表 | `removeLonePlaceholder()`：真实标签进来前清掉占位 | `PaneTabsStorePlaceholderTests` 4 条 |
| 拖出的新窗口继承当前双栏模式，右侧多一个空占位 | `detachTabToNewWindow` 用默认初始化，读全局 `single_pane_mode` | `MainWindowController(startsWithSinglePane: true, showImmediately: false, runsSelfTests: false)`，装配完再显示 | 自检 ⑥（拖出新窗为单栏） |
| 标签条 20pt 缓冲内重排失效 / 指示线错位 | 判定与指示线在 stack / strip / window 三套坐标间混用 | 抽出纯函数 `FFTabReorder.insertionIndex`；两处都先转到 strip 坐标 | `FFTabReorderTests` 3 条 |
| 侧栏行、标签条按钮、发现药丸点不动 | 控件在 `.window` / `.title` 内被解析成 `dragWindow`，mouseDown 被当拖窗口 | `FFAreaResolver` 遇 `NSControl` / 点击手势只对 `.window` / `.title` 短路；`.panel` / `.tab` 保留（否则文件列表上的落点会丢） | `FFAreaResolverControlTests` 6 条 |

顺带修掉：按压反馈取错面板侧（按命中视图反查 `paneSide(containing:)`）；
窗口拖动加 4pt 阈值、未超阈值时 mouseUp 放行（标签条空白点击不再被吞）。
另加 `FFInteractionPolicyTests` 5 条锁定决策表既有行为（缓冲内重排 / 出缓冲搬标签 /
标题与窗口拖动 / 面板按压 / 把手优先），合计 18 条。
测试文件：`FlowFinder/Tests/FlowFinderTests/InteractionRegressionTests.swift`。

**仍未验**：物理拖拽手感（同上三重干扰）、桌面副本上的控件点击。
决策表里 `sidebarVisible` / `singlePane` 两个维度与 `.activateTab` /
`.marqueeSelect` / `.handledByControl` 三个意图目前是「有定义、无消费」，
清理留到真位移那一轮一起做。

### 1.7 2026-10-20 标签拖拽重做（第七轮，路线 B）

用户实测反馈：**拖标签/拖窗口严重卡顿；标签拖拽“感觉被改废了”**。审查确认：

- 单栏落点走错侧：`operationSide()` 单栏直接返回 `activePane`。
- 兄弟标签被清空：`acceptTabIntoPane()` 用 `replaceAll([session])` 覆盖活动面板。
- 自检 ③ 直接传 `side:`，绕过真实落点判定，所以全绿也测不到。
- 插入线每事件改 Auto Layout 约束 → 整窗布局失效 → `FileListView.layout → applyColumnFit → rebuildColumns`，一次真实拖动采样中主线程活跃样本 74% 落在这条链。
- 拖动每事件全窗口 hitTest、浮层 `orderFront`、高亮重绘；窗口拖动逐事件 `setFrameOrigin`，绕过系统合并。
- `updatePaneUI` 每次状态发射 reload 两个列表 + 同步 `attributesOfFileSystem`；每窗口鼠标监视器 deinit 不移除。

重做落地（详见 `SPEC-2026-10-20-DRAG-REDO.md` / `PLAN-2026-10-20-DRAG-REDO.md`）：

| 新模块 | 职责 |
|---|---|
| `UI/FFDropResolver.swift` | 纯落点决策：reorder / merge / split / newWindow / returnToSource |
| `UI/FFDragGeometryCache.swift` | 每窗口屏幕坐标几何；按 `NSApp.orderedWindows` 前到后排序 |
| `UI/FFDragOverlay.swift` | 完整胶囊浮层 + 1px 描边；frame-based，不参与 Auto Layout |
| `UI/FFPaneDrag.swift` | 60Hz 帧调度、几何快照、resolver 接入；窗口拖动改 `performDrag` |

已确认行为：单栏拖右半 → 新面板在右、原面板保留其余标签；目标单栏拆双栏保留目标标签；
窗口内无效区域（侧栏/红绿灯/标题空白/“+”）→ 回原位、不新建窗；最后标签允许拖出，
无窗口时 Dock 点击重开；跨窗口标签条按指针左右半插入。

**验证**：`make swift-test` **190 条 0 失败**；`FF_SELFTEST=1` **135 项 0 失败**
（拖拽 10 步 + 决策表 71 + 区域 7 + 行为 4 + 焊接 21 + 外壳 22）。
**未验**：真实拖拽 60fps 采样、活动标签浮层/窗口拖动手感（合成事件在本机仍不可靠）。
窗口拖动默认走原生 `performDrag`；`FF_NATIVE_WINDOW_DRAG=0` 回退到 60Hz 自管拖动。

### 1.6 2026-10-21 UI/UX 与结构整改（UIUX-REDO，历史）

> **布局/视觉部分已被 §1.7 取代；** `PaneStore`/`MetadataService`/任务/工具/性能层继续保留。

规格 `docs/SPEC-2026-10-20-UIUX-REDO.md`（D-01..D-12），计划
`docs/PLAN-2026-10-20-UIUX-REDO.md`（Task 1–11）。本轮按「原地绞杀」分片落地，
不提交、不推送，全部改动留在工作区。

**已落地模块**

| 模块 | 文件 | 作用 |
|---|---|---|
| 视觉常量 | `UI/FFVisualTokens.swift`、`UI/FFContrast.swift` | 4/8/12/16/24 间距、28pt 状态栏/行高、系统强调色、对比度工具 |
| 快捷键契约 | `UI/FFKeyboardContract.swift`、`UI/FFShortcutSettings.swift` | Finder 基线键位、设置页默认值/冲突检测；⌘1/⌘2 聚焦面板，⌥⌘1/⌥⌘2 切列表/图标 |
| 统一状态栏 | `UI/FFStatusBarText.swift`、`UI/FFStatusBarView.swift` | 单行 Active/选择/磁盘摘要 + 仅选中时出现「详情 ⌘I」 |
| 面板真值 | `Model/PaneStore.swift`、`UI/WindowFocusModel.swift` | 粒度变更（files/selection/filter/viewMode）、单一 activePane |
| 性能策略 | `UI/FFPerformancePolicy.swift` | 标签计数只在目录/文件集合变化时刷新；任务仅变化时发布 |
| 按需详情 | `Bridge/MetadataService.swift`、`UI/FFDetailsPopoverController.swift` | ⌘I popover、generation token、关闭即取消；选中不再同步读媒体 |
| 工具协议 | `UI/FFToolProtocol.swift`、`FFToolRegistry.swift`、`FFToolPopoverController.swift` | `FFTool`/上下文/可用性/注册表；工具浮层显示活动面板与选择 |
| 任务真值 | `Bridge/TaskService.swift`、`UI/TaskProgressBar.swift`、`UI/TaskPanelWindowController.swift` | 复制/移动/查重/批量写进度；任务中心合并应用任务与系统任务 |
| 协调器接缝 | `UI/PaneCoordinator.swift`、`ToolCoordinator.swift`、`TaskCoordinator.swift`、`SidebarCoordinator.swift`、`WindowShellCoordinator.swift` | 面板/工具/任务/侧栏状态所有权从 MainWindowController 分出 |
| 安全默认 | `UI/FFDestructivePolicy.swift` | 冲突默认跳过；查重结果零勾选（需显式「选择重复项」）；永久删除明确不可撤销 |

**性能止血**

- 选中不再触发整表 reload；`PaneStore.apply` 用路径/数量/首尾路径签名，避免十万级数组深比较。
- 标签计数按签名门控；任务轮询 0.5s→空闲 2s，且数组不变不发布。
- `refresh()` 改用 `invalidateCacheAsync`，主线程不再等 FFI 信号量。
- 缩略图磁盘缓存文件名改为完整 key 的稳定 hash（不含 `/`），写盘前建目录，清理每 100 次写摊销。
- Debug 构建新增 signposts：`Render.list`、`PaneStore.apply`、`Details.show/load`、`Task.publish`。

**安全与一致性**

- 查重默认不再预勾选删除项；新增「选择重复项」显式批量操作；永久删除保持二次确认。
- 冲突解析默认 `.skip`；替换必须显式选择。
- 设置页移除两个无人读取的死开关（智能排序/保留选择位置），新增「删除前确认」；快捷键录制检测冲突并提示。
- 搜索框统一 28pt/13pt；双击搜索结果定位父目录并选中目标文件。
- 旧 `FFDiscoverPanel` 枚举/控制器退役，文件重命名为 `FFPillButton.swift`；工具入口改为注册表驱动。

**验证**

- 【已跑】`make build` BUILD SUCCEEDED；`make swift-test` **258 条 0 失败**；`FF_SELFTEST=1` **135 项 0 失败**（拖拽 10 + 决策表 71 + 区域 7 + 行为 4 + 焊接 21 + 外壳 22）。
- 【视觉已验（1400×900 浅色）】双栏主窗口、单↔双切换、⌘I 详情 popover、工具 popover、设置（通用/快捷键）、搜索面板。实测发现并修复：
  - 单→双切换后第二块面板宽度恒为 0（看起来仍像单栏）：插入子视图后强制 `adjustSubviews` + 同步 `setPosition`，并补回归测试；
  - 搜索面板搜索框被标题栏裁切：移除 `fullSizeContentView`；
  - 辅助窗口 ⌘W 无响应：`menuCloseTab` 先判断 key window；
  - 状态栏「61 GB 可用 可用」重复；文件夹选中时「计算中…」永不更新；详情日期英文——均已修。
- 【未验】1060×700、深色/高对比/Reduce Motion 截图；VoiceOver 人工走查（自动测试覆盖 label/hit target/对比度）。
- 【性能采样】`sample` 5 秒：主线程样本全部在事件循环/菜单跟踪，未出现应用侧 FFI、reload 或目录枚举长栈；拖拽 60fps、选中 <50ms、500 项首屏 <300ms 的精确数值仍未测。
- 【部分完成】Task 9 只完成 coordinator 接缝与状态所有权迁移；MainWindowController 仍持有布局/拖拽/标签装配，后续可按 coordinator 继续搬迁。

### 1.7 2026-10-21 双操作区结构回归（LAYOUT-ROLLBACK，接手必读）

用户在真机验收后判定 UIUX-REDO 的“单行工具栏 + 全局底栏 + 独立详情浮层”是失败改造。
本轮以 HEAD `732a5f4` 为视觉参考，外科式恢复旧结构，保留后台/性能改造。

**恢复**

- 每侧固定 72pt 两行工具栏；搜索、排序、分组、列表/图标、新建文件夹常驻。
- 每侧操作区内 54pt `ExpandableDetailsBar` 浮层；无选择保持收起目录摘要。
- `⌘I` 展开当前面板详情栏，不再创建独立 popover。
- 移除横跨双栏的全局 28px 状态栏；`FFStatusBarView/FFStatusBarText/FFDetailsPopoverController` 已退役。

**新增**

- 第二行应用级逐项开关：`FFToolbarRow2Preferences`，视图选项齿轮内勾选，左右一致，默认全开。
- 三边微光：`FFPaneGlow` 原生 layer 阴影（无描边），向下偏移让底部/左右更明显，顶部标签区保持干净；
  参数取 `FFGlowSpec`（blur 9 / opacity .50）。第一版渐变描边实测仍是硬边，已淘汰。
- 强调色唯一来源：`FFAccent`；首次启动清除旧粉色 `#ff375f`，默认系统强调色；
  标签下划线、面包屑、选中行、拖拽浮层全部统一。
- 详情栏元数据异步化：PDF/AV/目录不再同步读取；图片分辨率由 `MetadataService` 后台读。

**保留**

`PaneStore`、`MetadataService`、`TaskService`、上下文工具浮层、原生标签/拖拽、异步 FFI、缩略图缓存、安全默认。

**验证**

- `make build` BUILD SUCCEEDED；`make swift-test` **258 条 0 失败**；`FF_SELFTEST=1` 135 项 0 失败。
- 1400×900 浅色真机走查：双栏结构、两行工具栏、两侧详情栏、⌘I、第二行配置、三边微光、无全局底栏均生效。
- 强调色迁移后默认系统蓝；旧粉色设置已清除。
- 未验：1060×700、深色/高对比/Reduce Motion 截图；VoiceOver；精确 60fps/首屏数值。

**已知取舍**

- 顶部不画强调线，活动面板完全由三边微光提示；若远看不够明显，可在下一轮增加 1px 中性分隔线而不是恢复发光。
- 详情栏图片分辨率/文件夹项目数为异步；PDF 页数/AV 时长未在默认 provider 中实现，字段缺省不显示，不阻塞 UI。

### 1.8 2026-10-21 UI/UX 全界面精修（第十轮，接手必读）

规格 `docs/SPEC-2026-10-21-UIUX-POLISH.md`，计划 `docs/PLAN-2026-10-21-UIUX-POLISH.md`，
逐条台账 `docs/REQUIREMENTS-LEDGER.md`（R-17，U-01..U-13）。

**圆角与层级**

- 半径统一为窗口 12 / 面板 12 / 详情与卡片 8 / 控件 6，全部 `cornerCurve = .continuous`。
- 面板卡片从 16 收敛到 12；详情栏 10→8；活动面板阴影路径同步 12，不再出现内层大于外层。

**详情检查器**

- 默认展开高度 120pt；范围 120–面板 45%（上限 260）；超出内容进入纵向滚动。
- 预览图标由设置 > 外观“详情预览大小”控制（48–96，默认 64），图标区宽度随之收敛。
- 信息区按宽度 <480 单列、≥480 两列；路径单行中间省略 + tooltip；字段顺序保持“名称/类型/大小/日期/位置/标签/说明”。
- 旧 210pt 展开高度一次性迁移到 120pt。

**工具 / 搜索 / 查重**

- 工具浮层按“整理 / 任务 / 系统”分组，标题只写“工具”，副标题路径 + 选择摘要；批量重命名、查重提供上下文提示；工具行可键盘执行。
- 搜索窗口空态居中：图标、标题、说明、主按钮“构建内容索引”、次入口“只搜索文件名”；筛选区合并为单张卡片。
- 查重窗口四段：条件卡片（路径/浏览/开始停止 + 扫描方式/类型/最小大小）、结果（空态开始扫描）、预览（选择组提示）、动作栏（组数/文件数、可释放空间、选择重复项、取消选择、确认删除）。
- 查重默认零勾选与永久删除二次确认保持不变。

**辅助窗口与安全默认**

- 冲突弹窗按钮顺序改为 跳过 / 保留两者 / 替换…；跳过默认，替换危险色并置末。
- 标签关闭视觉 20、命中 24；侧栏最小宽度 180。
- 设置/批量重命名只做 token 与边距统一；不重排结构。

**本轮修掉的三个真机问题**

1. **旧粉色残留**：迁移键已置位后仍保留 `#ff375f`，活动面板发粉。改为按“用户是否显式选色”判断，旧默认色每次启动清除，显式选择保留；`FFAccentSourceTests` 增 2 条。
2. **⌘I 被右键菜单抢占**：右键“显示简介”带 Cmd+I，实际打开旧独立简介窗口。移除该键位，⌘I 回到区内详情栏；`FFAccessibilityTests` 增 1 条。
3. **辅助窗口白底白字**：搜索/查重/设置单例复用后静态 `cgColor` 不随主题刷新。新增 `FFSolidSurfaceView`，在窗口迁移/布局/外观变化时按有效外观解析背景与边框；幂等辅助窗口响应 ⌘W。

**验证**

- `make build` BUILD SUCCEEDED；XCTest **282 条 0 失败**；`FF_SELFTEST=1` **135 项 0 失败**。
- 浅色 1400×900 / 深色主窗口、紧凑详情、工具浮层、搜索空态、查重空态、设置卡片真机走查通过。
- `FFMotion.animationDuration` 继续读系统 Reduce Motion；浅色/深色/高对比主文本对比度由 `FFAccessibilityTests` 覆盖。
- **未验**：高对比模式逐屏截图（对比度已自动测试）、VoiceOver 完整走查、1060×700 全屏截图。

**P-01 圆角回归修复（2026-10-21 追加）**

真机像素扫描发现左面板左上/右上为直角、右面板左上圆角但右上直角：`SquircleView` 只设了 `cornerRadius`，而整幅工具栏/列表背景作为子视图盖住了圆角。新增 `FFPaneContentClipView`（12pt、`.continuous`、`masksToBounds = true`），工具栏/列表/网格进入裁切层；外层 `SquircleView` 保留背景与微光阴影，详情浮层留在裁切层外。自测中三处“直接子视图找 FileListView”的假设改为 `leftFileListView`，自检覆盖恢复 135 项。
验证：XCTest **282 条 0 失败**；`FF_SELFTEST=1` **135 项 0 失败**；真机截图四个顶角均为连续曲率。

**P-04 1060 宽度修复（2026-10-21 追加）**

面板最小宽从 450 降到 400，split view 两处硬编码 450 改为 `FFDividerGlowMath.minPaneWidth`；窗口最小宽保留 1060×700。侧栏 180 + 两面板 400×2 + 留白/分隔线约 1012，1060 内成立。新增 2 条宽度约束 XCTest；1060×700 真机截图仍待补（当前 CUA 边缘拖拽未能稳定触发窗口缩放）。

**已知取舍**

- 详情展开高度仍可由用户拖拽调整，但被钳制在 120–260（且不超过面板 45%）；超出内容滚动而不是继续长高。
- 工具浮层中的 AI 工具仍为“即将推出”禁用态，不产生副作用。
- 查重窗口 `showWindow(scanPath:)` 每次打开会清空上一轮结果，保证空态/条件区从干净状态开始。

### 1.9 2026-10-21 0.8.0 Beta 顶栏与交互修复（第十一轮，接手必读）

规格 `docs/SPEC-2026-10-21-UI-FIX-BETA.md`，计划 `docs/PLAN-2026-10-21-UI-FIX-BETA.md`，
台账 `docs/REQUIREMENTS-LEDGER.md`（R-18，D-01..D-09）。**版本按用户明确纠正为 0.8.0 (8001) Beta，
不是 0.9.0**；分支名 `feat/v0.9-overhaul` 仅为历史命名。

**顶栏（A1 焊死式）**

- 标题带 36→30；活动标签 28 / 非活动 24；全部中心线 16pt（与红绿灯、侧栏三图标、＋ 对齐）。
- 活动标签与面板同色，由 `PaneTabStripBackdrop` + `FFTabSilhouette` 绘制 9pt 内凹肩线；
  去掉下划线、整圈描边与标签自身背景；新增 12pt folder 图标。
- 关闭 × 只活动/hover 出现，＋ 与 × 统一 24pt 命中；侧栏三图标 hover 底色，间距 4pt。
- 隐藏侧栏：首个标签左缘 112（标签条容器 78），动画完成与 `splitViewDidResizeSubviews` 后重算；修掉停在 x=0 压红绿灯的根因。
- 操作区卡片顶边随标题带从 36 上移到 30，列表多 6pt 内容高度。

**行为**

- 红绿灯关闭：`FFWindowChrome` 在窗口级 mouseDown 监视器最前放行标准窗口按钮；
  物理点击实测关窗成功、进程存活（`[WINDOWCHROME]`）。
- 同目录拖放：`FFFileDropPolicy` 过滤同父目录、自身、子目录；列表与网格都接入，不再弹冲突窗。
- 版本治理：启动检测同 Bundle ID 的其它进程（`FFInstanceGuard` + NSAlert）；关于页显示构建时间与路径；
  `make swift-test` 改用 `/tmp/flowfinder-xctest-derived`；8 个旧副本已移入废纸篓。

**验证**

- `make build` BUILD SUCCEEDED；XCTest **301 条 0 失败**；`FF_SELFTEST=1` **153 项 0 失败**
  （决策表 71 / 区域 7 / 行为 4 / 焊接 35 / 侧栏避让 4 / 外壳 22 / 落点 10）。
- AX 实测：＋ 新建标签；物理点击关窗（窗口数 1→0，进程仍存活）；隐藏侧栏后首标签左缘 112（容器 78）、>102；
  侧栏读到 `0.8.0 (8001) Beta`；双开时 `[INSTANCE]` 检测到另一进程并返回 1000（继续打开）。
- 当前运行：`~/Desktop/FlowFinder.app`（0.8.0 / 8001），缓存构建同源。

**未验**

- A1 肩线、hover 底色、图标线宽的像素级目测：本机屏幕录制权限未授予，无法自动截图。
- 真实同目录拖拽手感（策略层已测，交互入口已接）。
- 1060×700、深色/高对比逐屏截图。

**接手提醒**

- 不要再从 Xcode 的 DerivedData 运行主 App；日常测试只用 `~/Desktop/FlowFinder.app`（`make demo` 生成）。
- 旧副本清单在 `/tmp/ff-old-builds-cleanup-*.txt`；如需恢复可从废纸篓取回。
- 隐藏侧栏的 112 是「首个标签左缘」；标签条容器在 78（= 112 − 卡片留白 8 − 标签退让 26）。不要再把 112 当成容器左缘，否则标签会被推到 146。

### 1.10 2026-10-21 后续 UI 重做 v2（设计已确认；Phase 0–7 已完成）

规格 `docs/SPEC-2026-10-21-UI-REDESIGN-V2.md`，实施计划
`docs/PLAN-2026-10-21-UI-REDESIGN-V2.md`（Phase 0–7），台账 R-19。
用户列了 12 项，设计已逐项确认。Phase 0 加 Debug 诊断与回归测试；Phase 1 落地尺寸三档、
顶栏 token 与 SF/Phosphor 图标；Phase 2 完成全局顶栏 C2、隐藏侧栏修复；Phase 3 完成
面板宽度模型、比例缩放、分栏把手与首帧定位；Phase 4 完成详情浮层 v2；
Phase 5 完成文件标签系统；Phase 6 完成设置页视觉 A；Phase 7 完成构建/测试/自检/产物收口。
图二 bug 两次 Record & Replay：一次只捕到 Qoder，一次捕到 FlowFinder 但 12 张截图均正常，
未复现；诊断日志 + 20 轮压力保留。

**已确认**

- 顶栏改为窗口级全局栏：红绿灯 → 侧栏开关 → 面板 1 标签组 → 面板 2 标签组 → 分隔线 →
  皮肤 → 单双栏。C2 密度：44pt 顶栏 / 38pt 标签 / 6pt 顶部空条 / 22pt 共用中线 /
  13pt 标签文字 / 16pt 图标 / 10pt 内凹。侧栏隐藏时右侧按钮不再消失，面板内工具栏保持 8pt 缩进。
- 详情栏保留浮层：高度 132–300 可拖；左侧预览独立列 96–200 可拖（默认 132）；
  基础字段 类型/大小/修改/创建/位置/标签/说明；去掉所有者/权限/磁盘与“在 Finder/更多”；
  类型专属字段（文件夹项目数、图片尺寸、视频时长/分辨率、音频时长/比特率、PDF 页数、
  应用版本、压缩包文件数）按类型显示。文件名换行可编辑，位置换行可复制，标签可删可加。
- 隐藏侧栏面包屑/搜索右移已在实机确认，根因是 `leadingInset=112` 同时作用于面板工具栏。
- 面板宽度：侧栏宽度只由侧栏缝决定；窗口缩放时两栏等比、侧栏不变；分栏拖拽不碰侧栏；
  两栏首选 400、软最小到硬下限 360；单↔双按隐藏面板宽度收窄/恢复，侧栏宽度不变。
  分栏把手命中/双击 50/50/吸附点待确认。
- 侧栏工具入口：移到全局顶栏最前（红绿灯 → 工具 → 折叠侧栏 → 标签组…）；侧栏品牌区
  只保留名称/版本，不再有“工具”药丸；分组菜单保留。
- 视觉尺寸：设置 > 外观提供 紧凑/舒适/大 三档，默认舒适（正文 13 / 行 30 / 图标 18 /
  标签 13）；顶栏 C2 44/38 固定，仅标签文字 12/13/14 随档位。
- 图标库：混合方案——系统 chrome 用 SF Symbols，文件类型/自定义图标用 Phosphor（MIT，
  6 权重）；不采用 Lucide（现状）、Tabler（偏硬）、Iconoir（偏淡）、Remix（自定义许可）。
- 设置页：保留 7 分区与功能，只统一视觉；A 原生分组卡片（12pt 卡片 / 40pt 行 /
  24–28pt 控件 / 正文 13 / 说明 11）；外观页新增界面尺寸三档。
- 文件标签：访达原生标签；设置 > 标签管理为唯一新建/改名/改色/删除/排序/合并入口；
  改名/改色/删除同步所有已打文件（删除二次确认）；侧栏列表带计数、⌘多选 AND；
  右键/⌥⌘T 选择器批量打标签，详情栏使用同一选择器。

**图二空白 bug（Phase 0 结果）**

- 触发面：隐藏/显示侧栏、切单/双栏、拖标签；用户不记得精确步骤。
- CUA 连续交替侧栏/单双栏压测：AX 表格/行数正常，未稳定复现。
- 新增 `FFLayoutDiagnostics`（`FFPaneModeAnimator.swift`）：侧栏显隐完成、单双栏应用、
  拖出新窗口后及各自下一拍输出 `[LAYOUT]` 只读快照（window / split / wrapper / clip /
  list / detailsBar / isHidden / superview）。**不触发布局、不重绘**。
- `FFShellLayoutTests` 新增 3 条：诊断零误报、`showImmediately:false` 新窗口布局、
  20 轮交替侧栏/单双栏 × 左右活动面板；全量 **XCTest 305 条 0 失败**。
- `FF_SELFTEST=1`：既有 153 项 + 新增 `runLayoutStressSelfTest` **20 轮/80 快照 0 失败**；
  日志 0 条 `ANOMALY`。
- **新证据**：拖出新窗口刚 `showWindow` 时，主分栏首帧 50/50（侧栏 700 / 面板 700），
  随后才收敛到侧栏 220 左右；该帧内容与详情栏均正常。是否与空白 bug 同源尚未证实。
- **根因仍未确定**；禁止用延迟或强制重绘掩盖。Phase 2 重做全局顶栏时消除首帧瞬态，
  真机若复现，直接读 `/tmp/ff-debug.log` 的 `[LAYOUT]` + `ANOMALY`。

**Phase 1 设计基础（已完成）**

- `FFSizeLevel` / `FFSizePreference`：紧凑 12/28/16、舒适 13/30/18、大 14/32/20
  （正文字号/行高/图标）；默认舒适，持久化键 `ff_ui_size_level`；
  `FFVisualTokens.rowHeight/iconSize/Font.body` 改为随偏好计算；设置 > 外观新增三档控件。
- `FFTopBarMetrics`：44 栏 / 38 标签 / 6 空条 / 22 中线 / 13 标签字 / 16 图标 / 10 内凹 / 16 边距。
- 图标：`FFIconResolver` 为全部 104 个 `FFIconName` 建立映射；系统 chrome 用 SF Symbols，
  文件类型/文件夹用 Phosphor（`Resources/Icons/Phosphor/regular|duotone`，MIT 许可证随包）；
  标签用 SF `tag`/`tag.fill`（Phosphor 无 tags）。`FFIcon.missingSymbols()` /
  `missingAssets()` 作为自检；104 图标联系表人工核对无破图。
- 焊接自检的“＋/× 与标签中线对齐”改为比较 alignment rect，避开 NSButton 对 SF Symbol
  自动加的内边距（raw frame 会比 24×24 大）。
- 验证：XCTest **312 条 0 失败**；自检 **153 项 + 20 轮/80 快照 0 失败**。
- **已知未联动**：文件列表行高仍由旧“列表密度”（26/30/36）控制，未与“界面尺寸”合并；
  留到 Phase 6 统一。旧 Lucide SVG 已无调用点，暂留资源，Phase 7 清理。

**Phase 2 全局顶栏（已完成）**

- `FFGlobalTopBar`（`PaneTabs.swift`）：44pt 窗口级顶栏，顺序 工具→侧栏→左标签→右标签→
  分隔线→主题→单双栏；标签组按左右面板实际 frame 手动对齐，跨分栏不再依赖 Auto Layout。
- C2 指标：标签 38 / 空条 6 / 内容 22 中线 / 内凹 10 / 顶栏键命中 28 / 图标 16。
  活动标签内容相对标签框上移 3pt（NSStackView flipped，约束用负值）。
- 工具入口从侧栏品牌区迁到顶栏最前；侧栏品牌只留名称/版本；侧栏顶部控制行已删除。
- 隐藏侧栏：工具/侧栏键常驻，标签组右移让位；面板工具栏始终 8pt，面包屑/搜索不再右移。
- 新窗口：`prepareForInitialDisplay()` 在显示前完成侧栏/分栏定位；拖出新窗口首帧
  从 700pt（50/50）变为 1120pt，`[LAYOUT]` 可验证。
- 验证：XCTest **316 条 0 失败**；自检 **155 项 + 20 轮/80 快照 0 失败**；
  实机 1400 双栏/隐藏侧栏截图通过。
- **未验**：1060 窗口、深色主题、真实全屏（测试中快捷键被其它 App 抢走）；
  `DuplicateScanBrowseRegressionTests` 依赖 NSOpenPanel，全量套件偶发 30s 超时（单独通过），
  属已知抖动，与本轮顶栏改动无关。

**Phase 3 面板宽度（已完成）**

- `FFPaneWidthMath`：首选最小 400、硬下限 360，按窗口宽度软降；25/50/75 吸附（12pt），
  双击 50/50。
- `FFSplitView`：12pt 热区、拖动 `pt` 浮标（挂在 mainContainer，不能放进 NSSplitView，
  否则会被当成第 3 个面板）、双击/吸附；命中限制在分栏自身 bounds 内。
- 宽度记忆：侧栏宽度只由侧栏拖拽写；面板宽度/比例只由中缝拖拽/双击写；
  窗口缩放、单双切换、程序化 setPosition 都不写 `sidebar_width`。
- 窗口缩放：侧栏按偏好宽度钉住，两栏按记忆比例伸缩；单↔双往返侧栏宽度不变。
- 启动/新窗：`applyInitialSplitPositions()` 在显示前同步设置分隔线，消除首帧 50/50。
- 验证：XCTest **322 条 0 失败**；自检 **164 项 + 20 轮/80 快照 0 失败**。
- 查重浏览 NSOpenPanel 全量套件抖动已在测试内激活 App 修复，全量稳定通过。
- **未验**：真实鼠标拖拽的浮标位置/吸附手感、1060 窗口、深色、真实全屏。

**Phase 4 详情浮层（已完成）**

- 展开高度 132–300（默认 132）；预览列 96–200（默认 132），图标随列宽缩放。
- 视觉改为实体表面（与面板同色）+ 12pt 连续圆角 + 0.5pt 边框 + 柔和阴影，去掉第二层玻璃。
- 名称两行换行、单击编辑、Enter 保存、Esc 取消；位置两行换行、点击复制。
- 字段：类型/大小/修改/创建/位置/标签/说明；移除文件来源、磁盘可用、EXIF/相机、编码/帧率/格式、
  构建号/Bundle ID、字数等；类型专属保留并补齐 ZIP 内含文件数（读 EOCD，不调外部命令）。
- 列表底部按详情栏高度让位（FileListView 内部补 8pt），最后一行不被浮层盖住。
- 验证：XCTest **329 条 0 失败**；自检 **164 项 + 20 轮** 0 失败。
- **未验**：详情展开态实机截图（临时 App 前台控制不稳）、1060/深色/全屏。

**Phase 5 文件标签（已完成）**

- `TagCatalog`（`TagIndexStore.swift`）是标签定义/排序唯一真值：新建（同名合并）、
  改名/改色/删除同步所有文件、上下排序；删除前异步统计影响文件数。
- `TagIndexStore.mutateTag` 跨文件改名/改色/删除；`removeDefinition` 只删定义（批量
  删除完成后的收尾）。
- 侧栏 ⌘ 点选多标签 AND，再次点选取消；高亮改为集合；计数仍按当前目录。
- `TagSelectorDialog` 支持多路径：只应用增删差异，不覆盖各文件其它标签；
  右键标签子菜单批量/混合态/清除所有/管理；⌥⌘T、文件菜单、详情栏标签按钮共用。
- 设置 > 标签管理：新建/改名/改色/删除/上下排序；改名到已存在名称时合并。
- 验证：XCTest **334 条 0 失败**（AND、跨文件改名/删除、批量、合并 5 条）；
  自检 **164 项 + 20 轮** 0 失败。
- **未验**：设置页标签管理器视觉、真实 Finder 双向互通、全局计数（当前按目录）。

**Phase 6 设置视觉（已完成）**

- `FFSettingsMetrics`：12pt 卡片 / 40pt 行 / 26pt 控件（switch 24）/ 16pt 内边距 /
  行距 2 / 标题 13 / 说明 11。
- 分区卡片 12pt 连续圆角、标题 13 semibold、图标 16；行 hover 8pt 圆角；
  popup/segmented/textField/button 统一 26pt，switch/slider 24pt。
- 保留 7 分区与全部功能；标签管理接入 `TagCatalog`；外观“界面尺寸”三档沿用。
- 验证：XCTest **335 条 0 失败**；自检 164 + 20 轮 0 失败。
- **未验**：设置页浅/深色实机截图。

**Phase 7 收口（已完成）**

- `make build`：Rust + Swift Debug BUILD SUCCEEDED。
- XCTest **335 条 0 失败**；自检 **164 项 + 20 轮/80 快照** 0 失败。
- 产物：`/tmp/FlowFinder-0.8.0-Beta-r19.app`；**已按用户确认执行 `make demo`
  覆盖桌面副本** `~/Desktop/FlowFinder.app`（2026-10-21 21:14，0.8.0 / 8001），并启动成功。
- 未运行 `make swift-test`（内含 `pkill -f "MacOS/FlowFinder"`，会杀用户副本）；等价使用
  `xcodebuild test`。
- **未提交、未推送。**
- 未验：1060/深色/真实全屏/真实拖拽浮标/详情展开态/设置与标签管理器视觉/Finder 互通。

**待定实现细节**

- “界面尺寸”与“列表密度”的合并方式（未做）。
- 上述人工走查项。
- 其余 12 项设计均已确认，见上文「已确认」。

### 1.11 2026-10-22 第二轮整改（第十三轮 R-20，接手必读）

用户看完第十二轮产物后提 4 项：① 红绿灯没跟按钮/标签对齐；② 标签整体太高，操作面板上边缘要上移；
③ 工具面板要重构并放回品牌隔壁；④ 移除操作面板的新建文件夹按钮，第二行显示设置按钮并入显示设置。
按「可视化对比稿 → 一次一问 → 锁定 → TDD」推进，规格 `SPEC-2026-10-21-UI-ROUND2.md`，
计划 `PLAN-2026-10-21-UI-ROUND2.md`（Task 1–4 全部执行）。实现跨 2026-10-21 深夜至 2026-10-22 凌晨。

**已确认决策（用户原话/选项）**

| ID | 决策 |
|---|---|
| D-01 | 顶栏 36 / 活动标签 30 / 非活动 26 / 顶部空条 6 / 内容共用中线 18pt；红绿灯中心移到 18pt；操作面板上边缘上移 8pt（可视化选 A） |
| D-02 | 工具入口从顶栏删除，放回品牌右侧「工具」胶囊（「位置还是放回品牌隔壁」） |
| D-03 | 工具页做成侧栏内页面（选 1 侧栏页 + 分组纵向列表），文件区保持可见 |
| D-04 | 「这个是工具页面的入口，其他操作是右键菜单负责的」——页面不显示路径/选中/活动面板 |
| D-05 | 工具页只列 5 个可用工具（查重 / 批量重命名 / 任务中心 / 设置 / 关于），AI 不进页面 |
| D-07 | 第二行删新建文件夹与齿轮，眼睛改名为唯一「显示设置」，菜单合并显示项 + 第二行显示 + 显示列（可视化选 A） |
| D-09 | 版本规则 `A.B.C-yymmddxx`：每次迭代构建自动更新内部构建号 |

**改了什么**

- 顶栏：`FFTopBarMetrics` 36/30/6/18 + `tabContentOffset 3`；`FFInteractionPolicy` 36/30/26/命中 28；
  `FFGlobalTopBar` 去掉 `toolButton`，侧栏开关成为最左控件；`MainWindowController.alignTrafficLightsToTopBar()`
  在 `windowDidBecomeKey` / `handleWindowLayout()` / `updateGlobalTopBarLayout()` / 首帧后重对齐系统按钮。
- 工具页：新增 `UI/FFToolPage.swift`（`FFToolPageCatalog` + `SidebarToolPageView` + `FFToolRowView`），
  删除 `UI/FFToolPopoverController.swift`（浮层被侧栏页取代）；`SidebarView` 新增 `toolPill` 与
  `toggleToolPage/showToolPage/closeToolPage`，胶囊位置随侧栏宽度在名称行/版本行之间换行（阈值 200pt）；
  `FFPillButton` 新增 `isSelected`（强调色底/字）与可调高度；`FFIcon` 新增 `.wrench`。
- 第二行：`FFToolbarRow2Item` 删 `newFolder`（旧偏好值自动忽略）；`PaneToolbar` 删新建文件夹按钮、
  齿轮按钮与悬停气泡，`displaySettingsButton`（眼睛）成为唯一入口，菜单由 `makeDisplaySettingsMenu()` 组装；
  `MainWindowController` 删 `paneToolbarDidClickNewFolder` 与 `setFolderSelectionCount` 调用。
  新建文件夹仍走文件菜单 / 右键菜单 / ⇧⌘N。
- 版本：新增 `scripts/bump-version.sh`（`CFBundleVersion = yymmddxx`，同日再构建自动 +1，旧值 `8001` 重置为当日 01），
  `lib-version.sh` 导出 `FF_DISPLAY_VERSION`，`Makefile` 的 `build`/`release`/`beta` 前置递增并新增 `bump-version` 目标，
  `FFBuildInfo.displayVersion` 改为 `0.8.0-26102201 Beta` 格式。

**当轮实测数字**

- XCTest **349 条 0 失败**（2026-10-22，`xcodebuild test -scheme FlowFinderTests -destination platform=macOS`）。
- 应用内自检 **163 项 0 失败**（POLICY 71 + REGION 7 + BEHAVIOR 4 + WELD 35 + AVOID 5 + WIDTH 9 + SHELL 22 + 落点 10）
  **+ 布局压力 20 轮 0 失败**；AVOID 由 6 降为 5 是因为顶栏工具键已删除，对应断言随之移除。
- `make build` BUILD SUCCEEDED，输出 `✓ 版本 0.8.0-26102201`；产物 `~/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app`。
- 按用户指令执行 `make demo`：构建号递增为 **0.8.0-26102202**，已覆盖 `~/Desktop/FlowFinder.app` 并启动；
  `codesign --verify` 通过（valid on disk / satisfies Designated Requirement）；在**最终产物**上重跑自检
  **163 项 0 失败 + 20 轮布局压力 0 失败**（日志 `/tmp/ff-debug.log`）。
- 测试污染修复：`FFVisualTokensTests` 增加 `accent_color` 快照/恢复（用户曾在设置里选过石墨色，
  使「默认跟随系统强调色」断言读到了真实偏好）。

**未验项（下一轮或人工必须补）**

- 真机走查已完成一半（2026-10-22，用户点「允许」后）：
  - 【实机】窗口截图 + 像素测量：红绿灯红色圆中心 **17.5pt**、活动标签文字中心 **17.5pt**（规范 18pt，误差 0.5）；
    侧栏版本行实测 `0.8.0-26102201 Beta`；品牌旁为 24pt「工具」胶囊；第二行只剩一个「显示设置」按钮（AX `id 36`）。
  - 【实机】展开显示设置菜单：显示隐藏文件 / 隐藏文件标签 / 隐藏文件后缀 / 显示系统文件 + 「显示列」7 项 +
    「第二行显示」4 项（搜索 / 排序 / 分组 / 列表 / 图标），**没有新建文件夹**。
- 【实机】工具页打开态（2026-10-22 补）：点品牌旁胶囊后 AX 读到 `工具 / 返回收藏` +
  整理（重复文件扫描可用、批量重命名禁用「先选择文件」）/ 任务（任务中心）/ 系统（设置、关于 FlowFinder）共 5 行，
  文件区与双栏不受影响；截图 `/tmp/ff-toolpage-26102202.png`。
- 【实机】窄侧栏（2026-10-22 补）：`sidebar_width=180` 重启后名称完整、版本号截断
  `0.8.0-26102202…`、「工具」胶囊换到版本号所在行；截图 `/tmp/ff-narrow-180.png`（已恢复 206pt）。
- 需人工确认：红绿灯物理点击关窗、极矮窗口下工具页滚动、工具胶囊与工具行的 VoiceOver 可操作性。
- 桌面副本已覆盖为 `0.8.0-26102202 Beta` 并启动成功（`make demo`），用户可直接在桌面副本实测四项。
- **未提交、未推送。**
- 权限门槛备忘：启动后 macOS 首次会弹「访问桌面文件夹」的 TCC 授权框，它会让 Computer Use 超时；
  `FF_SKIP_PERMISSION_GATE=1` 只跳过应用自己的权限门，挡不住系统 TCC。授权后即可正常自动化。

---

### 1.12 2026-10-22 批次 1：设置接线 / 终端入口 / 工具页无障碍（第十四轮 R-21）

用户要求「全部接线」并逐项确认行为。审计纠正：`startup_location` 与 `default_view_mode`
原本已接线；真正失效的是 5 个控件 + 2 个孤儿键，完整会话只缺活动面板。

- 新增 `FFAppSettings`（集中读取 + 可注入 UserDefaults）、`FFDragBehaviorPolicy`、`FFSortPolicy`、
  `FFSelectionRestore`、`MoveConfirmation`、`FFUpdateDecision`、`FFUpdateChecker`、
  `FFSMBConnectionStore`/`FFSMBURL`/`FFSMBStatusText`。
- 设置：移动前确认（与既有删除确认拆分）、默认操作行为三选、文件夹优先排序、刷新保持选中、
  启动检查更新（完整版本戳比较 + 24h 节流 + 关于页手动检查）、SMB 默认域（对话框新增域字段）、
  SMB 自动重连（持久化 + 启动重连 + 底部状态条 + 重试）。
- 完整会话：`last_active_pane` 持久化并在「上次打开的位置」时恢复活动面板。
- 终端入口：`NSWorkspace` 打开 Terminal，删除 osascript。
- 无障碍：工具胶囊 AX button/label/pressed + Space/Return；工具行接入 keyViewLoop、焦点环。
- 验证：XCTest **368 条 0 失败**；自检 **163 + 20 轮**；`make build` 出 `0.8.0-26102203`；
  设置页真机 AX + 截图 `/tmp/ff-batch1-settings.png`。
- 未验：真实 SMB 断线提示、更新提示（需新 Release）、移动确认/终端实际点击、工具页 Tab 人工走查。

### 1.13 2026-10-22 批次 2：功能回归测试 6 组（第十五轮 R-22）

- 新增 `FFBatch2IntegrationTests` 15 条：跨栏 ⌘⇧C/⌘⇧X/在另一侧打开、搜索过滤与清空、
  ⌘F 聚焦、Tab 环含胶囊与工具行、文本编辑 ⌘C 隔离、Finder 标签 plist 写入/读回、
  文件夹优先、刷新保持/清除选中、硬编码棘轮、隐私用途声明。
- 测试钩子：`FFSearchPolicy`、`PaneToolbar.searchFieldForTesting`、
  `MainWindowController.keyViewLoopForTesting()`。
- 环境坑：测试目录必须用 `/tmp`；`/var/folders` 在 XCTest harness 下会被 Rust 枚举为 0 条。
- 验证：XCTest **383 条 0 失败**；自检 **163 + 20 轮**；`make build` 出 `0.8.0-26102204`。
- 未验：真实拖拽手感、真实 SMB 断线、更新提示。

---

### 1.14 2026-10-22 批次 3：文档与代码对齐（第十六轮 R-23）

- `REQUIREMENTS.md` 重写为 2.1：按 R-19…R-22 的实现更新状态，保留未实现项为 backlog，
  新增本轮能力清单与宣称对照；`ACCEPTANCE.md` 重写为 1.1：侧栏 220/180–280、
  详情 54/132–300、行高 26/30/36（标签 44/48/56）、顶栏 36/30/26/18，新增设置/更新/SMB/无障碍验收。
- `README.md` 修 5 处过期宣称；R-19 PLAN 的台账编号改为 R-19；代码规模更新为 Swift 111 文件 / 约 43,800 行。
- 本批无代码、无测试变更；基线仍为 XCTest 383 / 自检 163 + 20 轮 / 版本 0.8.0-26102204。

---

### 1.15 2026-10-22 批次 4：首次引导 / 崩溃日志 / Tab 环 / AI 命名（第十七轮 R-24）

- `OnboardingWindowController`：首次启动独立欢迎窗口（双栏图示、权限状态、⌘⇧C/⌘F/Space）；
  「开始使用」写 `onboarding_completed`，「稍后再看」只关本次；帮助菜单可重开。
- `FFCrashLog`：未捕获异常写入 `~/Library/Logs/FlowFinder/crash.log`。
- keyViewLoop 接入侧栏收藏列表；工具注册表去掉 AI 字样（按类型自动打标签 / 自动整理）。
- 实机：首启弹窗正常，点击开始使用后二次启动不再弹；截图 `/tmp/ff-onboarding2.png`。
- 验证：XCTest **389 条 0 失败**；自检 **163 + 20 轮**；版本 `0.8.0-26102209`。
- 未验：帮助菜单重开引导的自动化点击；崩溃日志未人为触发。
- 收口（2026-10-22）：`make demo` 覆盖桌面副本为 `0.8.0-26102209`（签名验证通过），最终产物自检 **163 + 20 轮** 0 失败。
- 发布（2026-10-22）：GitHub Release `v0.8.0-b1`（Prerelease），产物 DMG / ZIP / SHA256；
  https://github.com/waltxao/FlowFinder/releases/tag/v0.8.0-b1

---

### 1.16 2026-10-22 真机走查问题修复（第十八轮 R-25）

- 名称列：自动布局下限改为「可用宽度 40% / 不低于 160pt」，500pt 面板不再截断成 80pt。
- 启动：改为立即加载 + 权限门并行，权限门最多 3s，失败/空目录在门完成后重试；首屏 30s → 1.08s。
- 详情栏：订阅 `$state.selectedFiles`，移动/删除后自动回到「未选择文件」。
- 工具页：返回收藏时焦点还给工具胶囊。
- 新增「前往文件夹…」（⇧⌘G），支持 `~` 与绝对路径。
- 验证：XCTest **393 条 0 失败**；自检 **163 + 20 轮**；桌面副本 **0.8.0-26102212**。
- AX 全量枚举 5000 行 RSS 183→792/893MB 的问题已由 §1.18 R-26 修复。

---

### 1.17 2026-10-22 未实现 / 未验证清单（接手先读）

#### 未实现

| 项 | 现状 |
|---|---|
| R-02 单双面板真位移动画 | 仅窗口宽度 + 透明度动画，面板 frame 无位移；用户已裁定自管布局，未实施 |
| J2-08 双栏同步导航 / J2-09 目录差异对比 | 未实现 |
| J3-10 按日期/类型批量整理 | ✅ 已完成（R-29，见 §1.21） |
| C-01 字体令牌 | 两套令牌 + 122 处硬编码 |
| R-06 图标线宽 1.75 | SVG 烘焙，不可参数化 |

#### 未验证

真实拖拽手感/60fps、红绿灯物理点击、1060/深色/高对比/全屏、SMB 真实断线、更新提示、QuickLook、VoiceOver 完整走查（含文件列表逐行/列朗读）、详情/设置/标签管理器截图、冷启动与 10,000 行 ≥55fps 正式测量、Finder 标签/说明人眼互通。1 万行常驻内存已由 R-26 在 Release 实测 174.9→185.2MB；详情栏文件说明的界面文本输入手势未实机点击；J2-07 递归 500 条截断提示未加；J3-10 重名冲突「跳过」场景未单独实机构造验证。
测试环境：`DuplicateScanBrowseRegressionTests.testBrowseSheetReappearsAfterDeleteAndRescan` 全量并发下偶发失败（单跑与复跑全量通过）；`testDeleteIsNonBlocking` 在测试宿主移动真实文件到废纸篓时曾超时。2026-10-22 R-29 复跑全量 422 条 0 失败。

#### 发布与工作区

- `v0.8.0-b1` 资产基于 **26102209**，不含 R-25…R-34。
- 桌面副本已于 2026-10-22 经用户授权覆盖为 **26102235**（含 R-25…R-35）并启动验证；上一次覆盖为 26102221（R-25…R-29）。Release 仍为 **26102215**。
- R-25…R-34 改动**未提交、未推送**。
- 基线：XCTest **434 条：分批 428 + 新增类 4 定向通过 + 2 条既有环境测试** / 自检 163 + 20 轮（26102224 基线；26102226/27 自检宿主窗口未创建）。

---

### 1.18 2026-10-22 AX 行虚拟化（第十九轮 R-26）

- 根因：默认 `NSTableView` 的 AX 树按行/列/cell 展开；AX 客户端深枚举 5000 行会反复触发 `viewFor`（独立探针实测 165 万次），FlowFinder 的 cell 创建含图标/缩略图/标签药丸，RSS 183→792/893MB。
- 实现：`FileListView.swift` 新增 `FFAXRowDataSource` 与 `FFAXRowElement: NSAccessibilityElement`；`FFQuickLookTableView` 覆写 `AXRowCount` / `AXRows` / `AXVisibleRows` / `AXSelectedRows` / `AXChildren` / `AXSelectedChildren`。每行只暴露「名称，类型，大小」摘要，`accessibilityChildren` 为空，不物化 cell；`AXSelectedCells` / `AXVisibleCells` / `AXRowHeaderUIElements` 返回空。`selectRowIndexes` 发 `selectedRowsChanged`；`reloadData` 与分页追加后调用 `invalidateAXRows()`。
- 代价：列级 cell 朗读被有意关闭，VoiceOver 走行级摘要；K-05 只要求侧栏名称/类型，未回退。
- 测试：新增 `FFAXVirtualizationTests` 4 条（5000 行完整代理、零 cell 创建、选中往返/按下、刷新失效）；全量 **397 条 0 失败**；自检 **163 + 20 轮** 0 失败（DEBUG 26102214）。
- 真机：Release `26102215` 独立 Bundle ID 副本，10,000 个零字节文件单栏 + 空右栏；正常 RSS **174.9MB**；外部 AX 全量枚举 **10,202 元素 / 10,006 行 / 120,329 属性** 后 **185.2MB**（+5.4MB）；`AXPress` 第 9999 行 → `AXSelectedRows=1, index=9999`，RSS 185.9MB。5000 行 Debug：216→220MB，AX 后 226MB。
- 未验：VoiceOver 人工逐行朗读/列朗读、移动/重命名后的听感确认；列级 AX 语义为有意取舍。
- **2026-10-22 R-30 审计纠偏（重要）**：独立副本用系统 AX 客户端复测时，表格仍暴露每行 4 个 cell；选中一行后还会额外出现一条同名、disabled 的轻量行。说明 `FFAXRowElement` 目前是并行附加而非替换默认行，R-26 不能按「已完成」计；下一批 P1 需用真实 AX 客户端重新验收，不能只依赖 4 条假数据源单测。

---

### 1.19 2026-10-22 文件说明迁移 Finder 注释（第二十轮 R-27 / J3-11）

- 问题：详情栏「文件说明」存 `UserDefaults["fileDescriptions"]`（绝对路径 key），列表「说明」列读 Spotlight `kMDItemFinderComment`；两个入口数据源不一致，改名/移动丢说明。
- 实现：`FFListColumns.swift` 新增 `FFFinderCommentStore`，用 `com.apple.metadata:kMDItemFinderComment` binary plist 读写；空值移除 xattr，兼容纯文本旧 xattr。详情栏优先读 Finder 注释、回退旧字典；列表说明列缓存改读 xattr。保存成功清旧字典并刷新；失败保留本地回退并中文提示。
- 迁移：首次启动 4s 后后台一次性迁移；路径存在且 Finder 注释为空才写；已有注释/失效路径/失败保留旧字典；成功条目删除；迁移标记 `fileDescriptionsMigratedToFinderCommentV1`。迁移跑完清缓存并刷新列表。
- 测试：新增 `FFFinderCommentStoreTests` 5 条（读写往返、纯文本兼容、迁移只写空注释、只跑一次、失败保留）；全量 **402 条 0 失败**；自检 **163 + 20 轮** 0 失败（DEBUG 26102216）。
- 真机：独立 Bundle ID 副本预置旧字典后启动；xattr 实际 **56 字节**，解码「旧说明迁移测试」；旧 `fileDescriptions` 键删除、迁移标记 1；展开详情栏 AX 读到「旧说明迁移测试」。
- 未验：详情栏描述字段在展开栏滚动区，自动化坐标点击受限；界面文本输入/回车保存未实机点击，store 写入与迁移已覆盖；Finder「显示简介」人眼确认待补。

---

### 1.20 2026-10-22 搜索范围（第二十一轮 R-28 / J2-07）

- 问题：搜索固定为当前栏递归 3 层 / 上限 500，没有范围 UI，无法只搜当前目录或两侧同时搜。
- 实现：`FFSearchScope`（本栏 / 含子目录 / 双栏）+ `PaneState.searchScope`。`本栏`/`双栏` 只过滤当前目录；`含子目录` 才调度递归（仍 3 层 / 500 条）；离开递归会取消挂起任务并清除追加结果。`PaneToolbar` 在搜索框右侧加 22pt 紧凑范围菜单（A 方案），带 AX label「搜索范围」，随搜索项隐藏，进入 keyViewLoop。`MainWindowController` 负责双栏镜像：任一侧搜索框驱动两侧；进入双栏同步两侧查询/范围，离开双栏清除对侧镜像并恢复完整列表；程序化更新不触发 delegate 循环。
- 测试：新增 7 条（范围枚举、工具栏菜单、三种范围过滤、双栏镜像/退出）；全量 409 条 407 通过（2 条测试宿主环境失败，见 §1.17）；自检 **163 + 20 轮** 0 失败（DEBUG 26102218）。字体 lint 手动核验 **127 / 9**，未超预算。
- 真机：DEBUG `26102217/18` 独立副本，左 `/tmp/ff-j207-left`、右 `/tmp/ff-j207-right`。
  - 双栏 + 输入 `alpha`：两侧搜索框都显示 `alpha`；左只剩 `alpha.txt`，右只剩 `alpha-right.txt`；子目录 `alpha-deep.txt` 不出现。
  - 左切「含子目录」：左出现 `alpha.txt + alpha-deep.txt`；右查询清空、范围回「本栏」，右栏 2 项恢复。
  - 左切「本栏」：左只剩 `alpha.txt`，右保持完整 2 项。
- 未验：递归命中 500 条时的「已截断」提示未加；搜索范围不跨启动持久化（每次启动回「本栏」）。

---

### 1.21 2026-10-22 批量整理（第二十二轮 R-29 / J3-10）

- 问题：Rust FFI `ff_organize_by_date/type` 已有但 Swift 无入口，无法按日期/类型整理当前目录。
- 实现（Swift 侧，Rust FFI 未使用、未改未删）：
  - `FFOrganizePlanner`（纯函数）：日期三档 `YYYY/MM/DD·YYYY/MM·YYYY` 默认 YYYY/MM、中文 9 类别；范围=当前目录全部顶层文件（子文件夹不动、排除隐藏文件）；目标重名→Conflict 不覆盖。
  - `FFOrganizeSheet`（FFModalSheet）：整理方式/日期格式弹出、统计「N 项移动 · M 项重名跳过」、计划清单（重名行橙色）、`执行后可 ⌘Z 一次撤销整批`；空目录/读取失败/无可整理文件走 sheet alert 中文提示。
  - `PaneState.performOrganize`：generation 计数防串批、后台 `moveItem`、`CoreBridge.invalidateCache`、发 `.paneFileOperationChanged`；`registerUndoOrganize` 整批一次 ⌘Z（右键菜单出现「重做批量整理」）。
  - 双入口：工具页 `batch-organize` 行（整理组，工具页共 6 工具）→ `menuBatchOrganize`；右键「整理当前目录…」→ `.fileListBatchOrganize` 通知（仅响应本窗口面板，Wave2 P0-4）。
- 真机发现并修复（TDD）：① Sheet body 塌陷成重叠一行——`buildBody` 子视图漏设 `translatesAutoresizingMaskIntoConstraints = false`，autoresizing 约束冲突被 `FFModalSheet` 量高时拆掉；② 工具页行是 AX button 但无 `accessibilityPerformPress`，AXPress 无效——补覆写（键盘路径原本就通）；③ 工具页断言 5→6 工具、Tab 环 6 行，新增 `testToolRowSupportsAXPress`。
- 测试：新增 13 条（12 条 FFOrganize 计划/执行/撤销 + 1 条 AXPress）；全量 **422 条 0 失败**（一次全量中 DuplicateScan 回归并发偶发失败，单跑与复跑通过）；自检 **163 + 20 轮** 0 失败（DEBUG 26102220）；新增文件 0 处裸 `NSFont`（存量 122）。
- 真机（DEBUG 26102220 独立 Bundle ID 副本，`/tmp/ff-org-test`）：AXPress 打开 Sheet 渲染完整；「按类型」→ /图片、/文档、/音频且日期格式弹出隐藏；执行后 3 文件实际位于 `2025/11/`、`sub` 未动、列表自动刷新；⌘Z 后文件回根目录；右键入口弹出同一 Sheet。
- 注意：独立 Bundle ID 副本与桌面副本**共享** `~/Library/Application Support/FlowFinder/`（缓存/索引/会话路径未按 bundle 隔离，既有行为），副本右栏会恢复用户真实会话——验证只在 `/tmp` 执行。
- 未验：重名冲突「跳过」行未单独实机构造验证；整理不含子文件夹内部（按定稿）；撤销不跨会话持久。

---

### 1.22 2026-10-22 项目文件夹整理与 AI 资源入库（用户指令）

- docs 归档：2026-10-18～10-21 的 11 份 PLAN、9 份 SPEC 及 `AUDIT-2026-10-19.md`、`交接文案-2026-10-20.md` 共 **21 份**移入 `docs/archive/2026-10/`（git mv 保留历史）；docs 根层只留 REQUIREMENTS / REQUIREMENTS-LEDGER / HANDOVER / ACCEPTANCE / DESIGN-SPEC / PRODUCT、当前批次 `PLAN/SPEC-2026-10-22-BATCH1.md`、`images/`、`index.html`。
- 构建产物清理（用户确认）：删除 `build/`（127M）与 `build_stale_0021/`（135M）——Makefile 产物已改写 `~/Library/Caches/FlowFinderBuild/`，两目录不再被引用；`build-beta/`（v0.8.0-b1 发布资产）保留。释放约 262M。
- AI 资源入库：新增 `resources/ai-tools/`——`skills/`（15 个本项目相关用户级 Skill 快照，源自 `~/.qoder-cn/skills/`）、`plugins/grillme-matt/0.1.0`（插件完整拷贝）、`MCP-AND-SKILLS.md`（MCP 服务登记 + Skill 用途表 + 快照来源对照）。清单详见该文件。
- 未提交、未推送（连同 R-25…R-29）。

---

### 1.23 2026-10-22 P0 数据安全修复（第二十三轮 R-30，接手必读）

用户确认「按计划执行」后完成第 0 批两条 P0：

- **重命名覆盖**：`PaneViewModel.renameFile` 在 FFI 前检查目标存在；目标存在且 `fileResourceIdentifier` 不是同一文件时拒绝并提示「已存在同名文件，请换一个名称」。只大小写变化的重命名仍允许。后端正向 `ff_rename` 未改；这是 UI 层止损。
- **查重零保留**：新增 `FFDuplicateSelectionPolicy.canMarkForDeletion`；`DuplicateGroupView` 试图删除最后一项时拒绝、恢复行状态并 beep。每组至少保留一个。
- **永久删除确认**：`DeleteConfirmDialog.isPermanent` 强制确认、忽略并隐藏「不再询问」、副标题固定「此操作无法撤销」；查重窗口传 `isPermanent: true`。永久删除失败项收集后在 sheet 中列出，不再静默。
- 测试：新增 4 条（`FFRenameCollisionTests` 2 条 + `FFDestructivePolicyTests` 2 条）；全量 **426 条：424 通过 + 1 条既有测试宿主废纸篓超时**；自检 **163 + 20 轮** 0 失败。全量串跑存在既有跨测试套件挂起，本轮按测试类分 15 批执行。
- 构建：`make build` 成功，版本 **0.8.0-26102222**；**未执行 `make demo`**，桌面副本仍为 26102221。
- 未验：重命名冲突的界面错误横幅/内联编辑回退手势、查重零保留的 beep/行状态恢复、永久删除失败 sheet 均未实机点击。
- **审计纠偏**：R-26 的 AX 行虚拟化不能按「已完成」计——独立副本系统 AX 树仍暴露每行 4 个 cell，选中后额外出现同名 disabled 行；已降级为部分完成，排入下一批 P1。

**测试环境坑（新）**：测试宿主与桌面副本同 Bundle ID，会触发单实例提示；测试源码在外置卷时 `testHardcodedTokenBudget` 会卡在目录 `open`。当前验证方式：把工程镜像到内置盘 `/tmp`，在镜像里改测试宿主 Bundle ID，按测试类分批跑。产品工程与桌面实例不动。

---

### 1.24 2026-10-22 P1 UI 状态与入口修复（第二十四轮 R-31）

- 工具栏：`PaneToolbar` 新增 `setSortField/setGroupBy`；`updatePaneUI` 同步 searchQuery/searchScope/sortField/groupBy，导航、切标签、列头排序后第二行不再停留在旧状态。
- 工具页：`SidebarToolPageView.updateContext` 按可用性签名增量重建；`SidebarView.refreshToolPageContext` 由 `updatePaneUI`/`activatePane` 触发；“返回收藏”纳入 Tab 环；焦点环绘制不再被 hover 守卫挡住。
- 标签/侧栏：单标签 `×` 关闭窗口；侧栏「在新标签页中打开」只按收藏有效性置灰，不再依赖被故意设为 `.disallowed` 的 `window.tabbingMode`。
- 右键：`ensureClickedItemSelected` 在复制/剪切/删除/跨栏/拷贝路径前先选中右键点击项；点击已选中项保留多选。
- 整理：右键「整理当前目录」按通知 source 视图路由到左/右面板，不再固定 activePane；按类型时「日期格式」标题同步隐藏。
- 显示设置：菜单改为固定名词 + 勾选态；隐藏的 Row2 控件移出 keyViewLoop。
- F-06 文案：右键菜单「AI 自动打标签」改为「按类型自动打标签」；关于页「AI 智能分类」改为「按类型自动分类」。
- 测试：新增 4 条 + 更新 3 条断言；全量 **430 条：分批 428 通过 + 2 条既有环境测试**；自检 **163 + 20 轮** 0 失败。
- 构建：`make build` 成功，版本 **0.8.0-26102224**；未执行 `make demo`，桌面副本仍为 26102221。
- 实机（DEBUG 26102223/26102224 独立 Bundle ID 副本）：显示设置菜单固定名词通过；工具页打开时全选 3 项后「批量重命名」即时可用；侧栏「在新标签页中打开」成功开出 Desktop 标签；单标签 `×` 关闭窗口；右键 clickedEntry 拷贝路径为 beta；非活动栏右键整理 Sheet 标题为右栏目录；整理 Sheet 按类型后「日期格式」标题消失；工具页 Tab 焦点环可见；P0 重命名冲突提示出现且未覆盖 beta。
- 未验：查重零保留 beep/行状态恢复（策略/单测已覆盖）、永久删除失败 sheet、右键删除/剪切后源/目标面板刷新的实机组合。

---

### 1.25 2026-10-22 全量 UI/UX 验收第一轮（R-32，进行中）

完整报告：`docs/AUDIT-2026-10-22-UX.md`；证据截图在 `docs/images/audit-2026-10-22/`。

- **F-01 P1 实时主题切换失配（已修复 R-33）**：R-32 复现深色→浅色后侧栏/顶栏/工具栏白字白底、列表头/详情栏仍深色；R-33 修复玻璃窗口显式外观与详情栏 cgColor 刷新，DEBUG 26102226 浅→深→浅实机通过。
- **F-08 P1 批量重命名（已修复 R-34）**：只处理文件，文件夹忽略并在标题提示；空扩展名不再追加点号；尾点清理。新增 4 条纯函数测试；窗口实机触发仍受菜单焦点限制。
- **F-02 P1 详情栏（已修复 R-35）**：展开后只剩「名称 + 创建日期」；根因是重排在同一轮布局遍历内读取尚未重排的信息区 frame（栏 132pt / 子视图仍 30pt），改为按栏自身 bounds 推导可用宽高；DEBUG 26102235 实机 3 种宽度 9 字段全部可见、无内部滚动条。磁盘可用空间仍未显示。
- **F-03 P1 网格**：文本文件全部棋盘格占位；单元偏挤。
- **F-04 P1 多标签**：12 个标签时后续标签与 `+` 被裁，无溢出处理。
- **F-05 P1/P2 查重**：Button 泄漏、组名 hash、`Zero KB`/`bytes`、右侧“删除”与底部 0 选择矛盾、筛选未接线。
- **F-06 P2 设置**：文件管理图标缺失、44pt 过期文案、指向不存在的“删除与安全”、界面尺寸未生效。
- **F-07 P2 列表**：修改日期列默认截断，长文件名尾部截断。
- **F-09 P2 设置分区**：“文件管理”实际只有“删除与安全”且缺图标；标签行多余“/”；网络存储空态重叠/无内容滚动条；快捷键重置行被搜索框裁切。
- **F-11 P1 1060×700**：Row2 控件重叠/裁切；列表类型、大小列消失，只剩名称/修改日期。
- 本轮通过：工具页上下文/焦点、侧栏新标签、单标签关闭、右键 clickedEntry、非活动栏整理、整理 Sheet 按类型、重命名冲突、关于页 AI 文案、冲突弹窗（跳过/保留两者/替换）。
- **Blocked（不冒充通过）**：删除确认、移动确认、标签弹窗、文件简介、QuickLook、引导/权限、高对比/VoiceOver/Reduce Motion、SMB 真实断线/更新、活动面板发光（窗口未 key）。补验方式见审计报告 §7。

---

### 1.26 2026-10-22 F-02 详情栏流动布局（第二十八轮 R-35，接手必读）

- **症状**：展开详情栏只剩「名称 + 创建日期」，其余 7 个字段不可见；无滚动条可救（`hasVerticalScroller` 已按 D-06 关闭）。
- **根因**：`rearrangeFlow()` 由 `layout()` 推迟到本轮布局遍历内执行，却用**子视图 frame**当可用空间——
  实测栏 `bounds` 132pt、`contentModules` 108pt，而 `infoScrollView` 仍是折叠态 30pt（约束已 active，
  引擎尚未把新 frame 下发到子视图）。`FFDetailsFlowLayout` 于是按 30pt 只给每列排 1 行；
  遍历结束后没有任何事件再触发重排，错误布局固化。
  教训：**布局回调里只能读自身 bounds 与已知常量，不能读后代 frame**；先前「改成读 clip 高度」无效正是踩同一坑。
- **修复**：新增 `infoAreaSizeForFlow`（高 = `bounds.height - 6 - 18`，宽 = `bounds.width - 8×2 - 图标区 - 8`），
  行高改在脱离视图层级的 `flowMeasureRig` 里按该宽度测量，删掉布局内的递归 `layoutSubtreeIfNeeded()`，
  把 8/8/6 缩进提成 `expandedSideInset` / `iconDividerWidth` 常量，让推导口径与约束同源。
- **回归**：`FFDetailsLayoutTests.testExpandedDetailsFlowFitsAllRowsIntoVisibleHeight`
  ——刻意不 flush 布局、直接调 `rearrangeFlow()` 复现「子视图未重排」时刻；改前红（0 行 ≠ 8 行），改后绿。
  既有 `testRowsStayAttachedWithScrollableOverflow` 仍断言「应具备纵向滚动能力」，与 D-06 冲突，
  已按新契约改写（`hasVerticalScroller == false` + 可见列总高 ≤ 可视高度）并更名 `testRowsStayAttachedWhenBarShrinks`。
- **验证**：全量 16 批 **435 条 0 失败**；自检 153 通过 / 0 失败 + 布局压力 20 轮 0 失败；
  独立副本（`com.flowfinder.f02.live`，DEBUG `0.8.0-26102235`）实机 760 / 1400 / 1600 三种宽度截图见
  `docs/images/audit-2026-10-22/15~17-f02-after-*.png`。
- **未做**：磁盘可用空间（`_ = diskFree`）仍未展示；长名/长路径尾部截断归 F-07。
- **桌面副本（2026-10-22 用户授权后）**：覆盖为 **0.8.0-26102235** 并启动（PID 13208，窗口 1400×900，侧栏版本标签实测 `0.8.0-26102235 Beta`）。
  部署方式：直接复制 `make build` 已产出的 Debug 包（`~/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app`，二进制 22:23 晚于全部源码），
  未重跑 `make demo` 以免多递增一次构建号；`codesign --verify --deep` 通过（adhoc），旧 26102221 包备份在 `/tmp/ff-desktop-backup/`。

### 1.27 2026-10-23 第四轮 UI/UX 审计全量修复（R4-01…R4-32，接手必读）

审计：`docs/AUDIT-2026-10-23-UIUX-R4.md`（32 条确认 + 24 条通过 + 撤回/Blocked 各有记录）。
用户指令「开始全量修复」→ 按审计 §9 的五批全部做完，**未提交、未推送、未覆盖桌面副本**。

- **第 1 批 R4-01 本地化根因**：工程此前**没有任何 `.lproj`**，中文界面里的 `Cancel`/`OK`/`bytes`/24 小时制
  来自系统默认本地化与未指定 locale 的 formatter。新增 `Resources/zh-Hans.lproj/InfoPlist.strings`、
  Info.plist 补 `CFBundleDevelopmentRegion` 与 `CFBundleLocalizations`，formatter 统一中文 locale；`FFLocalizationTests` 6 条。
- **第 2 批 R4-03/R4-02**：面板工具栏改「溢出分级」（`PaneToolbar.swift`，窄面板把分组/范围/排序收进「更多」，
  下拉宽度由策略写死并有测试守住）；被宽度挤掉的列在「显示列」菜单标明原因；
  任务中心终态成为事实终点，迟到进度不能把已完成任务改回「进行中」（`TaskService.swift:65`）。
- **第 3 批 R4-06/07/08/09/10/11**：新增 `FFNaming` 作为除侧栏/工具注册表外所有入口的唯一叫法来源；
  侧栏开关改名避开 AppKit 保留的 `toggleSidebar:`（恒置灰的根因）；注册窗口菜单（`MainMenu.swift:24`）；
  省略号统一 `…`；撤销/重做回「编辑」菜单并补校验；批量重命名入口禁用时写明阈值。`FFMenuContractTests` 17 条。
- **第 4 批 R4-04/05/13–18**：主题卡与设置侧栏选中态、未实现协议置灰 + tooltip、文件管理分区名/病句/伪设置行、
  网络存储页容器与空态统一、快捷键页、关于页文案、全局搜索筛选与复选框外观、⇧⌘N 新建文件夹进入内联重命名并选中新项。
  `FFSettingsPolishTests` 15 条、`FFNewFolderRenameTests` 2 条。
- **第 5 批 R4-21…R4-31 + R4-12/19/32**：详情栏位置 tooltip / 说明占位 / 目录大小异步汇总、任务面板条纹与按钮可用性、
  「定位」按钮、侧栏「位置」去重、主题卡铺满、小字对比度 **2.26→5.89**、⌘⇧.、详情栏显隐归位「显示」菜单、
  查重窗口只读路径框与最小尺寸 **600×400→720×480**、标签选择弹窗可点色点。
- **R4-32 是修 R4-12 时新抓到的独立缺陷类**（见 §7.2），影响面不止批量重命名。

**本轮三个必须带走的教训：**

1. **新测试文件没注册 pbxproj 会变成假绿**：症状是 `Executed 0 tests … ** TEST SUCCEEDED **`。
   `FFMenuContractTests` 首跑即中招（见 §7.1）。任何新测试类跑完必须确认 `Executed N tests` 不是 0。
2. **`cacheDisplay(in:to:)` 不合成容器 `layer.backgroundColor`**：用它验背景色必得假绿，
   但它适合验「子视图有没有画出来」——`FFBatchRenameTests.testBottomBarControlsArePainted` 就是这么用的
   （整条按钮栏纯色即失败），绕开了窗口遮挡。
3. **动态色在构建期解析一次 = 钉死**（R4-32），已提为 `FFDynamicBackgroundView`，见 §7.2。

**本轮取证限制（下一个接手的人必须知道）**：本机被用户自有窗口完全遮挡，
`NSRunningApplication.activate` + AXRaise 也无法把隔离副本置顶，所以**整屏目视截图与坐标点击不可用**；
可靠手段只有 `screencapture -x -o -l<windowID>`（窗口自身 surface）、AX frame（`/tmp/ffgeom.swift`）
和进程内位图。任何「看不见」的结论先怀疑遮挡，再怀疑布局。

**基线（2026-10-23 收口后以最终源码复跑实测）**：XCTest **17 批 516 条净 0 失败**（BATCH1 一条废纸篓类异步等待超时属环境抖动，单独复跑 16.8s 通过）、
应用内自检 **153 通过 + 20 轮布局压力 0 失败**、Rust core **200 通过 0 失败**。
**桌面副本（2026-10-23 用户授权后）**：`make build` 出 **0.8.0-26102301**（R4 全量），
走 `flowfinder-desktop-copy-deploy` 门禁（新鲜度 + `codesign --verify --deep` 通过）备份旧包到
`/tmp/ff-desktop-backup/FlowFinder-26102235.app` 后覆盖；实机取证 **PID 16478、窗口 260,30 1400×900、
侧栏版本标签实测 `0.8.0-26102301 Beta`**。未重跑 `make demo`（避免多递增一次构建号）。

**本轮遗留观察（未修，已定性）**：

1. `FF_SELFTEST=1` 的 20 轮布局压力下，某栏目录加载会超过 10s 守卫并弹出「目录响应超时（磁盘或网络无响应），可重试」
   （日志 `/tmp/ff-debug.log`：9:51:25.713 `mode=loading` → 9:51:35.657 `mode=error`，前置 `[CACHE-DIAG] listDirectory … cacheResult=-4`）。
   同一副本**去掉自检、正常启动复跑：0 次超时**，两栏均到 `mode=content`；且直接执行二进制启动时系统报
   `sandbox_extension_issue_file_to_process failed … (Operation not permitted)`，说明受保护目录的枚举在压力轮次里被拖住。
   判定：**自检压力路径 + 非 LaunchServices 启动的环境产物，不是常规使用缺陷**。
2. 但暴露一个真实的诊断文案问题：10s 守卫无论根因是磁盘、网络、权限还是主线程排队，一律写「磁盘或网络无响应」，
   会把用户往错方向引；同毫秒内 `[STATE-OVERLAY]` 被重复写 6–8 次，说明错误态在每轮布局里都被重设。
   两条都归下一轮（提示分级 + overlay 幂等），本轮未改。
3. **R4-08 只修了一半**：注册窗口菜单后窗口清单已恢复（副本实测「窗口」菜单末尾出现 `FlowFinder` 条目），
   但「进入全屏幕」实测仍不存在（只有系统注入的「填充 / 居中 / 全屏幕平铺」），且全库没有任何
   `collectionBehavior` / `toggleFullScreen` 声明——要支持全屏得先确认自绘顶栏与 `titlebarAppearsTransparent`
   在全屏下的行为，属独立改动，归下一轮。

**2026-10-23 接手复核修正（不改写上方当轮记录，以本节实测为准）**

| 上方原文 | 复核结论（2026-10-23 接手轮实测） |
|---|---|
| 遗留观察 1「正常启动 0 次超时…不是常规使用缺陷」 | **定性不成立**。全新身份副本首启两栏同时「目录响应超时（磁盘或网络无响应）」，重试后仍超时；`sample` 显示工作线程 100% 停在 `open()`（`bulk_read.rs:114`），主线程空闲。见 §1.28 C1 |
| 遗留观察 2「10s 守卫文案一刀切」 | 可达性已证实（首启即触发），归 §1.28 C1 一并修 |
| 第 4 批 R4-18「进入内联重命名并选中新项」 | **半条不成立**：只选中新项，不进入行内编辑（两次新建、截图与 AX 均无编辑框）。见 §1.28 C3 |
| 遗留观察 3「『进入全屏幕』实测仍不存在」 | **记录不准确**：26102301 的「显示」菜单里有「进入全屏幕」（全库仍无 `toggleFullScreen`/`collectionBehavior`，即系统注入项）。应表述为「系统注入项存在、工程未声明全屏支持、行为未测」。见 §1.28 C2 |
| 第 4 批 R4-05「置灰并在 tooltip 写明尚未实现」 | **机制写错**：实测与代码都是**内联提示标签**（「FTP 暂未支持，目前只能连接 SMB 共享。」）+ 禁用「连接」按钮，`ConnectServerDialog.swift` 全文无 `toolTip`。见 §1.28 C16 |
| P3 R4-27「小字对比度 2.26→5.89」 | **待复算**：深色下实测侧栏分组标题 1.88、详情栏「46 项」1.84（同法对照选中项 9.30）。口径不同（1x 截图、取最暗/最亮 4% 均值），但明显低于 5.89，需按原口径复测后定性。见 §1.28 C14 |

---

### 1.28 2026-10-23 接手复跑 + 四轮真机实测（接手实测轮，接手必读）

**范围**：基线全量复跑 + 五份独立 Bundle ID 副本、四轮真机实测，逐条核对 R4 审计与台账声称。
本轮**未改产品代码、未 commit、未覆盖桌面副本**。证据：`docs/images/audit-2026-10-23-takeover/`（26 个文件）。

**基线复跑（当次实测）**：Rust **200 通过 / 0 失败**（3.49s）；Swift XCTest **17 批 516 条 / 失败测试 0 / 失败断言 0 / 挂起 0 / 构建失败 0 / COVERAGE complete**（BATCH1 本轮一次通过，未复现上轮的废纸篓类超时）；
应用内自检 **7 类 153 + 落点 ①–⑩ 全 PASS + 20 轮布局压力 0 失败**。
**153 与 163 的口径差已解释**：`[SELFTEST] ①…⑩` 是独立打印的 PASS 行，不在 7 类汇总里，**163 = 153 + 10**（本轮日志 `FAIL` 计数 0）。

**取证环境**：macOS 27.2；Qoder 窗口常年压在副本之上，`front-assert` 持续 `OWNERSHIP=MISMATCH`、**坐标点击全程不可用**；
可用手段仍只有 PID-exact AX（`ax-window.swift` / 自定义 AX 工具）、`screencapture -l<windowID>`、进程内 `cacheDisplay`、`sample`。

**本轮必须带走的四条教训**

1. **AX 设置选中行会崩溃（P1）**：任何 AX 客户端（含 VoiceOver）对文件列表 `setAccessibilitySelectedRows` 触发
   `EXC_BREAKPOINT/SIGTRAP` —— `FFQuickLookTableView.setAccessibilitySelectedRows(_:)` 的 `$0.accessibilityIndex()`
   （`FileListView.swift:153`），2/2 独立副本复现、偏移一致。根因方向：`accessibilityRows()/accessibilitySelectedRows()`
   用 `unsafeBitCast` 把 `FFAXRowElement` 伪装成 `NSAccessibilityRow`（`:134-149`），回写时收到的对象未必是自家元素。
   这条同时**阻塞了 R4-21/31 等需要「先选中一行」的验收**。
2. **首启受保护目录卡在 `open(2)`（C1）**：`sample` 显示 `com.flowfinder.dirlist` 线程 1648/1648 采样停在 `open()` →
   `bulk_read::list_dir_bulk_native`（`bulk_read.rs:114`）；主线程空闲、应用不卡死，但 10s 守卫先弹「磁盘或网络无响应」，
   重试会再排一个同样会卡死的请求。预置 `/tmp` 路径的同一副本首帧即出内容 → 与受保护目录（TCC/iCloud）强相关。
3. **共享偏好会被副本改写**：副本与桌面共享 `~/Library/Preferences/com.flowfinder.native.json`（Rust 侧固定文件名）。
   本轮一次误点把 `appearance.theme` 改成 `2`，收尾已 diff 并还原到原始 md5。**今后每轮收尾必须 diff + 还原该文件**。
4. **「工具窗口为键窗口 → 菜单/快捷键全废」本轮又绊了 3 次**（设置 ⌘,、工具 › 重复文件扫描…、⌘T）：
   驱动前**先关掉所有工具窗口**并确认为主窗口为键窗口，再读菜单。

**与台账冲突（C 清单，修复队列见台账 §3「2026-10-23 接手实测」行）**

- 产品：C1 首启 `open()` 卡死 + 文案误导 · C3 ⇧⌘N 不进内联重命名 · C4 外部终端变更不刷新（应用内操作会刷新）·
  C7 查重组名仍 hash · C8 可释放量单位丢失/不一致 · C9 确认删除常亮且 0 选择点击无反馈 ·
  C10 查重列头字面「按钮」· C11 6 个标签即裁切无溢出 · C13 文件夹大小不递归汇总（4 KB vs 实际 1.3 MB）·
  C14 深色小字对比度待复算 · **C15 AX 选中必崩**。
- 文档口径：C2 全屏项存在 · C6 分批验证 Skill 的镜像**假隔离**（`Resources/Info.plist` 硬编码 bundle id，改 pbxproj 改不动产物身份）·
  C16 R4-05 是内联标签不是 tooltip · C18 `REQUIREMENTS.md:84` J4-08 标 ✅ 与 R-26「部分完成」冲突（已降级为 🔧）。
- 待定：C17 R4-31 色点 `AXPress` 返回不支持，需一次真实鼠标点击定性。

**复核通过（本轮实测成立）**：R4-01 本地化 · R4-02 任务终态（已完成 · 100%）· R4-04/R4-26 外观页选中态与铺满 ·
R4-05 FTP 内联提示 + 端口联动 · R4-06 命名统一 · R4-07 侧栏开关（菜单与 ⌥⌘S 均生效）· R4-08 窗口清单 ·
R4-09 省略号 · R4-10 撤销归位 · R4-11 阈值禁用 · R4-12 批量重命名窗口五项 · R4-13/14/15/16 设置四页 ·
R4-19 单面板无死标签 · R4-21 ①②（位置完整路径 help、说明「双击添加说明」占位）· R4-22/23/24 任务中心 ·
R4-28 ⌘⇧. · R4-29 详情栏显隐 · R4-30 只读路径 + 720×480 · R4-32 深色窗口背景（批量重命名与查重窗口）·
**J1-07 记住上次目录 · J2-03 跨栏拖拽（同盘移动、两栏即时刷新）· J4-06 QuickLook 空格/方向键/Esc · L-02 红绿灯关窗 ·
R-08 卡片留白只调宽（受控：位置与尺寸不变，仅左栏 457→446）· R-30 每组默认保留 + 独立确认弹窗（固定「无法撤销」、无「不再询问」）·
R-01/R-14 拖标签出窗成新窗（单栏、路径正确、源折单栏）· 主题重启持久化 · 空态文案**。

**C15 已于同日修复（TDD + 真机复验）**：setter 改为 `selectedRows as NSArray` → 只接受本表 `FFAXRowElement`；根因是 getter 侧 `unsafeBitCast` 造出的非法协议存在数组被 AppKit 回填。新增 2 条回归（外来行不改选中 / 本表行生效），全量 **17 批 518 条净失败 0**（唯一失败项单跑通过，判 ENV/ORDER-DEPENDENT），真机连续 3 次 AX 写选中不再崩溃。详见台账 §3。

**C1 部分修复（同轮）**：只修了「误导文案 + 授权误报」两条（超时文案列出权限/iCloud/网络三种原因；权限门超时显示「待确认」而非「已授权」），**Rust 侧 `open(2)` 阻塞本身未动**——阻塞 syscall 不可中断，可中断化需换非阻塞枚举或进程隔离，属独立改动；卡死时阻塞线程仍会泄漏。真机本轮未能复现卡死（新身份首启两栏直接载入 13/12 项），新文案的现场显示未取得真机证据。全量 17 批 **519 条 0 失败**。

**查重窗口簇 C7–C10 已修（同轮）**：组名去 hash、字节单位统一（`FFByteText`）、确认删除补 tooltip、组头补无障碍标签；`FFDuplicateLayoutTests` 5/5，全量 521 条（唯一失败项是详情栏布局 flaky，今日 2 败 2 过）。真机因查重窗口驱动不出（菜单/⌘D 无响应）未复核。

**修复队列现状（截至 2026-10-23 本会话结束）**

| 项 | 状态 | 证据/下一步 |
|---|---|---|
| C15 AX 选中必崩 | **已修** | 台账 §3；`FFAXVirtualizationTests` 6 条；真机 3/3 |
| C1 首启目录卡死 | **部分修**（文案 + 权限门状态机） | Rust `open(2)` 阻塞未动；真机卡死未复现 |
| C7–C10 查重簇 | **已修**（C9 降级为视觉问题） | `FFDuplicateLayoutTests` 5/5；真机未复核（窗口驱动不出） |
| C3 ⇧⌘N 不进内联重命名 | **已修** | 根因：`.ffTagCacheWarmed` 通知在重命名开始后 33-43ms 触发 `reloadData()` 销毁 textField。修复：`tagCacheWarmed`/`listColumnsDidChange`/Combine sink 三处加 `guard !isRenaming`；`isRenaming` 改 internal。`FFNewFolderRenameTests` 3/3；真机 0.8.0-26102305 ⇧⌘N 后输入「C3-fix-test」+ Return 成功重命名 |
| C13 文件夹大小不汇总 | **已修**（R4-21 已实现异步递归汇总） | 真机验证：`calculateFolderSizeAsync` 正确递归汇总——"照片 2026" 算出 32 KB（2 文件 31875 字节，`du -sh` 36K）；"子目录"（含嵌套子目录）算出 307 KB（2 文件 307200 字节，`du -sh` 300K）。`[DETAILS-DIAG]` 日志确认异步块被调用、守卫通过、sizeField 被回填 |
| C4 外部变更不刷新 | 待修 | 需在真实目录（非 /tmp）复测 FSEvents 是否启动 |
| C5 任务中心双空态 | **已修** | `TaskPanelWindowController.swift:211` 空态时 `statusLabel.stringValue = ""`（中央 `emptyLabel` 已传达空态） |
| C11 多标签溢出 | 待修 | 属布局取舍，动手前需先出 HTML 对比稿 |
| C14 深色小字对比度 | 待定 | 需按台账原口径复算 |
| C6 Skill 假隔离 | 待修 | 镜像内还需改 `Resources/Info.plist` 的 `CFBundleIdentifier` |
| flaky：详情栏行数 | 新增技术债 | `FFDetailsBarTypeRowsFlowTests.testRowsStayAttachedWhenBarShrinks` 今日 2 败 2 过，疑测试间状态污染 |

**本轮未验（原因明确，不冒充通过）**：VoiceOver 全走查（用户不测）· 高对比度（需改系统设置）· 60fps 手感采样（需 Instruments）·
SMB 真实连接（无服务器凭据）· 查重「实际执行删除 / 失败 sheet」· R4-31 色点可点性 · 长路径中段截断场景 · 拖拽手感评价（几何已过）。

### 1.29 2026-10-23 缺陷修复 + macOS 26 液态玻璃适配 + 真机 Bug 修复（第五轮审计后续）

**C5 修复**：任务中心空态时 `statusLabel`（右上角工具栏区）与 `emptyLabel`（中央覆盖层）同时显示「暂无任务」。修复：`TaskPanelWindowController.swift:211` 空态时 `statusLabel.stringValue = ""`，仅保留中央 `emptyLabel` 传达空态。

**右键菜单补全**：
- 「批量重命名…」缺失——`FFPaneMenuBuilder.buildMenu`（`FFCommon.swift`）在「重命名」后新增菜单项，`FFPaneActionsController.batchRenameSelected` 转发至 `MainWindowController.menuBatchRename`，`updateMainMenu` 按所选文件数（排除目录）控制可见/禁用 + tooltip。
- 「用所选项目新建文件夹」阈值从 `>= 2` 改为 `>= 1`（选中 1 个文件也可新建文件夹）。

**macOS 26 液态玻璃适配**：
- `MainWindowController.setupUI`（原 lines 873-885）窗口级背景改为 `#available(macOS 26.0, *)` 条件分支：macOS 26+ 用 `NSGlassEffectView(.regular, cornerRadius: 0)`，旧版保留 `NSVisualEffectView(.underWindowBackground)`。
- `FFGlassView` 已有完整液态玻璃封装（`.window`/`.panel`/`.component` 三级），panel/component 级早已使用 `NSGlassEffectView`。本次补全的是主窗口背景这一最后一个直接使用 `NSVisualEffectView` 的位置。
- `ThemeManager.findMainContainer()` 已支持 NSGlassEffectView 作为 contentView（lines 191-193），无需改动。
- 其他窗口（DuplicateScan/Settings/ModalSheet/TagRemovalSheet）已迁移至 `FFSolidSurfaceView`/`FFOpaqueContainerView`/`FFDynamicBackgroundView`，不涉及液态玻璃。

**按钮液态玻璃适配**：
- `FFPillButton`（发现功能药丸）：macOS 26+ 用 `NSGlassEffectView(.clear)` 胶囊背景替代自绘 `labelColor` 半透明底色；选中态叠 accent tint `CALayer`；焦点环保留。
- `FFHoverIconButton`（侧栏图标按钮）：macOS 26+ 用圆形 `NSGlassEffectView(.clear)` 作为 hover 背景，仅 hover/press 时显示。
- `FFSidebarRevealHost.button`（显示侧栏按钮）：macOS 26+ 用 28pt 圆形 `NSGlassEffectView(.clear)` 作为玻璃底座。
- 标准 `.rounded`/`.accessoryBarAction` 按钮由系统自动处理液态玻璃，无需改动。
- 面包屑/标签栏按钮在实体工具栏上（`FFDesign.operationAreaElevated`），不改。

**编译状态**：Swift 零错误。链接失败仅因 Rust FFI 库未针对当前架构编译（环境问题，非代码问题）。

**Bug 修复（真机测试反馈）**：
- **Bug 1（列表/网格单击变选择）**：`NSGlassEffectView` 直接作为 `window.contentView` 在 macOS 26 上拦截鼠标事件。修复：改用普通 `NSView` 容器作为 contentView，玻璃视图与 mainContainer 并列（玻璃底层、内容上层）。
- **Bug 2（网格文件夹图标尺寸异常）**：`itemSize` 高度初始 `+12` vs 缩放 `+20` 不一致（统一为 `+20`）；图标源 48pt 被拉伸到 88pt 显示（改为按 `thumbnailMaxEdge` 生成）。
- **Bug 3（列表选中框之间无间隙）**：根因是 `selectionHighlightStyle = .regular` 让系统先画满宽无间隙高亮，覆盖自定义 `drawSelection(in:)` 的 inset 间隙。修复：`selectionHighlightStyle` 改为 `.none`，`draw(_:)` 在 `super.draw` 之前手动调用 `drawSelection(in:)` 绘制 `insetBy(dx: 4, dy: 1)` + 5pt 圆角高亮，相邻选中行之间留出 2pt 间隙。

**改动文件**：`TaskPanelWindowController.swift`（1 行）、`FFCommon.swift`（新增菜单项 + FFHoverIconButton 玻璃适配）、`FFPaneActionsController.swift`（新增 action + 阈值修复）、`MainWindowController.swift`（液态玻璃分支 + FFSidebarRevealHost 玻璃底座 + Bug 1 视图层级重构）、`SidebarView.swift`（注释更新）、`FFPillButton.swift`（玻璃胶囊背景）、`FileGridView.swift`（Bug 2 itemSize 高度统一 + 图标源尺寸按 thumbnailMaxEdge 生成）、`FileListView.swift`（Bug 3 `selectionHighlightStyle` 改 `.none` + `draw(_:)` 手动调用 `drawSelection(in:)` + `dy: 0` → `dy: 1`）。

---

## 1.30 2026-10-24 详情栏重做（液态玻璃 + 三档小白条 + 完整内容）

规格与决策台账：`docs/SPEC-2026-10-23-DETAILSBAR.md`（10 项决策全部锁定）。最终 Debug **0.8.0-26102403**（真机证据采集于 26102402）；隔离副本 `com.flowfinder.native.detailsbarverify` 实机取证；**桌面副本已于 2026-10-24 用户授权覆盖为 26102403**（旧包备份 `/tmp/ff-desktop-backup/FlowFinder-26102308.app`，`codesign --verify --deep --strict` 通过）；**未提交、未推送**。

**用户决策**
- 空间关系 **C**：保持浮层；列表/网格 `contentInsets.bottom` + **`scrollerInsets.bottom`** 都 = 栏高 + 8，滚动条止于栏顶。
- 高度 **三档 54 / 132 / 240pt**，中点吸附 **93 / 186**；大档再受面板高 45% 约束。
- 小白条：白色胶囊 38×4pt、命中 120×16；**移除箭头按钮**；点击 = 折叠 ↔ 上次展开档；拖动 = 1:1 跟手、松手吸附；⌘I 与点击一致。
- 内容溢出：**栏内滚动**（`hasVerticalScroller = true`），全部行保留，不再隐藏末行。
- 图标：**A+B+C** 三入口（右下角手柄拖动 / 右键预设 64·48·96·200 / 触控板捏合）；上限 **200pt**；图标区宽 = max(132, 图标+32)，上限 **232pt**，信息区可退化为单列；设置页滑杆同步 48–200。
- 名称/路径：**不限行完整换行**；移除固定 `preferredMaxLayoutWidth=320`，按实际列宽回填。
- 玻璃：macOS 26 `NSGlassEffectView(.regular)`（旧系统 `NSVisualEffectView`）；玻璃作为底层兄弟视图，内容置上，避免再次拦截鼠标。
- 动画：0.28s `cubic-bezier(.32,.72,.28,1)`；拖动不插值；「减弱动态效果」降级。

**实现落点**
- `FFDetailsLayout.swift`：`FFDetailsTier` / `FFDetailsBarTierState` / 三档与吸附 / 图标边长三角夹紧 / 图标区宽 / 滚动列数 / 上次展开档持久化。
- `FFCommon.swift`：`FFDetailsFlowLayout.scrollLayout`（全部行分配、不截断）。
- `ExpandableDetailsBar.swift`：`FFDetailsGripHandle`（点击/拖动 4pt 分界 + AX Increment/Decrement）、`FFIconResizeHandle`、右键预设菜单、`magnify`、玻璃背景、滚动信息区、不限行换行、三档状态机。
- `FileListView.swift` / `FileGridView.swift`：`contentInsets` + `scrollerInsets` 同步。
- `SettingsWindowController.swift`：详情预览滑杆 48–200。

**验证**
- 新增 `FFDetailsBarV2Tests` **14 条**；详情三组 **33 条 0 失败**（2026-10-24 08:19）；Rust **200 通过 / 0 失败**。
- 全量 Swift **472 条：470 通过 / 2 条环境失败**（2026-10-24 实测）：`testHardcodedTokenBudget` 读取 `UI/` 目录 POSIX EINTR（shell 读同一目录正常）；`testDeleteIsNonBlocking` 删除通知 15s 超时（既有 flaky，未改 PaneState/TaskService）。代码相关失败 0。
- 真机：窗口 25115 @ (260,30) 1400×900；截图 `docs/images/audit-2026-10-24-detailsbar/`：
  - `01-collapsed-54.png` / `02-standard-132-image.png` / `03-large-240-icon200.png`。
- AX 拉手 `调整详情栏高度` pos (715,782) size 120×16，Value **54 → 132 → 240 → 132**（Increment/Decrement 各 `err=0`）。
- 点击拉手展开（54→132）与收起（按大档→54）各一次；右键图标菜单四项齐全，选「大」后标准档夹紧、大档 200。
- 大档下列表滚到底：最后一行完整在栏上方，列表滚动条止于栏顶。
- **桌面副本同步**：2026-10-24 用户授权覆盖为 26102403；启动 PID 49203、窗口 25479 @ (260,30) 1400×900，侧栏版本标签实测 `0.8.0-26102403 Beta`；重签名后 macOS TCC 权限被重置，Desktop/Documents 读取超时，需用户在系统设置重新授权（本轮未代点）。

**未验证/人工**
- 连续拖动 1:1 手感（合成拖拽事件未稳定送达）；触控板捏合真机手势；深色玻璃截图；信息区溢出后的实际滚动截图；设置页滑杆 48–200 真机拖动。

**踩坑**
- 新测试文件必须补 pbxproj 4 处条目（本轮首次用了与 `zh-Hans.lproj` 冲突的 FFFB ID，导致资源路径指向测试目录、构建报 `Tests/FlowFinderTests/zh-Hans.lproj` 不存在；改用 FFFC 后恢复）。
- 测试调用 `applyPreviewIconSize` 默认会写共享 `details_preview_size`，污染同进程后续测试与桌面 App；测试改为 `persist: false`，并已把被写成 120 的共享键恢复为默认。
- 全量串跑偶发 0% CPU 挂起（既有环境问题）；本轮改用 `-test-timeouts-enabled YES -maximum-test-execution-time-allowance 90` 重跑。

---

## 1.31 2026-10-24 工具模块合并到底栏

规格：`docs/SPEC-2026-10-24-TOOLSBAR.md`。最终 Debug **0.8.0-26102405**；**桌面副本已自动更新为 26102405**（2026-10-24 起每次构建自动覆盖）；隔离副本 `com.flowfinder.native.toolsverify` 真机取证；**未提交、未推送**。

**构建与桌面副本（2026-10-24 起强制）**
- `make build` 结束后自动执行 `scripts/deploy-desktop-copy.sh`：签名门禁 → 备份旧版到 `/tmp/ff-desktop-backup/FlowFinder-<旧版本>.app` → 覆盖 `~/Desktop/FlowFinder.app` → 校验签名/版本 → 重启桌面副本。
- 只覆盖不构建：`make desktop-copy`；只覆盖不重启：`FF_DESKTOP_RELAUNCH=0 make desktop-copy`。
- ad-hoc 重签每次都会改变代码签名，macOS TCC 可能重置文件访问权限；启动后若出现「需要文件访问权限」需用户在系统设置重新授权（未代点）。

**用户决策（7 项）**
- 详情栏右侧**外侧** 36pt 圆形扳手按钮；点击向左长成工具栏，详情栏缩成 **54pt 圆，只显示文件图标**（无文字、不可点）。
- 几何 **A**：详情圆 left 8，工具栏 left 70 → 右缘（右侧留 52pt 给圆钮），双列工具。
- 高度 **B**：工具栏继承详情栏当前档位（54/132/240），无拉手；54 档列表滚动。
- 返回 **自动**：执行任一工具后立即回详情（工具窗口/Sheet 继续）；切换选中文件、目录或活动面板也回详情；无手动返回。
- 工具栏**不自动缩回圆钮**；右端圆钮保留为蓝色高亮状态指示，**不可点**。
- 侧栏品牌旁工具胶囊与侧栏工具页入口退役。

**实现落点**
- 新增 `FFToolsBar.swift`：`FFRoundToolButton`（AXPress、整圆热区）、`FFDetailsCircleView`、`FFToolsBarRow`（整行热区、AXPress、可用性提示）、`FFToolsBarView`（玻璃、双列滚动）、`FFToolsModuleCoordinator`（open/close/自动回详情/高度常量同步）。
- `MainWindowController`：详情栏 trailing 改 -52；每面板安装协调器；`toolContext(for:)` 按面板取上下文；`updatePaneUI` 调 `contextDidChange`；`activatePane` 切换活动面板关闭所有工具；⌘I 先关工具再展开详情。
- `SidebarView`：胶囊不再加入视图层级（对象保留仅供旧测试直接调用）。
- 测试：新增 `FFToolsBarV2Tests` 7 条；删除侧栏工具页/胶囊的 12 条旧测试，`FFBatch4Tests`/`FFBatch2IntegrationTests` 去掉胶囊/Tab 环断言；全量 467 条（472 − 12 + 7）。

**验证**
- `FFToolsBarV2Tests` **7/7**；`FFToolPageCatalogTests` 3/3；全量 **467 条断言 0 失败**；Rust 200/0。
- 全量套件被判失败仅 2 条既有环境 flaky：`DuplicateScanBrowseRegressionTests.testBrowseSheetReappearsAfterDeleteAndRescan` 串跑 30s 谓词超时、**单独复跑 16.8s 通过**；`FFBatch2IntegrationTests.testHardcodedTokenBudget` 外部卷 POSIX EINTR（shell 读同目录正常）。
- 真机隔离副本（窗口 25587 @ 260,30 1400×900）：
  - `docs/images/audit-2026-10-24-toolsbar/01-tools-open-132.png`：详情先展开 132 → 工具栏 132、双列 6 工具、详情圆、右圆钮蓝色；
  - `02-tools-open-54.png`：详情收起 54 → 工具栏 54，列表滚动；
  - 点「任务中心」「设置」→ 对应窗口打开且底栏立即回详情；切换选中文件 → 底栏自动回详情并显示新文件摘要；
  - 可用性提示正常（批量重命名「至少需要 2 个文件」）；右端圆钮工具态为状态指示。
- 全量日志：`docs/images/audit-2026-10-24-toolsbar/full-suite-26102405.log`。

**未验证/人工**
- 活动面板切换的物理点击自动回详情（代码已接 `activatePane`，本轮用选中变化路径验证）。
- 54 档工具栏只有约 1 行可见，需滚动（用户选择 B 的直接结果）。
- 深色玻璃、减弱动态 morph、全部 6 个工具真实执行（本轮验证任务中心与设置）。
- 桌面副本已于 2026-10-24 自动更新为 26102405（`make desktop-copy` 首次执行，备份 26102404）；桌面 App 启动后因重签触发权限门，需用户重新授权。

**踩坑**
- 工具栏高度最初用 `heightAnchor == detailsBar.heightAnchor`，在无窗口测试容器里被内容固有高度把详情栏一起撑到 180；改为打开时同步常量（`toolsBarHeightConstraint.constant = detailsBar.currentHeight`）。
- 共享 `FFDetailsBarLastExpandedTier` 被真机操作写成 240，污染新测试（详情栏在 400 高容器扩到 180）；测试 setUp/tearDown 隔离并清理共享键。
- 自定义行的图标/文字子视图会截获点击；`FFRoundToolButton`/`FFToolsBarRow` 覆写 `hitTest` 让整圆/整行成为热区，并补 `accessibilityPerformPress`。

---

## 1.32 2026-10-24 药丸详情栏 + 独立圆形工具簇（推翻并取代 §1.31）

规格：`docs/SPEC-2026-10-24-TOOLSBAR.md`（第二轮）、`docs/SPEC-2026-10-23-DETAILSBAR.md`（本轮修订）。最终 Debug **0.8.0-26102408**（26102407 工具清单调整后重建）；`make build` 已自动备份 26102407 并覆盖/重启桌面副本；**未提交、未推送**。

**为什么推翻 §1.31**
用户判定第一版「36pt 圆钮 + 双列文字工具栏」理解错误：要的是「54pt 药丸详情 + 54pt 圆形工具」，展开隐藏工具按钮，工具态详情缩成 54 圆、工具变成 N 个**独立 54pt 圆**紧贴 54pt ×，而不是药丸容器/文字列表/状态指示圆钮。

**锁定模型（本轮）**
- 默认：54pt 药丸（半径 27）+ 54pt 圆形扳手，同高同心；栏 trailing −70。
- 展开：132/240 **卡片**（12pt 圆角，内边距 30/52；不再沿用高度/2 的药丸半径）；工具按钮自动隐藏，卡片铺到 trailing −8。
- 点击白色拉手或药丸/展开卡片空白区域都切换折叠展开。
- 工具态：仅折叠时可开；详情缩成 left 8 的 54pt 图标圆；原按钮变 54pt ×；N 个独立 54pt 玻璃圆右对齐紧贴 ×（默认间隙 8）。
- 仅列**当前可用的文件工具**：文件夹无选中 3、选中 ≥2 个 4、空路径 1；**设置/关于是应用命令，不进入工具簇**；执行后自动回默认；选中/目录/活动面板变化只刷新，不关闭；关闭只认 ×。
- 窄面板：间隙 8 → 2 → 横向滚动（内容右对齐）。

**实现落点**
- `ExpandableDetailsBar`：`updatePillShape()` 在布局/档位变化时把栏体、玻璃、描边圆角同步为**折叠 27 / 展开 12**；`compactView` 改为 `FFPillPassThroughView`（整块穿透命中），空白点击由 `FFMouseInterceptorView.onClick` → `handleGripClick()`；新增 `onExpansionChanged`；收起态隐藏状态栏；compact 填满 54 并垂直居中，左右 20；展开内边距按档位 30/52。
- `FFToolsBar.swift` 重写：`FFGlassCircleButton`（54pt 玻璃基类、hover、整圆热区、AXPress、隐藏/淡出时 hitTest 返回 nil、`acceptsFirstMouse`）、`FFRoundToolButton`、`FFCloseToolButton`、`FFToolCircleButton`、`FFDetailsCircleView`、`FFToolsClusterView`（滚动 + 8→2 压缩 + 右对齐）、`FFToolsModuleCoordinator`（打开/关闭/自动回默认/上下文刷新/展开隐藏按钮/trailing −70↔−8）。
- `MainWindowController`：详情栏 trailing 交由协调器管理；每面板一个协调器。
- `FFMiniThumbnailStackView.swift`：`FFMouseInterceptorView` 增加单击回调；新增 `FFPillPassThroughView`。

**测试**
- 先红后绿：`FFDetailsPillTests` 4 条（半径 27/12/12、内边距 30/52、内容居中、状态栏隐藏、空白点击）；`FFToolsBarV2Tests` 12 条（默认同高同心、展开隐藏并铺满、展开不可开、详情缩圆 + ×、3/4/1 刷新不关闭、独立 54 圆紧贴 ×、8→2→滚动、执行回默认、× 关闭、活动面板保持、AX、真实窗口 mouseDown）。
- 定向回归 **48 条 0 失败**（详情三组 26 + 工具 12 + catalog 3 + FFBatch4 7）。
- Rust `cargo test` **200 passed / 0 failed**。
- 全量 Swift **538 条 0 失败**（29.060s；`-skip-testing` 排除 2 条既有环境测试）。`DuplicateScanBrowseRegressionTests.testBrowseSheetReappearsAfterDeleteAndRescan` 单独复跑 **16.656s 通过**；`FFBatch2IntegrationTests.testHardcodedTokenBudget` 在 `timeout 150` 内 **Executed 0 tests**（测试宿主/外部卷阻塞；shell 直接读取同目录 87 个 UI 文件 0.04s，文件本身正常）。
- 应用内自检 `FF_SKIP_PERMISSION_GATE=1 FF_SELFTEST=1`：策略 71 + 区域 7 + 行为 4 + 焊接 35 + 避让 5 + 宽度 9 + 外壳 22 = **153 通过 / 0 失败**，独立落点 ①–⑩ 全 PASS，布局压力 **20 轮 0 失败**（26102406 日志 `/tmp/ff-debug.log`；进程检查完成后未自行退出，90s 超时终止，属既有行为；26102407/26102408 未重跑）。

**真机（桌面副本 `0.8.0-26102408`，窗口 26221 @ 260,30 1400×900）**
- 证据目录 `docs/images/audit-2026-10-24-pilltools/`：
  - `01-default-pill.png`：默认 54 药丸 + 54 圆扳手；
  - `02-tools-5.png`：历史（26102406）无选中 5 个工具圆 + ×；
  - `03-tools-6.png`：历史（26102406）选中 2 项 6 个工具圆（批量重命名出现）；
  - `04-expanded-132.png`：首版 132 胶囊（历史，暴露内容被半圆端裁切）；
  - `05-run-settings-returned.png`：执行「设置」后自动回默认，设置窗口独立；
  - `06-default-pill-26102407.png` / `07-expanded-card-26102407.png`：修复后默认药丸与 132 卡片（12pt 圆角、内容完整）；
  - `08-tools-3-26102408.png` / `09-tools-4-26102408.png`：26102408 无选中 3 个文件工具、选中 2 项 4 个（均无设置/关于）。
- AX：滑块「调整详情栏高度」Value 54 ↔ 132；工具态按钮依次为重复扫描/批量重命名/批量整理/任务中心/设置/关于 + 关闭工具；选中变化后批量重命名实时消失且工具不关闭。
- **物理点击（非 AXPress）26102408**：点工具钮 → 3 个工具圆；选中 2 项 → 4 个；点 × → 回默认。26102407 曾验证点设置圆打开设置并回默认，26102408 起设置/关于不在圆钮中。
- 点击药丸空白（窗口坐标约 500,741）实测 54 → 132。

**26102406 真机回归缺陷与根因（26102407 已修）**
- **工具钮物理点击无效**：工具钮与关闭钮共用同一 frame，关闭钮初始 `isHidden=true` 但 `FFGlassCircleButton.hitTest` 未判断 `isHidden`，仍返回自身；关闭钮后添加、层级更高，吞掉了工具钮的全部鼠标点击（AXPress 不经过 hitTest，所以此前误判为通过）。修复：隐藏或 `alphaValue ≤ 0.01` 时 hitTest 返回 nil；补 `acceptsFirstMouse`。新增 `testToolButtonReceivesPhysicalMouseDownInWindow`：先红在 `hitTest` 返回 `FFCloseToolButton`，修复后绿。
- **展开态被药丸圆角裁切**：`updatePillShape()` 一律使用 `bounds.height/2`（132→66），展开卡片内容被半圆端裁掉。修复：折叠 27、展开 12；单测由“半径 66/120”改为“12”。

**未验证/人工**
- 240 大档真机截图（单测覆盖半径 12/内边距 52）。
- 深色玻璃、减弱动态动效、捏合手势、窄面板横向滚动与全部 6 个工具的真实执行。
- 拖动拉手连续手感与背景点击收起（单测覆盖，真机以拉手收起）。
- 工具圆钮的 Tab 环未接（鼠标与 AXPress 可用）。
- 桌面副本启动即弹出「需要文件访问权限」应用内门；已点「稍后」继续验证，未代点任何 TCC 系统授权。


## 1.33 2026-10-24 任务按钮注水 + 弹性开合动画（26102409）

规格：`docs/SPEC-2026-10-24-TOOLSBAR.md` T-11…T-13。最终 Debug **0.8.0-26102409**；`make build` 已自动备份 26102408 并覆盖/重启桌面副本；**未提交、未推送**。

**任务按钮**
- 有新任务记录（App 任务 ∪ Rust 系统任务，含已完成/失败，直到清除）时，右侧 54pt 工具钮换成 `.listChecks` 任务图标；点击仍打开工具簇，不直接开任务中心。
- 图标注水：已完成进度从图标底部上升，100% 注满；默认任务钮与簇内任务中心圆共用同一百分比。
- 进度聚合：有活动任务 = 活动任务平均；无活动但有记录 = 100%；无记录 = 0。已完成历史不会拉高新任务进度。
- 任务中心圆只在有任务记录时出现；清除记录后消失。无任务计数 2/3/0，有任务 3/4/1（无选中/选中≥2/空路径）。

**弹性动画**
- 圆钮按下 0.94（0.08s），松开弹簧回 1.0（0.22s）；动作改在 mouseUp 触发，AXPress 不变。
- 详情栏缩成按钮：宽度约束从整栏 0.34s 弹性收缩到 54×54，圆角 27 自然成圆；内容淡出、左侧图标圆淡入；完成后隐藏详情栏。
- 工具圆从 × 一侧向左 `CASpringAnimation` 滑入（damping 14 / stiffness 190 / stagger 0.025s），关闭反向滑回。
- 详情栏 54↔132/240 高度 0.36s、`(0.22, 1.18, 0.36, 1.0)` 轻微过冲；关闭 0.26s；内容 0.12s 淡入。
- 减弱动态效果全部跳变；工具簇内容刷新不重播入场。

**实现落点**
- `TaskService.swift`：`FFTaskSummary` + `FFTaskPresence.summary`（合并两个任务源、活动平均、无活动=1）。
- `FFToolProtocol`：`FFToolContext.hasTasks`；`TaskCenterTool` 无任务返回 `.disabled("暂无任务")`。
- `FFToolsBar.swift`：`FFWaterFillIconView`（mask 水位，0.3s 注水）、`FFGlassCircleButton.showTaskProgress`（0.2s 图标交叉淡化、AX 值）、按下/松开弹簧、工具簇 stagger 入场/反向退出、协调器订阅两个 `@Published` 任务源并维护宽度/内容形变。
- `ExpandableDetailsBar`：`prepareForMorphOut/In`、`animateMorphContentIn`、高度弹性曲线。
- `MainWindowController`：`toolContext(for:)` 注入 `hasTasks`。

**验证**
- `FFTaskButtonTests` 3/3：进度聚合、任务中心条件显隐/注水、任务钮切换/恢复且仍能开工具簇。
- `FFToolsBarV2Tests` 13/13（新增真实窗口形变收敛测试）；`FFDetailsPillTests` 4/4；catalog 3/3；定向 23/0。
- 全量 Swift **542 条 0 失败**（29.243s；跳过 2 条既有环境测试）；Rust 200/0（未改 Rust）。
- 真机 26102409：AX 确认物理点击后工具簇打开且无任务时只有重复扫描/批量整理两个圆；详情栏在打开过程中保持可见，完成后隐藏。
- **真机动画录屏/TCC 阻塞**：取证时系统弹出「FlowFinder 想访问文稿文件夹」，按纪律未代点；录屏未捕捉到点击后的中间帧，弹性手感与任务注水尚未真机确认，需用户处理 TCC 后用真实任务复验。

**未验证/人工**
- 弹簧手感（按下、收缩、滑出、展开过冲）需真机目视/录屏确认。
- 有真实任务时的注水图标与进度推进；减弱动态效果；240 大档弹性。
- 260+ 条历史项不受影响；`FFTaskSummary` 只读快照，不改变任务执行逻辑。

## 1.34 2026-10-25 侧栏与搜索真机审计 + 两个导航缺陷修复（26102501）

最终 Debug **0.8.0-26102501**；`make build` 已自动备份 26102409 并覆盖/重启桌面副本；**已推送 `origin/feat/v0.9-overhaul`（功能提交 `1ccba73`，2026-10-25）**。

**审计结论**
- 侧栏实际只有 **个人收藏 / 位置 / 标签** 三段；早期截图里的「工作区 / 最近任务 / 站点 / 自动化 / 扩展 / 更多 / waltxx」是后面 Qoder 窗口透过液态玻璃的**透字**，把 FlowFinder 移到壁纸区后全部消失（`/tmp/ff-resume-261024/moved-right.png`）。后续审计不要再把这些当成缺失项。
- 已验：收藏单击导航（下载 / AI 生图）、位置行（Iris-Data / Parallels Desktop / Macintosh HD）、设备悬停信息（名称 / 文件系统 / 容量 / 可用 / 使用率）、标签筛选与再点恢复、收藏右键 6 项、搜索范围菜单、`含子目录` 真实递归（临时目录当前层 1 条 / 深层追加 1 条）、搜索清空后列表恢复。

**缺陷 1：收藏复点无效（已修）**
- 现象：当前目录在收藏的子目录内时，该收藏行保持选中；单击它一次不导航（需先点另一个收藏）。
- 根因：导航只挂在 `outlineViewSelectionDidChange`，选中行不变时没有事件。
- 修复：`SidebarView.swift` 的 `FFFNoDisclosureOutlineView` 增加 `onReselectRow`——`mouseDown` 记录点击行是否为“按下前已选中”，`super.mouseDown` 返回后若仍是单击、且鼠标位移 ≤3pt（排除拖动收藏重排），调用 `navigateToSelectedFavorite()`。接线在 `favoritesOutlineView` 初始化处，与 Enter 激活复用同一导航入口。

**缺陷 2：清空搜索后 Return 误入首项（已修）**
- 现象：搜索 → ⌘A/Delete 清空 → Return，列表恢复全量，同时同一个 Return 打开自动选中的首项，直接进入第一个文件夹（未命名文件夹 / sub 两次复现）。
- 根因：搜索框 Enter 固定走 `paneToolbarDidRequestOpenResult`；该方法在无选中时先落首项再 `menuOpen`，没有判断搜索词是否为空。
- 修复：`MainWindowController.paneToolbarDidRequestOpenResult` 在激活面板后先判 `searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`，空/纯空白直接 return；非空仍保留“无选中落首项再打开”的原设计。

**验证**
- 新增 `FFBatch2IntegrationTests.testSearchEnterWithEmptyQueryDoesNotOpenFirstItem`：先搜 alpha 再清空，调用 Enter 打开入口，断言路径不变且 `selectedFiles` 为空。`xcodebuild build-for-testing` 通过；单测 **passed (0.914s)**；全套未重跑（最近全量 542 条 0 失败，2026-10-24）。
- 真机桌面副本 26102501：子目录内单击 AI 生图收藏一次即回 AI 生图根（`fix1-inside.png` → `fix1-after-reselect.png`）；搜索 Gemini → 清空 → Return 后仍在 AI 生图，未进入 `未命名文件夹`（`fix2-search.png` → `fix2-after-empty-return.png`）。临时目录与测试数据已清理，AI 生图 57 项完整、废纸篓为空。
- 重启后桌面副本弹出自身「需要文件访问权限」门与系统「FlowFinder 想访问『桌面』」TCC；按纪律未点允许，需用户选择“稍后/不允许/允许”后继续使用。

**后续补验（同版本 26102501）**
- 六个收藏逐个单击均跳转正确（桌面 / 文档 / 下载 / 应用程序 / AI 生图 / Cline）。
- 侧栏拖宽：从边缘条起拖可调宽，从列表内容区起拖无效；恢复后 outline 186 / 滚动区 208，跨重启持久化未验。
- 标签：新建（AX「创建」）、改色、删除均生效；无重命名菜单项。
- 收藏右键 6 项在临时收藏 `~/Downloads/ff-fav-test` 上逐项执行：显示简介（独立窗口，位置 `/Users/waltxao/Downloads`、0 字节 1 项）、新标签页、新窗口（面包屑与 `probe.txt` 行正确）、上移/下移（AX 顺序往返复原）、从边栏移除（余 6 项；`SidebarFavorites` 解码为 桌面/文档/下载/应用程序/AI 生图/Cline）。临时目录已删，Downloads 刷新后不再出现。
- 双栏搜索：首次进入右栏 Desktop 报「目录读取超时」，重试即载入；再次进入 3s 内正常（偶发，与 C1 同型，未取样）。范围「双栏」时两侧输入框同步，输入 `2026` 后左 9 行 / 右 6 行各自过滤；切「本栏」后解耦（左清空恢复 12 行、右保留 `2026`）；切回单栏 804×900，保留当前活动栏的标签。证据为本地 `docs/images/audit-2026-10-25-sidebar-search/`（含个人文件名，未随公开仓库上传）。

**补验发现（未修）**
- 末项「下移」菜单项仍为 ON，点击 no-op；首项「上移」边界未验。
- 外部删除已选目录并刷新后，详情栏仍残留 `ff-fav-test -- · 文件夹`；清空 `AXSelectedRows` 也不消失。与早前「误入后详情栏残留 sub」同型，已第二次复现——建议单独立项查详情栏/选中项同步。

**仍未验**
- 侧栏宽度跨重启；动画手感/减弱动态/240 弹性（仍是 26102409 的未验项）。

## 1.35 2026-10-26 v0.8.0-b2 发布（26102601）

- **发布**：GitHub prerelease [`v0.8.0-b2`](https://github.com/waltxao/FlowFinder/releases/tag/v0.8.0-b2)，构建 `0.8.0-26102601`；产物 `FlowFinder-0.8.0-b2.dmg` / `.zip` / `.sha256`。
- **内容**：R-25…R-39 + 2026-10-25 侧栏/搜索修复与补验；已知问题（末项「下移」未置灰、外部删除后详情栏残留已删项）未修，随版说明。
- **打包**：`BETA_LABEL=b2 make beta`；产物在 `build-beta/`；打包改写的 `.a/.dylib` 已按路径还原，只提交版本号与文档。
- **验证**：CFBundleShortVersionString `0.8.0` / CFBundleVersion `26102601`；`codesign --verify --deep --strict` 通过；DMG/ZIP `shasum -a 256 -c` OK；XCTest 542（2026-10-24，全套未重跑）/ 自检 153 + 20 轮 / Rust 200。
- **分支**：发布提交推送到 `feat/v0.9-overhaul`，并快进 `main`；tag 用 `--target <40位SHA>` 固定到发布提交，发布后回读校验。
- **桌面副本**：`make beta` 不部署桌面副本，当前桌面副本仍为 26102501；需要更新时单独执行 `make build` 或 `make desktop-copy`。

## 2. 产品定位

| 项 | 结论 |
|---|---|
| 是什么 | macOS 原生双面板文件管理器（Swift/AppKit UI + Rust core，FFI C ABI） |
| 平台 | **仅 macOS 桌面**，不做移动端、不做 Intel 通用包（当前 arm64-only） |
| 不做什么 | 不做网盘、不做同步、不做插件系统、不做多标签页之外的窗口管理 |
| 目标用户 | 需要双栏对照搬运文件的本地重度用户 |
| 当前状态 | 0.8.0 Beta（0.8.0-26102601，Release v0.8.0-b2），预发布；正式版（1.0）未排期 |

---

## 3. 代码地图

### 3.1 顶层结构

```
flowfinder-native/
├── FlowFinder/                 # Xcode 工程
│   ├── FlowFinder/             # 应用源码（84 文件 / 39,759 行）
│   │   ├── App/                      # 入口、AppDelegate（2 文件）
│   │   ├── Bridge/                   # Swift↔Rust 桥接（11 文件，CoreBridge 为主）
│   │   ├── Model/                    # FileEntry / PaneState 等（6 文件）
│   │   ├── UI/                       # 全部界面（59 文件 / 32,705 行）
│   │   ├── Libraries/                # build-rust.sh 产物（.a/.dylib，不入库）
│   │   └── Resources/                # Info.plist、图标
│   ├── Tests/FlowFinderTests/  # XCTest（9 文件 / 2,804 行）
│   └── FlowFinder.xcodeproj
├── rust-core/                        # Rust core（24 文件 / 13,529 行）
│   ├── src/ffi/mod.rs                # FFI 入口（3,124 行）
│   ├── src/ffi/tests.rs              # FFI 集成测试（1,768 行）
│   ├── src/core/                     # 18 个功能模块
│   ├── include/ff_ffi.h              # C ABI 头文件
│   └── target/                       # cargo 缓存（1.4G，不入库）
├── docs/                             # 五件套 + 官网（index.html/images）
├── scripts/                          # build-rust.sh / package-beta.sh / 集成测试
├── build/Products/                   # 旧产物目录（已迁到内置卷缓存，见 §6.2）
└── Makefile
```

### 3.2 需要重点认识的巨型文件

| 文件 | 行数 | 实际职责（远超文件名） |
|---|---|---|
| `UI/FileListView.swift` | 2,450 | 列表 + 列头 + 分组 + 行视图 + 缩略图 + 键盘 + 拖拽 + 右键 |
| `UI/MainWindowController.swift` | 2,342 | 窗口骨架 + 双面板装配 + 设备浮层 + 进度栏 + 通知 + 焦点 |
| `UI/SidebarView.swift` | 2,321 | 收藏 outline + 标签 + 设备 + 工具面板 + 右键菜单 |
| `UI/ExpandableDetailsBar.swift` | 2,243 | 详情栏全部形态（收起/展开/多选/空态/标签药丸） |
| `UI/FileGridView.swift` | 1,798 | 网格 + 分组 + 选中 + 拖拽 |
| `UI/SettingsWindowController.swift` | 1,415 | 设置全部页 |
| `rust-core/src/ffi/mod.rs` | 3,124 | 全量 C ABI（函数多而薄，但单文件过大） |

---

## 4. 架构与数据流

```
AppDelegate → MainWindowController
                ├─ SidebarView（收藏/标签/设备）
                ├─ PaneContainer ×2
                │    ├─ PaneToolbar（导航 + 面包屑 + 搜索/排序/分组/视图）
                │    ├─ FileListView / FileGridView
                │    └─ ExpandableDetailsBar（浮层覆盖）
                └─ TaskProgressBar
                        │
                 PaneViewModel（每面板一个，Combine $state）
                        │
                   CoreBridge（Swift）
                        │  C ABI
                 rust-core::ffi/mod.rs
                        │
     bulk_read / fsevents / sqlite_cache / content_index(FTS5) / tags / …
```

关键事实：

- **状态单一来源是 `PaneState`**（`PaneViewModel.$state` 驱动 UI）。但「活动面板」
  另有 `activePane` + 第一响应者两个真值源，历史上多次出现菜单操作打到另一面板的 bug。
- **目录列举**走独立并发队列 + 10s 超时；共享队列曾被慢目录（iCloud）阻塞成死锁。
- **文件变更**走真实 FSEventStream + 300ms 去抖，300ms 后通知刷新。
- **选中态颜色**三处统一读 `FFAccent`（默认 `#0a84ff`，设置可改），失焦统一
  `unemphasizedSelectedContentBackgroundColor`。
- **设置**存 UserDefaults（Rust 侧 `~/Library/Preferences/com.flowfinder.native.json`，
  Swift 侧 `.plist`），两边都有，改动时注意双写。
- **封面式设计令牌**只有 `FFDesign.Text`（9 档字号）与少量背景/圆角常量；
  字号仍有 126 处硬编码（见 §8）。

---

## 5. 设计基线（大改也不能丢的东西）

`DESIGN-SPEC.md` §1 把视觉分成两类，**这是终止「像不像访达」扯皮的根本规则**：

| 类别 | 范围 | 要求 |
|---|---|---|
| 对标访达 | 材质、选中态、字号、行高、侧栏结构、列头、分组、面包屑、详情栏内容项 | 必须一致，可测量 |
| 产品自主 | 双行工具栏 72pt、双操作区、详情栏浮层高度、设备浮层、标签行式 | 按规格执行，**不得以「不像访达」为由返工** |

其他硬约束：

- 侧栏宽度默认 220（可拖 180–280，记忆）；窗口最小 1060×700（侧栏 180 + 两区各 400 + 留白/分隔线）。
- 操作区超椭圆圆角 16pt；详情栏玻璃浮层；设备浮层是唯一实体卡片。
- 活动面板 = 整块 1.5pt 强调色内描边（W-08），点击面板任一控件即切换。
- 列表选中框左右内缩 4pt + 5pt 圆角（C-04）。

---

## 6. 构建 / 测试 / 发布

### 6.1 环境

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
# 当前机器：macOS 27.2 beta (26B5112a) + Xcode-beta + Homebrew Rust
```

### 6.2 常用命令

| 命令 | 作用 |
|---|---|
| `make build` | Rust core + Debug app（产物 `~/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app`） |
| `make demo` | build 后复制到 `~/Desktop/FlowFinder.app`（**用户实测必做**） |
| `make rust-test` | cargo test（200 项） |
| `make swift-test` | xcodebuild test（190 个用例，2026-10-20 实测全绿） |
| `make beta` | `scripts/package-beta.sh` 出 DMG/ZIP 到 `build-beta/` |
| `make version` | 打印版本（真源：Xcode 工程） |

### 6.3 六个必须知道的环境事实

1. **工程没有 `FlowFinder` 共享 scheme**，只有 `FlowFinderTests`。
   Debug 构建走 `-target`（不支持 `-derivedDataPath`，用 `SYMROOT`/`OBJROOT` 绝对路径）。
2. **跑 Swift 测试前先 `pkill -f "MacOS/FlowFinder"`**。单实例策略会让测试宿主秒退，
   表现为 `test runner hung before establishing connection` 假故障。
3. **测试宿主连不上已恢复**（2026-10-20 实测）：2026-10-18 曾 100% 报
   `test runner hung before establishing connection`，定位为开发模式被重置
   （`DevToolsSecurity` 当时 disabled，现为 enabled）。`make swift-test` 现已跑通
   190 条；若复现，先查 `DevToolsSecurity -status` 与 `xcode-select -p`，再 clean 重试。
   **双保险验证**：`FF_SKIP_PERMISSION_GATE=1 FF_SELFTEST=1` 直接跑可执行文件，
   启动时穷举 135 项断言（拖拽 10 步 / 决策表 71 / 区域 7 / 行为 4 / 焊接 21 / 外壳 22）；
   配合 `~/Desktop/FlowFinder.app` 实测（`make demo`）。
4. **外置卷会让 xcodebuild 挂死**（2026-10-20 实测）：仓库位于 `/Volumes/...` 时，
   llbuild 的 BuildEngine 卡在 `condition_variable` 永不返回——现象是
   `Building Swift (Debug)...` 后数分钟无输出、无 `swift-frontend` 进程。
   同一仓库换到内置卷立即正常。Makefile 已把产物目录默认放到
   `~/Library/Caches/FlowFinderBuild`；需要改回项目内用
   `make DERIVED=$(pwd)/build build`（已知会触发挂死）。
5. **合成鼠标事件三重干扰**（2026-10-20 实测）：本机 CGEvent 的 y 是**屏幕顶部**
   原点（与 CGWindowList 差一整屏）；TCC 授权弹窗吃点击（换签名后要重新点）；
   桌面常被 Finder/WorkBuddy 窗口遮挡。物理交互验证只能人工做。
6. **测试宿主的侧栏图标会卡布局**（2026-10-20 实测）：scheme 已设
   `CFFIXED_USER_HOME=/tmp/flowfinder-test-home` 与 `FF_SKIP_SIDEBAR_ICONS=1`。
   否则自定义收藏指向慢卷/网络路径时，`NSWorkspace.icon(forFile:)` 在主线程
   `getattrlist` 上阻塞，单个控制器初始化可达 26 秒，表现为 XCTest 整体挂住。

### 6.4 版本号与发布

- 版本唯一真源：`project.pbxproj` 的 `MARKETING_VERSION`（当前 0.7.9）与
  `CURRENT_PROJECT_VERSION`（7901）。发版时四处同步：pbxproj、`rust-core/Cargo.toml`、
  `README.md` 徽标、`CHANGELOG.md`。
- 发布用 `make beta` → `gh release create vX.Y.Z ...`（当前走预发布）。
- **Release 通道在本机不可用**：Homebrew rustc 1.96.1 + macOS 27 生成 mis-aligned
  LINKEDIT dylib，`dlopen` 拒绝；测试版打包走 `package-beta.sh`（Debug 构建 + ad-hoc 签名）。
  `lto = "thin"` 可用，fat LTO 必炸。
- 产物 ad-hoc 签名，首次打开需右键 → 打开；Developer ID 公证未接（缺凭据 Secrets）。
- **官网下载直链写死了 tag**（`docs/index.html`），下次发版必须同步改，否则按钮指向旧包。

---

## 7. 工程约定与平台坑（都是踩过的）

### 7.1 Xcode / 工程

- 新增 Swift 文件必须在 `project.pbxproj` **注册四处**（PBXBuildFile / PBXFileReference /
  Group children / Sources phase），否则静默不参与编译。**注册前先 grep 候选 ID**——
  复用已占用 ID 会让 Xcode 解析到旧 fileRef，新文件静默丢失（表现为「cannot find X in scope」）。
  测试文件漏注册更阴：不报错，直接 `Executed 0 tests … ** TEST SUCCEEDED **` 假绿（2026-10-23 R4 实测）。
- 勿对 `project.pbxproj` 执行 `git checkout`，正确改法是编辑而不是回滚。
- 委托创建的 `NSTableRowView` 其 `selectionHighlightStyle` 默认 `.none`；此时
  NSTableView 用系统强调色自绘，行视图的 `drawSelection` 覆写不会生效。要自绘必须显式设 `.regular`。

### 7.2 AppKit 布局

- 瞬态可变约束（列宽、定高）一律 `defaultHigh`，`required` 会瞬态无解、刷冲突日志。
- 隐藏视图的约束**仍参与求解**；动态行列表用清空/重建，不要靠 `isHidden`。
- `FFModalSheet` 两个坑：关闭必须走 `parent.endSheet`（`close()` 会毒化后续
  `NSOpenPanel` sheet）；高度测量要两段式（先撑到已知尺寸再量 `fittingSize`）。
- **动态语义色不能构建期解析成 CGColor 快照**（2026-10-23 R4-32）：`NSColor.windowBackgroundColor.cgColor`
  在没有 drawing-appearance 上下文时解析出 **Aqua 值**（实测无上下文 255,255,255，darkAqua 才是 30,30,30），
  而 `layer.backgroundColor` 只接受快照，构建时写一次就把背景钉死在旧外观上，主题切换后不跟随。
  唯一正确写法是 `FFDynamicBackgroundView`（`FFModalSheet.swift`）：`wantsUpdateLayer` +
  `effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = … }` +
  `viewDidChangeEffectiveAppearance() { needsDisplay = true }`。仍有残留旧写法：`FileInfoWindowController.swift:507` 的标签 pill（每次刷新重建）。
- **`cacheDisplay(in:to:)` / `bitmapImageRepForCachingDisplay` 不合成容器 `layer.backgroundColor`**：
  它只画子视图绘制，所以用它验背景色必然假绿；但正适合验「子视图到底画没画出来」
  （`FFBatchRenameTests.testBottomBarControlsArePainted`：按钮栏矩形内颜色种类 ≤3 即判没画）。

**2026-10-20 交互大改新增的坑（全部实测踩过，详见台账与日志）：**

- `NSView.mouseDownCanMoveWindow` 默认对**不透明视图返回 true**（`isOpaque` 默认 true）——
  堆栈视图/卡片全是窗口拖动区；别改 `isOpaque`（有主题重绘副作用），要覆写本属性。
- 窗口顶部 28pt 是**系统标题栏拖动区**，先于内容视图吃 mouseDown →
  `window.isMovable = false` + 窗口级 local monitor 在分发前接管。
- **press 类手势绝不能消费 mouseDown**：吞掉后拖出窗口外松手 mouseUp 回不来，
  系统认为鼠标还按着 → 整个 OS 的点击都失灵。
- `NSSplitView` 是**翻转坐标系**（isFlipped = true）：split 内做 Y 判定
  （如标题带排除）必须按 isFlipped 分支，顶部是 y 0..36 而非「高度−36」。
- 增删 `NSTableColumn` 后**必须 `reloadData()`**（否则「列头在、行全空」）；
  表格 0 行时不能走增量 `insertRows`，要加 `!displayRows.isEmpty` 守卫。
- 算列宽要扣 `intercellSpacing`（默认 3pt/列），否则最后一列被裁。
- `CAShapeLayer` 遮罩挂窗口 contentView 会**整窗不渲染**（套容器也一样）→
  窗口圆角用 `layer.cornerRadius` + `cornerCurve = .continuous`。
- 跨视图拖拽别用 `NSDraggingSession`（要求拖拽源就是收到 mouseDown 的视图；
  标题栏带内的 down 根本到不了视图）——用窗口级 monitor 自管。
- 标签重排判定横跨 **screen / window / strip / stack 四套坐标**：命中要把
  window 点转 strip 点，指示线要把 stack 点转 strip 点；混用不会报错，只会
  「重排恒失效」或「指示线飘到别处」（第六轮修过一次）。
- `FFRegionAware` 翻译区域时，`NSControl` / 点击手势只在 `.window` / `.title` 内
  短路（返回 nil，交给控件）；**不要对所有区域短路**——`.panel` / `.tab` 必须保留，
  否则拖标签到文件列表上会找不到落点。
- 新 Swift 文件注册 pbxproj 用独立 ID 段：`FFC2000`/`FFC3000`/`FFC4000`/`FFC5000` 已占用。

### 7.3 Rust / FFI

- `build-rust.sh` 的重链接必须带 `-framework CoreServices`，否则 FSEventStream 符号未定义、
  静默回退到直接拷贝 dylib。
- 目录列举、FSEvents 必须各自独立队列/线程，QoS 用 USER_INITIATED，避免主线程优先级反转。
- FFI 结构体布局有断言测试，改字段顺序会直接编译失败——这是有意的。

### 7.4 其他

- 错误文案一律经 `FFErrorText.humanize` 转中文 + 给下一步；errno 必须精确解析，
  不能用 `contains`（`os error 28` 含子串 `os error 2`）。
- 侧栏通知必须带窗口身份守卫（`isOwnSidebarNotification`），多窗口下否则会误杀/误触。
- 调试日志用 `NSLog`（`print` 在 stdout 重定向时全缓冲）。
- 编译缓存会重放陈旧诊断与旧测试数，采信前先 clean 强制重编译。
- **菜单取证必须在应用激活后读**：`NSMenuItem.enabled` 由 `validateMenuItem` 在菜单打开时决定，
  应用未激活时逐条读**全部返回 false**（2026-10-23 曾据此误判「设置…」被禁用）。
  先 `NSRunningApplication.activate` 再读；条目存在性同理，且要区分「系统注入项」与「工程自建项」，
  别把「没读到」写成「误判」。
- **窗口完全被遮挡时的取证**：`screencapture -x -o -l<windowID>` 拿窗口自身 surface（不受遮挡影响）、
  AX frame、进程内 `cacheDisplay` 位图三者可用；整屏截图与坐标点击不可用（会打到遮挡窗口）。

---

## 8. 已知债务（大改清单的输入）

| 类型 | 项 | 位置 / 说明 |
|---|---|---|
| 结构 | **五个巨型文件** | 见 §3.2；列表 2450 行、主窗口 2342、侧栏 2321、详情栏 2243、网格 1798 |
| 结构 | Controller 同时管布局/数据/通知/焦点 | `MainWindowController` 有 100+ 方法，改动牵一发动全身 |
| 一致性 | 126 处硬编码字号未令牌化 | `FFDesign.Text` 之外散落全文；批量替换会动行高，须单独一轮 |
| 正确性 | 「活动面板」双真值源 | `activePane` + firstResponder，已有多次分派错误历史 |
| 功能 | P-05 卷操作无 UI | `ff_volume_*` 零调用（推出/挂载/健康状态） |
| 功能 | P-08 AI 整理卡未接线 | 设计稿有，UI 是禁用占位 |
| 功能 | X-05 标签缺重命名 | 新建/改色已有 |
| 功能 | X-08 连接服务器两个无效控件 | 记住密码 / 自动连接 |
| 测试 | ~~Swift 测试宿主连不上~~ **已恢复** | 2026-10-20 实测 190 条全绿；根因是开发模式被重置（`DevToolsSecurity`），复现时先查该开关 |
| 测试 | 逻辑单测覆盖集中在少数纯函数 | `FFBreadcrumbSegments` / `FFStartupPath` / `FFErrorText` / `SidebarFavoritesStore` + 本轮 `FFTabReorder` / `PaneTabsStore` / `FFInteractionPolicy` / `FFAreaResolver` 是正例，可作模板 |
| 交互 | **面板切换「真位移」未做** | 用户已裁定放弃 NSSplitView 自管两块面板 frame（拖边调宽与宽度记忆连带重写）；现实现为窗口宽度插值 + opacity 关键帧，面板本体无位移 |
| 交互 | **跨窗口拖拽手感待人工复验** | 模型/代码/断言齐（台账 R-01），物理拖拽受合成事件三重干扰未端到端验证；桌面副本上的控件点击同样待人工过一遍 |
| 交互 | **第七轮拖拽手感/60fps 待复验** | 纯 resolver 190/0、自检 135/0；合成事件无法可靠驱动真实拖拽。人工验收：单栏右半拆双栏、目标单栏保留标签、无效落点回原位、活动标签完整胶囊、连续拖 3 秒 p95 <16.7ms。`FF_NATIVE_WINDOW_DRAG=0` 可回退窗口拖动 |
| 性能 | 侧栏收藏图标同步查 LaunchServices | 自定义收藏指向慢卷/网络路径时，`NSWorkspace.icon(forFile:)` 在主线程 `getattrlist` 阻塞；XCTest 曾因此每个控制器卡 26s。测试 scheme 已用 `FF_SKIP_SIDEBAR_ICONS=1` 规避，应用内仍同步 | 后续把非标准图标改后台加载 + 占位 |
| 构建 | Rust dylib 重链接产物不可用 | `build-rust.sh` 的 ld 重链接会让 FFI 调用在应用内超时；已默认关闭（`FF_RELINK=1` 才启用），直接用 cargo 产物 |
| 发布 | 公证未接、Release 工具链坏 | 只能出 ad-hoc 预发布包 |
| 发布 | 官网下载直链写死 tag | 每次发版手改 `docs/index.html` |
| 验收 | J3 全键盘旅程未验收 | ⌘F → 输入 → ↑↓ → Enter 全链路 |

---

## 9. 大改建议（按投入产出排序）

1. ~~**先恢复测试通道**~~ **已完成（2026-10-20）**：根因是开发模式被重置，
   `DevToolsSecurity` 启用后 `make swift-test` 190 条全绿；`FF_SELFTEST` 135 项
   作为应用内双保险。以后测试宿主再挂，先查该开关与 `xcode-select -p`。
2. **面板切换「真位移」**（用户已裁定）：放弃 NSSplitView 自管两块面板 frame，
   拖边调宽与宽度记忆连带重写——单独一轮做，勿与其它改动混合。
3. **抽纯函数补测试**。已有多个先例；大改前把 `PaneState` 的排序/分组/过滤、
   路径拼接、标签排序等逻辑从 View 里剥出来，先写测试再动 UI。
4. **拆巨型文件**。建议顺序：`MainWindowController`（拆成 Window/PaneAssembly/
   DevicePanel/ProgressBar 四个 extension 文件）→ `FileListView`（列表数据源/行视图/
   键盘拖拽三块）→ `SidebarView` → `ExpandableDetailsBar`。每次只拆一个文件、
   拆完立刻 `make demo` 人工过一遍三条主旅程。
5. **收敛真值源**。把 `activePane` 与 firstResponder 合并成单一「焦点面板」概念，
   菜单/键盘/描边都从它派生。
6. **字号令牌收尾**（126 处）。这一项会动行高与视觉，必须单独一轮、逐屏截图比对。
7. 最后再动 `ffi/mod.rs`（3124 行）——它薄而多，拆分收益低于风险。

大改的验收口径建议直接沿用 `docs/ACCEPTANCE.md` 的三条旅程 + J3 键盘旅程，
不要新造一套。

---

## 10. 本次整理记录（2026-10-18）

### 10.1 删除（101 个已跟踪文件 + 约 530MB 未跟踪产物）

| 类别 | 内容 | 理由 |
|---|---|---|
| 历史规划稿 | `.omo/`（46）、`docs/superpowers/`（43） | v0.7.4/各轮重设计的 agent 产物，已被五件套取代 |
| 迁移文档 | `MIGRATION_LOG.md`、`MIGRATION_PLAN.md` | Tauri→原生迁移已完结 |
| 旧说明 | `VERIFICATION.md`、`DEVELOPMENT.md`、`SUBPROJECT_TEMPLATE.md` | 与 README、本文件重复 |
| 旧发版说明 | `docs/release-notes/`（5 份 0.6.x） | CHANGELOG + GitHub Releases 已覆盖 |
| 旧设计史 | `修改历史-2026-08-30-原生体验重设计.md` | 已被 DESIGN-SPEC 变更记录取代 |
| 调试/备份 | `docs/ff-debug-20260806.log`、`REQUIREMENTS.md.bak_20261017` | 垃圾与备份 |
| 误入库二进制 | `rust-core/libflowfinder_core_relinked.dylib`（2.9M） | 7/29 构建产物，全仓零引用 |
| 构建缓存 | `FlowFinder/.build/`（124M）、`build/Intermediates`（249M）、`build-beta/DerivedData`（142M）、`build-beta/*.dmg/.zip`（7.2M） | 可再生；发布包已在 GitHub Release |
| 其他 | `.superpowers/`（3.2M）、5 个 `.DS_Store`、`CONTINUE_DEV_PROMPT.md` | agent 工作目录与垃圾 |

仓库体积 2.3G → 1.8G（剩余主要是 `rust-core/target` 1.4G，刻意保留以省重编时间）。

### 10.2 保留

五件套 + 本文件、`docs/index.html` + `docs/images/`（官网）、`build/Products`（桌面副本来源）、
`rust-core/target`、`Libraries/`（当前构建产物）、`.trae`/`.vscode`（工具配置）。

### 10.3 找回方式

被删的历史文档都在 Git 历史里，例如：

```bash
git log --oneline -- docs/MIGRATION_LOG.md        # 找删除前的提交
git show <commit>:docs/MIGRATION_LOG.md > /tmp/x.md
```

`.gitignore` 已补：`.omo/`、`rust-core/*relinked*.dylib`、`docs/*.log`。

---

## 11. 接手清单

```
1. 读本文件 → PRODUCT.md → DESIGN-SPEC.md §1（两类基准）→ ACCEPTANCE.md 三条旅程
   → **REQUIREMENTS-LEDGER.md（R-01..R-14 交互台账）→ SPEC-2026-10-20.md（§1.1–§1.14）
   → SPEC-2026-10-20-DRAG-REDO.md（第七轮拖拽重做）**
2. 验证构建：export DEVELOPER_DIR=... && make build && make demo
3. 验证 Rust：make rust-test（应 200 passed）
4. 验证 Swift：**不要**跑 `make swift-test`——它开头是 `pkill -f "MacOS/FlowFinder"`，会连用户桌面上
   正在跑的实例一起杀掉（用户明令禁止）。改用隔离镜像 + 分批：`rsync` 源码到 `/tmp` 镜像并改独立
   Bundle ID，再按测试类分批 `xcodebuild test … -only-testing:FlowFinderTests/<类>`，
   每类核对 `Executed N tests` 不为 0（见 §7.1 假绿）。总数以本文件顶部「验证基线」为准
   （2026-10-23 为 17 批 516 条 0 失败）。
   若报 test runner hung，先查 `DevToolsSecurity -status`，见 §6.3
5. 跑一遍主旅程：双栏导航 / 跨栏复制 / 标签筛选 / 搜索 / Quick Look
   **+ 2026-10-20 新增交互旅程**：拖标签出窗成新窗 → 拖回操作区变双栏 /
   卡片留白调宽（窗口不动）/ 隐藏侧栏看标签避让 / 列头右键开关列
   **+ 第七轮拖拽验收**：单栏拖右半（左面板保留其余标签）/ 目标单栏拆双栏 /
   侧栏上松手回原位（不新建窗）/ 活动标签浮层是完整胶囊 / 连续拖 3 秒看是否跟手
6. 大改前先做 §9 第 3 条：抽纯函数 + 补测试，再动结构
7. 任何 UI 改动先用 make demo 出包，让用户在桌面副本上实测
8. 改完立即更新 `REQUIREMENTS-LEDGER.md` + 本文件（§1.x / 版本 / 验证基线 / 未验项）+ `CHANGELOG.md`「未发版」段；版本变更同步 SPEC/PLAN
9. 发版时四处同步版本号，并改官网下载直链
10. 有疑问一次只问一个问题
```

---

**交接完成。** 当前代码可构建、可运行、可出包；XCTest **430 条（分批 428 通过 + 2 条既有环境测试）**、应用内自检 **163 项**
与布局压力 **20 轮**全绿（2026-10-22 实测）。0.8.0 Beta 顶栏与交互修复见 §1.9；后续 UI 重做 v2
设计与 Phase 0–7 状态见 §1.10；第二轮整改见 §1.11；批次 1 设置接线见 §1.12；批次 2 功能回归测试见 §1.13；AX 行虚拟化见 §1.18；文件说明迁移见 §1.19；搜索范围见 §1.20。当前第一优先补的洞仍是 R-20 的真机走查（工具页 Tab 人工走查、红绿灯物理点击）、VoiceOver 人工走查与测试宿主环境两条阻塞。
结构债务仍集中在 MainWindowController 的布局/拖拽/标签装配，大改请继续按 coordinator 接缝搬迁。
