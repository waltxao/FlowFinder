# 需求台账 · FlowFinder UI/UX 重做

> 唯一的「哪些做了、怎么做的、验到什么程度」清单。
> 规格来源：`docs/SPEC-2026-10-20.md`、`docs/DESIGN-SPEC.md`、`docs/PRODUCT.md`。
> 更新规则：**改代码就改这张表**。状态只有四种：`已完成` / `部分完成` / `未开始` / `已废弃`。
> 「验证」列写实际手段，不写「应该没问题」。
> **同步纪律（2026-10-21 起，强制）：** 每次修改必须在同一轮同时更新本表与 `HANDOVER.md`；
> 只认当次实测数字；收尾前检查 `git diff -- docs/` 是否覆盖本轮全部改动，没有文档改动视为未完成。
> 历史条目中的 190 / 258 / 282 / 135 / 335 / 164 是当轮实测值；**当前全量基线以 2026-10-24 R-39（26102409）的 542 条 0 失败（跳过 2 条既有环境测试；重复扫描单跑 16.656s 通过；token budget 外部卷阻塞）/ 自检 153 + 20 轮布局压力为准**（2026-10-23 接手轮为 516 条，见 §3 与 `HANDOVER.md` §1.28；2026-10-24 R-37 首次工具模块为 467 条，已被 R-38 取代）。**2026-10-25 新增 1 条回归单测 `testSearchEnterWithEmptyQueryDoesNotOpenFirstItem` 单跑通过（0.914s），全套未重跑，不改变 542 的全量基线。**

---

## 0. 状态总览

| 批次 | 内容 | 状态 |
|---|---|---|
| A | #1 拖动模型（面板级）· #8 边缘调宽 | **#1 已被第四轮「标签级」模型取代（见 R-01）**；#8 仍有效 |
| B | #3 列表四列与可选列 · #10 垂直中线 | 已完成 |
| C | #4 顶部对齐 · #5 窗口圆角 · #7 三控制图标 | 已完成（#5 用连续曲率近似） |
| D | #6 侧栏图标 · #9 发光 · #2 切换动画 | #6/#9 已完成；#2 部分完成 |
| 第四轮 | R-11 点击失效 · R-01 标签级拖拽 · R-12 启动卡顿 | 见逐条台账 |
| 第八轮 | R-15 UI/UX 与结构整改（D-01..D-12） | 自动化已完成；视觉/性能人工验收待补 |
| 第十轮 | R-17 UI/UX 全界面精修（U-01..U-13） | 已完成（自动化 + 浅/深色真机走查）；高对比/VoiceOver 人工验收待补 |
| 第十一轮 | R-18 0.8.0 Beta 顶栏与交互修复（D-01..D-09） | 已完成（自动化 + AX 实测）；A1 像素与 hover 目测待用户确认 |
| 第十二轮 | R-19 0.8.0 Beta 后续 UI 重做 v2（Phase 0–7） | 已完成（自动化 + 部分实机）；1060/深色/真实全屏/真实拖拽手感人工验收待补 |
| 第十三轮 | R-20 0.8.0 Beta 第二轮整改（D-01..D-09） | 已完成（自动化 + 真机走查） |
| 第十四轮 | R-21 批次 1：设置接线 / 终端入口 / 工具页无障碍 | 已完成（自动化 + 设置页真机）；SMB 断线与更新提示未触发 |
| 第十五轮 | R-22 批次 2：功能回归测试 6 组 | 已完成（383 条 XCTest） |
| 第十六轮 | R-23 批次 3：需求/验收文档原位重写 | 已完成（文档与代码对齐） |
| 第十七轮 | R-24 批次 4：引导/崩溃日志/Tab 环/AI 命名 | 已完成（自动化 + 首启实机） |
| 第十八轮 | R-25 真机走查问题修复（5 项） | 已完成 |
| 第十九轮 | R-26 AX 行虚拟化 | **部分完成（审计复核）**：轻量行单测通过，但独立副本系统 AX 树仍暴露每行 4 个 cell，选中后额外出现同名 disabled 行；下一批修 |
| 第二十轮 | R-27 J3-11 文件说明迁移 Finder 注释 | 已完成（迁移/读取真机 + store XCTest）；详情栏文本输入手势未实机点击 |
| 第二十一轮 | R-28 J2-07 搜索范围（本栏 / 含子目录 / 双栏） | 已完成（7 条自动化 + 真机三范围走查）；2 条既有异步测试受测试宿主环境阻塞 |
| 第二十二轮 | R-29 J3-10 批量整理（预览 Sheet + 整批 ⌘Z） | 已完成（12+1 条自动化 + 真机双入口/执行/撤销走查）；真机发现并修复 Sheet 塌陷与工具行 AXPress 两处缺陷 |
| 第二十三轮 | R-30 P0 数据安全（重命名覆盖 / 查重零保留 / 永久删除确认） | 已完成（4 条新增自动化）；界面错误横幅与 beep 未实机点击 |
| 第二十四轮 | R-31 P1 UI 状态与入口修复 | 已完成（4 条新增 + 2 条断言更新）；实机通过：工具页上下文/焦点、显示设置、侧栏新标签、单标签关闭、右键 clickedEntry、整理路由、Sheet 按类型、重命名冲突、F-06 文案 |
| 第二十五轮 | R-32 全量 UI/UX 验收第一轮 | **进行中**：主窗口/列表/网格/详情/设置 7 分区/查重/批量重命名/冲突/1060×700 已走查；F-02/F-03/F-04/F-05/F-06/F-07/F-08/F-09/F-11 待修；详见 `AUDIT-2026-10-22-UX.md` |
| 第二十六轮 | R-33 F-01 实时主题切换修复 | 已完成（浅→深→浅实机通过）；全量 428 分批通过；自检宿主本轮窗口未创建 |
| 第二十七轮 | R-34 F-08 批量重命名目录/尾点修复 | 已完成（4 条纯函数测试；只处理文件、空扩展名不加点、尾点清理）；窗口实机触发受菜单焦点限制 |
| 第二十八轮 | R-35 F-02 详情栏 1–4 列流动布局 | 已完成（1 条新增回归 + 1 条既有断言改口径）；全量 16 批 **435 条 0 失败**；自检 153 通过 / 0 失败 + 布局压力 20 轮 0 失败；实机 3 种宽度全部字段可见、无内部滚动条 |
| 第二十九轮 | R-36 详情栏重做：液态玻璃 + 三档拉手 + 完整内容 | **已实现（最终 Debug 0.8.0-26102403；证据 26102402；桌面副本已覆盖 26102403）**：10 项决策锁定；详情三组 33 条 0 失败；全量 472 条 470 通过 / 2 条环境失败（外部卷 EINTR + 既有删除通知 flaky）；真机三态/图标 200/右键菜单/AX 调档/避让已取证；连续拖拽手感、捏合、深色玻璃待人工 |
| 第三十轮 | R-37 工具模块合并到底栏 | **已被 R-38 取代（历史）**：第一版 36pt 圆钮 + 双列文字工具栏被用户判定理解错误；Debug 0.8.0-26102405 实现仅作历史，不再代表目标 |
| 第三十一轮 | R-38 药丸详情栏 + 独立圆形工具簇（推翻 R-37） | **已实现（Debug 0.8.0-26102408；`make build` 自动备份 26102407 并覆盖/重启桌面副本）**：默认 54pt 药丸（半径 27）+ 54pt 圆扳手同高同心；展开 132/240 **卡片（12pt 圆角）**、内边距 30/52 并自动隐藏按钮；点击拉手或药丸/卡片空白切换；工具态详情缩 left 8 的 54 圆、工具变 N 个独立 54pt 玻璃圆右对齐紧贴 54pt ×；仅列当前可用的文件工具 3/4/1（设置/关于不进入工具簇）；执行回默认；选中/目录/活动面板变化只刷新不关闭；窄面板 8→2→横向滚动；新增 `FFDetailsPillTests` 4 条 + 重写 `FFToolsBarV2Tests` 12 条；定向 48 条 0 失败、Rust 200/0；真机窗口 26221 截图 9 张（`docs/images/audit-2026-10-24-pilltools/`），物理点击工具钮/×通过；全量数字见 HANDOVER §1.32 |
| 第三十二轮 | R-39 任务按钮注水 + 弹性开合动画 | **已实现（Debug 0.8.0-26102409；`make build` 自动备份 26102408 并覆盖/重启桌面副本）**：有任务记录时右侧 54pt 工具钮换任务图标（点击仍开工具簇），默认钮与簇内任务中心圆共用图标注水进度；进度 = 活动任务平均，无活动但有记录=100%，无记录=0；任务中心仅在有任务时出现，无任务 2/3/0、有任务 3/4/1；圆钮按下/松开弹簧、详情栏 0.34s 宽度收缩成 54 圆、工具圆从 × 侧 stagger 滑出、详情栏 0.36s 过冲展开、关闭 0.26s；减弱动态跳变；新增 `FFTaskButtonTests` 3 条 + 形变收敛测试 1 条；全量 542/0；真机动画因 TCC 弹窗未完成目视/录屏，标未验 |
| 第三十三轮 | 2026-10-25 侧栏/搜索真机审计 + 两个导航缺陷修复 + 剩余项收口（26102501） | **已完成（自动化 + 真机）**：修复收藏复点无效、清空搜索后 Return 误入首项；新增 1 条回归单测（单跑 0.914s 通过；全套未重跑）；补验六个收藏、侧栏拖宽、标签新建/改色/删除、收藏右键 6 项、双栏/本栏搜索；未修发现：详情栏残留已删项（第二次复现）、末项「下移」未置灰 |

自检总量：**153 项 + 20 轮布局压力 0 失败**（2026-10-24 在 26102406 复跑；26102407–26102501 未重跑自检）。
Swift XCTest 当前全量基线：**542 条 0 失败**（2026-10-24 R-39 实测；跳过 2 条既有环境测试，详见 HANDOVER 顶部）。2026-10-25 仅新增 1 条回归单测并单跑通过（0.914s），**全套未重跑**，不抬高总数。历史：2026-10-23 接手轮 **516 条**、2026-10-22 第二十八轮 **435 条** 均为当轮实测值。
布局压力自检 **20 轮 0 失败**（2026-10-24 当轮实测值）。

| 层 | 项数 |
|---|---|
| 决策表穷举 | 71（区域 4 × 状态 16，含把手仲裁维度） |
| 区域解析 | 7（含调宽把手 Y 排除、卡片留白改面板区） |
| 拖动行为 | 4 |
| 标签焊接 | 35（A1 背板接线、＋/× 中心线） |
| 侧栏隐藏避让 | 5（第十三轮删顶栏工具键后由 6 降为 5） |
| 面板宽度 | 9 |
| 列表与外壳 | 22 |
| 落点状态机 | 10（摘标签 / 并入 / 单栏右半拆双栏 / 搬空判定 / 搬空折叠 / 拖出新窗单栏 / 无效落点 / 目标单栏拆双栏 / 最后标签 / 跨窗口标签条） |

> 自检数字随自检覆盖的路径变化：第六轮是 129（6 步落点 + 19 焊接），
> 第七轮扩到 10 步落点并把焊接自检固定为双标签环境，合计 135。
> 只认当次日志实数，不复用旧文档里的数字。

> **验证手段分级**（本台账所有「验证」列都按此标注）：
> 【断言】= `FF_SELFTEST` 应用内断言；【实机】= 真机截图 / 几何日志 / 合成事件；
> 【未验】= 代码在、但没有任何执行证据。

---

## 1. 十项需求逐条台账

### R-01 拖动模型（标签级 · 支持跨窗口）

| 项 | 内容 |
|---|---|
| 需求原文 | 按住操作面板拖动不能拖走窗口；单窗口多标签时标签拖出、再拖入应变成双窗口 |
| 拖的对象 | **标签**（第四轮定）。跟手的是 1:1 标签浮层 |
| 落点分流 | 标签条 → 并入该面板；操作区 → 单栏拆出第二面板（窗口自动加宽）/ 双栏并入该侧；窗口外 → 独立成新窗口 |
| 源窗口 | 面板被搬空自动关窗 |
| 实现位置 | `UI/FFPaneDrag.swift`、`UI/MainWindowController+Tabs.swift`（`takeTabOut` / `transferTab` / `acceptTab` / `detachTabToNewWindow`） |
| 验证 | 【断言】落点状态机 4 项（摘标签 / 并入标签条 / 拆出第二面板 / 搬空判定）全 PASS<br>【实机】「拖出成新窗口」已观察到发生（窗口列表出现第二个 FlowFinder 窗口）<br>【未验】**拖回变双栏、跨窗口落点高亮、条内重排的手感**——合成事件在本机受三重干扰（CGEvent y 为屏幕顶部原点、TCC 弹窗、其它窗口遮挡），未能可靠驱动 |
| 审计发现并已修 | `isOutsideStripBuffer` **坐标系混用**：拿窗口坐标（y≈864..900）与屏幕坐标（y≈1028）比较，缓冲判定恒为「已出条」→ 条内重排完全失效。已改为先 `window.convertPoint(fromScreen:)` 再比较 |
| 第五轮 C 校准 | 用户实测「拖回结果不对 + 新面板位置不对」，逐条确认后修三处：① 单栏拖入时**新面板按落点侧**（拖右出右、拖左出左，窗口向该侧加宽、贴屏幕边保护；旧实现固定出在活动面板对侧）；② 同窗口拖空源面板 → **面板折叠、窗口变单栏**（旧实现留空占位）；③ 加宽几何重写（目标宽 = 侧栏 + 操作区×2 + 留白，钳制到屏幕内，只改宽度不动高度——修掉 2015×622 异常尺寸） |
| 验证 | 【断言】落点状态机 6 项（摘标签 / 并入标签条 / **落点侧新面板** / 搬空判定 / **搬空折叠** / **拖出新窗为单栏**）全 PASS<br>【断言】XCTest 7 条锁定占位清理与缓冲重排<br>【未验】物理拖拽手感仍需人工确认（环境三重干扰，见「已知限制」） |
| 状态 | 已完成（模型、代码与断言齐；**物理拖拽手感待人工复验**）。第七轮已按路线 B 重做落点/性能，见 R-14 |

### R-02 单双面板切换动画

| 项 | 内容 |
|---|---|
| 需求原文 | 切换单/双面板要平滑，带弹性 |
| 落地 | 0.36s、`CAMediaTimingFunction(0.32,1.28,0.48,1)`；窗口宽度用 `NSAnimationContext` 同曲线插值；contentView 叠一层 opacity 关键帧（1→0.72→1）做「推挤 + 回弹」观感 |
| 实现位置 | `UI/FFPaneModeAnimator.swift`；`MainWindowController.handlePaneModeToggle` + `resizeWindowKeepingSidebar`（`isAnimatingPaneMode` 分支） |
| 验证 | 断言时长常量 0.36s；实机切换观察窗口宽度过渡 |
| 未做到的 | **面板本身没有位移动画**。面板显隐是 `NSSplitView` 的 arranged subview 增删，NSSplitView 不参与隐式动画 |
| 本轮裁定 | 用户选了「**真位移（自管布局）**」：放弃 NSSplitView 自己排两块面板的 frame，拖边调宽与宽度记忆一并重写。**本轮未实施**（改动面覆盖整个分栏体系，单独一轮做） |
| 状态 | 部分完成 |

### R-03 列表四列与可选列

| 项 | 内容 |
|---|---|
| 需求原文 | 恢复四列（名称、类型、大小、修改时间），另加可选列（创建时间、标签、文件说明、注释），三个入口 |
| 列定义 | `name` / `kind` / `size` / `modified`（默认四列）+ `created` / `tags` / `comment`（可选） |
| 实现位置 | `UI/FFListColumns.swift`（列定义、可见性与列宽持久化、菜单构建、Finder 说明缓存）<br>`UI/FileListView.swift`（`rebuildColumns()`、`applyColumnFit()`、`viewFor` 分列渲染）<br>`UI/MainMenu.swift`（显示 → 显示列）<br>`UI/PaneToolbar.swift`（工具菜单 → 显示列）<br>列头右键：`tableView.headerView?.menu`（同一份菜单） |
| 列宽策略 | **先缩后排**：先按列宽把各列压到 `minWidth`，压到最小仍放不下才整列收起。收起顺序 说明 → 标签 → 创建日期 → 类型 → 大小 → 修改日期，名称永不收 |
| 持久化 | `list_visible_columns`（字符串数组）、`list_column_widths`（字典） |
| 说明列 | 走 Spotlight `kMDItemFinderComment`，`FFFinderCommentCache` 后台读取 + 缓存；未命中先显示「—」 |
| 验证 | 22 项列表自检：默认四列、必选列不可关、翻转可见性、收起顺序、排序键、**可选列经真实 `viewFor` 渲染出非空文本**；截图确认四列与列头完整 |
| 状态 | 已完成 |

### R-04 隐藏侧栏后红绿灯与标签条对齐

| 项 | 内容 |
|---|---|
| 需求原文 | 隐藏侧栏后红绿灯要右移，与标签条共线；标签条要避让 |
| 实现位置 | `UI/SidebarView.swift`（`alignTopControlsWithTrafficLights`：控制行 top 由 zoomButton 中心反算）<br>`UI/MainWindowController.swift`（`applySidebarHiddenToolbarInset` 与 `updateTabStripFrames` 共用 `FFInteractionPolicy.titleContentInset`） |
| 避让量 | 侧栏可见 → 8（贴卡片左缘）；隐藏 → 106（红绿灯 70 + 浮动开关 96 + 10） |
| 验证 | 几何日志：隐藏侧栏后左标签条 `x=106`，与红绿灯/开关零重叠；截图核对 |
| 状态 | 已完成 |

### R-05 窗口圆角

| 项 | 内容 |
|---|---|
| 需求原文 | 窗口圆角要和面板同一套曲线（超椭圆），半径 12 |
| 实际做法 | `CALayer.cornerRadius = 12` + `cornerCurve = .continuous`（Apple 自家的连续曲率圆角，与面板 squircle 同族）；`NSVisualEffectView` 外套一层 `FFWindowRootView` 承载圆角 |
| 实现位置 | `UI/FFWindowShape.swift`（`install` / `update` / `FFWindowRootView`）；`MainWindowController` 里随窗口尺寸与全屏进出刷新 |
| 走过的弯路 | 先用 `SquircleView.squirclePath` 做 `CAShapeLayer` 遮罩——**实测整窗内容区渲染成空白**（只剩红绿灯），换容器承载同样空白。因此改用连续曲率。细节记在文件头注释 |
| 验证 | 断言 `cornerRadius == 12` 且 `cornerCurve == .continuous`；截图确认内容正常、四角圆滑 |
| 状态 | 已完成（曲线用连续曲率近似超椭圆，不是路径级 squircle） |

### R-06 侧栏位置区与收藏区图标 18pt

| 项 | 内容 |
|---|---|
| 需求原文 | 位置区、收藏区图标统一 18pt、线宽 1.75 |
| 实现位置 | `UI/SidebarView.swift`：新增 `SidebarMetrics.rowIconSize = 18`，行图标约束改引用该常量（原 20pt） |
| 线宽 | 图标是 SVG 资源按尺寸渲染，线宽烘焙在资源里，**没有可调参数**；只能改尺寸 |
| 验证 | 截图核对图标包围盒；与 13pt 文字重心 |
| 状态 | 部分完成（尺寸已改，线宽不可参数化） |

### R-07 三个控制图标 16pt

| 项 | 内容 |
|---|---|
| 需求原文 | 隐藏侧栏 / 主题 / 单双窗三个图标 16pt，右缘距侧栏右边 12pt |
| 实际做法 | 图标 15 → **16pt**；位置**拆成两组**（第四轮裁定）：隐藏侧栏紧跟红绿灯（与窗口控制同组），主题与单双窗靠侧栏右缘（右缘距 12） |
| 实现位置 | `UI/SidebarView.swift`：`topControlsRow` 只放隐藏侧栏按钮；新增 `rightControlsRow`（主题 + 单双窗），trailing −12，与控制行垂直居中 |
| 验证 | 截图核对两组图标位置与红绿灯的垂直关系 |
| 状态 | 已完成 |

### R-08 移除分隔发光条 + 面板边缘调宽（含第五轮手感修复）

