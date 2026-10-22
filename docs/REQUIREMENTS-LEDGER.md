# 需求台账 · FlowFinder UI/UX 重做

> 唯一的「哪些做了、怎么做的、验到什么程度」清单。
> 规格来源：`docs/SPEC-2026-10-20.md`、`docs/DESIGN-SPEC.md`、`docs/PRODUCT.md`。
> 更新规则：**改代码就改这张表**。状态只有四种：`已完成` / `部分完成` / `未开始` / `已废弃`。
> 「验证」列写实际手段，不写「应该没问题」。
> **同步纪律（2026-10-21 起，强制）：** 每次修改必须在同一轮同时更新本表与 `HANDOVER.md`；
> 只认当次实测数字；收尾前检查 `git diff -- docs/` 是否覆盖本轮全部改动，没有文档改动视为未完成。
> 历史条目中的 190 / 258 / 282 / 135 / 335 / 164 是当轮实测值；**当前总览以 §0 的 389 / 163 为准**。

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

自检总量：**163 项断言，0 失败**（`FF_SELFTEST=1`；2026-10-22 第十七轮实测，日志 `/tmp/ff-debug.log`）。
Swift XCTest：**389 条，0 失败**（`xcodebuild test -scheme FlowFinderTests`，2026-10-22 实测）；
布局压力自检 **20 轮 0 失败**。

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

---

## 2. 已知限制与技术债

| 项 | 说明 | 处置 |
|---|---|---|
| ~~`xcodebuild test` 在本机挂死~~ **已恢复** | 根因是开发模式被重置（`DevToolsSecurity` 当时 disabled，现 enabled）；2026-10-21 第十轮实测 282 条全绿 | 复现时先查 `DevToolsSecurity -status` 与 `xcode-select -p`；`FF_SELFTEST` 135 项作为双保险 |
| 合成鼠标事件不可靠 | CGWindowList 左上原点 / CGEvent 左下原点；`addLocalMonitorForEvents` 只拦 NSApplication 派发的事件 | 判定逻辑在应用内直接断言；事件派发交 AppKit |
| 合成事件环境三重干扰 | ① 本机 **CGEvent 的 y 是「屏幕顶部」原点**（与 CGWindowList 窗口坐标差一整屏）；② TCC 授权弹窗会吃掉点击；③ 桌面常被 Finder / WorkBuddy 窗口遮挡，点击打到别的 App | 物理拖拽验证需人机配合：清理桌面 → FlowFinder 置前台 → 手动拖 |
| 面板切换无位移动画 | `NSSplitView` 不参与隐式动画 | 见 R-02 |
| 加宽几何 | 2015×622 异常窗口已修：目标宽 = 侧栏 + 操作区×2 + 留白，钳制到屏幕可视宽度，只改宽度不动高度 | 已修（SPEC §1.14） |
| 说明列依赖 Spotlight | `kMDItemFinderComment` 需 CoreServices | 缓存 + 后台补 |
| 跨窗口拖拽手感未验 | 见 R-01 / R-14 | 人工验收：拖出 → 新窗口；拖回操作区 → 双栏 + 高亮；无效落点回原位 |
| 第七轮拖拽 60fps 未采样 | 结构级改动已完成（frame-based 插入线、几何缓存、60Hz、宽度守卫），但合成事件驱动不了真实拖拽 | 桌面副本上连续拖 3 秒 + Instruments/sample，p95 <16.7ms、无 `FileListView.layout → applyColumnFit → rebuildColumns` |
| 第七轮浮层/窗口拖动手感未验 | 完整胶囊浮层、1px 描边、`performDrag` 原生窗口拖动已接 | 人工确认：活动标签浮层不是文字幽灵；窗口拖动跟手；必要时 `FF_NATIVE_WINDOW_DRAG=0` 回退 |
| 面板切换真位移未做 | 用户已裁定走「自管布局」，但改动覆盖整个分栏体系 | 单独一轮做，不与其它改动混 |

---

## 3. 变更记录

| 日期 | 内容 |
|---|---|
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
| 2026-10-22 | **第十七轮 R-24**：首次引导窗口、崩溃日志落盘、Tab 环接入侧栏收藏、AI 工具改名；XCTest 383→389；自检 163 + 20 轮；`make build` 出 `0.8.0-26102209`；首启/二启实机通过；未提交/未推送 |
| 2026-10-22 | **第十六轮 R-23**：批次 3 文档原位重写——REQUIREMENTS 2.1 / ACCEPTANCE 1.1 / README 5 处 / R-19 PLAN 编号 / HANDOVER 代码规模；无代码与测试变更；未提交/未推送 |
| 2026-10-22 | **第十五轮 R-22**：批次 2 功能回归 6 组 15 条（跨栏/搜索/键盘/标签互通/设置生效/静态 lint+权限）；XCTest 368→383；自检 163 + 20 轮；`make build` 出 `0.8.0-26102204`；未提交/未推送 |
| 2026-10-22 | **第十四轮 R-21**：7 个设置接线（移动前确认/默认操作行为三选/文件夹优先/刷新保持选中/启动检查更新/SMB 默认域/SMB 自动重连）、完整会话活动面板、终端改 NSWorkspace、工具胶囊与工具行无障碍。XCTest 349→368；自检 163 + 20 轮；`make build` 出 `0.8.0-26102203`；设置页真机 AX+截图；SMB 断线/更新提示未触发；未提交/未推送 |
| 2026-10-22 | **第十三轮 R-20**：顶栏 36/30/26/6 + 18pt 共用中线、红绿灯中心对齐 18pt、工具入口回品牌胶囊 + 侧栏工具页（5 工具 / 三组纵向列表）、第二行删新建文件夹与齿轮并合并进「显示设置」、版本规则改 `A.B.C-yymmddxx` 自动递增。XCTest 335→349；自检 164→163（顶栏工具键断言随功能删除）+ 20 轮 0 失败；`make build` 出 `0.8.0-26102201`；用户授权桌面访问后完成真机走查（红绿灯/标签中线 17.5pt=17.5pt、版本行、工具胶囊、第二行显示设置、合并菜单结构、工具页 5 行三组、180pt 窄侧栏胶囊换行），截图 `/tmp/ff-toolpage-26102202.png` 与 `/tmp/ff-narrow-180.png`；按用户指令 `make demo` 覆盖桌面副本为 `0.8.0-26102202` 并重跑自检 163/0；未提交/未推送 |
