# SPEC · FlowFinder UI/UX 与结构整改（原生克制 · 全量重做）

> 日期：2026-10-20 · 分支：`feat/v0.9-overhaul` · 状态：**布局/视觉部分已被 `SPEC-2026-10-21-LAYOUT-ROLLBACK.md` 取代**；`PaneStore`/`MetadataService`/任务/工具/性能层继续保留
> 关联：`HANDOVER.md`、`REQUIREMENTS-LEDGER.md`（R-01..R-14）、`SPEC-2026-10-20.md`、`SPEC-2026-10-20-DRAG-REDO.md`
> 基线：D-01..D-11 已由用户逐项确认（见 §0）

---

## 0. 决策台账（已确认）

| ID | 决策问题 | 用户选择 | 影响范围 |
|---|---|---|---|
| D-01 | 产品身份 | **优雅的现代化 Finder 进化版**：双栏 + 标签页 + 智能工具组（查重、批量等，可扩展） | 信息架构、视觉、工具 |
| D-02 | 插件边界 | **内部模块化，预留扩展接口**；本轮不做第三方安装 | 工具架构、安全 |
| D-03 | 工具组入口 | **暂留左侧边栏品牌区右侧**；本轮不改结构，只改善文案/提示/上下文 | 侧栏、工具协议 |
| D-04 | 浏览主界面布局 | **安静的原生双栏**：每侧一行工具栏、统一底部状态栏、系统蓝细边 | 主窗口、工具栏、状态栏 |
| D-05 | 快捷键与活动面板 | **Finder 为准 + 指挥官加速**：⌘1/⌘2 切面板；F5/F6 可选；单一 activePane | 菜单、快捷键、焦点 |
| D-06 | 视觉语言 | **原生克制**：系统强调色、SF Pro、细分隔线、2px 活动边；无发光/玻璃白边 | 全部 UI |
| D-07 | 详情与状态信息 | **统一 28px 状态栏 + ⌘I 按需浮层**；选中不再同步读媒体 | 状态栏、详情、性能 |
| D-08 | 标签形态 | **标准原生标签**；单标签保留轻量标签（D-12 修订，不隐藏）；拖拽仍从标签本体起手 | 顶部、标签、拖拽命中 |
| D-09 | 本轮交付边界 | **全量结构重做**：视觉/UX + 性能 + MainWindowController 拆分 + PaneStore/渲染管线 + 工具协议/注册表 | 全部 |
| D-10 | 结构迁移方式 | **原地绞杀**：tokens/布局 → PaneStore → 渲染管线 → 详情 → 工具 → 旧壳退役 | 迁移、回滚 |
| D-11 | 目标状态与显式假设 | **通过**：目标总览、性能门槛、工具药丸改法、本轮不做清单 | 验收基线 |
| D-12 | 单标签隐藏 vs 最后标签拖出 | **保留单标签**：标签条不隐藏，只显示一个轻量标签；最后标签仍可直接拖出 | 标签、拖拽 |

---

## 1. 审查证据

### 1.1 审查范围与方法

- 当前主界面真实截图（2026-10-20，3840×2160）。
- 84 个 Swift 源文件 / 39,759 行；9 个 XCTest 文件 / 2,804 行。
- 历史文档：`PRODUCT.md`、`DESIGN-SPEC.md`、`ACCEPTANCE.md`、`HANDOVER.md`、`REQUIREMENTS-LEDGER.md`、`AUDIT-2026-10-19.md`、`CHANGELOG.md`。
- 对标：Finder、Windows Explorer、Files、Spacedrive、Double Commander、Krusader、Yazi。
- UI/UX Pro Max 的层级、一致性、可访问性与反馈规则（适配 macOS HIG，不照搬移动端 44pt 规则）。
- 未覆盖：VoiceOver 全量走查、全部设置页的逐屏截图、真实 SMB/网络卷压测、所有空/错误/权限状态的真机枚举。

### 1.2 关键发现（证据分级）