| 项 | 内容 |
|---|---|
| 需求原文 | 去掉双面板中间的发光条；改用面板边缘拖动调宽 |
| 实现位置 | `MainWindowController.swift` 的 `FFSplitView`（`handlePositionsProvider` / `handleCursor` / `grabOffset` / `applyDividerPosition`）：把手贴在卡片外沿，热区内按下即 1:1 跟随 |
| 宽度语义 | 左面板左缘调侧栏宽；中缝左宽右窄（窗口总宽不变）；上下边缘不响应 |
| 持久化 | `sidebar_width` + `pane_left_width`；拖动期间不写盘，松手由 `onResizeDragEnded` 补写 |
| 第五轮：手感修复 | 用户确认症状「A 窗口跟跑 + D 迟滞」。根因是**设计层冲突**：卡片 8pt 留白同时是「拖窗口」（§1.8）与「调宽把手」（本条），两套手势在同一块区域打架——monitor 判拖窗口放行事件，事件沿响应链又触发 `FFSplitView` 调宽，窗口与分隔线同动 |
| 仲裁（用户裁定 A） | **卡片留白只做调宽**。落地：决策表新增 `onResizeHandle` 维度 + `.resizeDivider` 意图（放行、monitor 不参与），规则「把手→调宽」优先于一切；拖窗口白名单删去「卡片留白」 |
| 顺带修掉 | ① 把手命中只看 X → 点缝隙附近的标签误判成调宽，限定标题带以下；② NSSplitView 是翻转坐标系，第一版 Y 守卫方向写反；③ 拖动期间每帧写 UserDefaults |
| 验证 | 【断言】决策表穷举 71 项（区域 4 × 状态 16 + 规则可达性）全 PASS；区域自检 7 项含「标题带内缝隙 X 不命中 / 标题带以下命中」<br>【未验】**实际拖动的手感**需人工确认（拖中缝 → 只有边缘动、窗口不动；拖侧栏缝 → 侧栏宽变化、窗口不动） |
| 状态 | 已完成（代码与断言）；**手感需人工复验** |

### R-09 激活发光淡化

| 项 | 内容 |
|---|---|
| 需求原文 | 发光太抢眼，峰值降到 0.07，层数与扩散不变 |
| 实现位置 | `UI/FFComponents.swift`（`FFActivePaneBorderView.draw`：14 层同心描边，`alpha = 0.055 * boost * (1 - t*0.72)`） |
| 验证 | 截图对比；峰值 0.055 ≤ 0.07 |
| 状态 | 已完成 |

### R-10 列表行垂直中线对齐

| 项 | 内容 |
|---|---|
| 需求原文 | 图标 / 名称 / 类型 / 大小 / 时间共用同一条水平中线（不是列内水平居中） |
| 实现位置 | `UI/FileListView.swift`：名称列图标与文字改 `centerYAnchor`（原为顶部 4pt 对齐，只在 26pt 行高下恰好等于居中）；元信息列统一 `configureTextCell`，全部 `centerY` + 语义对齐（`size` 右对齐，其余左对齐） |
| 验证 | 自检断言 `usesSharedRowMidline`；截图看图标与文字、各列数值同一中线 |
| 状态 | 已完成 |

### R-11 点击失效修复（2026-10-20 第四轮，最高优先）

| 项 | 内容 |
|---|---|
| 症状 | ① 应用内点文件、点工具栏按钮、点侧栏行全没反应；② **切到别的 App 也点不动**，要再点一下才恢复 |
| 根因 1 | `.pressFeedback` 意图在 `handleDown` 里 **返回 nil**，把 mouseDown / mouseUp 都吞了。决策表把「工具栏 / 文件列表 / 侧栏行」全映射到 pressFeedback → 所有控件点击失效 |
| 根因 2 | 同上：press 模式下每一次点击的 mouseDown 都被吞。指针拖出窗口外松手时 mouseUp 不回到本应用 → 系统认为鼠标仍按着 → 整个系统的点击都被当作拖拽续接 |
| 根因 3 | `FFPaneDragController` 是全局单例但 `install(for:)` 由每个窗口调用 → 第二个窗口把 `self.window` 覆盖，只有最后创建的窗口被接管，其余窗口的点击与拖动全部失灵 |
| 修法 | press 反馈**不再消费事件**（视觉下沉照做，事件原样放行）；事件按 `event.window` 路由到对应宿主（单一 app 级 monitor）；拖动**不消费 mouseDown**，保住 AppKit 的鼠标归属，mouseUp 一定回来；监听 `didResignActive` 复位拖拽状态并补发 mouseUp |
| 为什么不能靠全局监视器 | `NSEvent.addGlobalMonitorForEvents` 需要辅助功能权限，本机未授予 → 事件根本收不到（已实测）。因此改走「不消费 mouseDown」这条路 |
| 验证 | 【实机】点击侧栏行 → `loadDirectory` 导航到目标目录（修复前点击无任何响应）；点击列表行 → `selectionDidChange` 触发；【断言】自检 0 失败。**「切到别的 App 也点不动」的恢复路径未实测**（无法在合成事件里安全复现卡死状态） |
| 第五轮修订 | 「拖窗口白名单」中的**卡片 8pt 留白**一项作废（与调宽把手冲突，仲裁为只做调宽，见 R-08）。拖窗口 = 侧栏空白 + 标签条空白 |
| 状态 | 已完成（应用内点击有实机证据；系统级恢复路径靠代码审查 + 失焦复位兜底） |

### R-12 启动卡顿（渲染不等标签）

| 项 | 内容 |
|---|---|
| 症状 | 应用启动后列表长时间空白（主线程卡在 `getxattr` 1–2 分钟，`sample` 实测） |
| 根因 | `warmCache` 已在后台预热标签，但**渲染与预热抢跑**：渲染时缓存还没热，`getTags` 退化成同步 xattr I/O，22 个条目就能把主线程堵住 |
| 修法 | 渲染路径改用 `TagBridge.cachedTags(path:)`（只读缓存、不做 I/O）；预热完成后发 `.ffTagCacheWarmed` 通知，列表据此整表刷新一次（此时全部命中缓存） |
| 代价 | 标签色点晚一帧出现 |
| 实现位置 | `Bridge/TagBridge.swift`（`cachedTags` / `warmCache(paths:completion:)`）、`Model/PaneState.swift`（预热完成广播）、`UI/FileListView.swift`（`tagCacheWarmed`） |
| 验证 | 【实机】冷启动 → `mode=content` **4 秒**（修复前主线程卡 `getxattr` 1–2 分钟）；列表行正常渲染 |
| 状态 | 已完成 |

### R-13 第六轮回归修复与 XCTest 护栏（2026-10-20）

用户实测反馈四个回归；**先写测试观察失败，再改实现**。XCTest 通道实测可用：
144 → 162 条，修前 19 处失败，修后全绿。

| # | 回归 | 根因 | 修法 | 护栏 |
|---|---|---|---|---|
| 1 | 单标签拖回自己的标签条 → 「占位 + 标签」两个 | `PaneTabsStore.add/insert` 不清理只剩占位的列表 | `removeLonePlaceholder()`：真实标签进来前清掉占位 | `PaneTabsStorePlaceholderTests` 4 条 |
| 2 | 拖出的新窗口继承双栏模式，右侧多一个空占位 | `detachTabToNewWindow` 默认初始化读全局 `single_pane_mode` | 指定 `startsWithSinglePane: true`，装配完再显示；`runsSelfTests: false` 防自检递归 | 自检 ⑥ |
| 3 | 缓冲内重排失效 / 指示线错位 | stack / strip / window 三套坐标混用 | 抽出纯函数 `FFTabReorder.insertionIndex`，命中与指示线统一转 strip 坐标 | `FFTabReorderTests` 3 条 |
| 4 | 侧栏行、标签条按钮、发现药丸点不动 | 控件在 `.window` / `.title` 内被翻译成 `dragWindow` | `NSControl` / 点击手势只在这两个区域短路；`FFPillButton` 声明 `.panel` 且 `hitTest` 返回自身 | `FFAreaResolverControlTests` 6 条 |

顺带修掉：

- 按压反馈固定作用在左卡片 → 改为按命中视图反查 `paneSide(containing:)`
- 窗口拖动无阈值、点击被当成拖动 → 4pt 阈值；未超阈值时 mouseUp 放行
- 标签拖拽起手 `currentInsertionIndex` 未初始化 → 起手即设为源 index

另有 `FFInteractionPolicyTests` 5 条锁定决策表既有行为（缓冲内重排 / 出缓冲搬标签 /
标题与窗口拖动 / 面板按压 / 把手优先），与上表合计 18 条。

验证：

- `make swift-test`：**162 条 0 失败**（修前 19 处失败）
- `FF_SELFTEST=1`：**129 项 0 失败**
- 【未验】桌面副本上的控件点击与物理拖拽手感

状态：已完成（代码 + XCTest + 应用内断言）；人工手感待复验。

### R-14 第七轮：标签拖拽重做（路线 B，2026-10-20）

用户实测反馈「拖标签/拖窗口严重卡顿」「标签拖拽被改废了」。审查后确认是行为、测试、性能三层问题叠加。

| 项 | 内容 |
|---|---|
| 行为根因 | `operationSide()` 单栏直接返回 `activePane`（落点走错侧）；`acceptTabIntoPane()` 用 `replaceAll([session])` 覆盖活动面板（丢兄弟标签）；自检 ③ 直接传 `side:` 绕过真实判定 |
| 性能根因 | 插入线每事件改 Auto Layout 约束 → 整窗布局 → `FileListView.layout → applyColumnFit → rebuildColumns`；每事件全窗 hitTest / 浮层 / 高亮；窗口逐事件 `setFrameOrigin`；`updatePaneUI` 每次状态发射 reload 两个列表 + 同步 `attributesOfFileSystem`；每窗口鼠标监视器 deinit 不移除 |
| 实现 | 新增 `FFDropResolver`（纯落点）、`FFDragGeometryCache`（屏幕坐标几何）、`FFDragOverlay`（frame-based 浮层）；`FFPaneDrag` 接 60Hz 帧调度；窗口拖动改 `performDrag`（`FF_NATIVE_WINDOW_DRAG=0` 回退）；`FileListView` 宽度守卫；`PaneState` reload 策略；`applicationShouldHandleReopen` |
| 已确认语义 | 单栏右半拆双栏、原面板保留其余标签；目标单栏拆双栏、目标标签完整保留；无效落点回原位；最后标签可拖出、无窗口时 Dock 重开；跨窗口标签条按指针左右半插入 |
| 验证 | 【断言】XCTest **190 条 0 失败**；`FF_SELFTEST=1` **135 项 0 失败**（拖拽 10 + 决策表 71 + 区域 7 + 行为 4 + 焊接 21 + 外壳 22）<br>【未验】真实拖拽 60fps 采样；活动标签浮层/窗口拖动手感（合成事件在本机仍不可靠） |
| 回退 | `FF_NATIVE_WINDOW_DRAG=0` 启动，窗口拖动走 60Hz 合并的自管路径 |
| 状态 | 已完成（自动化）；**人工手感/60fps 待复验** |

### R-15 第八轮：UI/UX 与结构整改（UIUX-REDO，2026-10-21）

用户要求站在普通用户角度重审整个应用，对标 Finder/Explorer/开源文件管理器，
并用 UI/UX Pro Max、superpowers、TDD 与可视化逐项确认。决策 D-01..D-12 见
`SPEC-2026-10-20-UIUX-REDO.md`，实施计划见 `PLAN-2026-10-20-UIUX-REDO.md`。

| 决策 | 落地 | 验证 |
|---|---|---|
| D-01/D-02 产品身份与插件边界 | `FFTool`/`FFToolRegistry`/`FFToolContext`，内置工具注册；第三方安装未做 | `FFToolRegistryTests` 4 条 |
| D-03 工具入口留在侧栏品牌区 | `SidebarView` 药丸 → `FFToolPopoverController`，显示活动面板/路径/选择 | 真机未验（屏幕锁定） |
| D-04/D-06 安静原生双栏与视觉语言 | `FFVisualTokens`、2px 活动边、统一 28pt 状态栏、标准标签、单行工具栏 | `FFVisualTokensTests`/`FFShellLayoutTests`/`FFAccessibilityTests` |
| D-05 Finder 快捷键 + 活动面板 | `FFKeyboardContract`；⌘1/⌘2 聚焦面板、⌥⌘1/⌥⌘2 视图；`FFShortcutSettings` 冲突检测 | `FFKeyboardContractTests`、`FFShortcutSettingsTests` |
| D-07 状态栏 + 按需详情 | `FFStatusBarText`、`FFStatusBarView`、`MetadataService`、⌘I popover | `FFStatusBarTextTests`、`FFMetadataServiceTests`、`FFDetailsIntegrationTests` |
| D-08 标准原生标签 | `PaneTabs` 原生样式、单标签保留、关闭按钮 20×20 | `FFShellLayoutTests` |
| D-09 单一 activePane | `WindowFocusModel` + `PaneCoordinator`；菜单/状态栏读同一真值 | `PaneStoreTests`、`FFActivePaneIntegrationTests`、`FFShellCoordinatorTests` |
| D-10 原地绞杀 | 分片接缝：tokens → PaneStore/focus → 渲染守卫 → 详情 → 工具 → 任务 → coordinators | 258 条 XCTest |
| D-11 性能门槛 | 选中不 reload；签名比较；标签计数门控；任务发布门控；异步 FFI；缩略图 hash 缓存；signposts | 自动断言；**交互采样未做** |
| D-12 标签不隐藏 | 单标签保留轻量标签 | `FFShellLayoutTests` |

**安全默认**：冲突默认 `.skip`；查重结果零勾选（新增「选择重复项」显式操作）；
永久删除二次确认且文案明确不可撤销；设置页移除死开关，新增「删除前确认」。
`FFDestructivePolicyTests` 3 条覆盖。

**结构**：新增 `PaneStore`、`WindowFocusModel`、`PaneCoordinator`、`ToolCoordinator`、
`TaskCoordinator`、`SidebarCoordinator`、`WindowShellCoordinator`、`FFTaskService`；
退役 `FFDiscoverPanel` 枚举/控制器（保留并重命名 `FFPillButton.swift`）。
MainWindowController 仍持有布局/拖拽/标签装配，属后续搬迁项。

| 验证 | 结果 |
|---|---|
| `make build` | BUILD SUCCEEDED |
| `make swift-test` | **258 条 0 失败** |
| `FF_SELFTEST=1` | **135 项 0 失败** |
| 视觉 | **部分验证（1400×900 浅色）**：双栏、单↔双、⌘I 详情、工具 popover、设置、搜索；发现并修复 4 个可见问题（单→双面板 0 宽、搜索框裁切、辅助窗口 ⌘W、状态栏重复「可用」/文件夹“计算中”/日期语言） |
| 性能采样 | **部分验证**：`sample` 5 秒主线程均在事件循环/菜单跟踪，无应用侧长栈；精确门槛（选中 <50ms、首屏 <300ms、60fps）未测 |
| VoiceOver | **未验**：自动测试覆盖 label/hit target/对比度，人工走查待补 |
| 深色/高对比/1060×700 | **未验** |

| 状态 | 自动化已完成；视觉、性能、VoiceOver 人工验收待补 |
|---|---|

### R-16 第九轮：双操作区结构回归（2026-10-21）

用户真机验收后判定 UIUX-REDO 的结构改造失败：单行工具栏、全局底栏、独立详情浮层破坏了双操作区独立性。
按 `SPEC-2026-10-21-LAYOUT-ROLLBACK.md` 与 `PLAN-2026-10-21-LAYOUT-ROLLBACK.md` 执行结构回退。

| 项 | 决策 / 实现 | 验证 |
|---|---|---|
| D-01/D-02/D-03 | 双操作区、每侧两行工具栏、区内 54pt 详情栏；移除全局底栏 | `FFShellLayoutTests`、`FFDetailsIntegrationTests`、真机截图 |
| D-04/D-10/D-11/D-15 | 三边微光、上边留空、blur 9 / opacity .50 / fade 42%；颜色跟强调色；采用 `FFPaneGlow` 原生阴影，不再描边 | `FFGlowSpecTests`、真机截图 |
| D-05/D-14 | 保留 PaneStore/MetadataService/TaskService/工具/异步 FFI/安全默认 | 全量 XCTest/自检 |
| D-06/D-09 | 详情栏 54pt、⌘I 展开当前面板；无独立 popover | `FFDetailsIntegrationTests` |
| D-07/D-08 | 第二行应用级逐项开关、默认全开、齿轮常驻 | `FFToolbarPreferencesTests`、真机 |
| D-12 | `FFAccent` 单一来源；迁移清除旧粉色；默认系统强调色 | `FFAccentSourceTests`、`FFAccentSelectionTests` |
| D-13 | 保留上下文工具浮层 | 真机 |

**退役**：`FFStatusBarView`、`FFStatusBarText`、`FFDetailsPopoverController` 及对应旧测试。
**测试**：**258 条 0 失败**；自检 **135 项 0 失败**（2026-10-21）。
**未验**：1060×700、深色/高对比/Reduce Motion、VoiceOver、精确性能数值。
**状态**：已完成（自动化 + 1400×900 浅色真机走查）；其余人工验收待补。

### R-17 第十轮：UI/UX 全界面精修（2026-10-21）

规格 `docs/SPEC-2026-10-21-UIUX-POLISH.md`，计划 `docs/PLAN-2026-10-21-UIUX-POLISH.md`。
全部改动留在工作区，**未提交、未推送**。

| ID | 决策 | 实现落点 | 验证 |
|---|---|---|---|
| U-01 | 两张独立面板卡片，统一连续曲率 | `SquircleView` / `FFGlassView.cornerCurve` / `MainWindowController` | `FFRadiusTokensTests` |
| U-02 | 窗口 12 / 面板 12 / 详情 8 / 控件 6 | `FFVisualTokens.Radius`、`DesignTokens.Glass`、`ExpandableDetailsBar`、`FFPaneGlow` | `FFRadiusTokensTests`（3） |
| U-03 | 紧凑详情 inspector，默认 120pt、上限 45%（≤260）、溢出滚动 | `ExpandableDetailsBar`、`FFDetailsLayoutPolicy`、`FFDetailsFlowLayout` | `FFDetailsLayoutTests`、`FFDetailsBarLayoutTests`、`FFDetailsBarTypeRowsFlowTests` |
| U-04 | 详情预览图标应用级滑块 48–96（默认 64），信息随宽度自适应 | `FFDetailsLayout`、`ExpandableDetailsBar.applyPreviewIconSize`、设置 > 外观 | `FFDetailsLayoutTests`（6），真机滑块 |
| U-05 | 工具浮层分组；标题仅“工具”；默认作用活动面板；上下文提示 | `FFToolGroup`、`FFToolRegistry`、`FFToolPopoverController` | `FFToolRegistryTests`（6），真机浮层 |
| U-06 | 搜索独立窗口 + 中心空态 + 主 CTA“构建内容索引” | `SearchPanelController.makeEmptyStateView`、`updateEmptyState` | `FFSearchEmptyStateTests`，浅/深色截图 |
| U-07 | 查重条件 / 结果 / 预览 / 动作四段 | `DuplicateScanWindowController`、`DuplicatePreviewPanel` | `FFDuplicateLayoutTests`，浅/深色截图 |
| U-08 | 全部辅助界面纳入 | 搜索/查重/设置/批量重命名/任务中心 | 真机走查 |
| U-09 | 冲突默认“跳过”；替换危险色且置末 | `FFConflictPolicy.buttonOrder`、`ConflictResolver` | `FFDestructivePolicyTests` |
| U-10 | 设置/批量重命名只做 token 对齐 | `SettingsSectionView` 圆角 8、批量重命名 16pt 边距 | 真机走查 |
| U-11 | 标签关闭视觉 20 / 命中 24；侧栏最小 180 | `FFTabMetrics`、`FFTabCloseButton`、`MainWindowController.sidebarMinWidth` | `FFShellLayoutTests` |
| U-12 | 保留原生阴影微光，不描边 | `FFPaneGlow`、`FFGlowSpec` | `FFGlowSpecTests`，真机截图 |
| U-13 | 深色/高对比/Reduce Motion 验收修正 | `FFSolidSurfaceView`、`FFMotion`、动态系统色 | 浅/深色真机走查、`FFAccessibilityTests`、`FFVisualTokensTests` 对比度 |

**本轮额外修复**

