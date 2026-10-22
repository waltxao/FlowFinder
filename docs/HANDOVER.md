# FlowFinder 交接文档（大改前基线）

> **整理日期：** 2026-10-18（基线）· **2026-10-20 增补**（交互大改五轮，见 §1.5）· **2026-10-21 增补**（0.8.0 Beta 顶栏修复，见 §1.9）· **2026-10-22 增补**（第二轮整改，见 §1.11）
> **当前版本：** **0.8.0-26102209 Beta**（版本规则 `A.B.C-yymmddxx`，见 §1.11 D-09；桌面副本已覆盖 26102209）；**当前分支：`feat/v0.9-overhaul`（分支名沿用；产品版本按用户裁定为 0.8.0）**
> **最新 Release：** https://github.com/waltxao/FlowFinder/releases/tag/v0.8.0-b1（0.8.0 Beta · 构建 0.8.0-26102209）
> **本地路径：** `/Volumes/Iris-Data/文件管理系统/flowfinder-native`
> **代码规模：** Swift 113 文件 / 约 44,084 行（2026-10-22 实测）；Rust 24 文件 / 13,529 行
> **验证基线：** Rust 200 项全绿；**Swift XCTest 389 条 0 失败**（`xcodebuild test -scheme FlowFinderTests`，2026-10-22 实测，DerivedData 在 `/tmp/flowfinder-xctest-derived`）；**应用内自检 `FF_SELFTEST=1` 163 项 0 失败 + 布局压力 20 轮 0 失败**（日志 `/tmp/ff-debug.log`）

本文档是大改前的**唯一交接入口**。产品定义看 `PRODUCT.md`，视觉看 `DESIGN-SPEC.md`，
验收看 `ACCEPTANCE.md`，功能清单看 `REQUIREMENTS.md`。

> **同步纪律（2026-10-21 起，强制）：** 每次代码 / 行为 / 版本修改，必须在**同一轮**更新
> `REQUIREMENTS-LEDGER.md`（ID、状态、验证证据）与本文件（当前版本、验证基线、§1.x 轮次、未验项）；
> 需要时同步 `SPEC-*.md` / `PLAN-*.md` / `CHANGELOG.md`。**没有更新这两份文档视为任务未完成。**
> 只认当次实测数字，不复用旧数字。历史章节 §1.5–§1.10 中的 190 / 258 / 282 / 135 / 335 / 164 是当轮实测值；
> **当前基线以顶部 389 / 163 + 20 轮布局压力为准**。

---

## 1. 一句话现状

能日常使用的双面板文件管理器；**2026-10-20 在 `feat/v0.9-overhaul` 分支完成了
交互层五轮重做 + 第六轮回归修复 + 第七轮标签拖拽重做**（交互决策表 + 标签级跨窗口拖拽 +
纯落点 resolver + 60Hz 帧调度 + 点击失效修复 + 列表四列 + 启动卡顿修复），
XCTest 190 条与自检 135 项全绿，**未推送、未发版**；结构债务（巨型文件、双真值源）
原样保留，是大改下一步该动的地方。

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

## 2. 产品定位

| 项 | 结论 |
|---|---|
| 是什么 | macOS 原生双面板文件管理器（Swift/AppKit UI + Rust core，FFI C ABI） |
| 平台 | **仅 macOS 桌面**，不做移动端、不做 Intel 通用包（当前 arm64-only） |
| 不做什么 | 不做网盘、不做同步、不做插件系统、不做多标签页之外的窗口管理 |
| 目标用户 | 需要双栏对照搬运文件的本地重度用户 |
| 当前状态 | 0.7.9-b1，预发布；正式版（1.0）未排期 |

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
- 勿对 `project.pbxproj` 执行 `git checkout`，正确改法是编辑而不是回滚。
- 委托创建的 `NSTableRowView` 其 `selectionHighlightStyle` 默认 `.none`；此时
  NSTableView 用系统强调色自绘，行视图的 `drawSelection` 覆写不会生效。要自绘必须显式设 `.regular`。

### 7.2 AppKit 布局

- 瞬态可变约束（列宽、定高）一律 `defaultHigh`，`required` 会瞬态无解、刷冲突日志。
- 隐藏视图的约束**仍参与求解**；动态行列表用清空/重建，不要靠 `isHidden`。
- `FFModalSheet` 两个坑：关闭必须走 `parent.endSheet`（`close()` 会毒化后续
  `NSOpenPanel` sheet）；高度测量要两段式（先撑到已知尺寸再量 `fittingSize`）。

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
4. 验证 Swift：pkill -f "MacOS/FlowFinder" && make swift-test（总数以本文件顶部「验证基线」为准）
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

**交接完成。** 当前代码可构建、可运行、可出包；XCTest **349 条**、应用内自检 **163 项**
与布局压力 **20 轮**全绿（2026-10-22 实测）。0.8.0 Beta 顶栏与交互修复见 §1.9；后续 UI 重做 v2
设计与 Phase 0–7 状态见 §1.10；第二轮整改见 §1.11；批次 1 设置接线见 §1.12；批次 2 功能回归测试见 §1.13。当前第一优先补的洞仍是 R-20 的真机走查（工具页 Tab 人工走查、红绿灯物理点击）。
结构债务仍集中在 MainWindowController 的布局/拖拽/标签装配，大改请继续按 coordinator 接缝搬迁。