| ID | 观察 | 证据 | 影响 | 严重度 | 置信度 |
|---|---|---|---|---|---|
| F-01 | 工具组有四套入口：品牌旁 20pt 药丸、工具菜单、独立查重窗口、设置；没有统一上下文 | `UI/SidebarView.swift:301-303`、`UI/FFDiscoverPanel.swift:197,248-258`、`UI/MainMenu.swift:81,149` | 核心卖点不可发现；工具不知道作用于哪个面板/选择 | 阻断 | 已观察 |
| F-02 | 粉红强调色同时承担选中、面包屑、活动面板、悬停；14 层发光是窗口最响的元素；白字对 `#ff375f` 约 3.5:1 | `UI/FFComponents.swift:262-271`、`UI/MainWindowController.swift:948-961`、`UI/FileGridView.swift:405-407`、`UI/BreadcrumbBar.swift:591` | 文件内容被装饰压过；状态不可区分；对比度不足 | 高 | 已观察/推断 |
| F-03 | 每侧两行工具栏、8 个控件挤在 450pt 最小面板；搜索高度 24/26/32/14 四种；标签常驻且 36pt 标题带 | `UI/PaneToolbar.swift:338-346,391`、`UI/FFCommon.swift:989`、`UI/SearchPanelController.swift:446,489`、`UI/MainWindowController+Tabs.swift:28-31` | 顶部层级拥挤；小窗口压缩；视觉像三个产品拼起来 | 高 | 已观察 |
| F-04 | 详情栏在选中时同步读取 PDF/视频/网络元数据、目录内容 | `UI/ExpandableDetailsBar.swift:1331-1339,1939,2005-2014,2087-2096,2111` | 选中视频/PDF/SMB 文件时主线程卡住 | 阻断 | 已观察 |
| F-05 | 选中写入 `@Published state` → `updatePaneUI` → `updateViewMode` → `reloadData` / key-loop 重建；每次方向键都可能整表重建 | `UI/FileListView.swift:2363`、`UI/FileGridView.swift:1452`、`UI/MainWindowController.swift:1296,1930,2405-2415` | 选中延迟、缩略图取消、滚动抖动 | 阻断 | 已观察 |
| F-06 | 快捷键三套事实：⌘N/⌘⇧N 与 Finder 相反；Backspace 删除、菜单 ⌘⌫、右键 ⌘⌦；Return 重命名但菜单 F2；设置编辑器与运行时不一致 | `UI/MainMenu.swift:40,44,53,79`、`UI/FFCommon.swift:261-262,493`、`UI/FFPaneActionsController.swift:276`、`UI/SettingsWindowController.swift:691-712` | 误删/误操作；自定义不可信 | 高 | 已观察 |
| F-07 | 活动面板双真值：`activePane` + firstResponder；鼠标点列表才切换；Tab 进入右面板不更新；侧栏标签作用于上次点击面板 | `UI/MainWindowController.swift:2552,2696-2702`、`UI/PaneToolbar.swift:435-437` | 命令打到错误面板 | 高 | 已观察 |
| F-08 | 大目录 O(n²)：分页追加触发多路 reload；`rebuildDisplayRows` 全量比较诊断；`FFPaneReloadPolicy` 深比较全部 FileEntry | `UI/PaneState.swift:1218-1234`、`UI/MainWindowController.swift:1919-1922`、`UI/FileListView.swift:683-690,608-635`、`UI/MainWindowController.swift:2901-2912` | 大目录滚动/加载卡顿 | 高 | 已观察 |
| F-09 | 缩略图磁盘缓存键含完整路径，被当文件名；斜杠导致写盘失败且每次启动重生成；每次写后枚举缓存目录 | `Bridge/ThumbnailManager.swift:248-250,262,278-282` | 缩略图慢、磁盘缓存无效 | 高 | 已观察 |
| F-10 | 渲染路径用 `TagBridge.getTags`（同步 xattr），只有前 500 个预热；标签计数每次状态发射全目录 xattr；任务轮询每 0.5s 发布并重绘 | `UI/FileGridView.swift:446`、`UI/FileListView.swift:1921`、`Bridge/TagBridge.swift:61-68`、`UI/MainWindowController.swift:1948,1961-1980`、`UI/TagCountService.swift:30-64`、`Bridge/TaskSchedulerManager.swift:28-60` | 滚动卡、空闲也耗电 | 高 | 已观察 |
| F-11 | 主线程同步 FFI 等待（`invalidateCache` semaphore）在复制/粘贴/显示过滤后调用 | `Bridge/CoreBridge.swift:745-761`、`Model/PaneState.swift:205-209`、`UI/MainWindowController+MenuActions.swift:274` | 长任务时界面冻结 | 高 | 已观察 |
| F-12 | 巨型文件与耦合：MainWindowController 2,948 行；四套列表表示；没有工具协议/注册表；工具各自为政 | `UI/MainWindowController.swift`、`UI/FileListView.swift`、`UI/DuplicateScanWindowController.swift:526,628-646`、`UI/BatchRenameWindowController.swift:339-346` | 任何 UI 改动都牵一发动全身；无法持续加工具 | 阻断 | 已观察 |
| F-13 | 破坏性默认：冲突默认 Replace；永久删除复用“可撤销”文案；查重默认勾选所有重复项 | `UI/ConflictResolver.swift:107-123`、`UI/DeleteConfirmDialog.swift:68`、`UI/DuplicateScanWindowController.swift:537,590-596,636` | 数据丢失/错误恢复承诺 | 高 | 已观察 |
| F-14 | 可访问性缺失：Discover 行/药丸无 accessibility label/键盘路径；关闭“×”14×14；工具栏 24 高 | `UI/FFDiscoverPanel.swift:70-178,311-392`、`UI/PaneTabs.swift:250-251`、`UI/PaneToolbar.swift:391` | VoiceOver/键盘用户不可用 | 高 | 已观察 |

### 1.3 结论

问题不是“某几个页面不好看”，而是**三层同时失配**：

1. **信息架构**：工具组没有一等公民入口；活动面板没有单一真值；顶部/底部控制重复。
2. **交互契约**：快捷键、焦点、破坏性默认与 Finder/用户预期冲突。
3. **渲染与状态**：选中、详情、缩略图、标签计数、任务轮询把主线程当成廉价资源。

因此本轮不接受“只换皮”。按 D-09/D-10 做全量结构重做，但按切片迁移，每片可运行、可验收、可回滚。

---

## 2. 目标与非目标

### 2.1 目标