- 旧粉色 `#ff375f` 在迁移键已置位后仍残留：改为每次启动检查“用户是否显式选色”，旧默认色清除，显式选择保留。
- 右键菜单“显示简介”抢占 ⌘I，实际弹出旧独立窗口：移除该菜单项键位，⌘I 回到区内详情栏。
- 辅助窗口单例复用后静态 `cgColor` 不随主题刷新，搜索窗口出现白底白字：新增 `FFSolidSurfaceView`，在窗口迁移/布局/外观变化时按有效外观重新解析背景与边框。
- 辅助窗口（设置/搜索/查重/批量重命名/任务中心）响应 ⌘W 关闭自身。

**验证**：`make build` BUILD SUCCEEDED；XCTest **282 条 0 失败**；`FF_SELFTEST=1` **135 项 0 失败**（2026-10-21）。
浅色与深色主窗口、详情栏、工具浮层、搜索、查重、设置真机走查通过；浅/深/高对比主文本对比度由 `FFAccessibilityTests` 自动验证。
**未验**：高对比模式逐屏截图（对比度已自动测试）、VoiceOver 完整走查、1060×700 全屏截图。

**P-01 圆角回归修复（2026-10-21 追加）**

真机像素扫描确认：左面板左上/右上直角、右面板左上圆角但右上直角。根因是 `SquircleView` 未裁切内容，工具栏/列表整幅背景盖住圆角。新增 `FFPaneContentClipView`（12pt 连续曲率、`masksToBounds`），工具栏/列表/网格进入裁切层；外层卡片保留背景与微光，详情浮层留在裁切层外。`FFShellLayoutTests` 新增 1 条结构回归；自检改用 `leftFileListView` 恢复区域/行为/外壳覆盖。
验证：XCTest **282 条 0 失败**；自检 **135 项 0 失败**；真机截图四角一致。

**P-04 1060 宽度（2026-10-21 追加）**：`minPaneWidth` 450→400，split view 两处硬编码 450 改为常量；窗口最小宽保留 1060×700。新增 `FFShellLayoutTests` 2 条宽度约束测试；真机 1060 截图待补。

**状态**：已完成（自动化 + 浅/深色真机走查）；上述三项人工验收待补。

### R-18 第十一轮：0.8.0 Beta 顶栏与交互修复（2026-10-21）

规格：`SPEC-2026-10-21-UI-FIX-BETA.md`；计划：`PLAN-2026-10-21-UI-FIX-BETA.md`。
版本裁定：**0.8.0 (8001) Beta**（用户明确纠正，不是 0.9.0）。

| ID | 决策 | 实现 | 验证 |
|---|---|---|---|
| D-01 | A1 焊死标签：30pt 标题带；活动 28 / 非活动 24；全部中心线 16pt；9pt 内凹肩线；无下划线/整圈描边 | `FFInteractionPolicy`、`PaneTabStripBackdrop`、`FFTabSilhouette`、`PaneTabItemView` | `FFTopBarLayoutTests` 5；WELD 35（含背板可见/填色、＋/× 中心） |
| D-02 | 顶栏图标：侧栏三图标 24pt 命中 / 16pt 线性 / 4pt 间距 / hover；＋ 13pt、× 10pt，均 24pt 命中 | `FFHoverIconButton`、`SidebarView.makeSidebarIconButton`、`PaneTabStripView` | 编译 + WELD 中心线；hover 目测待用户 |
| D-03 | 隐藏侧栏：首个标签左缘 112（容器 78）；动画结束与分栏变化后重算 | `FFTabStripLayout`、`MainWindowController.setSidebarVisible`、`splitViewDidResizeSubviews` | AVOID 4（首标签 112、容器 78、>102、仍 28pt） |
| D-04 | 系统红绿灯关闭：mouseDown 监视器先放行标准窗口按钮 | `FFWindowChrome`、`FFPaneDragController.handleDown` | `FFWindowChromeTests` 3；物理点击关闭成功（日志 `[WINDOWCHROME]`，窗口数 1→0，进程存活） |
| D-05 | 同目录拖放完全无操作：同父目录/自身/子目录过滤 | `FFFileDropPolicy`、`FileListView.validate/acceptDrop`、`FileGridView` | `FFFileDropPolicyTests` 7；真实拖拽手感待用户 |
| D-06 | 0.8.0 (8001) Beta；侧栏版本 + 关于页构建时间/路径 | pbxproj、`FFBuildInfo`、`SidebarView`、`SettingsWindowController` | `FFBuildInfoTests` 2；AX 读到 `0.8.0 (8001) Beta` |
| D-07 | 同 Bundle ID 多进程启动提示 | `FFInstanceGuard`、`AppDelegate.warnIfAnotherInstanceIsRunning` | `FFInstanceGuardTests` 2；双开实测日志 `[INSTANCE]` 返回 1000 |
| D-08 | 删除全部 8 个旧副本（移入废纸篓） | 清单 `/tmp/ff-old-builds-cleanup-*.txt` | 8 个源路径均已不存在；`mdfind` 只剩 Desktop |
| D-09 | `make swift-test` 使用 `/tmp` DerivedData，避免再生成可启动副本 | `Makefile` | 301 条全绿；`/tmp/flowfinder-xctest-derived` |

**未验（明确）**

- A1 肩线、hover 底色、图标线宽的像素级目测：本机屏幕录制权限未授予，无法自动截图。
- 同目录拖放的真实鼠标手感：合成拖拽不可靠，策略层已测，交互入口已接。
- 0.8.0 在 1060×700、深色/高对比下的逐屏截图。

**清理证据**：8 个旧副本已从原路径移入废纸篓；当前运行进程为
`~/Desktop/FlowFinder.app`（0.8.0 / 8001）。缓存构建保留在
`~/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app`。

### R-19 第十二轮：0.8.0 Beta 后续 UI 重做 v2（设计已确认；Phase 0–7 已完成）

规格：`SPEC-2026-10-21-UI-REDESIGN-V2.md`；实施计划：`PLAN-2026-10-21-UI-REDESIGN-V2.md`（Phase 0–7）。
用户列出 12 项；设计已逐项确认。Phase 0 加 Debug 诊断与回归测试；Phase 1 落地尺寸三档、
顶栏 token 与 SF/Phosphor 图标；Phase 2 完成全局顶栏 C2、隐藏侧栏修复与新窗口首帧修复；
Phase 3 完成面板宽度模型、比例缩放与分栏把手；Phase 4 完成详情浮层 v2；
Phase 5 完成文件标签目录、跨文件同步、AND 过滤与统一选择器；Phase 6 完成设置页视觉 A；
Phase 7 完成构建/测试/自检/产物收口。

| 项 | 决策/发现 | 验证/证据 |
|---|---|---|
| 顶栏（2/4/5/11） | 全局窗口级顶栏；顺序 红绿灯→侧栏开关→面板1标签→面板2标签→分隔线→皮肤→单双栏；C2 密度：44pt / 标签38 / 6pt 空条 / 22pt 中线 / 文字13 / 图标16 / 10pt 内凹 | 可视化对比稿用户选定 C2 |
| 详情栏（7） | 保留浮层；高度 132–300 可拖；左侧预览列 96–200 可拖（默认132）；基础字段 类型/大小/修改/创建/位置/标签/说明；去掉所有者/权限/磁盘与“在 Finder/更多”；类型专属字段按类型显示 | 可视化确认；展开态实机截图（图二同窗口） |
| 隐藏侧栏（5） | 实机确认工具栏被 112pt 推到右侧；决定 112 只用于顶栏/标签条，面板工具栏保持 8pt 缩进 | CUA 截图 `/tmp/ff-step-dual-hide.png` |
| 面板宽度（6） | 侧栏宽度只由侧栏缝改；窗口缩放两栏等比；分栏拖拽不碰侧栏；软最小 400 / 硬下限 360；单↔双按隐藏栏收窄并恢复，侧栏不变 | 可视化对比稿用户选定 A（等比）+ B（单双收窄）+ 软最小 |
| 侧栏工具（8） | 工具入口移到全局顶栏最前（红绿灯→工具→折叠侧栏→标签组）；侧栏品牌只留名称/版本；保留分组菜单 | 可视化对比稿用户选定 D + 最前顺序 |
| 视觉尺寸（11） | 设置 > 外观提供 紧凑/舒适/大 三档，默认舒适 13/30/18；顶栏 C2 44/38 固定，标签文字 12/13/14 | 可视化对比稿用户选定三档 |
| 图标库（12） | 混合：SF Symbols 系统 chrome + Phosphor 文件类型/自定义；Phosphor MIT / 6 权重 | GitHub API + 真实 SVG 同尺寸对比稿用户选定 |
| 设置页（9） | 保留 7 分区与功能，只统一视觉；A 原生分组卡片（12pt/40pt 行/24–28 控件/13/11 字）；外观新增界面尺寸三档 | 可视化对比稿用户选定 A |
| 文件标签（10） | 访达原生标签；改名/改色/删除同步所有文件；设置内嵌管理器为唯一新建入口；侧栏列表+计数、⌘多选 AND；选择器批量打标签 | 可视化确认；数据行为用户选定同步所有文件 |
| 图二显示 bug（3） | 同步/异步交替压测未复现；新增单栏活动面板切换、新窗口显示前布局、20 轮交替压力回归；Phase 2/3 修掉新窗与启动首帧 50/50 | `FFShellLayoutTests` 多项；全量 XCTest 334；自检 20 轮/80 快照 0 失败 |
| Phase 0 诊断（3） | Debug-only `FFLayoutDiagnostics` 在侧栏显隐完成、单双栏应用、拖出新窗口后及其下一拍输出只读帧快照；不触发布局/重绘 | `/tmp/ff-debug.log` 的 `[LAYOUT]` 行；全量 0 条 `ANOMALY`；新窗口首帧抓到主分栏 50/50 瞬态（侧栏 700/面板 700），内容与详情栏正常，根因未证实 |
| Phase 1 尺寸/token | `FFSizeLevel` 三档 12/28/16、13/30/18、14/32/20（正文字号/行高/图标）；`FFSizePreference` 持久化，默认舒适；`FFVisualTokens.rowHeight/iconSize/Font.body` 随偏好计算；`FFTopBarMetrics` 44/38/6/22/13/16/10/16；设置 > 外观新增三档控件 | XCTest 7 条（3 尺寸/token + 4 图标）；`FFVisualTokensTests` 与 `FFDesignFoundationTests` 全绿 |
| Phase 1 图标 | 全部 104 个 `FFIconName` 映射到 SF Symbols 或 Phosphor；文件类型/文件夹用 Phosphor regular+duotone（`Resources/Icons/Phosphor/`，MIT）；标签用 SF `tag`/`tag.fill`（Phosphor 无 tags）；移除 `FFIcon` 的 Lucide 加载路径 | `missingSymbols`/`missingAssets` 自检为空；104 图标联系表人工核对无破图；自检 153 + 20 轮 0 失败 |
| Phase 2 顶栏 | 新增 `FFGlobalTopBar` 44pt 窗口级顶栏：工具→侧栏→左标签→右标签→分隔线→主题→单双栏；标签组按面板 frame 手动对齐；标签 38 / 空条 6 / 22 中线 / 内凹 10 / 命中 28；活动标签内容上移 3（NSStackView flipped）；工具入口迁到顶栏最前，侧栏品牌只留名称/版本；隐藏侧栏工具栏固定 8pt；`prepareForInitialDisplay()` 消除新窗口 50/50 首帧 | 5 条顶栏/隐藏侧栏/单栏/新窗口 XCTest；自检 AVOID 6 项全过；实机 1400 双栏 + 隐藏侧栏截图；新窗口首帧 1120pt |
| Phase 3 宽度 | `FFPaneWidthMath` 首选 400/硬 360 软降；窗口缩放侧栏钉住偏好宽度、两栏按记忆比例；单↔双侧栏不变；`FFSplitView` 12pt 热区、拖动 `pt` 浮标、25/50/75 吸附、双击 50/50；宽度记忆只在侧栏缝/中缝松手写；启动同步分隔线消除首帧 50/50 | 6 条 XCTest（4 纯几何 + 单双往返 + 窗口缩放）；WIDTH 自检 9 项；全量 322 0 失败；真实拖拽浮标/吸附手感未验 |
| Phase 4 详情浮层 | 展开高度 132–300（默认 132）；预览列 96–200（默认 132）且图标随列宽缩放；实体表面 + 12pt 圆角 + 0.5pt 边框 + 阴影，去掉第二层玻璃；名称两行编辑/ Esc 取消、位置两行点击复制；移除文件来源/磁盘/EXIF/编码等技术字段；类型专属字段补齐（ZIP 读 EOCD）；列表按详情高度让位 | XCTest 329（详情策略/默认高度/预览列/ZIP/复制路径/列表留白）；自检 164 + 20 轮；展开态实机截图未拿到 |
| Phase 5 文件标签 | `TagCatalog` 统一标签定义/排序；改名/改色/删除同步所有文件（索引∪Spotlight），影响数提示；同名合并；侧栏 ⌘ 多选 AND；`TagSelectorDialog` 多路径批量差异应用；右键批量/清除/管理；⌥⌘T 与详情栏共用；设置管理器改名/改色/删除/排序/新建 | XCTest 334（AND/改色改名删除同步/批量/合并 5 条）；自检 164 + 20 轮；Finder 双向互通与设置管理器视觉未验 |
| Phase 6 设置视觉 A | `FFSettingsMetrics` 12pt 卡片 / 40pt 行 / 26pt 控件 / 13·11 字；分区标题 13 semibold、图标 16、16pt 内边距；控件工厂统一高度；7 分区与功能保留；标签管理接入 TagCatalog | XCTest 335（设置度量）；自检 164 + 20 轮；设置浅/深色截图未验 |
| Phase 7 收口 | `make build` Rust+Swift 成功；XCTest 335；自检 164 + 20 轮；产物 `/tmp/FlowFinder-0.8.0-Beta-r19.app`；已覆盖桌面副本（0.8.0 / 8001，已启动）；未提交/未推送 | 本台账/HANDOVER/PLAN/CHANGELOG 同步 |
| 待定细节 | 文件列表行高仍由旧“列表密度”控制，未与“界面尺寸”合并；1060/深色/真实全屏/真实拖拽浮标/详情展开态/设置与标签管理器视觉/Finder 互通待人工验收 | 后续人工走查 |

**本轮代码变更**：Phase 0 诊断；Phase 1 尺寸三档/SF+Phosphor；Phase 2 全局顶栏；Phase 3 宽度模型/分栏把手；Phase 4 详情浮层 v2；Phase 5 新增 `TagCatalog`、`TagIndexStore.mutateTag/removeDefinition`、`PaneState.tagFilters` 与 AND 过滤、`TagSelectorDialog` 多路径批量、侧栏多选高亮、设置管理器 CRUD/排序/合并、右键批量/清除/管理；Phase 6 新增 `FFSettingsMetrics` 并统一 section/row/控件高度；Phase 7 `make build` + 335 XCTest + 164 自检收口，产物放 `/tmp`。旧 Lucide SVG 已无调用点，暂留资源待后续清理。

### R-20 第十三轮：0.8.0 Beta 第二轮整改（顶栏 / 工具页 / 第二行 / 版本规则）

规格：`SPEC-2026-10-21-UI-ROUND2.md`；实施计划：`PLAN-2026-10-21-UI-ROUND2.md`（Task 1–4）。
用户提出 4 项：红绿灯不对齐、标签太高、工具面板重构回品牌旁、移除新建文件夹并把第二行设置并入显示设置。
决策经可视化对比稿逐轮确认（顶栏 A · 36/30/18；工具页形态 1 侧栏页 + 分组纵向列表；工具清单 5 个；第二行 A 合并）。
实现日期 2026-10-21 深夜至 2026-10-22 凌晨。

| ID | 决策 | 实现位置 | 验证/证据 |
|---|---|---|---|
| D-01 | 顶栏 36 / 活动标签 30 / 非活动 26 / 空条 6 / 共用中线 18；标签内容相对框中心上移 3；操作面板上边缘上移 8 | `UI/FFVisualTokens.swift`（`FFTopBarMetrics`）、`UI/FFInteractionPolicy.swift`、`UI/PaneTabs.swift` | 【断言】`FFTopBarLayoutTests` 2 条（度量 + 18pt 中线）、`FFDesignFoundationTests.testTopBarC2Metrics`；WELD 35 项 |
| D-01b | 红绿灯垂直中心移到 18pt（水平位置与系统按钮顺序不变） | `UI/MainWindowController.swift` `alignTrafficLightsToTopBar()`，在 `windowDidBecomeKey` / `handleWindowLayout` / `updateGlobalTopBarLayout` / 首帧后重对齐 | 【断言】`FFShellLayoutTests.testTrafficLightsAlignToTopBarCenterline`（实测偏差 ±1.5pt 内）；【未验】物理点击红绿灯关窗本轮未重跑 |
| D-02 | 工具入口从全局顶栏移除，放回品牌右侧 24pt「工具」胶囊（wrench 图标） | `UI/PaneTabs.swift`（删 `toolButton`）、`UI/SidebarView.swift`（`toolPill`）、`UI/FFPillButton.swift`（`isSelected` + 可调高度）、`UI/FFIcon.swift`（`.wrench` → SF `wrench.and.screwdriver`） | 【断言】`SidebarToolPageToggleTests` 3 条；AVOID 自检由 6 降为 5（顶栏工具键断言随功能删除） |
| D-03 | 工具页为侧栏内页面：点胶囊切换，点「返回收藏」或再点胶囊退出；文件区不受影响 | `UI/FFToolPage.swift`（`SidebarToolPageView`）、`UI/SidebarView.swift`（`toggleToolPage` / `showToolPage` / `closeToolPage`） | 【断言】`SidebarToolPageToggleTests.testPillTogglesToolPageAndRestoresFavorites` |
| D-04 | 工具页不显示路径/选中/活动面板，也不承载选中项操作 | `UI/FFToolPage.swift`（头部只有「工具」+「返回收藏」） | 【断言】`SidebarToolPageViewTests.testHeaderOmitsPathSelectionAndPane` |
| D-05 | 工具页只列 5 个可用工具（查重 / 批量重命名 / 任务中心 / 设置 / 关于），AI「即将推出」不进页面 | `UI/FFToolPage.swift`（`FFToolPageCatalog.includedToolIDs`） | 【断言】`FFToolPageCatalogTests.testCatalogListsFiveApprovedToolsInOrder` |
| D-06 | 工具页内部为分组纵向列表：整理 / 任务 / 系统，行高 32、图标 16、标题 13、提示 11 | `UI/FFToolPage.swift`（`grouped(context:)` + `FFToolRowView`，自 `FFToolPopoverController` 迁入） | 【断言】`FFToolPageCatalogTests.testCatalogGroupsInApprovedOrder`、`SidebarToolPageViewTests.testRowsMatchCatalog` / `testDisabledRowIgnoresClick` |
| D-07 | 第二行删「新建文件夹」与齿轮；眼睛改名为唯一「显示设置」，菜单合并显示项 + 第二行显示 + 显示列 | `UI/FFToolbarPreferences.swift`（删 case `newFolder`）、`UI/PaneToolbar.swift`（`displaySettingsButton` / `makeDisplaySettingsMenu`）、`UI/MainWindowController.swift`（删 `paneToolbarDidClickNewFolder` / `setFolderSelectionCount`） | 【断言】`FFToolbarRow2MergeTests` 4 条（含旧 `newFolder` 偏好被忽略）；`FFShellLayoutTests` / `FFAccessibilityTests` 同步更新 |
| D-08 | 新建文件夹入口不变：文件菜单、右键菜单、⇧⌘N | `UI/MainMenu.swift`、`UI/FFCommon.swift`（`FFPaneMenuBuilder`）、`FFPaneActionsController` | 【断言】`FFKeyboardContractTests` / `FFShortcutSettingsTests`；本轮未改代码，仅确认工具栏按钮移除后仍有入口 |
| D-09 | 版本命名规则 `A.B.C-yymmddxx`：`MARKETING_VERSION` 保持 `0.8.0`，`CFBundleVersion` 改存 `yymmddxx`，显示层拼成 `0.8.0-26102202 Beta`；每次 `make build/release/beta` 自动递增 | `scripts/bump-version.sh`（新增）、`scripts/lib-version.sh`（`FF_DISPLAY_VERSION`）、`Makefile`（`bump-version` 目标 + build/release/beta 钩子）、`UI/FFCommon.swift`（`FFBuildInfo.displayVersion`） | 【断言】`FFBuildInfoTests.testDisplayVersionFollowsDateStampedRule`；【实机】`make build` 输出 `0.8.0-26102201`，`make demo` 递增到 `0.8.0-26102202` 并覆盖桌面副本；脚本 dry-run 验证同日再构建 → `26102202`，旧值 `8001` → 重置为当日 `01` |

