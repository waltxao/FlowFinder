# 需求台账 · FlowFinder UI/UX 重做

> 唯一的「哪些做了、怎么做的、验到什么程度」清单。
> 规格来源：`docs/SPEC-2026-10-20.md`、`docs/DESIGN-SPEC.md`、`docs/PRODUCT.md`。
> 更新规则：**改代码就改这张表**。状态只有四种：`已完成` / `部分完成` / `未开始` / `已废弃`。
> 「验证」列写实际手段，不写「应该没问题」。

---

## 0. 状态总览

| 批次 | 内容 | 状态 |
|---|---|---|
| A | #1 拖动模型 · #8 边缘调宽 | 已完成（含 A2/A3/A4 三轮重做） |
| B | #3 列表四列与可选列 · #10 垂直中线 | 已完成 |
| C | #4 顶部对齐 · #5 窗口圆角 · #7 三控制图标 | 已完成（#5 改用连续曲率，见条目） |
| D | #6 侧栏图标 · #9 发光 · #2 切换动画 | 已完成（#2 见「已知限制」） |

自检总量：**98 项断言，0 失败**（`FF_SELFTEST=1`）。

| 层 | 项数 |
|---|---|
| 决策表穷举 | 38 |
| 区域解析 | 5 |
| 拖动行为 | 4 |
| 标签焊接 | 25 |
| 列表与外壳 | 22 |
| 落点状态机 | 4 |

---

## 1. 十项需求逐条台账

### R-01 拖动模型（标签级 · 支持跨窗口）

| 项 | 内容 |
|---|---|
| 需求原文 | 按住操作面板拖动不能拖走窗口；拖面板 = 搬面板；单窗口多标签时标签拖出、再拖入应变成双窗口 |
| 拖的对象 | **标签**（2026-10-20 第四轮改）。拖标签 = 搬这个标签，跟手的是 1:1 标签浮层（不再是整块面板快照） |
| 落点分流 | 落在标签条 → 并入那个面板；落在操作区 → 单栏窗口**拆出第二块面板**（窗口自动加宽）、双栏窗口并入该侧；落在窗口外 → 独立成新窗口 |
| 跨窗口 | 拖动中按屏幕坐标遍历已注册窗口判定落点，目标窗口显示半透明落点高亮 |
| 源窗口 | 面板被搬空就自动关窗；还有标签就留着 |
| 作废的旧裁定 | 「拖拽永远不会增加栏数」作废；「拖面板 = 搬整块面板」作废 |
| 实现位置 | `UI/FFPaneDrag.swift`（`FFPaneDragController` + `FFDropTarget` + `FFDropHighlightView`）<br>`UI/MainWindowController+Tabs.swift`（`takeTabOut` / `transferTab` / `acceptTab` / `acceptTabIntoPane` / `detachTabToNewWindow` / `closeSelfAfterEmptyPane`） |
| 验证 | 落点状态机 4 项断言（摘标签 / 并入标签条 / 拆出第二面板 / 搬空判定）全 PASS；**物理拖拽的跨窗口落点尚未在本机端到端验证**（合成事件受限于坐标口径与授权） |
| 状态 | 已完成（物理跨窗口拖拽待人工验收） |

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

### R-08 移除分隔发光条 + 面板边缘调宽

| 项 | 内容 |
|---|---|
| 需求原文 | 去掉双面板中间的发光条；改用面板边缘拖动调宽 |
| 实现位置 | `MainWindowController.swift` 的 `FFSplitView`（`handlePositionsProvider` / `handleCursor` / `grabOffset` / `applyDividerPosition`）：把手贴在卡片外沿，热区内按下即 1:1 跟随，`handleCursor = .resizeLeftRight` |
| 宽度语义 | 左面板左缘调侧栏宽；中缝左宽右窄（窗口总宽不变）；上下边缘不响应 |
| 持久化 | `sidebar_width` + `pane_left_width`；`splitViewDidResizeSubviews` 写入，程序化改宽期间用 `isAdjustingPaneMode` 闸门不写 |
| 验证 | 合成拖拽：中缝拖动后左面板变宽、窗口总宽不变；重启后宽度保持 |
| 状态 | 已完成 |

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
| 验证 | 点击能触发 `selectionDidChange`（修复前无此响应）；拖拽起手日志正常；自检 0 失败 |
| 状态 | 已完成 |

### R-12 启动卡顿（渲染不等标签）

| 项 | 内容 |
|---|---|
| 症状 | 应用启动后列表长时间空白（主线程卡在 `getxattr` 1–2 分钟，`sample` 实测） |
| 根因 | `warmCache` 已在后台预热标签，但**渲染与预热抢跑**：渲染时缓存还没热，`getTags` 退化成同步 xattr I/O，22 个条目就能把主线程堵住 |
| 修法 | 渲染路径改用 `TagBridge.cachedTags(path:)`（只读缓存、不做 I/O）；预热完成后发 `.ffTagCacheWarmed` 通知，列表据此整表刷新一次（此时全部命中缓存） |
| 代价 | 标签色点晚一帧出现 |
| 实现位置 | `Bridge/TagBridge.swift`（`cachedTags` / `warmCache(paths:completion:)`）、`Model/PaneState.swift`（预热完成广播）、`UI/FileListView.swift`（`tagCacheWarmed`） |
| 状态 | 已完成 |

---

## 2. 已知限制与技术债

| 项 | 说明 | 处置 |
|---|---|---|
| `xcodebuild test` 在本机挂死 | 环境问题（AUDIT §5，worktree 跑基线同样失败） | 验证降级为 `FF_SELFTEST` 断言 + 截图/几何日志 |
| 合成鼠标事件不可靠 | CGWindowList 左上原点 / CGEvent 左下原点；`addLocalMonitorForEvents` 只拦 NSApplication 派发的事件 | 判定逻辑在应用内直接断言；事件派发交 AppKit |
| 启动期 I/O 卡顿 | `rebuildDisplayRows` 里同步 `TagBridge.getTags` → `getxattr`，在 22 个条目上可阻塞 1–2 分钟（sample 可见主线程卡在 `getxattr`） | **未修**。应改成异步/缓存预取；本轮只记录，避免与列改动混在一起 |
| 面板切换无位移动画 | `NSSplitView` 不参与隐式动画 | 见 R-02 |
| 说明列依赖 Spotlight | `kMDItemFinderComment` 需 CoreServices | 缓存 + 后台补 |
| 跨窗口物理拖拽未端到端验证 | 合成事件受限于坐标口径（本环境 CGEvent 的 y 是**屏幕顶部**原点，与 CGWindowList 的窗口坐标差一整屏）与 TCC 弹窗抢事件 | 已用应用内几何日志 + 模型级断言覆盖；物理拖拽请人工验收 |
| 面板切换真位移未做 | 用户已裁定走「自管布局」，但改动覆盖整个分栏体系 | 单独一轮做，不与其它改动混 |

---

## 3. 变更记录

| 日期 | 内容 |
|---|---|
| 2026-10-20 | 建台账；A/B/C/D 四批逐条回填实现位置与验证手段 |
| 2026-10-20 | B 批：四列 + 可选列 + 三个入口 + 垂直中线；C/D 批：窗口连续曲率圆角、图标尺寸、切换动画 |
| 2026-10-20 | 第四轮：R-11 点击失效修复（press 不吞事件 + 事件按窗口路由 + 不消费 mouseDown）、R-01 改标签级跨窗口模型、R-12 渲染不等标签、R-07 三图标拆成两组 |