1. **优雅**：原生克制视觉；没有粉红发光、玻璃白边、七种图标尺寸；长时间使用不累。
2. **高效**：双栏/标签/键盘/批量是核心；选中、详情、滚动不再卡。
3. **可信**：活动面板单一真值；命令、快捷键、菜单、右键、设置一致；破坏性操作安全。
4. **可扩展**：内部工具协议/注册表；新增工具不改 MainWindowController；第三方安装留到以后。

### 2.2 非目标（本轮不做）

- 第三方插件安装、沙箱、签名、插件市场。
- 工具组迁移到独立工作台/右侧检查器（D-03 defer）。
- 完整查重/批量 review workspace（Phase 3）。
- 面板切换“真位移”（Phase 3，除非结构重做自然覆盖）。
- 改动 Rust core / 文件操作语义 / 网络协议。
- 重新设计标签色系统；保留用户标签颜色。

### 2.3 目标用户与首要任务

- 目标用户：需要双栏对照搬运/整理文件的 macOS 重度用户，同时希望界面安静、可信、不需要记一堆私有快捷键。
- 首要任务：在左右两个目录之间快速浏览、比较、复制/移动、批量整理，并能随时调用查重/批量工具。
- 次要任务：搜索、标签筛选、Quick Look、多标签/多窗口并行。

### 2.4 成功标准

- 用户能在不读文档的情况下完成：双栏搬运、开/关标签、切换活动面板、搜索、Quick Look、查重。
- 选中文件不再触发整表重建；详情不再阻塞主线程。
- 视觉上不再出现“粉红发光压过文件”“两套底部详情栏”“两套搜索框”。
- 新增一个内部工具只需实现 `ToolProtocol` 并注册，不改 MainWindowController。

---

## 3. 目标信息架构与布局

### 3.1 窗口骨架

```
┌─────────────────────────────────────────────────────────────────────┐
│ 侧栏 220pt │ 操作区（双栏）                                          │
│            │ ┌──────────────────────┬──────────────────────┐        │
│ 品牌 + 工具 │ │ 标签条（原生）        │ 标签条（原生）        │        │
│ 收藏        │ │ 工具栏（单行）        │ 工具栏（单行）        │        │
│ 位置        │ │ 文件列表/网格         │ 文件列表/网格         │        │
│ 标签        │ │ （活动面板 2px 蓝边） │                      │        │
│            │ └──────────────────────┴──────────────────────┘        │
│            │ 统一状态栏：Active / 选择摘要 / 磁盘 / 详情 ⌘I          │
└─────────────────────────────────────────────────────────────────────┘
```

- 侧栏默认 220pt（160–280 可拖）；窗口最小 1060×700。
- 双栏等宽；分隔线 1px；调宽把手保留现有逻辑。
- 活动面板只在顶部显示 2px 系统强调色边；不再有 14 层发光/整圈描边。
- 底部一条 28px 状态栏，横跨整个操作区（不是每面板一条）。

### 3.2 侧栏

- 顶部：品牌名 + “工具”药丸（D-03：仍在品牌区右侧）。
- 分区：个人收藏 / 位置 / 标签；分区标题 11pt medium；行高 28pt。
- 选中：系统强调色淡底 + 不抢眼的左侧 2px 指示；不再整行高饱和色块。
- 工具药丸：扳手图标 + “工具”；hover 提示“工具组（作用于当前面板/选择）”；点击弹出锚定 popover。
- 不再把“AI 生图”等实验入口混在收藏区；实验功能统一进工具 popover 并标注状态。

### 3.3 面板与标签

- **标准原生标签**（D-08 + D-12）：
  - 标签条高度 26–28pt；活动标签 24–26pt，非活动 20–22pt；活动标签底部 2px 系统强调色。
  - **单标签时保留一个轻量标签，不隐藏**（D-12），保证“最后标签可直接拖出”仍有把手；≥2 标签时正常显示。
  - `+` 按钮仍在工具栏/标签条右端。
  - 标签标题显示路径最后一段；重名时附上级目录（tooltip 显示完整路径）。
  - 拖拽仍从标签本体起手；跨窗口/重排语义沿用上一轮 `FFDropResolver`。
  - 关闭：`×` 热区 ≥20×20pt；`⌘W` 关闭当前标签；`⌘⇧W` 关闭窗口。
- **工具栏（每侧一行）**：
  - 后退、前进、上一级；面包屑；搜索（展开式）；视图选项（排序/分组/列/密度）；溢出。
  - 排序/分组/列不再各占一个常驻按钮；统一进“视图选项”popover（`⌘J`）。
  - 搜索框高度统一 28pt；`⌘F` 在当前活动面板展开；`⌘⇧F` 全局搜索窗口。
  - 视图模式（列表/图标）放进视图选项；`⌘1/⌘2` 用于面板焦点，不与视图模式冲突。
- **列表/网格**：
  - 行高 28pt（可选 24pt 紧凑）；字号：文件名 13pt，元数据 11pt，列头 11pt medium。
  - 列：名称、类型、大小、修改日期（默认）；可选创建日期、标签、说明。
  - 选中：系统强调色 12–13% 淡底 + 1px 半透明描边；不改变文字颜色；失焦使用次级选中色。
  - 悬停：极淡背景，不移动布局；行内不出现跳动按钮。
  - 网格：名称 12pt；图标/缩略图固定框；选中同样用淡底 + 描边，不再两个高饱和色块。