**本轮代码变更**：顶栏度量与标签内容偏移、红绿灯对齐、`FFGlobalTopBar` 去工具键、`FFPillButton` 选中态与高度、`.wrench` 图标、新增 `FFToolPage.swift`（目录 + 页面 + 工具行）、删除 `FFToolPopoverController.swift`（浮层被侧栏页取代）、`PaneToolbar` 第二行合并、`FFToolbarRow2Item` 去 `newFolder`、版本脚本与显示格式。
测试：新增 `FFToolPageTests.swift`（10 条）、`FFToolbarRow2MergeTests`（4 条）、顶栏/红绿灯 3 条、版本 1 条；`FFVisualTokensTests` 新增强调色隔离 setUp（用户此前在设置里选过石墨色，导致「默认跟随系统强调色」断言被真实偏好污染）。

**真机证据（2026-10-22，桌面副本 0.8.0-26102202）**：① 顶栏/红绿灯：窗口截图像素测量「红绿灯中心 17.5pt = 活动标签文字中心 17.5pt」（规范 18pt，误差 0.5）；② 第二行：只剩一个「显示设置」按钮（AX id 36），菜单实机展开为 4 个显示开关 +「显示列」7 项 +「第二行显示」4 项、无新建文件夹；③ 工具页：点品牌旁「工具」胶囊打开，AX 实测 `工具 / 返回收藏` 头部 + 整理（重复文件扫描可用、批量重命名禁用并提示「先选择文件」）/ 任务（任务中心）/ 系统（设置、关于 FlowFinder）共 5 行，文件区与双栏不受影响，截图 `/tmp/ff-toolpage-26102202.png`；④ 窄侧栏：`sidebar_width=180` 重启后名称完整、版本号截断为 `0.8.0-26102202…`、胶囊换到版本行，截图 `/tmp/ff-narrow-180.png`。
**未验项**：红绿灯物理点击关窗、极矮窗口下工具页滚动、VoiceOver 走查工具页与胶囊需人工确认。
**收口**：用户授权后执行 `make demo`，桌面副本已覆盖为 `0.8.0-26102202 Beta` 并启动成功；最终产物（Desktop 副本）上重跑自检 **163 项 0 失败 + 20 轮 0 失败**，`codesign --verify` 通过。

### R-21 第十四轮：批次 1（设置接线 / 终端入口 / 工具页无障碍）

规格：`SPEC-2026-10-22-BATCH1.md`；计划：`PLAN-2026-10-22-BATCH1.md`。
用户选择「全部接线」并逐项确认行为；审计纠正：`startup_location` 与 `default_view_mode` 原本已接线，
真正失效的是 5 个控件 + 2 个孤儿键，完整会话仅缺活动面板。

| 项 | 决策 | 实现位置 | 验证 |
|---|---|---|---|
| 移动前确认 | 只管移动（拖拽/⌘⇧X/剪切粘贴/菜单）；删除确认保持原样；默认关 | `UI/MoveConfirmation.swift`、`FileListView`、`MainWindowController+MenuActions` | XCTest 2 条（门控/文案） |
| 默认操作行为 | 三选：跟随访达/总是复制/总是移动；⌘ 反转 | `UI/FFAppSettings.swift` `FFDragBehaviorPolicy`、`FileListView.isMoveOperation` | XCTest 4 条 |
| 文件夹优先排序 | 新行；默认开；关闭后纯字段排序 | `FFSortPolicy`、`PaneState.sortEntries`、设置页 | XCTest 2 条 |
| 刷新保持选中 | 新行；默认关；仅恢复仍存在项 | `FFSelectionRestore`、`PaneState.refresh/loadDirectory` | XCTest 2 条 |
| 启动检查更新 | 完整版本戳比较，回退营销版本；24h 节流；提示去下载；关于页手动检查 | `UI/FFUpdateDecision.swift`、`UI/FFUpdateChecker.swift`、`AppDelegate`、设置关于页 | XCTest 3 条；网络/提示未触发 |
| SMB 默认域 | 连接对话框新增域字段并预填；URL 支持 `domain;user@host` | `UI/FFSMBConnection.swift`、`ConnectServerDialog` | XCTest 3 条 |
| SMB 自动重连 | 持久化「下次自动连接」的服务器；启动重连；断线/成功/失败状态提示 + 重试 | `FFSMBConnectionStore`、`SMBBridge.reconnectSavedConnections`、`MainWindowController.showSMBStatus` | XCTest 3 条；真实断线未触发 |
| 完整会话 | 恢复活动面板；路径与单/双栏沿用既有持久化 | `FFStartupPath.activePane`、`MainWindowController.windowWillClose` | XCTest 1 条 |
| 终端入口 | 改用 `NSWorkspace` 打开 Terminal，删除 osascript | `BreadcrumbBar.openInTerminal` | 编译 + 代码审查；未实点 |
| 工具页无障碍 | 胶囊 AX role/label/pressed + Space/Return；工具行接入 keyViewLoop、焦点环；禁用行不抢焦点 | `FFPillButton`、`FFToolPage`、`SidebarView`、`MainWindowController.buildKeyViewLoops` | XCTest 2 条 |

**真机证据**：设置 > 通用/文件操作区截图 `/tmp/ff-batch1-settings.png`，AX 实测「移动前确认」「默认操作行为（跟随访达/总是复制/总是移动）」「文件夹优先排序」「刷新保持选中」「启动时检查更新」均在位。

**未验**：真实 SMB 断线与状态栏提示（需网络卷）、更新提示（需线上有新 Release）、移动确认弹窗与终端打开的实际点击、工具页 Tab 循环的人工走查。

### R-22 第十五轮：批次 2（功能回归测试 6 组）

只补测试与最小测试钩子，不改用户可见行为。新增 `FFBatch2IntegrationTests`（15 条）+ 既有 368 条，共 **383 条**。

| 组 | 覆盖 | 测试 |
|---|---|---|
| 跨栏操作 | ⌘⇧C 落地、⌘⇧X 删源、在另一侧打开 | `testCopyToOtherPaneLandsInDestination`、`testMoveToOtherPaneRemovesSource`、`testOpenInOtherPaneNavigatesRight` |
| 搜索 | 关键词过滤/清空恢复、深度 3/上限 500 常量 | `testSearchFiltersByNameAndClears`、`testSearchPolicyLimits`（`FFSearchPolicy` 抽取） |
| 键盘与焦点 | ⌘F 聚焦搜索框、Tab 环含胶囊与 5 行、文本编辑 ⌘C 不写文件剪贴板 | `testCmdFFocusesActivePaneSearchField`、`testKeyViewLoopIncludesToolPillAndRows`、`testTextEditingCopyDoesNotTouchFileClipboard` |
| 标签互通 | Finder binary plist 数组写入、原生读回 | `testTagWriteUsesFinderBinaryPlistArray`、`testTagReadsBackNativeTags` |
| 设置生效 | 文件夹优先开关、刷新保持/清除选中 | `testFolderFirstSortOnAndOff`、`testRefreshKeepsSelectionWhenEnabled`、`testRefreshClearsSelectionWhenDisabled` |
| 静态 lint + 权限 | 字体 ≤122 / 颜色 ≤9 棘轮；5 条用途声明 | `testHardcodedTokenBudget`、`testRequiredUsageDescriptionsPresent` |

**测试钩子**：`FFSearchPolicy` 常量、`PaneToolbar.searchFieldForTesting`、`MainWindowController.keyViewLoopForTesting()`。
**已知环境坑**：`NSTemporaryDirectory()`（/var/folders）在 XCTest harness 下被 Rust `getattrlistbulk` 枚举为 0 条，测试目录必须用 `/tmp`（与 `PaneStateDeleteFilterTests` 一致）。

**未验**：真实拖拽手感、真实 SMB 断线、更新提示仍需人工/真实环境。

### R-23 第十六轮：批次 3（文档与代码对齐）

用户选择「原位重写」。本批只改文档，不改代码、不重新构建。

| 文档 | 变更 |
|---|---|
| `REQUIREMENTS.md` | 升到 2.1：J1-01/02/07、J3-07/08、J5-01/05、C-08 等改为 ✅ 并给实现位置；保留 J1-04/J1-06/J2-08/09/J3-10 为 ❌；J3-09/J4-01/J5-02 标 ⚠️/🔧；新增「本轮新增能力 R-19…R-22」与更新后的宣称对照 |
| `ACCEPTANCE.md` | 升到 1.1：侧栏 220/180–280、详情收起 54/展开 132–300、行高按密度 26/30/36（标签 44/48/56）、顶栏 36/30/26/18；新增 T-10、V-11/12、O-08、S-14/15、F-07…F-11、A-01…A-04；发布门槛按现状重排 |
| `README.md` | 修 5 处：系统要求 12.0+、Beta 表述、下载文件名以 Release 页为准、标签写入已是访达格式、任务中心按实际能力描述（不再宣称暂停/恢复/优先级） |
| `PLAN-2026-10-21-UI-REDESIGN-V2.md` | Phase 7 的台账编号 R-20 → R-19 |
| `HANDOVER.md` | 代码规模更新为 Swift 111 文件 / 约 43,800 行 |

**未验**：文档中标注 ⚠️ 的真机项不变（拖拽手感、SMB 断线、更新提示、VoiceOver、1060/深色/全屏）。

### R-24 第十七轮：批次 4（首次引导 / 崩溃日志 / Tab 环 / AI 命名）

用户选择「A + 首次引导页」，引导形态经可视化选定「独立欢迎窗口」。

| 项 | 实现 | 验证 |
|---|---|---|
| 首次引导 | `UI/OnboardingWindowController.swift`：双栏图示 + 权限状态 + 3 快捷键；开始使用写 `onboarding_completed`；稍后再看不写；帮助菜单可强制重开 | `FFBatch4Tests` 3 条；实机首启弹窗、按钮后二次启动不再弹；截图 `/tmp/ff-onboarding2.png` |
| 崩溃日志 | `UI/FFCrashLog.swift`：未捕获异常写入 `~/Library/Logs/FlowFinder/crash.log` | `FFBatch4Tests` 1 条 |
| Tab 环 | 侧栏收藏列表加入 keyViewLoop | `FFBatch4Tests` 1 条 |
| AI 命名 | 注册表标题改为「按类型自动打标签」「自动整理」 | `FFBatch4Tests` 1 条 |

**实机发现并修复**：欢迎窗口底部留白过大、按钮未靠右；改为按内容自适应高度 + 底部左右对齐。
**真实未验**：帮助菜单重开引导未完成自动化点击验证（代码路径简单）；崩溃日志未人为触发。
**收口（2026-10-22）**：`make demo` 覆盖桌面副本为 `0.8.0-26102209`（codesign 通过），最终产物自检 **163 项 + 20 轮 0 失败**；本轮改动已提交并推送。

### R-25 第十八轮：真机走查问题修复

真机走查（0.8.0-26102209）发现 2 个 P1、3 个 P2；本轮修复 5 项，AX 内存问题保持开放。

| 问题 | 修复 | 验证 |
|---|---|---|
| P1 名称列在 500pt 面板被挤到 120pt | `FFColumnFitPolicy.nameFloor`：名称列至少占可用宽度 40%、不低于 160pt；`applyColumnFit` 使用该下限 | `testNameColumnFloorIsFortyPercentWithMinimum`；实机 500pt 面板文件名完整可读 |
| P1 启动被权限门阻塞约 30s，首屏误显示「此文件夹为空」 | 改为立即加载 + 权限门并行；权限门上限 3s；门完成后仅对失败/空目录重试 | 实机首屏加载 **30s → 1.08s** |
| P2 移动/删除后详情栏仍显示旧文件 | 订阅左右 `$state.selectedFiles`，模型层选中变化直接更新详情栏 | `testDetailsBarClearsAfterMovedSelection` |
| P2 工具页返回后焦点丢给窗口 | `closeToolPage` 把第一响应者还给工具胶囊 | `testClosingToolPageRestoresPillFocus` |
| P2 缺少「前往文件夹」 | 前往菜单新增「前往文件夹…」⇧⌘G；支持 `~`/绝对路径，非法路径中文提示 | `testGoToFolderNormalization` |
| P1 AX 全量枚举 5000 行导致 RSS 183→792/893MB | **R-26 已修复**：AX 行虚拟化，保留完整行索引，每行只暴露轻量摘要 | 见 R-26；Release 1 万行 AX 全量枚举后 RSS 185.2MB |

**版本**：`make demo` 覆盖桌面副本为 **0.8.0-26102212**；最终产物自检 **163 + 20 轮** 0 失败。
**注意**：已发布的 `v0.8.0-b1` 产物基于 `26102209`，不含本轮 5 项修复。

### R-26 第十九轮：AX 行虚拟化

**根因（systematic-debugging）**：默认 `NSTableView` 的 AX 树按行/列/cell 展开；AX 客户端深枚举 5000 行时反复调用 `viewFor`（独立探针实测 165 万次），FlowFinder 的 cell 创建含图标、缩略图与标签药丸，导致 RSS 183→792/893MB。

| 项 | 实现 | 验证 |
|---|---|---|
| 轻量行代理 | `FFAXRowDataSource` + `FFAXRowElement: NSAccessibilityElement`：每行只暴露名称/类型/大小摘要，`accessibilityChildren()` 返回空，不创建行视图/cell | `testAXRowsKeepFullCountWithoutCellChildren`（5000 行、cell 子元素 0） |
| 完整行语义 | `FFQuickLookTableView` 覆写 `AXRowCount` / `AXRows` / `AXVisibleRows` / `AXSelectedRows` / `AXChildren` / `AXSelectedChildren`；`AXRows` 用 `unsafeBitCast` 桥接 `NSAccessibilityRow` | 真机 `AXRows=10000`、`AXChildren=10000`、`AXChildrenInNavigationOrder=10000` |
| 选中/刷新 | `selectRowIndexes` 发 `selectedRowsChanged`；`reloadData` 与分页追加后 `invalidateAXRows()` | `testAXSelectionRoundTripAndPress`、`testAXRowsInvalidateAfterReload`；真机 `AXPress` 第 9999 行 → `AXSelectedRows` index 9999 |
| 禁止 cell 级 AX | `AXSelectedCells` / `AXVisibleCells` / `AXRowHeaderUIElements` 返回空，避免 cell 物化 | `testAXEnumerationDoesNotCreateCellViews`（AX 枚举前后 `viewFor` 不增加） |

**真机验收（Release `0.8.0-26102215`，独立 Bundle ID 副本）**：10,000 个零字节文件单栏 + 空右栏；正常 RSS **174.9MB**；外部 AX 客户端全量枚举 **10,202 元素 / 10,006 行 / 120,329 属性** 后 RSS **185.2MB**（+5.4MB，<250MB）；`AXPress` 第 9999 行后 `AXSelectedRows=1, index=9999`，RSS 185.9MB。5000 行 Debug `26102213/14`：216→220MB；AX 后 226MB。
**测试**：`FFAXVirtualizationTests` 新增 4 条；全量 **397 条 0 失败**；`FF_SELFTEST=1` 163 项 + 20 轮 0 失败（DEBUG `26102214`）。
**剩余**：VoiceOver 人工逐行朗读/列朗读未走查；本轮选择行级摘要，列级 cell AX 有意关闭（K-05 只要求侧栏名称/类型）。移动/重命名后 AX 标签随 `reloadData` 刷新，已由测试覆盖，未做 VoiceOver 听感确认。

### R-27 第二十轮：J3-11 文件说明迁移 Finder 注释

**问题**：详情栏「文件说明」读写 `UserDefaults["fileDescriptions"]`（绝对路径为 key），列表「说明」列读 Spotlight 的 `kMDItemFinderComment`；两个入口数据源不一致，改名/移动后旧说明丢失。

| 项 | 实现 | 验证 |
|---|---|---|
| Finder 注释读写 | 新增 `FFFinderCommentStore`：`com.apple.metadata:kMDItemFinderComment` binary plist 字符串；空值移除 xattr；兼容纯文本旧 xattr | `testFinderCommentRoundTrip`、`testReadsPlainTextFallback` |
| 旧数据迁移 | 首次启动 4s 后后台一次性迁移：路径存在且 Finder 注释为空才写入；已有注释/失效路径/写入失败保留旧字典；成功条目删除；写迁移标记 | `testMigrationWritesOnlyWhenFinderCommentEmpty`、`testMigrationRunsOnlyOnce`、`testMigrationKeepsEntryWhenWriteFails` |
| 统一读取 | 详情栏 `getFileDescription` 优先 Finder 注释、回退旧字典；列表说明列缓存改为读 xattr | 真机迁移后详情栏 AX 读到「旧说明迁移测试」 |
| 写入反馈 | 写 Finder 注释成功→清旧字典、更新缓存、刷新列表；失败→保留本地回退并中文提示「无法写入 Finder 说明」 | store 写入路径 + 迁移真机 xattr 解码 |

**真机证据（2026-10-22，DEBUG 26102216 独立 Bundle ID 副本）**：预置旧字典 `/tmp/ff-j311/note.txt = 旧说明迁移测试` 后启动；4s 后 xattr 实际 **56 字节**，解码为「旧说明迁移测试」；旧 `fileDescriptions` 键已删除，迁移标记为 1；详情栏 AX 文本为「旧说明迁移测试」。
**测试**：新增 5 条 `FFFinderCommentStoreTests`；全量 **402 条 0 失败**；自检 **163 + 20 轮** 0 失败。
**剩余**：详情栏描述字段位于展开详情栏滚动区，自动化坐标点击受限；界面文本输入/回车保存未实机点击，写入 store 与迁移路径已覆盖。Finder「显示简介」人眼确认仍待补。

### R-28 第二十一轮：J2-07 搜索范围（本栏 / 含子目录 / 双栏）

**问题**：搜索固定为「当前栏递归 3 层 / 上限 500」，没有范围 UI；用户无法只搜当前目录，也无法两侧同时搜。

| 项 | 实现 | 验证 |
|---|---|---|
| 范围枚举 | `FFSearchScope`（本栏 / 含子目录 / 双栏）+ `PaneState.searchScope`；`searchesSubdirectories` / `searchesBothPanes` 纯语义 | `FFSearchScopeTests.testScopeTitlesAndBehavior` |
| 范围控件 | `PaneToolbar` 在搜索框右侧加 22pt 紧凑菜单（A 方案），`AX` label「搜索范围」，随搜索项一起隐藏，进入 keyViewLoop | `testToolbarExposesScopeMenu`、`testToolbarSearchFieldCanBeProgrammaticallyUpdated` |
| 搜索语义 | `本栏`/`双栏` 只过滤当前目录；`含子目录` 才调度递归（仍 3 层 / 500 条）；离开递归会取消挂起任务并清除已追加结果 | `testSearchScopeCurrentFiltersOnlyCurrentDirectory`、`testSearchScopeRecursiveAppendsSubdirectoryMatches`、`testSearchScopeBothPanesFiltersCurrentDirectoryOnly` |
| 双栏镜像 | 任一侧搜索框驱动两侧；进入双栏同步两侧查询/范围，离开双栏清除对侧镜像并恢复完整列表；程序化更新不触发 delegate 循环 | `testSearchScopeBothPanesMirrorsQueryAcrossPanes` |
| 布局 | 范围菜单压缩优先级 735，搜索框仍先让位；自检 20 轮无异常 | `FF_SELFTEST=1` 163 + 20 轮 |

**真机证据（DEBUG 26102217/18 独立 Bundle ID 副本，左 `/tmp/ff-j207-left`、右 `/tmp/ff-j207-right`）**：
- 双栏 + 输入 `alpha`：两侧搜索框都显示 `alpha`；左只剩 `alpha.txt`，右只剩 `alpha-right.txt`；子目录 `alpha-deep.txt` 不出现。
- 左切「含子目录」：左出现 `alpha.txt + alpha-deep.txt`；右侧查询清空、范围回「本栏」、`alpha-right + beta-right` 恢复。
- 左切「本栏」：左只剩 `alpha.txt`，右保持完整 2 项。
**测试**：新增 7 条；全量 409 条 407 通过（2 条既有异步测试受测试宿主真废纸篓/目录加载阻塞，其中 overlay 单跑通过）；自检 163 + 20 轮 0 失败。
**剩余**：递归命中 500 条时的「已截断」提示未加；搜索范围不跨启动持久化（每次启动回「本栏」）。

### R-29 第二十二轮：J3-10 批量整理（预览 + 撤销）

**问题**：Rust FFI `ff_organize_by_date/type` 已有但 Swift 无入口，用户无法按日期/类型把当前目录顶层文件归入子文件夹。

| 项 | 实现 | 验证 |
|---|---|---|
| 计划纯函数 | `FFOrganizePlanner`：日期三档 `YYYY/MM/DD·YYYY/MM·YYYY`（默认 YYYY/MM）、中文 9 类别；范围=当前目录全部顶层文件（子文件夹不动、排除隐藏文件）；目标已存在同名→Conflict 不覆盖 | `FFOrganizePlannerTests` 等新增 12 条（计划生成、三档日期、类型分组、冲突、candidates 排除规则） |
| 执行与撤销 | `PaneState.performOrganize`（generation 计数防串批、后台 `moveItem`、`CoreBridge.invalidateCache`、发 `.paneFileOperationChanged`）+ `registerUndoOrganize`/`undoOrganize`/`redoOrganize`，整批一次 ⌘Z | XCTest 覆盖执行/撤销注册；真机 ⌘Z 后文件回到根目录 |
| 预览 Sheet | `FFOrganizeSheet`（FFModalSheet）：整理方式/日期格式弹出、统计「N 项移动 · M 项重名跳过」、计划清单（重名行橙色）、`执行后可 ⌘Z 一次撤销整批`；空目录/读取失败/无可整理文件走 sheet alert 中文提示 | 真机 AX：3 项移动 → /2025/11，sub 未列入 |
| 双入口 | 工具页 `batch-organize` 行（group 整理，共 6 工具）→ `menuBatchOrganize`；右键菜单「整理当前目录…」→ `.fileListBatchOrganize` 通知（Wave2 P0-4 仅响应本窗口面板） | 真机两入口均弹出 Sheet；右键菜单出现 `重做批量整理`（撤销已入菜单） |
| Rust FFI | `ff_organize_by_date/type` 保持不动；UI 未走此 FFI，计划与执行都在 Swift 侧 | Rust 200 项不受影响 |

**真机发现并修复（TDD）**：① Sheet body 塌陷成重叠一行——`buildBody` 7 个子视图漏设 `translatesAutoresizingMaskIntoConstraints = false`，autoresizing 约束冲突在 `FFModalSheet` 量高时被拆；② 工具页行暴露 AX button 但无 `accessibilityPerformPress`，AXPress 无效——补覆写（键盘 Tab+回车路径原本就通）。另更新工具页断言 5→6 工具、Tab 环 6 行，并新增 `testToolRowSupportsAXPress`。
**真机证据（2026-10-22，DEBUG 26102220 独立 Bundle ID 副本，`/tmp/ff-org-test`：photo.jpg/report.pdf/song.mp3 修改时间 2025-11-02 12:00 + sub/nested.txt）**：工具页 AXPress 打开 Sheet（渲染完整）；「按类型」切换后计划变 /图片、/文档、/音频且日期格式弹出隐藏；取消正常；「执行整理」后 3 文件实际位于 `/tmp/ff-org-test/2025/11/`、`sub` 未动、列表自动刷新为 2025/sub 两项；⌘Z 后 3 文件回到根目录；右键 photo.jpg → 菜单含「整理当前目录…」→ 点击弹出同一 Sheet。
**测试**：新增 13 条（12 条 FFOrganize + 1 条 AXPress）；全量 **422 条 0 失败**；自检 **163 + 20 轮** 0 失败；字体 lint 新增文件 0 处裸 `NSFont`（存量 122）。
**注意事项**：独立 Bundle ID 副本与桌面副本**共享** `~/Library/Application Support/FlowFinder/`（缓存/索引/会话路径未按 bundle 隔离），副本右栏会恢复用户真实会话——本轮只在 `/tmp` 目录执行整理；该共享是既有行为，未在本轮改动。
**剩余**：整理范围不含子文件夹内部（按定稿如此）；撤销栈仅保留最近一批，跨会话不持久；重名冲突行的「跳过」文案未单独实机构造验证。

---

### R-30 第二十三轮：P0 数据安全（重命名覆盖 / 查重零保留）

**问题**：内联重命名直接调用 Rust `std::fs::rename`，同名目标文件会被静默覆盖；查重可把一组内所有文件都标为删除，且永久删除复用废纸篓的「不再询问」，失败无提示。

| 项 | 实现 | 验证 |
|---|---|---|
| 重命名冲突 | `PaneViewModel.renameFile` 在调用 FFI 前检查目标存在；若目标存在且不是同一文件（fileResourceIdentifier 不同）则拒绝并提示「已存在同名文件，请换一个名称」，源文件与目标均保留 | 新增 `FFRenameCollisionTests` 2 条：同名不覆盖、源保留、错误提示；新名称正常改名 |
| 大小写改名 | 通过 `fileResourceIdentifier` 判定同一文件，允许仅大小写变化的重命名不被误判为冲突 | 由同一实现路径覆盖，未单独构造 APFS 大小写用例 |
| 查重零保留 | `FFDuplicateSelectionPolicy.canMarkForDeletion` 要求标记后仍有未标记项；`DuplicateGroupView` 在试图删除最后保留项时拒绝、恢复行状态并 beep | `testDuplicateSelectionCannotDeleteEveryRemainingFile` |
| 永久删除确认 | `DeleteConfirmDialog.isPermanent`：永久删除不读取「不再询问」、隐藏该复选框、副标题固定「此操作无法撤销」；查重窗口传 `isPermanent: true` | `testPermanentDeleteAlwaysRequiresConfirmation`；旧废纸篓路径行为保持不变 |
| 删除失败反馈 | 查重批量永久删除收集失败项，完成后以 sheet 提示「已删除 N 个，失败 M 个」并列出前 8 项 | 代码级；未实机构造失败项 |

**测试**：新增 4 条（2 重命名 + 2 查重/永久删除策略）。全量 **426 条**：**424 通过**；`PaneStateDeleteFilterTests.testDeleteIsNonBlocking` 1 条（2 个断言）在测试宿主移入废纸篓时超时，单跑同样复现，属既有测试宿主环境问题，与本轮无关。自检 **163 项 + 20 轮布局压力 0 失败**（DEBUG 26102222）。全量串跑存在既有跨测试套件挂起；本轮按测试类分 15 批执行，全部 426 条均已运行。

**构建**：`make build` 成功，版本 **0.8.0-26102222**；未执行 `make demo`，桌面副本仍为 26102221。

**未验**：重命名冲突的界面错误横幅/内联编辑回退手势未实机点击；查重零保留的 beep/行状态恢复未实机点击；永久删除失败 sheet 未构造。

---

### R-31 第二十四轮：P1 UI 状态与入口修复

**问题**：工具栏排序/分组与 PaneState 脱节；工具页只在打开瞬间读上下文；单标签 × 无响应；侧栏「在新标签页中打开」永久置灰；右键操作可能作用于旧选中项；右键整理忽略发起面板；整理 Sheet 与显示设置存在文案/焦点问题。

| 项 | 实现 | 验证 |
|---|---|---|
| 工具栏状态同步 | `PaneToolbar.setSortField/setGroupBy`；`updatePaneUI` 同步 searchQuery/searchScope/sortField/groupBy；程序化更新不触发 delegate | `testToolbarSortAndGroupPopupsSyncFromState` |
| 工具页上下文 | `SidebarToolPageView.updateContext` 按可用性签名增量重建行；`SidebarView.refreshToolPageContext` 由 `updatePaneUI`/`activatePane` 触发 | `testToolPageRefreshesAvailabilityAfterContextChange` |
| 工具页焦点 | `返回收藏` 纳入 `focusableViewsForTesting`；焦点环绘制不再被 `hovered` 守卫挡住 | `testToolPageRowsAreFocusable` 更新为 7 项；`testKeyViewLoopIncludesToolPillAndRows` 同步 |
| 标签/侧栏入口 | 单标签 `×` 关闭窗口；侧栏「在新标签页中打开」只按收藏有效性置灰，不再依赖系统 tabbingMode | 代码级；未实机点击 |
| 右键点击项 | `ensureClickedItemSelected`：右键未选中项先选中；点击已选中项保留多选；复制/剪切/删除/跨栏/拷贝路径共用 | 代码级；未实机构造右键路径 |
| 整理路由 | `handleFileListBatchOrganize` 按通知 source 视图选择左右面板，不再固定 `activePane` | 代码级；未实机构造非活动栏右键 |
| 整理 Sheet 文案 | 「日期格式」标题提升为实例属性，按类型时与日期格式弹出同步隐藏 | 实机：按类型后 AX 树中「日期格式」标题消失 |
| 显示设置语义 | 菜单固定名词「显示隐藏文件 / 显示文件标签 / 显示文件后缀 / 显示系统文件」+ 勾选态；隐藏的 Row2 控件移出 keyViewLoop | `testDisplaySettingsMenuUsesFixedLabels`、`testHiddenRow2ControlsLeaveKeyViewLoop`；实机菜单文案通过 |
| F-06 文案 | 右键菜单「AI 自动打标签」改为「按类型自动打标签」；关于页「AI 智能分类」改为「按类型自动分类」 | `testContextMenuIncludesOrganizeCurrentDirectory` 增加断言；定向绿 |

**测试**：新增 4 条 + 更新 3 条既有断言。全量 **430 条**：分批 **428 通过**；`DuplicateScanBrowseRegressionTests` 单跑通过（全量串跑受既有 sheet/TCC 环境超时）；`PaneStateDeleteFilterTests.testDeleteIsNonBlocking` 测试宿主废纸篓超时（既有环境问题）。自检 **163 + 20 轮 0 失败**（DEBUG 26102224）。

**构建**：`make build` 成功，版本 **0.8.0-26102224**；未执行 `make demo`，桌面副本仍为 26102221。

**实机（2026-10-22，DEBUG 26102223/26102224 独立 Bundle ID 副本）**：
- 显示设置菜单固定名词通过；工具页打开时全选 3 项后「批量重命名」即时可用；侧栏新标签成功开出 Desktop；单标签 `×` 关闭窗口。
- 右键 clickedEntry：选中 alpha 后右键 beta「拷贝路径」，剪贴板为 `/tmp/ff-p2-left/beta.txt`，选中项切到 beta。
- 非活动栏右键整理：左栏活动时右键右栏，Sheet 标题为 `整理预览 — ff-p2-right`。
- 整理 Sheet 切「按类型」后「日期格式」标题消失。
- 工具页 Tab 焦点环：焦点落在「批量整理」行，蓝色焦点环可见。
- P0 重命名冲突：alpha 改名 beta.txt，界面出现「已存在同名文件，请换一个名称」，beta 内容未被覆盖、alpha 保留。
- 右键菜单 AI 文案已改为「按类型自动打标签」。

**未验**：查重零保留的 beep/行状态恢复（策略/单测已覆盖）、永久删除失败 sheet、右键删除/剪切后源/目标面板刷新的实机组合。

---

### R-32 第二十五轮：全量 UI/UX 验收（第一轮）

完整报告：`docs/AUDIT-2026-10-22-UX.md`。

本轮覆盖：深色/浅色双栏主窗口、列表、网格、详情栏、设置通用/外观/关于、查重空态与结果、工具页、整理 Sheet、右键 clickedEntry、非活动栏整理、重命名冲突、多标签溢出。

**新增/确认的高优先级问题**：

| ID | 级别 | 问题 | 证据 |
|---|---|---|---|
| F-01 | P1 | 实时切换深浅色后侧栏/顶栏/工具栏文字白字白底，列表头/详情栏仍深色；重启才恢复 | `images/audit-2026-10-22/05-light-settled.png` |
| F-02 | P1 | 详情栏仍 1 列 + 内部滚动条，标签/文件说明折叠，磁盘空间未显示 —— **R-35 已修**（磁盘空间仍待补） | 修复前 `07-light-details.png`；修复后 `15/16/17-f02-after-*.png` |
| F-03 | P1 | 网格视图所有文本文件显示棋盘格占位 | `images/audit-2026-10-22/09-multitab.png` |
| F-04 | P1 | 12 个标签时后续标签与 `+` 被裁，无溢出处理 | `images/audit-2026-10-22/09-multitab.png` |
| F-05 | P1/P2 | 查重窗口：Button 泄漏、组名 hash、`Zero KB`/`bytes`、右侧“删除”与底部 0 选择矛盾、筛选未接线 | 本轮 AX/截图 |
| F-06 | P2 | 设置：文件管理图标缺失、44pt 过期文案、指向不存在的“删除与安全”、界面尺寸未生效 | 本轮截图 |
| F-07 | P2 | 列表修改日期默认截断、长文件名尾部截断 | `images/audit-2026-10-22/01-initial.png` |
| F-08 | P1 | 批量重命名把目录纳入；`{name}.{ext}` 对无扩展名生成 `Empty Folder.`/`Projects.` 尾点名称，预览无告警 | `images/audit-2026-10-22/10-batch-rename.png` |
| F-09 | P2 | 设置分区：“文件管理”实际只有“删除与安全”且缺图标；标签行多余“/”分隔符；网络存储空态重叠/无内容滚动条；快捷键重置行被搜索框裁切 | 第二轮截图 |
| F-10 | 通过 | 冲突弹窗：默认跳过，跳过/保留两者/替换顺序与 destructive 样式正确 | `images/audit-2026-10-22/11-conflict.png` |
| F-11 | P1 | 1060×700 最小窗口 Row2 控件重叠/裁切；类型、大小列消失 | `images/audit-2026-10-22/12-1060x700.png` |

**Blocked（不冒充通过）**：删除确认、移动确认、标签弹窗、文件简介、QuickLook、首次引导/权限、高对比/VoiceOver/Reduce Motion、SMB 真实断线/更新提示、活动面板发光（窗口未 key）。原因与补验方式见 `AUDIT-2026-10-22-UX.md` §7。

**下一轮顺序**：F-01 → F-11（Row2/列宽，与 F-04 一并先出视觉方案）→ F-02（1/2/4 列对比稿）→ F-04（滚动/溢出菜单）→ F-08（批量重命名目录/尾点）→ F-03/F-05/F-06/F-07/F-09 → 补 Blocked 项。

---

### R-33 第二十六轮：F-01 实时主题切换修复

- 根因：玻璃窗口在显式浅/深色下仍把 `window.appearance` 设为 `nil`，实时切换后侧栏/顶栏/标签按旧外观解析；详情栏实体表面 `cgColor` 只在初始化时写一次。
- 实现：`ThemeManager.applyMode` 显式浅/深色时把窗口 appearance 一起锁定，只有 `.system` 才交给系统；详情栏增加 `.appearanceChanged` 刷新 `surfaceView` 底色/描边；顶栏与标签条增加 `refreshAppearance()`，控制器主题回调统一调用。
- 验证：独立副本 DEBUG `26102226` 浅→深→浅实机截图，侧栏/顶栏/列表头/详情栏颜色全部正确；全量分批 **428 条 0 失败**；自检因测试宿主窗口未创建未跑起来（环境阻塞，不冒充通过）。
- 构建：`make build` 成功，版本 **0.8.0-26102226**；未执行 `make demo`，桌面副本仍为 26102221。
- 剩余 P1：F-11 1060×700、F-02 详情栏、F-04 多标签、F-08 批量重命名目录/尾点，随后 F-03/F-05/F-06/F-07/F-09。

---

### R-34 第二十七轮：F-08 批量重命名目录/尾点修复

- 问题：批量重命名把目录纳入；`{name}.{ext}` 对无扩展名生成 `Empty Folder.`、`Projects.` 尾点名称，预览无告警。
- 实现：`showWindow` 只接收文件，忽略文件夹并在窗口标题提示「已忽略 N 个文件夹」；全为文件夹时弹中文提示。新增 `FFBatchRenamePattern` 纯函数：空扩展名时移除 `.{ext}`，名称统一清理尾随空白与点号；序号占位符行为不变。
- 测试：新增 `FFBatchRenamePatternTests` 4 条（空扩展名、正常扩展名、尾点清理、序号占位符）全绿。全量新增类定向通过；其余分批 428 通过；两条既有环境测试仍按前口径（DuplicateScan 单跑通过、delete 超时）。
- 构建：`make build` 成功，版本 **0.8.0-26102227**；未执行 `make demo`，桌面副本仍为 26102221。
- 未验：批量重命名窗口实机触发仍受菜单焦点限制；标题忽略提示未实机截图。

---

### R-35 第二十八轮：F-02 详情栏 1–4 列流动布局修复

- 问题：展开详情栏后只剩「名称 + 创建日期」两行（其余字段不可见），D-06「按空间排 1–4 列、无内部滚动条」不达标。
- 根因（实机日志定位）：`ExpandableDetailsBar.rearrangeFlow()` 用 `infoScrollView.contentView.bounds.height`
  当可用高度、用 `columnsStack.bounds.width` 当可用宽度。重排在 `layout()` 触发的**同一轮布局遍历**内执行，
  此时栏自身 `bounds` 已是展开态 132pt，而子视图尚未被约束引擎重排——实测 `contentModules` 108pt 而
  `infoScrollView` 仍是折叠态 30pt，`FFDetailsFlowLayout.columnLayout` 因此返回 `[[0],[4]]`（每列 1 行）；
  遍历结束后没有任何事件再次触发重排，错误布局固化（这也是先前「改成读 clip 高度」无效的原因）。
- 实现：新增 `infoAreaSizeForFlow`，可用宽高一律由栏自身推导
  （高 = `bounds.height - 顶部热区 6 - 状态栏 18`；宽 = `bounds.width - 左右缩进 8×2 - 图标区 - 分界线 8`）；
  行高改在脱离视图层级的测量台 `flowMeasureRig` 内按该宽度测量，不再依赖真实列的滞后宽度；
  移除 `rearrangeFlow` 里的 `layoutSubtreeIfNeeded()`（布局遍历内递归 flush）；
  把 `expandedView` 的 8/8/6 与分界线 8 提成 `expandedSideInset` / `iconDividerWidth` 常量，推导口径与约束同源。
- 测试：新增 `FFDetailsLayoutTests.testExpandedDetailsFlowFitsAllRowsIntoVisibleHeight`
  （刻意不 flush 布局、直接调用 `rearrangeFlow` 复现「子视图未重排」时刻）：改前红 `0 ≠ 8`，改后绿；
  既有 `FFDetailsBarTypeRowsFlowTests` 的「信息区应具备纵向滚动能力」断言与 D-06 冲突，
  改为 `hasVerticalScroller == false` + 可见列总高不得超过可视高度，并随契约更名为
  `testRowsStayAttachedWhenBarShrinks`。
- 验证：全量 16 批 **435 条 0 失败**（首轮第 4 批 1 条即上述旧断言，改后复跑 30/30）；
  布局相关 5 类 45 条 0 失败；自检 `FF_SELFTEST=1` 7 类通过 153 / 失败 0 + 布局压力 20 轮 0 失败。
  独立副本（Bundle ID `com.flowfinder.f02.live`，DEBUG **26102235**，PID 校验）实机展开态：
  双栏 1400 / 单窗口 1600 / 最小宽 760 三种宽度下 名称·种类·大小·位置·创建日期·修改日期·分辨率·标签·文件说明
  全部可见、无内部滚动条、无裁切，见 `images/audit-2026-10-22/15-f02-after-dual-pane.png`、
  `16-f02-after-single-1600.png`、`17-f02-after-min-760.png`。
- 遗留（另计）：长文件名/路径在窄列尾部截断归 F-07；磁盘可用空间仍未展示（`_ = diskFree`）未纳入本轮。
- 构建：`make build` 成功，版本 **0.8.0-26102235**；本轮文档收口后经用户授权覆盖桌面副本为 **0.8.0-26102235** 并启动验证（见下方变更记录「桌面副本同步」）。

---

## 2. 已知限制与技术债