### 3.4 状态栏与详情

- 28pt 统一状态栏：
  - 左：`Active: <面板名>`（活动面板）。
  - 中：选择摘要（无选择=目录项数；单选=名称/大小/类型；多选=数量+总大小；文件夹=项数/计算中）。
  - 右：磁盘可用空间、`⌘I 详情`、筛选 chip（如有）。
- `⌘I` 打开详情 popover（锚定活动面板/选中项）：
  - 内容：缩略图/图标、名称、类型、大小、创建/修改、位置、标签、Finder 说明、页数/时长（按需）。
  - 元数据后台读取 + generation token；关闭即取消；不阻塞选中。
- `Space` 仍是 Quick Look；详情 popover 不替代 Quick Look。
- 无选择时不创建详情卡；多选时显示聚合摘要，不逐项打开媒体。

### 3.5 工具组（保留现有位置，改善上下文）

- 工具 popover 标题：`工具 · 作用于 <活动面板名>`；副标题：当前路径 + 选择摘要。
- 工具卡：图标、名称、一句说明、可用状态（可用/需选择/需文件夹/未启用 + 原因）。
- 现有工具：重复文件扫描、批量重命名、标签整理、任务面板（逐步接入）。
- “AI 自动标签”等未完成能力：显示“未启用”并说明原因，不再放在可点击的收藏区或伪入口。
- 工具执行结果：默认进入现有窗口（查重/批量），但必须携带活动面板上下文；Phase 3 再统一 review workspace。
- 快捷键：工具 popover 可用 `⌘K` 打开（可选，Phase 1 可先不做；不得与现有快捷键冲突）。

### 3.6 设置、搜索、查重、批量窗口

- 统一使用同一套 tokens：字号、间距、圆角、按钮、空/错误态。
- 设置：
  - 删除/接线无效开关（“文件操作确认”等）。
  - 快捷键编辑器与实际运行时一致；显示冲突检测；恢复默认。
  - 新增“工具组”开关（是否显示工具药丸/哪些工具启用）。
- 搜索：
  - 统一 28pt 搜索框；范围 chip（当前文件夹 / Mac / 标签）；清除按钮。
  - 结果行高 28pt；双击结果在活动面板定位并选中父目录。
- 查重/批量：
  - 统一标题栏、工具栏、空/扫描中/结果态；结果列表使用虚拟化/分页。
  - 默认不勾选任何重复项；永久删除与移到废纸篓分开；撤销承诺只在真实可撤销时出现。
  - 扫描默认作用于活动面板当前目录，而不是 `~`。

---

## 4. 视觉系统（原生克制）

### 4.1 颜色

- **强调色**：`NSColor.controlAccentColor`（跟随系统强调色）。用于选中、焦点、活动面板边、链接；不再硬编码粉红。
- **表面**：
  - 窗口：`windowBackgroundColor`
  - 面板：`controlBackgroundColor` / `textBackgroundColor`（按主题）
  - 侧栏：`underPageBackgroundColor` 或 `sidebar` 语义色
  - 分隔线：`separatorColor`
- **文字**：`labelColor` / `secondaryLabelColor` / `tertiaryLabelColor`。
- **标签色**：沿用现有标签色；只用于标签点/胶囊，不作为全局强调色。
- **对比度**：正文 ≥4.5:1；大字号/图标 ≥3:1；浅色/深色分别验证。
- **禁止**：粉红发光、整圈高饱和描边、半透明大面积填充、彩色渐变背景。

### 4.2 字体与字号

- 系统字体 `NSFont.systemFont`（SF Pro），不使用自定义字体。
- 类型刻度：
  - 17pt semibold：空状态/详情标题（少量）
  - 15pt medium：分区标题/弹窗标题
  - 13pt regular：文件名、正文、菜单
  - 11pt regular/medium：元数据、列头、辅助说明
- 行高：正文 1.4–1.5；列表行 28pt；紧凑 24pt。
- 数字列使用 tabular figures（大小/日期/计数）。
- 长文件名截断用尾部省略 + tooltip 完整路径；不换行撑高行。

### 4.3 间距、圆角、边框

- 间距刻度：4 / 8 / 12 / 16 / 24。
- 圆角：控件 6；卡片/面板 8–10；窗口 12（连续曲率，保留）。
- 边框：1px hairline；只有 popover/浮层允许一层轻阴影，列表/面板不加内发光。
- 工具栏高度 32–36pt；按钮热区 ≥24×24pt（桌面），图标 16pt。
- 侧栏行高 28pt；图标 18pt；文字 13pt。

### 4.4 图标

- 统一一套线性图标（SF Symbols 或现有 Lucide 模板），只使用 14/16/18pt 三档；不再出现 9/11/12/13/15/20 混用。
- 文件类型图标使用系统图标或统一彩色文件夹；不再混用彩色 3D 文件夹、线框图标和真实文件图标。
- 图标与文字基线对齐；图标-only 按钮必须有 accessibilityLabel/toolTip。

### 4.5 动效