| 项 | 说明 | 处置 |
|---|---|---|
| ~~`xcodebuild test` 在本机挂死~~ **已恢复** | 根因是开发模式被重置（`DevToolsSecurity` 当时 disabled，现 enabled）；2026-10-21 第十轮实测 282 条全绿 | 复现时先查 `DevToolsSecurity -status` 与 `xcode-select -p`；`FF_SELFTEST` 163 项作为双保险 |
| 合成鼠标事件不可靠 | CGWindowList 左上原点 / CGEvent 左下原点；`addLocalMonitorForEvents` 只拦 NSApplication 派发的事件 | 判定逻辑在应用内直接断言；事件派发交 AppKit |
| 合成事件环境三重干扰 | ① 本机 **CGEvent 的 y 是「屏幕顶部」原点**（与 CGWindowList 窗口坐标差一整屏）；② TCC 授权弹窗会吃掉点击；③ 桌面常被 Finder / WorkBuddy 窗口遮挡，点击打到别的 App | 物理拖拽验证需人机配合：清理桌面 → FlowFinder 置前台 → 手动拖 |
| 面板切换无位移动画 | `NSSplitView` 不参与隐式动画 | 见 R-02 |
| 加宽几何 | 2015×622 异常窗口已修：目标宽 = 侧栏 + 操作区×2 + 留白，钳制到屏幕可视宽度，只改宽度不动高度 | 已修（SPEC §1.14） |
| 说明列依赖 Spotlight | `kMDItemFinderComment` 需 CoreServices | 缓存 + 后台补 |
| 跨窗口拖拽手感未验 | 见 R-01 / R-14 | 人工验收：拖出 → 新窗口；拖回操作区 → 双栏 + 高亮；无效落点回原位 |
| 第七轮拖拽 60fps 未采样 | 结构级改动已完成（frame-based 插入线、几何缓存、60Hz、宽度守卫），但合成事件驱动不了真实拖拽 | 桌面副本上连续拖 3 秒 + Instruments/sample，p95 <16.7ms、无 `FileListView.layout → applyColumnFit → rebuildColumns` |
| 第七轮浮层/窗口拖动手感未验 | 完整胶囊浮层、1px 描边、`performDrag` 原生窗口拖动已接 | 人工确认：活动标签浮层不是文字幽灵；窗口拖动跟手；必要时 `FF_NATIVE_WINDOW_DRAG=0` 回退 |
| 面板切换真位移未做 | 用户已裁定走「自管布局」，但改动覆盖整个分栏体系 | 单独一轮做，不与其它改动混 |

### 2.5 未实现 / 未验证清单（截至 2026-10-22 · 0.8.0-26102218）

#### A. 未实现（有明确需求或用户已裁定）

| ID/来源 | 项 | 当前状态 | 建议 |
|---|---|---|---|
| R-02 | 单双面板切换的**面板真位移动画** | 只有窗口宽度与透明度动画；面板 frame 无位移（台账唯一「部分完成」需求） | 单独立项，自管分栏布局 |
| J2-08 | 两栏同步导航（默认关） | 无 | 排期 |
| J2-09 | 目录差异对比（仅左/仅右/大小不同） | 无 | 排期 |
| C-01 | 单一字体令牌来源 | `FFDesign.Text` 与 `FFVisualTokens.Font` 并存，硬编码 `systemFont` 122 处（棘轮上限） | 逐步替换并收紧 lint |
| R-06 | 图标线宽 1.75 | SVG 线宽烘焙，只能改尺寸 | 重导资源或放弃该指标 |

#### B. 未验证（代码在，缺真机/人工证据）

| 类别 | 未验项 |
|---|---|
| 拖拽 | 真实拖拽手感、跨窗口落点高亮、条内重排、活动标签浮层、窗口拖动、60fps 采样 |
| 硬件/系统 | 红绿灯物理点击关窗、1060×700、深色、高对比、Reduce Motion、真实全屏 |
| 网络/更新 | 真实 SMB 断线与状态条、更新提示（需线上有新 Release） |
| 交互 | QuickLook 空格/方向键/Esc、移动确认与终端打开的实际点击、工具页 Tab 人工走查、设置搜索、工具行 Enter 执行 |
| 侧栏/搜索 | 侧栏宽度跨重启持久化、首项「上移」置灰边界（2026-10-25 已验：六个收藏逐个点、标签新建/删除/改色、收藏右键 6 项实际执行、侧栏拖宽、双栏/本栏搜索） |
| 可访问性 | VoiceOver 完整走查（侧栏、详情栏、工具页） |
| 视觉 | 详情栏展开态、设置页、标签管理器、工具页浅/深色截图 |
| 性能 | 冷启动 <2s、10,000 行 ≥55fps 未正式测量；常驻 <250MB 已在 Release 1 万行实测 **174.9→185.2MB** |
| 测试环境 | `testDeleteIsNonBlocking` 在测试宿主移动真实文件到废纸篓时超时（单跑同样复现）；`DuplicateScanBrowseRegressionTests` 在分批/全量串跑中受 sheet/TCC 环境影响，单跑通过；全量串跑存在既有跨测试套件挂起，按测试类分 15 批执行 | 检查测试宿主 TCC/废纸篓服务；分批判跑作为当前基线手段 |
| 互通 | Finder「显示简介」双向标签互通的人眼确认（写入格式已有自动化断言） |

#### C. 发布与工作区状态

| 项 | 状态 |
|---|---|
| 已发布 `v0.8.0-b1` | 构建 `0.8.0-26102209`；**不含 R-25…R-30，也不含 R4 全量修复** |
| 桌面副本 | **`0.8.0-26102501`**（2026-10-25 `make build` 自动覆盖/重启；备份 26102409 在 `/tmp/ff-desktop-backup/`） |
| 最新构建 | Debug **`0.8.0-26102501`**（侧栏/搜索导航修复）；Release `0.8.0-26102215`（R-26） |
| R-25…R-39 + 2026-10-25 侧栏/搜索修复与补验 | **待推送** `feat/v0.9-overhaul`（提交后回写哈希） |
| 基线 | XCTest 全量 **542 条 0 失败**（2026-10-24 R-39 实测，跳过 2 条既有环境测试：`testBrowseSheetReappearsAfterDeleteAndRescan` 单跑 16.656s 通过；`testHardcodedTokenBudget` 外部卷阻塞）/ 2026-10-25 新增 1 条回归单测单跑通过（0.914s，全套未重跑）/ 自检 **153 + 20 轮布局压力 0 失败**（2026-10-24）/ Rust **200 通过 0 失败**（2026-10-24 实测） |

---

## 3. 变更记录

> **2026-10-23 更正**：当日「第 3 批」行原先写「R4-08 的『进入全屏幕』由系统注入，属误判」，随后按实测（窗口菜单里只有「填充/居中/全屏幕平铺」，无「进入全屏幕」，且全库无 `collectionBehavior`/`toggleFullScreen` 声明）推翻——已就地改为「窗口清单已恢复、全屏半条未修转入下一轮」。教训：菜单条目要在应用激活且菜单真实打开后逐条读，`enable` 状态在未激活时全为 false（本轮探针曾因此误判），条目存在性同理要复核。

| 日期 | 内容 |
|---|---|
| 2026-10-25 | **侧栏/搜索剩余测试项真机收口（0.8.0-26102501）** —— ① 六个收藏（桌面/文档/下载/应用程序/AI 生图/Cline）逐个单击均正确跳转；② 侧栏从边缘条起拖可调宽、从列表内容区起拖无效；恢复后 outline 186 / 滚动区 208，跨重启持久化未验；③ 标签新建（AX「创建」）、改色、删除均生效，无重命名菜单项；④ 收藏右键 6 项在临时收藏 `~/Downloads/ff-fav-test` 上全部实际执行：显示简介（独立窗口；位置 `/Users/waltxao/Downloads`、0 字节 1 项）、在新标签页/新窗口打开（面包屑与 `probe.txt` 行正确）、上移/下移（AX 顺序往返复原）、从边栏移除（余 6 项；`SidebarFavorites` 解码为 桌面/文档/下载/应用程序/AI 生图/Cline）；临时目录已删、Downloads 刷新后不再出现；⑤ 双栏搜索：首次进入右栏 Desktop 报「目录读取超时」，点「重试」载入，再次进入 3s 内正常（偶发，与 C1 同型，未取样）；范围「双栏」时两侧输入框互相同步，输入 `2026` 后左栏 9 行 / 右栏 6 行各自过滤；切「本栏」后两栏解耦（左清空恢复 12 行、右保留 `2026`）；切回单栏 804×900，保留当前活动栏的标签。证据为本地 `docs/images/audit-2026-10-25-sidebar-search/`（含个人文件名，未随公开仓库上传）。**补验发现（未修）**：a) 末项「下移」在菜单里仍为 ON，点击为 no-op；b) 外部删除已选目录并刷新后，详情栏仍残留 `ff-fav-test -- · 文件夹`，清空 `AXSelectedRows` 也不消失（与「误入后详情栏残留 sub」同型，已第二次复现）。**未验**：侧栏宽度跨重启、首项「上移」边界、动画手感/减弱动态/240 弹性。随本轮推送 `feat/v0.9-overhaul`（哈希见 §2.5 C） |
| 2026-10-25 | **侧栏与搜索真机审计 + 两个导航缺陷修复（0.8.0-26102501）** —— ① **收藏复点无效**：当前目录位于某收藏的子目录时，该收藏行保持选中，复点不触发 selection change → 不导航；修复在 `SidebarView.swift` 的 `FFFNoDisclosureOutlineView` 增加 `onReselectRow`：mouseDown 记录“已选中行”，super 后若单击且位移 ≤3pt（排除拖拽重排）则调用 `navigateToSelectedFavorite()`。② **清空搜索后 Return 误入首项**：搜索框 Enter 走 `paneToolbarDidRequestOpenResult`，空词时仍会“落首项 + 打开”；修复在 `MainWindowController` 先判 `searchQuery.trimmingCharacters`，空/纯空白直接 return（只激活面板，不选/不开）。新增回归 `FFBatch2IntegrationTests.testSearchEnterWithEmptyQueryDoesNotOpenFirstItem`（0.914s 通过；`xcodebuild build-for-testing` 通过）。真机复核：子目录内单击 AI 生图收藏一次即回根（`fix1-inside.png` → `fix1-after-reselect.png`）；搜索 Gemini → 清空 → Return 后仍在 AI 生图（`fix2-search.png` → `fix2-after-empty-return.png`）。同轮审计：侧栏实际仅 个人收藏/位置/标签 三段，截图中的「工作区/最近任务/站点/自动化/扩展/更多/waltxx」是 Qoder 窗口透过液态玻璃的透字（窗口移到壁纸区即消失，`moved-right.png`），不是缺失 UI；含子目录递归用临时目录验到深层命中；收藏右键 6 项、标签筛选、位置悬停容量均正常。未验：双栏搜索、标签新建/删除/改色、收藏右键动作实际执行、侧栏拖宽、其余 4 个收藏逐个点。重启后弹出自身文件权限门与「访问桌面」TCC，未点允许，需用户处理。`make build` 已备份 26102409 并覆盖/重启桌面副本；当轮未提交、未推送，后由同日第三十三轮收口一并推送 |
| 2026-10-24 | **构建后自动更新桌面副本（用户规则）**：新增 `scripts/deploy-desktop-copy.sh` 并接入 `make build` 末尾——签名门禁 → 备份旧版到 `/tmp/ff-desktop-backup/FlowFinder-<旧版本>.app` → `ditto` 覆盖 `~/Desktop/FlowFinder.app` → 覆盖后签名/版本校验 → 终止旧桌面实例并重启。新增 `make desktop-copy`（只覆盖不构建）、`FF_DESKTOP_RELAUNCH=0`（只覆盖不重启）。首次执行将桌面从 26102404 更新到 **26102405**，旧版已备份；重签导致 TCC 权限重置，需用户重新授权。未提交/未推送 |
| 2026-10-24 | **R-37 工具模块合并到底栏** —— 7 项决策：圆钮浮详情栏外侧（36pt，栏 trailing 让出 52pt）；点击向左长成工具栏、详情栏缩成 54pt 图标圆（无文字不可点）；几何 A（圆左 8、工具栏 left 70→右缘、双列）；高度继承详情档位（54/132/240，无拉手，54 档滚动）；执行工具立即回详情、切换选中/目录/活动面板也回详情；不自动缩回圆钮；右端圆钮保留为蓝色状态指示不可点。实现：新增 `FFToolsBar.swift`（圆钮/详情圆/行/工具栏/协调器）；`MainWindowController` 每面板接线、`toolContext(for:)`、`updatePaneUI`/`activatePane` 自动回；`SidebarView` 工具胶囊入口退役；删除 12 条侧栏工具页测试、新增 `FFToolsBarV2Tests` 7 条。验证：工具 7/7、catalog 3/3、全量 467 条断言 0 失败（`DuplicateScanBrowseRegressionTests` 串跑超时但单跑 16.8s 通过；`testHardcodedTokenBudget` 外部卷 EINTR）；真机隔离副本 26102405：54/132 工具栏、任务中心/设置自动回、选中变化自动回、右圆钮状态指示。未覆盖桌面副本（26102404）；未提交/未推送 |
| 2026-10-24 | **R-38 药丸详情栏 + 独立圆形工具簇（推翻 R-37；26102407/26102408 回归修复）** —— 默认 54pt 药丸（半径 27）+ 54pt 圆扳手同高同心；展开 132/240 卡片（12pt 圆角，不沿用药丸半径）且按钮自动隐藏、卡片铺到 trailing −8；点击拉手或药丸/卡片空白切换；工具态仅折叠可开，详情缩 left 8 的 54pt 图标圆，原按钮变 54pt ×，N 个独立 54pt 玻璃圆右对齐紧贴 ×（间隙 8）；仅列当前可用的文件工具 3/4/1（设置/关于不进入工具簇）；执行回默认；选中/目录/活动面板变化只刷新不关闭；窄面板 8→2→横向滚动。实现：`ExpandableDetailsBar` 折叠 27/展开 12、穿透命中、onExpansionChanged、收起隐藏状态栏；重写 `FFToolsBar.swift`（玻璃圆基类含隐藏 hitTest 与 acceptsFirstMouse、工具/关闭/详情圆、滚动簇、协调器）；`MainWindowController` trailing 交由协调器。**26102406 真机缺陷**：① 关闭钮与工具钮同 frame，隐藏的关闭钮仍从 hitTest 返回自身，吞掉物理点击（AXPress 绕过 hitTest 所以前一轮误判通过）；② updatePillShape 一律用 height/2，132 展开被 66pt 半圆端裁切。修复：隐藏/淡出 hitTest 返回 nil + acceptsFirstMouse；展开改 12pt 卡片；新增窗口级 mouseDown 测试。**26102408**：按用户要求将「设置」「关于」移出工具簇（`includedToolIDs` 仅留 duplicate-scan/batch-rename/batch-organize/task-center），catalog 与工具计数同步为 3/4/1。测试：`FFDetailsPillTests` 4 + `FFToolsBarV2Tests` 12；定向 48/0；全量 Swift **538 条 0 失败**（跳过 2 条既有环境测试；重复扫描单跑 16.656s 通过；token budget 外部卷 0 条执行/150s 超时，shell 读同目录 0.04s）；Rust 200/0；自检 153/0 + 20 轮 0 失败（26102406 复跑，26102407/26102408 未重跑）。真机桌面副本 0.8.0-26102408（窗口 26221）：物理点击工具钮→3 圆（无选中）/4 圆（选中2）、×→回默认；132 卡片内容完整；截图 `docs/images/audit-2026-10-24-pilltools/`（01–09）。未验：240 真机/深色玻璃/减弱动态/捏合/窄面板滚动/全部工具执行/Tab 环。未提交/未推送 |
| 2026-10-24 | **R-39 任务按钮注水 + 弹性开合动画** —— 任务记录 = `FFTaskService` ∪ `TaskSchedulerManager`（含终态直到清除）；`FFTaskSummary` 聚合：活动任务平均，无活动但有记录=1，无记录=0。有任务时右侧 54pt 工具钮换 `.listChecks` 图标并图标注水（0.3s 水位，100% 注满），点击仍开工具簇；簇内任务中心圆仅在有任务时渲染并共用进度；无任务 2/3/0、有任务 3/4/1；设置/关于仍不在工具簇。动画：圆钮按下 0.94/松开弹簧（动作移到 mouseUp，AXPress 不变）；详情栏内容淡出后用 width 约束 0.34s 弹性缩到 54 圆（圆角 27），完成后隐藏；工具圆 `CASpringAnimation` 从 × 侧 stagger 0.025s 滑出、关闭反向；详情栏高度 0.36s `(0.22,1.18,0.36,1.0)` 过冲，关闭 0.26s；内容 0.12s 淡入；减弱动态跳变。测试：`FFTaskButtonTests` 3（聚合/条件显隐/按钮切换），`FFToolsBarV2Tests` 13（+真实窗口形变收敛），定向 23/0；全量 Swift **542 条 0 失败**（跳过 2 条既有环境测试）；Rust 200/0。真机 26102409：物理点击打开工具簇、无任务仅 2 圆、详情栏形变完成后隐藏已由 AX 确认；**动画手感与有任务注水因系统「访问文稿」TCC 弹窗未代点，未完成录屏/目视，标未验**。未提交/未推送 |
| 2026-10-24 | **桌面副本同步 26102403（用户授权）**：`make build` 产物 0.8.0-26102403；新鲜度（无源码晚于二进制）与 `codesign --verify --deep --strict` 通过；旧 26102308 备份到 `/tmp/ff-desktop-backup/FlowFinder-26102308.app` 后覆盖 `~/Desktop/FlowFinder.app`；启动 PID 49203、窗口 25479 @ (260,30) 1400×900，侧栏版本标签实测 `0.8.0-26102403 Beta`，详情栏收起态与白色拉手正常。重签名后 macOS TCC 权限被重置，Desktop/Documents 读取超时，需用户在系统设置重新授权（未代点）。未提交/未推送 |
| 2026-10-24 | **R-36 详情栏重做（液态玻璃 + 三档拉手 + 完整内容滚动）** —— 10 项用户决策（D-01 C 浮层+滚动条内缩 / D-02 C 三档 / D-02a A 点击回上次档 / D-03 A 栏内滚动 / D-04 A+B+C 图标三入口 / D-04a C 上限 200+图标区 232 / D-05 B 不限行换行 / D-06 A .regular 玻璃 / D-07 A ⌘I 与点击一致 / D-08 A 93/186 吸附）。实现：`FFDetailsTier` + `FFDetailsBarTierState`；`FFDetailsGripHandle`（38×4 白色胶囊、120×16 命中、点击/拖动 4pt 分界、AX Increment/Decrement）；移除 chevron 与 6pt 隐形热区；`FFIconResizeHandle` + 右键预设（64/48/96/200）+ 捏合；`NSGlassEffectView(.regular)` 底层兄弟视图（旧系统回退）；`hasVerticalScroller` + `scrollLayout` 全部行保留；名称/路径不限行并按列宽回填；列表/网格 `contentInsets` + `scrollerInsets` 同步；设置滑杆 48–200。测试：新增 `FFDetailsBarV2Tests` 14 条；详情三组 33 条 0 失败；Rust 200/0；全量 472 条 470 通过 / 2 条环境失败（外部卷 EINTR + 既有删除通知 flaky）。真机独立副本 `com.flowfinder.native.detailsbarverify` 0.8.0-26102402：三态截图（54/132/240+图标200）、AX 值 54→132→240→132、点击展开/收起、右键菜单选大、大档滚到底末行与滚动条均在栏上方。最终源码构建 26102403。未验：连续拖拽手感/捏合/深色玻璃/信息区溢出实际滚动截图；未提交/未推送 |
| 2026-10-23 | **C13 验证：文件夹大小递归汇总已由 R4-21 修复** —— 真机实测 `calculateFolderSizeAsync` 递归汇总正常：① "照片 2026" 算出 32 KB（2 文件 31875 字节，`du -sh` 36K）；② "子目录"（含嵌套子目录 `更深的目录/`）算出 307 KB（2 文件 307200 字节，`du -sh` 300K）。`[DETAILS-DIAG]` 日志确认异步块被调用、`self.entry?.path == path` 守卫通过、sizeField 被正确回填。台账原 C13「4 KB vs 实际 1.3 MB」为 R4-21 修复前的状态，本轮验证后标记为已修。未提交/未推送 |
| 2026-10-23 | **Issue 3 修复（真机测试反馈）：列表模式选中框之间无间隙** —— 根因：`FFTableRowView.selectionHighlightStyle = .regular` 让系统先画满宽无间隙选中高亮，覆盖自定义 `drawSelection(in:)` 的 `insetBy(dy: 1)` 间隙。修复：① `selectionHighlightStyle` 改为 `.none`（系统不画选中高亮）；② `draw(_:)` 在 `super.draw(dirtyRect)` 之前手动调用 `drawSelection(in:)` 绘制 inset 高亮（insetBy(dx:4, dy:1) + 5pt 圆角），确保选中底色在 cell 内容之下；③ `dy` 从 `0` 改为 `1`，相邻选中行之间留出 2pt 间隙。Swift 编译零错误。Debug `0.8.0-26102308`。未提交/未推送 |
| 2026-10-23 | **Bug 1+2 修复（真机测试反馈）**：① 列表/网格模式单击变选择——根因是 `MainWindowController.setupUI` 将 `NSGlassEffectView` 直接设为 `window.contentView`，macOS 26 上玻璃视图拦截鼠标事件导致子视图单击回调受阻。修复：改用普通 `NSView` 容器作为 `contentView`，`NSGlassEffectView`/`NSVisualEffectView` 与 `mainContainer` 作为并列子视图（玻璃底层、内容在上层），`ThemeManager.findMainContainer()` 已有此架构支持无需改动。② 网格模式文件夹图标尺寸不正确——两个根因：`layout.itemSize` 初始高度 `+12`（line 997）与缩放方法 `+20`（line 1354）不一致，统一为 `+20`；图标源尺寸硬编码 48pt 但 `setThumbnail` 约束到 `thumbnailMaxEdge`（默认 88pt），48pt 被拉伸 1.83x 模糊，改为按 `thumbnailMaxEdge` 生成（文件夹/文件占位/缩略图三处）。Swift 编译零错误。未提交/未推送 |
| 2026-10-23 | **按钮液态玻璃适配（macOS 26+）**：三个在玻璃表面上的自定义按钮添加 `NSGlassEffectView(.clear)` 液态玻璃背景——① `FFPillButton`（发现功能药丸）：胶囊形玻璃背景替代自绘 `labelColor` 半透明底色，选中态叠 accent tint 层，焦点环保留；② `FFHoverIconButton`（侧栏顶部图标按钮）：圆形玻璃 hover 背景替代自绘底色，仅 hover/press 时显示；③ `FFSidebarRevealHost.button`（显示侧栏按钮）：28pt 圆形玻璃底座包裹 24pt 按钮。标准 `.rounded`/`.accessoryBarAction` 按钮由系统自动处理液态玻璃。面包屑/标签栏按钮在实体工具栏上（`FFDesign.operationAreaElevated`），不改。Swift 编译零错误。未提交/未推送 |
| 2026-10-23 | **C5 修复 + 右键菜单补全 + macOS 26 液态玻璃适配**：① C5 任务中心双「暂无任务」——`TaskPanelWindowController.swift:211` 空态时 `statusLabel.stringValue = ""`（中央 `emptyLabel` 已传达空态，右上角不再重复）；② 右键菜单补「批量重命名…」——`FFPaneMenuBuilder.buildMenu` 在「重命名」后新增 `batchRenameSelected` 菜单项（`FFIconName.penLine` 图标），`FFPaneActionsController.batchRenameSelected` 转发至 `MainWindowController.menuBatchRename`，`updateMainMenu` 按所选文件数（非目录）控制可见/禁用 + tooltip（`FFNaming.batchRenameRequires`）；③ 「用所选项目新建文件夹」阈值从 `>= 2` 改为 `>= 1`（选中 1 个也可建新文件夹，标题按数量动态变化）；④ macOS 26 液态玻璃——`MainWindowController.setupUI` 窗口级背景改为 `#available(macOS 26.0, *)` 分支：macOS 26+ 用 `NSGlassEffectView(.regular, cornerRadius: 0)`，旧版保留 `NSVisualEffectView(.underWindowBackground)`；`ThemeManager.findMainContainer()` 已支持 NSGlassEffectView 作为 contentView（无需改动）；`SidebarView` 注释同步更新。Swift 编译零错误（链接失败仅因 Rust FFI 库未针对当前架构编译，环境问题）。未提交/未推送 |
| 2026-10-23 | **C3 修复：⇧⌘N 新建文件夹不进内联重命名** —— 根因：`.ffTagCacheWarmed` 通知在内联重命名开始后 33-43ms 触发，`tagCacheWarmed()` → `reloadData()` 重建所有 cell，编辑中的 textField 丢失 firstResponder，`controlTextDidEndEditing` 触发 `endInlineRename`，文件夹名保持不变。修复：① `FileListView.tagCacheWarmed()` 加 `guard !self.actionsController.isRenaming`；② `listColumnsDidChange()` 同理；③ Combine sink `$state` 订阅内加同一 guard；④ `FFPaneActionsController.isRenaming` 从 `private` 改为 `internal` 供视图层读取。**测试**：`FFNewFolderRenameTests` 新增 `testIsRenamingPropertyIsAccessible` 1 条，3/3 绿。**真机**：独立副本 0.8.0-26102305（PID 68105）⇧⌘N 后文本框持续可编辑、输入「C3-fix-test」+ Return 成功重命名，列表显示新名称；AX 树确认 element 320 `文本栏 (settable) Value: 未命名文件夹 4` 在 2 秒后仍存在（此前 33-43ms 即被销毁）。未提交/未推送 |
| 2026-10-23 | **查重窗口簇 C7–C10**：C7 组名由「重复组（hash 前 8 位）」改为「N 个相同文件 · 首个文件名」（新增纯函数 `DuplicateGroupTitle`）；C8 新增 `FFByteText.format`——<1000 一律「N 字节」（修掉 `0 KB` / `可释放 6` / `0字节` 三处丢单位或缺空格），≥1000 走 ByteCountFormatter file 档（1000 进制、与访达一致），替换查重窗口 4 处 formatter；C9 复核发现「确认删除」原本就是 `isEnabled = !allPaths.isEmpty`（0 选择时点击无反馈＝已禁用），本轮只补 tooltip 说明如何标记删除（视觉误导，不是逻辑缺陷）；C10 组头 NSButton 不再暴露默认标题「按钮」，补 `setAccessibilityLabel` 为组名。**测试**：`FFDuplicateLayoutTests` 新增 2 条（字节单位、组标题），5/5 绿；全量 17 批 **521 条**，`FFDetailsBarTypeRowsFlowTests.testRowsStayAttachedWhenBarShrinks`（8≠9）失败——今日 4 次全量中 2 败 2 过、单跑 1 过 1 败，判 `ENV/FLAKY`（查重改动不涉及详情栏布局）。**真机**：查重窗口本轮未能驱动打开（工具菜单与 ⌘D 均无响应），C7/C8/C10 的真机复核**未做**。未提交/未推送 |
| 2026-10-23 | **C1 部分修复（首启目录卡死的「误导文案 + 授权误报」）** —— 未改动 Rust 侧 `open(2)` 阻塞本身（阻塞 syscall 无法在用户态中断，要做可中断得换非阻塞 open 或进程隔离，属独立改动）。本轮修三点：① `CoreBridge` 超时文案由「目录响应超时（磁盘或网络无响应），可重试」改为「目录读取超时」，新增 `FFErrorText` 规则按「权限未授予 / iCloud 同步 / 网络卷无响应」三种可能给出下一步；② `FFPermissionGate` 去掉 `report.timedOut = false` 硬编码，改为「等待超时且无明确拒绝 → 待确认」；③ 引导页权限行新增「待确认」（橙色），不再把未应答显示成「已授权」。**测试**：新增 `testDirectoryTimeoutExplainsLikelyCauses`（先红：detail 为空）后绿，`OnboardingPolicy` 补 2 条断言；全量 **17 批 519 条 0 失败**。**真机**：本轮新身份副本首启两栏直接载入 13/12 项、无超时浮层 → 卡死**未复现**（环境相关），故「卡死时新文案的实际显示」**未取得真机证据**；根因仍在，卡死时阻塞线程仍会泄漏。未提交/未推送 |
| 2026-10-23 | **C15 修复：AX 选中必崩（P1）** —— 根因：`accessibilityRows/VisibleRows/SelectedRows` 用 `unsafeBitCast` 把 `[FFAXRowElement]` 当 `[NSAccessibilityRow]` 交出，AX 客户端回填 `AXSelectedRows` 时 AppKit 把运行时并不符合协议的对象桥接成协议存在数组，`compactMap` 首次取元素即 `_ArrayBuffer._getElementSlowPath → _assertionFailure`（SIGTRAP）。修法：setter 改为 `selectedRows as NSArray` 后按 `FFAXRowElement` + `table === self` + 索引边界过滤；显式空数组仍清空选中、只含外来对象则保持不动；getter/children 维持既有 bitcast（本轮实测 getter 路径无崩溃）。**试过并放弃**：① 让 `FFAXRowElement` 直接声明 `NSAccessibilityRow` —— 本 SDK 下 `accessibilityIdentifier()` 与 `NSAccessibilityElement` 可选性冲突，编译不过；② `NSObject` 句柄方案 —— 写路径不崩，但 AX 树里行全丢（VoiceOver 看不到行），属更严重退步。**测试**：`FFAXVirtualizationTests` 新增 2 条（外来行不改选中、本表行生效），先红（外来行把选中从 {2} 改成 {0}）后绿 6/6 全过；全量 **17 批 518 条**（较接手基线 +2，均为本轮新增），唯一失败 `FFDetailsBarTypeRowsFlowTests.testRowsStayAttachedWhenBarShrinks` 单跑 5/5 通过 → 判 `ENV/ORDER-DEPENDENT`，**净失败 0**。**真机**：独立副本连续 3 次 `AXSelectedRows` 写入全部 OK、进程存活、行索引映射正确（丙/甲/乙 排序下 row1=甲，与详情栏一致）。未提交/未推送 |
| 2026-10-23 | **接手复跑 + 四轮真机实测（未改产品代码、未 commit、未覆盖桌面副本）**：基线原样复跑 **Rust 200/0 · XCTest 17 批 516 条 0 失败（BATCH1 一次通过）· 自检 7 类 153 + 落点 ①–⑩ + 20 轮 0 失败**；**153 vs 163 口径差已解释**（落点 10 条为独立 PASS 行，163 = 153 + 10）。五份独立 Bundle ID 副本实测复核 R4 全 32 条与台账实机声称：**通过** R4-01/02/04/05（内联提示，非 tooltip）/06/07/08/09/10/11/12/13/14/15/16/19/21①②/22/23/24/26/28/29/30/32 + R-08（受控留白拖拽：位置与尺寸不变，仅左栏 457→446）+ R-30（独立确认弹窗、无法撤销、无「不再询问」）+ J1-07 + J2-03（跨栏拖拽同盘移动、两栏即时刷新）+ J4-06（Space/→/Esc）+ L-02（红绿灯关窗）+ R-01/R-14（拖标签出窗成新窗、源折单栏）+ 主题重启持久化。**冲突/新缺陷**：C1 首启受保护目录 `open(2)` 卡死（`bulk_read.rs:114`，`sample` 1648/1648 命中）+「磁盘或网络无响应」误导文案；C3 ⇧⌘N 不进内联重命名；C4 外部终端变更不刷新（应用内操作会刷新）；C5 任务中心空态两处「暂无任务」；C7 查重组名仍 hash；C8 可释放量单位丢失/不一致；C9 确认删除常亮且 0 选择点击无反馈；C10 查重列头字面「按钮」；C11 6 标签即裁切无溢出；C13 文件夹大小不递归汇总（4 KB vs 实际 1.3 MB）；C14 深色小字对比度实测 1.88/1.84（声称 5.89，待同口径复算）；**C15 P1：AX `setAccessibilitySelectedRows` 必崩（`FileListView.swift:153`，2/2 复现，SIGTRAP）**。文档口径：C2 全屏项存在、C6 Skill 镜像假隔离（`Resources/Info.plist` 硬编码 bundle id）、C16 R4-05 机制写错、C18 J4-08 已降级。未验：VoiceOver（用户不测）/高对比度/60fps/SMB/查重执行删除/R4-31 色点/长路径截断/拖拽手感。证据 `docs/images/audit-2026-10-23-takeover/`（26 个文件） |