- 微交互 150–200ms，ease-out；面板模式切换不超过 250ms（原 360ms 弹性改为克制曲线）。
- 不使用弹跳/回弹；`reduceMotion` 时改为交叉淡入或直接切换。
- 不再动画 width/height/top/left；用 transform/opacity 或窗口 resize（必要时）。
- 拖拽反馈沿用上一轮轻量方案（完整胶囊浮层、2px 插入线、1px 落点描边、无效落点回原位）。

### 4.6 暗色模式

- 使用语义色，不硬编码浅色/深色。
- 暗色下选中淡底透明度略高、边框更明显；标签色保持可读。
- 逐屏截图验证：主窗口、设置、搜索、查重、批量、空/错误/加载。

---

## 5. 交互契约

### 5.1 活动面板（单一真值）

- 新增 `WindowFocusModel`（或 `PaneStoreCoordinator` 中的 activePane）作为唯一真值。
- 以下行为全部更新 activePane：
  - 点击面板任意区域（工具栏、列表、网格、详情/状态栏对应侧）。
  - 键盘焦点进入面板（Tab/Shift-Tab）。
  - `⌘1` 左 / `⌘2` 右。
  - 打开该面板的标签、搜索、视图选项。
- firstResponder 只作为“键盘焦点”的派生，不再单独决定命令目标。
- 侧栏位置/标签/工具命令、菜单命令、工具栏操作都从 activePane 派生。
- 状态栏显示 `Active: <面板>`；活动面板顶部 2px 系统强调色边。
- 切换面板时保留各自的选择/滚动/筛选；不重置。

### 5.2 快捷键（默认）

| 操作 | 快捷键 | 备注 |
|---|---|---|
| 新窗口 | ⌘N | Finder 一致 |
| 新建文件夹 | ⌘⇧N | Finder 一致 |
| 新建标签页 | ⌘T | |
| 关闭标签页 | ⌘W | |
| 关闭窗口 | ⌘⇧W | |
| 移到废纸篓 | ⌘⌫ | 不再监听裸 Backspace |
| 重命名 | Return | F2 可选 |
| 快速查看 | Space | |
| 复制选中项 | ⌘D | |
| 显示简介 | ⌘I | 详情 popover |
| 后退/前进 | ⌘[ / ⌘] | |
| 上一级 | ⌘↑ | |
| 聚焦左/右面板 | ⌘1 / ⌘2 | |
| 下一/上一标签 | ⌃Tab / ⌃⇧Tab | |
| 当前面板搜索 | ⌘F | |
| 全局搜索 | ⌘⇧F | |
| 重复文件扫描 | ⌘⇧D | 作用于活动面板 |
| 复制/移动到另一面板 | ⌘⇧C / ⌘⇧X | F5/F6 可选加速键 |
| 设置 | ⌘, | |
| 工具 popover | ⌘K（可选） | 不与现有键冲突 |

- 菜单、右键、设置、提示必须与运行时使用同一份 `FFKeyboardContract` 数据；禁止三套硬编码。
- F5/F6/F7/F8 作为“指挥官加速键”可开关，默认关闭或在设置中启用；开启后仍不覆盖 Finder 标准键。
- 设置中的快捷键编辑器必须显示实际生效键、冲突检测、恢复默认。

### 5.3 选择与命中

- 单击选中；⌘单击多选；⇧单击范围选择；方向键移动；⇧方向键扩展。
- 点击空白清除选择；点击列表行切换 activePane + 选择。
- 双击打开；Return 重命名；Space Quick Look；⌘↓ 打开。
- 右键菜单目标 = 当前选择 + activePane；空白右键 = 当前目录。
- 悬停只做轻量背景，不显示行内按钮；删除/重命名等操作在右键/菜单/工具栏。
- 拖拽：沿用上一轮标签拖拽；文件拖拽仍走现有 `NSDraggingSession`；活动面板在起手时锁定。

### 5.4 标签与工具

- 标签：见 §3.3；单标签保留轻量标签（D-12），不隐藏；`+` 在所有状态下可达；标签溢出用横向滚动或压缩，不无限撑宽。
- 工具：见 §3.5；工具 popover 必须显示上下文；工具执行前若有破坏性动作，先预览/确认。
- 查重：默认不勾选；扫描默认当前目录；永久删除与废纸篓分开；可取消、可返回结果。
- 批量重命名：先预览后执行；支持正则/序号/大小写；冲突检测；可撤销。

### 5.5 破坏性操作与错误恢复

- 冲突处理：默认“跳过/保留两者”，Replace 必须显式选择；支持“全部应用”。
- 删除：默认移到废纸篓；永久删除单独入口 + 明确不可撤销；不再复用“可撤销”文案。
- 长任务：状态栏/任务中心显示文件名、字节进度、速度、剩余时间；可取消/重试；失败项可导出。
- 错误：说明原因 + 下一步；权限不足提供“打开系统设置”按钮；不阻塞首次启动。

### 5.6 可访问性

- 所有图标按钮有 accessibilityLabel/toolTip；工具卡/标签/关闭按钮可键盘到达。
- 焦点环 2px 系统强调色；焦点顺序 = 视觉顺序。
- 支持 VoiceOver 读取行名称、类型、大小、选中状态；列表/网格/工具结果提供行摘要。
- 支持 Reduce Motion、增大对比度、系统强调色、浅/深色。
- 不用颜色作为唯一状态编码；选中同时有背景/描边/文本权重变化。

---

## 6. 架构与迁移

### 6.1 新模块（原地绞杀）

| 模块 | 职责 | 替换/收编 |
|---|---|---|
| `PaneStore` | 每面板单一真值：files/selection/filter/sort/viewMode/history/session；粒度变更集（filesChanged / selectionChanged / filterChanged / viewModeChanged） | 演进 `PaneViewModel` + `PaneState`，不新增第二套状态 |
| `WindowFocusModel` | 唯一 activePane + 焦点派生；⌘1/⌘2、点击、Tab 都写它 | 收编 `activePane` + firstResponder 双真值 |
| `RenderPipeline` | 合并 list/grid 快照；选择只更新选择；文件/筛选/视图变化才重建；可见范围标签预热；去掉诊断数组 | 收编 FileListView/FileGridView 的多路 reload |
| `MetadataService` | 后台读取详情/媒体/Spotlight/Finder 说明；generation token；取消 | 收编 ExpandableDetailsBar.refresh |
| `ThumbnailCache` | 哈希 key、异步生成、摊销清理、失败回退 | 修 ThumbnailManager |
| `TaskService` | 任务模型、进度/取消/重试/历史；复制/移动/查重/批量接入 | 收编 TaskSchedulerManager/TaskPanel |
| `ToolProtocol` / `ToolRegistry` / `ToolContext` | 工具注册、上下文（activePane/selection/window/taskService）、可用性；工具 popover 渲染 | 收编 FFDiscoverPanel 硬编码枚举 |
| `WindowShellCoordinator` | 窗口 chrome、侧栏、面板、状态栏装配 | 拆 MainWindowController |
| `PaneCoordinator` | 单面板工具栏/标签/列表/详情/搜索装配 | 拆 MainWindowController |
| `TaskCoordinator` | 任务 UI/状态栏/任务中心 | 拆 MainWindowController |
| `DragCoordinator` | 现有 `FFPaneDragController` + resolver/geometry/overlay | 保留，接新 PaneStore |

### 6.2 数据流

```
CoreBridge / FSEvents
        ↓
PaneStore（单一真值，粒度变更集）
        ↓
RenderPipeline（合并快照 / 选择 diff）
        ↓
FileListView / FileGridView（只做渲染）
        ↓
WindowFocusModel（activePane）+ StatusBar
        ↓
ToolContext / MetadataService / TaskService
```

- 视图不再直接写 `@Published state`；选择/滚动/悬停只更新视图本地状态或发 `selectionChanged` 给 Store。
- Store 负责把选择/排序/筛选写回会话；加载仍由现有 Bridge/服务完成。
- 任何跨面板命令从 `WindowFocusModel.activePane` 取目标；不再从 firstResponder 猜。
- 详情/工具/任务只读 Store/Context，不直接读视图。

### 6.3 迁移切片（D-10）

1. **Slice 1 · 视觉与外壳**：tokens、侧栏、单行工具栏、原生标签、状态栏、2px 活动边、工具药丸文案/提示。旧状态/渲染不动；用适配层把现有数据喂给新视图。
2. **Slice 2 · PaneStore + WindowFocusModel**：把 `PaneState`/`PaneViewModel` 演进为 PaneStore；选择/排序/筛选/会话迁入；收编 activePane；旧 `updatePaneUI` 改为订阅粒度变更。
3. **Slice 3 · RenderPipeline**：合并 list/grid reload；选择只更新选择；去掉诊断数组；可见范围标签预热；大目录分页追加改用批量插入/一次 reload。
4. **Slice 4 · MetadataService + 详情/状态栏**：详情改按需 popover；后台媒体/Spotlight；缩略图缓存修复；标签计数按路径/文件变化；任务轮询按变化发布。
5. **Slice 5 · ToolProtocol/Registry + TaskService**：注册现有工具；工具 popover 显示上下文/可用性；查重/批量接入活动面板上下文；任务进度/取消/重试。
6. **Slice 6 · 外壳拆分 + 旧路径退役**：拆 MainWindowController 为 coordinators；删除旧 Discover 枚举、旧详情栏、旧工具栏重复路径；全量回归/性能验收。

每个切片必须：
- 可独立构建、运行、测试；
- 有明确回滚点（旧路径保留到该切片验收通过）；
- 不引入长期双 UI；旧路径在验收后删除；
- 更新台账/交接文档。

### 6.4 关键设计决定

- **不重写 Rust core**；Bridge/FFI 保持。
- **不引入第三方 UI 框架**；AppKit + 现有自绘组件，遵循 macOS HIG。
- **不保留粉红/玻璃/发光作为品牌识别**；FlowFinder 的识别来自双栏、标签、工具组与克制质感。
- **工具组本轮不迁移入口**；但工具协议/注册表先落地，为 Phase 3 的工作台/第三方扩展留接口。
- **详情/状态栏**：详情按需；状态栏轻量；不恢复常驻玻璃卡。
- **标签**：标准原生；单标签保留一个轻量标签（D-12），不隐藏；拖拽语义沿用上一轮；最后标签仍可直接拖出。

---

## 7. 性能验收

### 7.1 门槛