| 2026-10-23 | **桌面副本同步 + AI 资源入库 + 工作区归档（用户指令）**：① `make build` 出 **0.8.0-26102301**（R4 全量修复，构建号较 26102235 递增一次）；走 `flowfinder-desktop-copy-deploy` 门禁——新鲜度（二进制 10:23 晚于全部源码）与 `codesign --verify --deep` 均通过后备份旧包到 `/tmp/ff-desktop-backup/FlowFinder-26102235.app` 再覆盖，实机取证 **PID 16478、窗口 260,30 1400×900、侧栏版本标签实测 `0.8.0-26102301 Beta`**；未重跑 `make demo`（避免多递增构建号）。② AI 资源入库：`resources/ai-tools/skills-2026-10-23/` 新增 19 个 FlowFinder/macOS 工具链 Skill 快照（484K，源自 `~/.qoder/skills/`：xctest 分批验证、桌面部署门禁、CUA 审计链、AppKit 调试法等），`MCP-AND-SKILLS.md` 增补 §一·b/§三·b 与 R4 轮 MCP 使用实测（遮挡下置顶不可行、取证三手段）。③ 工作区归档：顶层 8 个 7–8 月遗留文件（icon.icns、容器*.png、ChatGPT Image、omo_vision_test.png、bug详细信息md.md、代码审查报告.md）经引用核对后**移动**（未删除）到 `../_archive/2026-10-23/` 并附逐文件判定 README；`SMBFileManager/`（3.8G 前身项目）与各设计目录有意不动。未提交/未推送 |
| 2026-10-23 | **第四轮 UI/UX 审计（R4）全量修复收口**（用户指令「开始全量修复」）：`docs/AUDIT-2026-10-23-UIUX-R4.md` 全部 32 条按 §9 五批处理完毕——第 1 批 R4-01、第 2 批 R4-03/R4-02、第 3 批 R4-06/07/08/09/10/11/20、第 4 批 R4-04/05/13–17/18、第 5 批 R4-21–31 + R4-12/19/32。全量 XCTest **17 批 516 条 0 失败**（较 435 基线 +81：本轮新建 `FFMenuContractTests` 17、`FFSettingsPolishTests` 15、`FFBatchRenameTests` 10、`FFLocalizationTests` 6、`FFTaskPanelTests` 6、`FFTagSelectorDialogTests` 3、`FFNewFolderRenameTests` 2 等类；字体棘轮收敛后再跑受影响的第 3 批 5 类 **48 条 0 失败**，其余批次无字体断言）、应用内自检 **153 通过 + 20 轮布局压力 0 失败**、Rust core **200 通过 0 失败**（同轮实测）；验证副本 = 隔离 fulltest Debug `0.8.0-26102235`（`/tmp/ff-r4b4-verify`，本轮未跑 `make build`，构建号未递增）；**未覆盖桌面副本、未提交、未推送**。真机走查限制：本机被用户自有窗口完全遮挡，`NSRunningApplication.activate`/AXRaise 均无法置顶，故视觉取证只用窗口 ID 截图 + AX frame + 视图内 `cacheDisplay` 自绘位图，**整屏目视与鼠标坐标点击未做**（坐标点击会落到遮挡窗口） |
| 2026-10-23 | **R4 测试基础设施缺陷（假绿）**：Xcode 工程无 filesystem-synchronized groups，`Tests/FlowFinderTests/` 下新建的 `.swift` 不会自动编译，直接产出「Executed 0 tests … ** TEST SUCCEEDED **」的假绿；新增测试类必须手补 4 处 pbxproj 条目（PBXBuildFile / PBXFileReference / group children / Sources phase）。第 3 批的 `FFMenuContractTests` 首跑即中招，补条目后 17 条全部真跑；后续任何新测试类先核对 `xcodebuild` 输出里的 `Executed N tests` 是否为 0 |
| 2026-10-23 | **第 5 批 P3 打磨（R4-21…R4-31）**：R4-21 详情栏 `位置` 写完整路径 tooltip（`ExpandableDetailsBar.swift:1443`）、`文件说明` 空值写占位而非空标签悬挂（:642/:1782）、文件夹 `大小` 异步递归汇总后回填（:1435/:2156）；R4-22 任务面板关掉交替色空行条纹（`TaskPanelWindowController.swift:123`）；R4-23「取消任务」按选中行可用性禁用并把原因写进 tooltip（:237-261）；R4-24 新增「定位」按钮（:94）+ `navigate(to:selecting:)` 顺带修「跳转后列表仍是陈旧内容」；R4-25 侧栏「位置」分区收录规则统一（`SidebarView.swift:1560-1710`），主目录不再作为设备入口重复出现在「个人收藏」旁；R4-26 设置主题卡不再固定 100×100 左对齐（随栏宽铺开、消除右侧死白）、去掉 `主题` 分区下多余的 `外观` 标题、月亮图标不再同时充当分区图标与「深色」选项图标；R4-27 小字统一走 `FFVisualTokens.hint`（secondaryLabel），实测对比度 **2.26→5.89**；R4-28 `显示隐藏文件` 补 ⌘⇧.（`MainMenu.swift:139-141`，原注释误标 R4-11，本轮已改标）；R4-29 详情栏显隐从「文件」菜单的「显示简介」归位到「显示」菜单并带快捷键（`MainMenu.swift:151`）；R4-30 查重窗口路径框改只读外观、最小尺寸 **600×400→720×480**（`DuplicateScanWindowController.swift:71`）；R4-31 标签选择弹窗色点改为可点选项、压缩下方空白。附带把两处写死的 10pt 小字收敛为 `FFVisualTokens.Font.hint`，使硬编码字体棘轮从越界的 128 回到预算 127（未放宽预算）；未提交/未推送 |
| 2026-10-23 | **R4-32（修复 R4-12 过程中新发现）深色模式下窗口背景钉死为纯白**：根因是 `NSColor.windowBackgroundColor.cgColor` 在没有 drawing-appearance 上下文时解析出 **Aqua 值**（实测无上下文 255,255,255 / darkAqua 30,30,30 / aqua 255,255,255），而 layer 只吃 CGColor 快照，构建期写一次就把背景钉在旧外观上——批量重命名窗口底部 56pt 留白带实测纯白、字段与图例按深色解析后在白底上隐形。把 `FFModalSheet` 里已有的正确写法提为 `FFDynamicBackgroundView`（`wantsUpdateLayer` + `performAsCurrentDrawingAppearance` + `viewDidChangeEffectiveAppearance`），接入 4 处构建期冻结点：`BatchRenameWindowController.swift:166`、`FileInfoWindowController.swift:76`、`FFTagRemovalSheet.swift:77`、`MainWindowController.swift:1549`（长期复用的 SMB toast 容器）；`FileInfoWindowController.swift:507` 的标签 pill 仍是旧写法（每次刷新重建，暂未改）；回归 `testWindowBackgroundFollowsLiveThemeSwitch` 先红（浅/深实测同为 255,255,255）后绿，实机深色窗口截图 `docs/images/audit-2026-10-23-r4fix/ff-r432-fixed.png`；未提交/未推送 |
| 2026-10-23 | **第 5 批 R4-12 批量重命名窗口 + R4-19/R4-20 复核**：R4-12 五项——① 跨目录同名冲突判定改为按各自目标目录（`existingNamesByDir`），不再把不同目录的同名误报为冲突、也不再漏报；② 空扩展名不再产生结尾 `.`，尾点统一清理；③ 冲突/改扩展名以颜色标注并在行内 tooltip 写明原因，图例常驻底部；④ 新增「只看冲突」开关（`onlyConflictsSwitch` + `visibleIndices`）；⑤ 计划清单改实线网格（`.solidHorizontalGridLineMask`）、默认前缀改为空。`FFBatchRenameTests` 10 条，其中 `testBottomBarControlsArePainted` 用 `cacheDisplay` 位图判定按钮栏是否画得出内容（整条纯色即失败），绕开窗口遮挡；另注意 `cacheDisplay` **不合成**容器 `layer.backgroundColor`，用它验背景会得到假绿。R4-19「单面板死标签」复核**不成立**：`PaneTabs.swift:852-855` 按 `showLeft/showRight` 隐藏非活动栏标签条，实测无点不到的条目；1400→810 自动收窄是 `FFPaneModeAnimator` 的设计行为，审计 §2 已标注。R4-20「编辑菜单校验」**成立并已修**：真实根因是列表视图自己的 `validateUserInterfaceItem` 抢先返回 true（`MainWindowController+MenuActions.swift:16`），无选中时剪切/复制现置灰、粘贴按剪贴板内容判定；未提交/未推送 |
| 2026-10-23 | **第 4 批 设置与对话框打磨（R4-04/05/13–18）**：R4-04 主题三卡与设置侧栏补选中态（描边 + 勾选，不再只靠色差）；R4-05「连接到服务器」四个协议里只有 SMB 可用，其余三项置灰并在 tooltip 写明「尚未实现」；R4-13 文件管理分区名与内容对齐、修病句、删除不生效的伪设置行；R4-14 网络存储页统一容器写法（消除两套行高）、三重空态收敛为一、服务器图标换成语义正确的 `externaldrive`；R4-15 快捷键页搜索框/录制入口可用性与文案；R4-16 「关于」去掉 AI 味文案、版本号与构建号分行；R4-17 全局搜索筛选语义去重叠、复选框改非禁用外观（原 `.small` + 置灰像不可用）；R4-18 ⇧⌘N 新建文件夹后进入内联重命名并选中新项（`PaneState`/`FileListView`/`FFPaneActionsController`，`FFNewFolderRenameTests` 2 条）；新增 `FFSettingsPolishTests` 15 条；`make build` 未跑，构建号仍为 26102235；未提交/未推送 |
| 2026-10-23 | **第 3 批 菜单契约与命名统一（R4-06/07/08/09/10/11）**：新增 `FFNaming` 作为除侧栏/工具注册表外所有入口的唯一叫法来源（任务中心/重复文件扫描/批量重命名/批量整理/移动到废纸篓/连接服务器/编辑标签/未命名文件夹/详情栏），消除「任务面板 vs 任务中心」「查重扫描 vs 重复文件扫描」等漂移；R4-07 侧栏开关改名避开 AppKit 保留的 `toggleSidebar:`（`NSWindow` 同名方法优先命中且验证为 false，菜单项恒灰），⌥⌘S 与菜单同时生效；R4-08 注册窗口菜单后**窗口清单已恢复**（2026-10-23 副本实测「窗口」菜单末尾出现 `FlowFinder` 条目，`MainMenu.swift:24`）；同一实测里**「进入全屏幕」仍不存在**，只有系统注入的「填充/居中/全屏幕平铺」，工程内没有任何 `collectionBehavior`/`toggleFullScreen` 声明（全库 grep 0 命中）——该半条**未修，转入下一轮**；R4-09 菜单省略号统一为 `…`；R4-10 撤销/重做从右键菜单首项挪回「编辑」菜单并补状态校验；R4-11 批量重命名入口在选中项不满足条件时禁用并写明阈值（`MainWindowController+MenuActions.swift:809`）；新增 `FFMenuContractTests` 17 条（枚举菜单项标题/键位/校验契约）；未提交/未推送 |
| 2026-10-23 | **第 2 批 主流程破坏（R4-03/R4-02）**：R4-03 面板工具栏改「溢出分级」——窄面板下分组/范围/排序三个文字下拉按分级收纳进「更多」，宽度由策略写死覆盖最长标题（`PaneToolbar.swift:65/134/345/374/445`，有测试守宽度），被宽度挤掉的列在「显示列」菜单里标明原因而非无声消失（`FileListView.swift:1294`），1060×700 声明最小尺寸下顶栏与列表不再重叠/丢列（既有 F-11 的同一根因）；R4-02 任务中心终态成为事实终点，迟到的进度回调不能把已完成任务改回「进行中」（`TaskService.swift:65`），新增 `FFTaskPanelTests` 6 条与 `FFDedupTaskLifecycleTests` 3 条；未提交/未推送 |
| 2026-10-23 | **第 1 批 R4-01 本地化根因**：工程此前**没有任何 lproj 资源**，中文界面里 `Cancel`/`OK`/`Sort By`/`bytes`/24 小时制等一整套英文串来自系统默认本地化与未指定 locale 的 formatter。补 `FlowFinder/FlowFinder/Resources/zh-Hans.lproj/InfoPlist.strings`（四类文件夹权限用途声明 + 应用名）、Info.plist 加 `CFBundleDevelopmentRegion = zh_CN` 并把 lproj 纳入 `CFBundleLocalizations`，字节单位与时间/数字 formatter 统一走中文 locale；新增 `FFLocalizationTests` 6 条（bundle 本地化命中、中文字节单位、24 小时制）；未提交/未推送 |
| 2026-10-22 | **桌面副本同步**：用户授权后覆盖 `~/Desktop/FlowFinder.app` 为 **0.8.0-26102235**（含 R-25…R-35）。直接复用 `make build` 已产出的 Debug 包（二进制 22:23 晚于全部源码，避免多递增一次构建号），`codesign --verify --deep` 通过（adhoc），旧 26102221 备份 `/tmp/ff-desktop-backup/`；启动验证 PID 13208、窗口 1400×900、侧栏版本标签实测 `0.8.0-26102235 Beta`；未提交/未推送 |
| 2026-10-22 | **第二十八轮 R-35（F-02 详情栏流动布局）**：根因是 `rearrangeFlow` 在同一轮布局遍历内读取尚未重排的 `infoScrollView`/`columnsStack` frame（实测栏体 132pt、子视图仍 30pt），每列只排 1 行且不再自愈；改为由栏自身 `bounds` 推导可用宽高（`infoAreaSizeForFlow`），行高改在脱离层级的测量台内测量，移除布局内递归 `layoutSubtreeIfNeeded`，缩进/分界线宽度提为常量与约束同源；新增 1 条回归（先红 `0≠8` 后绿）、1 条旧断言按「无内部滚动条」契约改写并更名；全量 16 批 435 条 0 失败、自检 153 通过 + 20 轮 0 失败；独立副本 DEBUG `0.8.0-26102235` 实机 3 种宽度 9 个字段全部可见、无滚动条；长名截断归 F-07、磁盘可用空间仍待补；构建当时未覆盖桌面副本，桌面副本已在同日收口时同步为 26102235（见「桌面副本同步」行）；未提交/未推送 |
| 2026-10-22 | **第二十三轮 R-30（P0 数据安全）**：内联重命名同名目标存在性检查（fileResourceIdentifier 允许大小写改名）；查重每组至少保留一个；永久删除独立确认（不复用「不再询问」、隐藏复选框、固定「无法撤销」文案）；查重删除失败 sheet；新增 4 条测试；全量 426 条 424 通过（1 条既有测试宿主废纸篓超时），自检 163 + 20 轮；Debug `0.8.0-26102222`；未提交/未推送 |
| 2026-10-22 | **第二十七轮 R-34（F-08 批量重命名）**：只处理文件、文件夹忽略并在标题提示；空扩展名不再追加点；尾点清理；新增 4 条纯函数测试；全量 428 分批 + 4 定向通过；Debug `0.8.0-26102227`；未提交/未推送 |
| 2026-10-22 | **第二十四轮 R-31（P1 UI 状态与入口）**：工具栏 search/scope/sort/group 同步；工具页上下文增量刷新、返回收藏入 Tab 环、焦点环脱离 hover；单标签 × 关窗；侧栏新标签入口恢复；右键先选中 clickedEntry；整理按发起面板路由；整理 Sheet 日期标题同步隐藏；显示设置固定名词 + 隐藏控件出 Tab 环；右键/关于去掉 AI 文案；新增 4 条测试 + 更新 3 条断言；实机通过工具页上下文/焦点、显示设置、侧栏新标签、单标签关闭、右键 clickedEntry、整理路由、Sheet 按类型、重命名冲突；全量 430（分批 428 通过 + 2 条既有环境测试），自检 163 + 20 轮；Debug `0.8.0-26102224`；未提交/未推送 |
| 2026-10-20 | 建台账；A/B/C/D 四批逐条回填实现位置与验证手段 |
| 2026-10-20 | B 批：四列 + 可选列 + 三个入口 + 垂直中线；C/D 批：窗口连续曲率圆角、图标尺寸、切换动画 |
| 2026-10-20 | 第四轮：R-11 点击失效修复（press 不吞事件 + 事件按窗口路由 + 不消费 mouseDown）、R-01 改标签级跨窗口模型、R-12 渲染不等标签、R-07 三图标拆成两组 |
| 2026-10-20 | 交接文档 `HANDOVER.md` 更新至第五轮状态（新模块表 / 交互模型速记 / 新增 AppKit 坑 / 债务与建议同步）；生成交接文案 `docs/交接文案-2026-10-20.md` |
| 2026-10-20 | **第五轮 C：拖动落点语义校准**（用户实测不符）——① 新面板按落点侧；② 同窗口搬空源面板折叠变单栏；③ 加宽几何重写（修 2015×622）；④ 卡片留白非把手部分不再拖窗口。SPEC §1.14 |
| 2026-10-20 | **第五轮 B：边缘调宽手感修复**——手势仲裁（卡片留白只做调宽，用户裁定 A）、决策表加 onResizeHandle 维度（穷举 38→71）、修 NSSplitView 翻转坐标系 Y 守卫、修把手命中只看 X、拖动期间停写 UserDefaults。SPEC §1.13 |
| 2026-10-20 | **台账审计（第五轮）**：① 修掉 `isOutsideStripBuffer` 坐标系混用（重排手势实际失效）；② 自检数 98→94 纠正；③ A 批标「已被取代」；④ R-01 从「已完成」降级「部分完成」并写明未验项；⑤ R-12 补实测证据（4 秒）；⑥ 排除 1920×30 窗口误判（全系 App 都有的系统保留窗口，非本应用 bug）；⑦ 新增「验证手段分级」与加宽几何待查项 |
| 2026-10-20 | **第六轮：回归修复 + 测试护栏（R-13）**——占位标签清理、拖出新窗强制单栏、标签重排纯函数与坐标统一、控件命中短路（含发现药丸）、按压反馈侧、窗口拖动阈值。XCTest 144→162（修前 19 处失败），自检 129 项 0 失败 |
| 2026-10-20 | **台账纠数**：自检总数 135→129（焊接 21→19、落点 5+5→6），并纠正「XCTest 通道不可用」的陈旧结论（实测 162 条全绿） |
| 2026-10-20 | **第七轮：标签拖拽重做（路线 B，R-14）**——纯 resolver / 几何缓存 / 60Hz 帧调度 / 轻量浮层；修单栏落点、兄弟标签、无效落点、目标单栏拆分、最后标签；窗口拖动改 `performDrag`；`FileListView` 列重算宽度守卫；`updatePaneUI` 重载策略。XCTest 190 / 自检 135 |
| 2026-10-20 | **第七轮数字按实测重写**：XCTest 190、自检 135（落点 10 + 焊接 21）；真实 60fps 采样与浮层/窗口拖动手感明确标为未验 |
| 2026-10-21 | **第十一轮 R-18**：0.8.0 Beta 顶栏重做（A1 焊接、30pt 带、28/24 标签、16pt 中心线、隐藏侧栏 112、图标 hover）；红绿灯关闭放行；同目录拖放无操作；版本/单实例/旧副本治理。XCTest 301、自检 153（WELD 35 + AVOID 4 + 其余 114） |
| 2026-10-21 | **第十二轮 R-19（设计已确认）**：用户提出 12 项 UI 重做；确认全局顶栏 C2（44/38/6pt 空条/22 中线）、详情浮层 v2、面板宽度模型、工具入口、尺寸三档、SF+Phosphor、设置 A、文件标签；实机确认隐藏侧栏工具栏右移。**Phase 0**：新增 `FFLayoutDiagnostics` 只读快照、3 条布局回归、20 轮压力自检；XCTest 302→305，自检 153 + 20 轮/80 快照 0 失败；图二未复现，抓到新窗口首帧 50/50 瞬态；**无生产行为改动** |
| 2026-10-21 | **Phase 1 完成**：尺寸三档与持久化、`FFTopBarMetrics`、外观“界面尺寸”控件、104 图标 SF/Phosphor 双后端、Phosphor regular+duotone 资源、图标自检与联系表核对；焊接自检改用 alignment rect 适配 SF Symbol 内边距。XCTest 305→312；自检 153 + 20 轮 0 失败 |
| 2026-10-21 | **Phase 2 完成**：`FFGlobalTopBar` 44pt 全局顶栏、标签组跨分栏对齐、22pt 共用中线、工具入口迁移、侧栏控制行移除、隐藏侧栏工具栏固定 8pt、新窗口首帧定位。XCTest 312→316；自检 153→155 + 20 轮 0 失败；实机 1400 双栏/隐藏侧栏截图通过 |
| 2026-10-21 | **Phase 3 完成**：400/360 软硬下限、25/50/75 吸附、双击 50/50、12pt 热区、拖动 pt 浮标、比例缩放、侧栏偏好宽度、宽度记忆只在拖拽松手写、启动/新窗首帧同步分隔线。XCTest 316→322；自检 155→164 + 20 轮 0 失败；查重浏览 NSOpenPanel 抖动修复 |
| 2026-10-21 | **Phase 4 完成**：详情浮层 132–300/预览列 96–200、实体表面、名称/位置换行、点击复制、技术字段清理、类型专属字段、ZIP 计数、列表让位。XCTest 322→329；自检 164 + 20 轮 0 失败 |
| 2026-10-21 | **Phase 5 完成**：`TagCatalog` 统一标签定义；跨文件改名/改色/删除同步；同名合并；侧栏 ⌘ 多选 AND；`TagSelectorDialog` 多路径批量差异；右键批量/清除/管理；⌥⌘T 与详情栏共用；设置管理器 CRUD/排序。XCTest 329→334；自检 164 + 20 轮 0 失败；Finder 互通/管理器视觉待补 |
| 2026-10-21 | **Phase 6 完成**：`FFSettingsMetrics` 12/40/26/13/11；分区卡片/行/控件统一；7 分区与功能保留；标签管理接入 TagCatalog。XCTest 334→335；自检 164 + 20 轮 0 失败 |
| 2026-10-21 | **Phase 7 收口**：`make build` 成功；XCTest 335 / 自检 164 + 20 轮全绿；产物 `/tmp/FlowFinder-0.8.0-Beta-r19.app`；按用户确认执行 `make demo` 覆盖桌面副本（0.8.0 / 8001）并启动成功；文档同步；未提交/未推送 |
| 2026-10-22 | **发布 v0.8.0-b1**：GitHub Release（Prerelease），构建 0.8.0-26102209；资产 DMG / ZIP / SHA256；Release 链接已写入 HANDOVER 与 CHANGELOG |
| 2026-10-22 | **第二十二轮 R-29**：J3-10 批量整理——`FFOrganizePlanner` 纯函数 + `FFOrganizeSheet` 预览（统计/计划清单/重名标橙）+ `PaneState.performOrganize` 整批 ⌘Z + 双入口（工具页 6 工具第 3 行 / 右键「整理当前目录…」）；真机发现并修复 Sheet body 塌陷（缺 translatesAutoresizingMaskIntoConstraints）与工具行缺 `accessibilityPerformPress` 两处缺陷；XCTest 409→422；自检 163 + 20 轮；Debug `0.8.0-26102220`；真机双入口/按类型切换/执行/⌘Z 撤销走查通过（独立副本与桌面副本共享 Application Support 为既有行为，仅对 /tmp 执行）；未提交/未推送 |
| 2026-10-22 | **收尾**：用户确认 `make demo` 覆盖桌面副本为 `0.8.0-26102221` 并启动；项目文件夹整理——21 份历史 PLAN/SPEC/AUDIT/交接文案 `git mv` 入 `docs/archive/2026-10/`，删除不再被引用的 `build/`（127M）与 `build_stale_0021/`（135M）；AI 资源入库 `resources/ai-tools/`（15 Skill 快照 + grillme-matt 0.1.0 插件 + `MCP-AND-SKILLS.md` 清单，详见该文件）；新增跨 Agent 交接文案 `docs/交接文案-2026-10-22.md`（工作流铁律/已知坑/下一步 J2-08、J2-09）；未提交/未推送 |
| 2026-10-22 | **第二十一轮 R-28**：J2-07 搜索范围——`FFSearchScope` + 搜索框右侧紧凑菜单、双栏镜像、含子目录递归守卫；7 条新增测试；全量 409 条 407 通过（2 条测试宿主环境失败）；自检 163 + 20 轮；Debug `0.8.0-26102218`；真机三范围走查通过；未提交/未推送 |
| 2026-10-22 | **第二十轮 R-27**：J3-11 文件说明迁移 Finder 注释——`FFFinderCommentStore` xattr 读写、首次启动后台迁移、详情栏/说明列统一读取、失败中文提示；XCTest 397→402；自检 163 + 20 轮；Debug `0.8.0-26102216`；真机迁移 xattr 56 字节解码「旧说明迁移测试」、详情栏 AX 读到；未提交/未推送 |
| 2026-10-22 | **第十九轮 R-26**：AX 行虚拟化——`FFAXRowElement` 轻量行代理、完整 AXRowCount/AXRows/AXChildren/导航顺序、选中通知、刷新失效；5000 行默认表格深枚举 165 万次 `viewFor` 的根因消除；XCTest 393→397；自检 163 + 20 轮；Debug `0.8.0-26102214`、Release `0.8.0-26102215`；Release 1 万行正常 174.9MB、AX 全量枚举后 185.2MB；未提交/未推送 |
| 2026-10-22 | **第十八轮 R-25**：修复名称列过窄、启动 30s 空目录、详情栏残留、工具页焦点、补前往文件夹；XCTest 389→393；`make demo` 出 `0.8.0-26102212`；AX 5000 行枚举内存问题开放；未提交/未推送 |
| 2026-10-22 | **第十七轮 R-24**：首次引导窗口、崩溃日志落盘、Tab 环接入侧栏收藏、AI 工具改名；XCTest 383→389；自检 163 + 20 轮；`make build` 出 `0.8.0-26102209`；首启/二启实机通过；未提交/未推送 |
| 2026-10-22 | **第十六轮 R-23**：批次 3 文档原位重写——REQUIREMENTS 2.1 / ACCEPTANCE 1.1 / README 5 处 / R-19 PLAN 编号 / HANDOVER 代码规模；无代码与测试变更；未提交/未推送 |
| 2026-10-22 | **第十五轮 R-22**：批次 2 功能回归 6 组 15 条（跨栏/搜索/键盘/标签互通/设置生效/静态 lint+权限）；XCTest 368→383；自检 163 + 20 轮；`make build` 出 `0.8.0-26102204`；未提交/未推送 |
| 2026-10-22 | **第十四轮 R-21**：7 个设置接线（移动前确认/默认操作行为三选/文件夹优先/刷新保持选中/启动检查更新/SMB 默认域/SMB 自动重连）、完整会话活动面板、终端改 NSWorkspace、工具胶囊与工具行无障碍。XCTest 349→368；自检 163 + 20 轮；`make build` 出 `0.8.0-26102203`；设置页真机 AX+截图；SMB 断线/更新提示未触发；未提交/未推送 |
| 2026-10-22 | **第十三轮 R-20**：顶栏 36/30/26/6 + 18pt 共用中线、红绿灯中心对齐 18pt、工具入口回品牌胶囊 + 侧栏工具页（5 工具 / 三组纵向列表）、第二行删新建文件夹与齿轮并合并进「显示设置」、版本规则改 `A.B.C-yymmddxx` 自动递增。XCTest 335→349；自检 164→163（顶栏工具键断言随功能删除）+ 20 轮 0 失败；`make build` 出 `0.8.0-26102201`；用户授权桌面访问后完成真机走查（红绿灯/标签中线 17.5pt=17.5pt、版本行、工具胶囊、第二行显示设置、合并菜单结构、工具页 5 行三组、180pt 窄侧栏胶囊换行），截图 `/tmp/ff-toolpage-26102202.png` 与 `/tmp/ff-narrow-180.png`；按用户指令 `make demo` 覆盖桌面副本为 `0.8.0-26102202` 并重跑自检 163/0；未提交/未推送 |