| 指标 | 目标 | 测量 |
|---|---|---|
| 选中响应 | <50ms | signpost / XCTest 结构测试 |
| 500 项目录首屏 | <300ms | 真机 + signpost |
| 列表/网格滚动 | 60fps | Instruments / sample |
| 主线程阻塞 | 无 >100ms | sample / signpost |
| 热启动到可用 | <2s | 启动计时 |
| 详情打开 | <100ms 显示骨架；元数据后台完成 | signpost |
| 大目录分页追加 | 单次批量更新，不触发多路 reload | 结构测试 + sample |

### 7.2 硬性约束

- 选中变化不得调用 `reloadData` / 重建 key loop / 重新生成缩略图。
- 渲染路径不得同步 `getTags`/xattr；只用缓存 + 可见范围预热。
- 详情/媒体/Spotlight 不得在主线程同步读；必须带 generation token。
- 任务轮询无变化不发布；无任务时停表。
- 缩略图磁盘缓存必须真正命中（hash key，不把路径当文件名）。
- 任何 `ffiQueue.sync` 不得从主线程调用（或改为 async）。
- 每个切片用 `sample`/Instruments 采样，保留证据。

---

## 8. 测试策略（TDD）

### 8.1 纯函数/单元

- `FFKeyboardContract`：默认映射、冲突检测、设置覆盖、菜单/右键/提示同一来源。
- `FFStatusBarText`：空/单选/多选/文件夹/加载/错误文案。
- `PaneStore`：粒度变更集、选择、排序、筛选、会话、活动面板。
- `RenderPipeline`：选择变化不 rebuild；文件变化 rebuild；视图模式变化一次；分页追加一次。
- `FFToolRegistry`：注册、可用性、上下文、重复 id、未启用原因。
- `FFMetadataRequest`：generation token、取消、旧结果丢弃。
- `FFConflictPolicy`：默认跳过/保留两者；Replace 显式。
- `FFTaskProgress`：字节/文件进度、取消、重试、失败项。

### 8.2 集成/UI

- 点击左/右面板任意区域 → activePane 正确；⌘1/⌘2；Tab 进入面板。
- 快捷键：⌘N/⌘⇧N/⌘⌫/Return/⌘W/⌘⇧W/⌘1/⌘2/⌃Tab。
- 标签：单标签保留轻量标签；多标签正常显示；拖拽仍工作；关闭/新建。
- 状态栏：四种选择状态文案；详情 popover 按需打开、关闭取消。
- 工具 popover：上下文标题、可用性、执行后携带 activePane。
- 查重/批量：默认不勾选、默认当前目录、永久删除文案。
- 空/加载/错误/权限状态：不阻塞、可重试、错误可恢复。

### 8.3 性能结构测试

- 选择 100 次，断言 list/grid `reloadData` 0 次（测试专用计数/通知）。
- 详情请求不调用主线程文件读取（注入 spy MetadataService）。
- 缩略图 key 为 hash，缓存写盘成功。
- 标签计数只在路径/文件变化时调度。
- 任务轮询无变化不发布。
- 分页追加只触发一次批量更新。

### 8.4 视觉/真机

- 1060×700、1400×900 两档；浅色/深色；100%/高对比/Reduce Motion。
- 主窗口、设置、搜索、查重、批量、工具 popover、详情 popover、空/错误/加载。
- 截图归档到 `docs/images/2026-10-21-uiux-*`（新目录）。
- 键盘旅程：⌘1/⌘2 → 方向键选择 → Space → Return → ⌘⌫ → ⌘Z？撤销行为按现有能力。
- 与 Finder/Explorer 对照：快捷键、路径栏、Quick Look、标签、工具入口。

### 8.5 现有护栏

- 190 条 XCTest 必须保持全绿；新增测试按 TDD 先红后绿。
- `FF_SELFTEST` 保留并扩展：activePane、状态栏、键盘契约、工具上下文。
- 每个切片构建成功 + 全量测试 + 自检 + 截图，再进入下一片。

---

## 9. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 全量重做导致回归 | D-10 原地绞杀；每片可运行/回滚；旧路径验收后删除 |
| 视觉改动与既有标签拖拽冲突 | 保留 FFDropResolver/Geometry/Overlay；标签形态改动只影响视觉与命中尺寸，拖拽测试覆盖 |
| 性能改动引入状态双源 | PaneStore 单一真值；视图只读；禁止视图直接写 @Published |
| 详情/工具异步导致旧结果覆盖 | generation token + 取消 + 关闭即丢弃 |
| 工具注册表过度设计 | 先定义最小 ToolProtocol；只接现有工具；第三方接口留空 |
| 设置/菜单/快捷键再次分叉 | FFKeyboardContract 单一来源；菜单/右键/设置/提示全部读它 |
| 视觉验收主观 | 每轮给真实截图 + 前后对比；以 D-06 规则与对比度为硬约束 |
| 范围膨胀 | 非目标清单 §2.2；Phase 3 工具工作台/第三方插件另开 |

---

## 10. 文件落点（预计）

| 类型 | 文件 |
|---|---|
| 设计 tokens | `UI/FFDesign.swift`（或扩展现有 DesignTokens/FFDesign） |
| 侧栏/工具 | `UI/SidebarView.swift`、`UI/FFDiscoverPanel.swift` → `UI/FFToolPopover.swift` |
| 主窗口/壳 | `UI/MainWindowController.swift` → `UI/WindowShellCoordinator.swift`、`UI/PaneCoordinator.swift` |
| 标签 | `UI/PaneTabs.swift`（标准原生标签；保留拖拽） |
| 工具栏 | `UI/PaneToolbar.swift`（单行；视图选项 popover） |
| 列表/网格 | `UI/FileListView.swift`、`UI/FileGridView.swift`、新 `UI/RenderPipeline.swift` |
| 状态/焦点 | `Model/PaneStore.swift`、`UI/WindowFocusModel.swift` |
| 详情 | `UI/ExpandableDetailsBar.swift` → `UI/FFDetailsPopover.swift` + `Bridge/MetadataService.swift` |
| 任务 | `Bridge/TaskService.swift`、`UI/TaskProgressBar.swift`、`UI/TaskPanelWindowController.swift` |
| 工具协议 | `UI/FFToolProtocol.swift`、`UI/FFToolRegistry.swift`、`UI/FFToolContext.swift` |
| 设置/搜索/查重/批量 | `UI/SettingsWindowController.swift`、`SearchPanelController.swift`、`DuplicateScanWindowController.swift`、`BatchRenameWindowController.swift` |
| 测试 | `Tests/FlowFinderTests/` 新增键盘/状态栏/PaneStore/渲染/详情/工具/任务/视觉结构测试 |
| 文档 | `HANDOVER.md`、`REQUIREMENTS-LEDGER.md`（R-15）、`CHANGELOG.md`、本文件 |

---

## 11. 验收清单

- [ ] 主窗口：无粉红发光；活动面板 2px 系统蓝边；系统强调色；浅/深色均通过对比度检查。
- [ ] 每侧一行工具栏；排序/分组/列进视图选项；搜索高度统一；单标签保留轻量标签（不隐藏），最后标签可直接拖出。
- [ ] 统一 28px 状态栏；详情按需 popover；选中不触发整表重建；详情不阻塞主线程。
- [ ] activePane 单一真值：点击/Tab/⌘1/⌘2/侧栏/菜单/工具全部一致。
- [ ] 快捷键与 Finder 一致；菜单/右键/设置/提示同一来源；F5/F6 可选。
- [ ] 工具 popover 显示上下文/可用性；现有工具携带 activePane；未完成能力不伪装可用。
- [ ] 查重默认当前目录、默认不勾选；永久删除与废纸篓分开；撤销承诺真实。
- [ ] 性能门槛 §7.1 全部达标（附 sample/signpost 证据）。
- [ ] PaneStore 单一真值；RenderPipeline 无选择重载；MetadataService 异步；ToolRegistry 可扩展。
- [ ] MainWindowController 拆分完成，旧路径删除；190+ XCTest/自检全绿。
- [ ] 文档/台账/CHANGELOG 更新；截图归档。

---

## 12. 显式假设

- 性能门槛按 D-11：选中 <50ms、500 项首屏 <300ms、滚动 60fps、无主线程 >100ms、热启动 <2s。
- 单标签保留轻量标签（D-12），标签条不隐藏；最后标签可直接拖出。
- 工具药丸仍在侧栏品牌区；改文案/图标/上下文提示，不迁移。
- 保留双栏、标签、标签色、Quick Look、Get Info、上一轮拖拽 resolver/geometry/overlay。
- 查重/批量本轮接入工具协议与上下文，但不重做完整 review workspace（Phase 3）。
- 设置/搜索/查重/批量窗口统一 tokens 与状态；不新增未列出的产品功能。
- 本轮不做第三方插件安装；ToolProtocol 预留扩展点，但只编译内置工具。

---

## 13. 实施状态（2026-10-21）

| 项 | 状态 | 证据 |
|---|---|---|
| 构建 | 通过 | `make build` → BUILD SUCCEEDED |
| XCTest | **260 条 0 失败** | `make swift-test`，2026-10-21 06:50 |
| 应用内自检 | **135 项 0 失败** | `FF_SELFTEST=1` 日志：拖拽 10 + 决策表 71 + 区域 7 + 行为 4 + 焊接 21 + 外壳 22 |
| D-01..D-12 自动化覆盖 | 通过 | 见 `REQUIREMENTS-LEDGER.md` R-15 映射表 |
| 视觉验收（1400×900 浅色） | **部分验证** | 双栏、单↔双、⌘I 详情、工具 popover、设置、搜索；已修单→双 0 宽、搜索框裁切、辅助窗口 ⌘W、状态栏文案 |
| 深色/高对比/1060×700 | **未验** | 需继续人工截图 |
| 性能采样（选中/首屏/滚动/主线程） | **部分验证** | `sample` 5s 主线程无应用侧长栈；精确门槛未测；代码侧已消除同步 FFI/选中 reload/数组深比较 |
| VoiceOver 人工走查 | **未验** | `FFAccessibilityTests` 覆盖 label/hit target/对比度 |
| MainWindowController 完全拆分 | **部分完成** | coordinator 接缝与状态所有权已迁移；布局/拖拽/标签装配仍在主控制器 |
| 旧路径退役 | 部分完成 | `FFDiscoverPanel` 枚举/控制器已退役；`ExpandableDetailsBar` 常驻栏仍保留代码但已隐藏 |

未验项需在解锁后的真实桌面上补：1060×700/1400×900 截图、sample 5s、VoiceOver 主旅程。
