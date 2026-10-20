# 变更日志

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/) 规范。

---

## [未发版]

### 交互决策表：把「按下去发生什么」收成一张表（2026-10-20 上午，A3 批）

用户反馈「问题有点多」，并提出是否改用 Chromium 组件。

**Chromium 路线的核查结论**：Chromium 的 `TabStrip` / `TabDragController` 在
`chrome/browser/ui/views/tabs/`，深度绑定 `WebContents`、`TabStripModel`、
`content::` 通知机制与 C++ Views 框架，**不是可复用的独立库**；唯一可嵌入形态
（CEF / Electron）等���整体重写。Rust 核心（24 模块 / 13.5k 行文件操作）不受影响。
→ 保留原生 AppKit + Rust 核心，只借鉴 Chromium「把拖拽判定收进单一状态机」的做法。

**四轮返工不是四个独立 bug，是同一个架构问题的四次显形**：
「按下去发生什么」这个判定被拆散在 hitTest 归并、mouseDownCanMoveWindow、
标题栏带、Auto Layout 约束四处，各自决定 → 同一区域的行为取决于当下状态。

**决策表**（`UI/FFInteractionPolicy.swift`，纯函数、不依赖 AppKit）：

| 区域 | 含义 | 意图 |
|---|---|---|
| `.window` | 侧栏空白、卡片 8pt 留白 | `dragWindow` |
| `.title` | 标签条空白（性质等同系统标题栏） | `dragWindow` |
| `.panel` | 工具栏、文件列表、详情栏、侧栏行 | `pressFeedback` |
| `.tab` | 标签胶囊 | 缓冲内 `reorderTab` / 出缓冲 `dragPane` |

区域由视图自我声明（`FFRegionAware` 协议），`FFAreaResolver` 统一翻译成意图——
新增功能是「给新视图加一行协议实现」，不是「再加一个 if」。
改造前实测散落规模：`mouseDownCanMoveWindow` 覆写 11 处、`hitTest` 覆写 11 处，
分布 9 个文件；改造后判定收在一处。

**布局修复**：

- 标签条从卡片容器里**提到窗口顶部 0..28**（与红绿灯同行），成为卡片包裹视图的子视图
- 卡片顶部让出标题区（28）+ 留白（8）= 36，**上下左右四周留白统一**
- 发光顶边内缩随之改为 36，**恢复四角圆角**（原先顶边是直角）
- 侧栏隐藏时标签条从 **x=106** 起（与工具栏共用同一避让量，改一处两处生效）

**顺带修掉一个必崩的既有 bug**：`FFQuickLookTableView.draggingEnded(_:)` 调了
`super.draggingEnded(sender)`，但 `draggingEnded:` 是 `NSDraggingDestination` 的
`@optional` 方法、`NSTableView` 并不实现 → 系统拖拽结束时 100% 崩溃
（运行时 `responds(to:)` 验证：只有 `draggingEnded:` 未实现，
`draggingExited:` / `concludeDragOperation:` 都实现了，不受影响）。

**自检扩到四层共 51 项**（全 PASS）：

| 层 | 项数 | 测什么 |
|---|---|---|
| 决策表穷举 | 38 | 区域 × 状态 全部组合 + 规则可达性 + 几何常量 |
| 区域解析 | 5 | 真实视图 hitTest → 区域 |
| 拖动行为 | 4 | 点位 → 意图 |
| 落点状态机 | 4 | 合并 / 回原位 / 挪槽 / 独立成窗 |

### 拖动模型再重做：只有标签能拖面板（2026-10-20 上午，A2 批）

上一版「拖面板 = 拖当前标签」仍有歧义：同一个区域按下去的结果**取决于当前状态**
（单栏单标签时拖工具栏＝拖窗口），用户无法形成稳定判断。本批把三件事彻底分开：

- **标签条常显并提到窗口顶部那一行**（与红绿灯同高 28pt）。卡片顶部因此重新变成工具栏 Row1，
  #4 的对齐基准也从「面包屑」改为「标签条」——红绿灯与标签条现在天然同高对齐
- **只有标签能拖面板**：条内（含 20pt 缓冲）= 重排标签；拖出缓冲 = 搬整块面板，1:1 浮层跟随
- **窗口拖动只剩三处白名单**：侧栏空白、面板卡片四周 8pt 留白、标签条空白（性质等同系统标题栏）
- **工具栏与文件列表不产生任何拖动**，按下只给 0.5pt 下沉的按压反馈，明确表达「这块是实的」
- **拖标签 = 搬整块面板**（不是搬标签内容）。落点：空槽 → 挪过去、窗口收窄；
  已占用槽 → 两块合并成一个（标签并集）、窗口变单栏；窗口外 → 整块面板拆成独立新窗口
- **旧标签拖放路径整体退役**：`NSDraggingSession` + `PaneTabDropReceiver` + `PaneTabDragContext`
  全部删除。标签条在标题栏带内，那一带的 mouseDown 会被系统标题栏先于内容视图抢走，
  `NSDraggingSession`（要求拖拽源就是收到 mouseDown 的视图）根本做不到
- **自检重写为四项**：① 拖到对面合并 ② 落在本侧回原位 ③ 单栏拖到另一半挪槽 ④ 拖出窗口独立成窗

### 面板拖动模型初版 + 边缘调宽（2026-10-20 上午，A 批）

- **拖操作面板不再拖走窗口**（#1，规格见 `docs/SPEC-2026-10-20.md`）：根因有两层——① `NSView.mouseDownCanMoveWindow` 对不透明视图默认返回 true，工具栏的堆栈视图/占位视图/面板卡片全都成了窗口拖动区；② 窗口顶部 28pt 是系统标题栏的拖动区，正好压在工具栏第一行上，标题栏会先于内容视图吃掉 `mouseDown`。修法：显式覆写 `mouseDownCanMoveWindow`（新增 `FFNonDragView` / `FFNonDragStackView`）+ 窗口 `isMovable = false` + **窗口级 local monitor 自管拖拽**，在事件分发之前就把「工具栏空白 / 标签条空白」接管成「拖面板」
- **拖面板 = 拖当前那个标签**（新模型）：双面板时拖到对面面板只搬当前标签，源面板被搬空才消失（合并成单面板）；单面板多标签时拖到窗口右半区拆出右面板、拖出窗口拆成独立新窗口；单面板单标签时没有第二个标签可搬，退化为拖窗口
- **拖影改为等大浮层**：整块面板 1:1 快照、0.55 不透明度、带投影的独立 `NSPanel` 跟随鼠标，原位置留虚线占位框（此前是 76×52 的小卡片示意）
- **列表空白处保留框选**：拖面板只从工具栏空白与标签条空白起手，文件列表的空白处仍是访达式的框选
- **移除所有分隔发光条**（#8）：双面板中缝与侧栏缝的渐变亮线、悬停高亮全部删除；把手改到**面板卡片的外沿**（左右卡片各 6pt 热区 + `resizeLeftRight` 光标），左面板左缘调**侧栏宽度**、中缝左宽右窄（窗口总宽不变），上下边缘不响应
- **窗口拖动只剩合法区域**：侧栏空白与面板卡片四周 8pt 留白可拖窗口，其余一律不拖
- **面板宽度记忆**：新增 `pane_left_width`，从单窗恢复双窗时放回记忆宽度而非中线
- **自检扩到八项**：原有五项（组内重排 / 跨组移动 / 同组不复制 / 单窗拆分 / 整组合并）之外，新增三项覆盖新拖动模型——⑥ 面板拖动并入对面（只搬当前标签，仍双面板）、⑦ 源面板被搬空 → 合并成单面板、⑧ 单面板拖到右半区 → 拆出右面板

### 列表元信息、网格选中与图标库收口（2026-10-20 凌晨）

- **列表四列合并为两列**（#11）：名称 + 元信息。元信息固定两项「大小 · 修改时间」（如 `503 KB · 7月14日 21:20`），11pt secondary 右对齐；目录没有有意义的字节数，只显示日期；类型列按规格裁掉。列宽策略改成「名称列吃全部弹性、元信息列定宽 180 不收缩」，面板变窄时先省略名称，元信息始终完整。元信息列头点击按修改时间排序（用户确认口径），按大小 / 按类型排序走工具栏排序菜单；为避免箭头画在元信息列上误导为「按日期排」，大小 / 类型排序时列头不画箭头
- **网格选中改为两段式**（#11）：此前整块 112×124 刷成强调色实底。现在拆成两块——图标背板（位于缩略图下层，四周各外扩 5pt，圆角 8）与文件名胶囊（跟随文字实测宽度，圆角 5，文字反白），中间留 2–4pt 净间隙；item 自身底色保持透明，Drop 高亮仍是整块 8% 淡底 + 描边，与选中互不覆盖
- **Lucide 全量替换系统图标**（#8）：全项目 **74 处** `NSImage(systemSymbolName:)` 清零，改为 `FFIcon.template` / `FFIcon.image`。覆盖右键菜单（撤销/重做/复制/剪切/粘贴/拷贝路径/移动/重命名/废纸篓/新建文件夹/收藏/标签/AI/查重/简介）、列表与网格占位图标、面包屑（复制路径/粘贴跳转/访达/终端/根卷/同级目录/更多路径）、工具栏 8 个导航与视图按钮、搜索框、标签栏关闭与新建、详情栏编辑与折叠箭头与空态占位、设置侧栏 7 个分区与 12 个分区卡片、外观三态按钮、搜索筛选的文件类型、SMB 面板、查重面板与预览、新建标签对话框控制点、标准位置彩色图标的内嵌符号。保留系统语义控件不动（窗口红绿灯、`NSOutlineView` 展开三角、菜单勾选、滚动条、`NSWorkspace` 真实文件图标）
- **构建产物默认改到内置卷**：仓库位于外置卷（`/Volumes/...`）时，llbuild 的 `BuildEngine` 会卡在 `condition_variable` 上永不返回——现象是 `Building Swift (Debug)...` 之后几分钟无输出、无 `swift-frontend` 进程，采样 `SWBBuildService` 可见主线程与全部 Lane 线程都停在条件变量等待。同一仓库换到内置卷 55 秒全新构建通过，因此 `DERIVED` 默认改到 `~/Library/Caches/FlowFinderBuild`；需要项目内产物时用 `make DERIVED=$(pwd)/build build`
- **权限门增加 `FF_SKIP_PERMISSION_GATE=1`**：自动化截图与自检场景下系统授权框会遮挡界面，且合成点击事件投不进 TCC 对话框（系统安全限制），只能跳过启动期预请求；该开关不改变各处的真实权限行为

### 拖拽与权限（2026-10-19 晚，对照 3 条反馈）

- **修好标签拖拽的三个真实故障**：#5 的拖动此前「看起来没实现」，原因是三处叠加——① `PaneTabItemView.hitTest` 忽略了 `frame.contains` 判定，越界的点也被本视图认领，而 NSStackView 逆序派发命中，结果**最后一个标签吞掉整条标签栏**：点任何标签都选中最后一个、拖任何标签拖走的也是最后一个；② 落点统一由窗口级接收器判定后，同组落点走了 `insert` 分支，拖一下会**复制**出一个标签；③ 标签条与接收器同时对拖拽类型注册，drop 归属不确定。现在标签条不再注册拖拽目标，全部落点按坐标分流：标签条内 = 组内重排 / 跨组追加，面板主体 = 并入最近侧，单窗另一半 = 拆分
- **标签宽度 84–180 → 100–200**（规格 T-01 / #5e）
- **启动期集中请求文件访问权限**（#3）：macOS 的 TCC 只在首次访问某个受保护目录时弹窗，逐目录浏览就是「每打开一个文件夹被问一次」；而且弹窗未应答时目录列举会阻塞，10 秒后误报「目录响应超时」。新增 `FFPermissionGate`：启动阶段并发触碰桌面/文稿/下载/外置磁盘，让系统把授权对话框一次走完，之后再放行两侧面板加载；被拒时给一次性引导（可直接跳「文件与文件夹」或「完全磁盘访问」）；菜单新增「检查文件访问权限…」「打开「完全磁盘访问」设置…」
- **列表标签改为单行色点**（#11）：药丸不再占第二行，行高统一走密度档位（26/30/36），名称后最多 4 个 6pt 色点 + `+N`
- **标准位置目录配色接入列表**（#11b）：桌面/文稿/下载/应用程序等按语义色合成图标，与网格一致
- **Debug 自检通道**：`FF_SELFTEST=1` 启动时自动跑「组内重排 / 跨组移动 / 同组不复制 / 单窗拆分 / 整组合并」五项断言，结果写入 `/tmp/ff-debug.log`（合成鼠标事件无法驱动 NSDraggingSession 的落点更新，故以真实视图坐标直接调用落点分流）

### 三次修订（2026-10-18 晚，对照 7 条验收意见）

- **发光位置移到操作区边缘**（#2）：上一轮把光晕整条画在卡片**内部**，看上去像给内容加了一圈亮边。现在发光视图挂在卡片外层包裹视图里、位于卡片**下层**，以卡片边界为**中心线**做 14 层同心描边（1→13pt 递减）：内半圈被卡片不透明背景盖住，外半圈留在卡片外的留白里向外发散，读起来是「从操作区边缘渗出的光」。卡片四周留白同步 4 → 8pt，正好容纳最外层描边外扩的 6.5pt（规格 W-08）
- **单窗口模式真正收起非活动操作区，并同步缩小窗口**（#5）：此前只对 arranged subview 设 `isHidden`，NSSplitView 并没有折叠它——用户看到的是两个操作区都在、窗口也没变小。改为把非活动侧从分栏里移除（`removeArrangedSubview` + `removeFromSuperview`），窗口按该侧宽度收窄（实测 1400 → 838），切回双窗还原原宽度与中线分隔（规格 W-07 / W-10）
- **只有一个标签时不显示标签条**（#3）：标签条高度约束改为可切换，标签数 ≤ 1 时收 0，工具栏顶到卡片顶部（总高 104 → 72pt）；第二个标签出现时自动展开。新建入口保留在「文件 → 新建标签页 ⌘T」与侧栏右键「在新标签页中打开」（规格 T-01 / T-10）
- **位置区不再显示「X GB 可用」**（#4）：磁盘行只留卷图标 + 卷名，容量信息保留在悬停气泡里（规格 B-06b）
- **顶部控制行与红绿灯对齐，夜间切换前置**（#6）：控制行（日间/夜间 → 单双窗切换）不再写死 top 常量，改为每次布局按红绿灯真实中心反算，换机型/换系统版本都不会错位（规格 W-09）
- **侧栏品牌区改版**（#7）：应用名改 **17pt semibold 蓝紫渐变**，两端色从应用图标像素里采样（HSB 蓝紫区间分两簇取加权平均，浅色压暗 / 深色提亮；取色失败回退内置色对）；整体下移离开红绿灯；版本号 11 → 10pt；设置与工具按钮从底部工具行移到名称后方，底部按钮行随之撤销（规格 B-02 / B-03 / B-12 废止）
- **修复夜间模式下标签胶囊白底白字**：标签激活态背景用 `CALayer.backgroundColor` 静态写入，`controlBackgroundColor.cgColor` 定格在创建时的浅色模式，切到夜间就成了白底白字。改为在当前 `effectiveAppearance` 下解析颜色，并随外观变化重绘（规格 T-10）

### 修复

- **路径栏首段取「路径所属的卷」**：此前一律把根卷名拼在最前面，`/Volumes/Studio` 会被渲染成「Macintosh HD > Volumes > Studio」——既多出一层并不存在的 `Volumes`，又把根卷名挂到了外接盘路径上（访达只显示盘符本身）。改由 `FFBreadcrumbSegments` 纯函数按挂载点解析：首段取该挂载点的卷名并改用磁盘图标，根卷路径行为不变；补 7 条单测（挂载卷 / 根卷 / 尾斜杠 / 空串）
- **面包屑飘到行尾**：Row1 里面包屑被拉满整行、内部又靠右对齐，短路径时看起来贴在窗格最右、与导航按钮隔着一大片空白。改为按内容宽度参与布局（新增 `intrinsicContentSize`），并在 Row1 末尾放弹性占位吸收剩余空白，面包屑紧贴刷新按钮（规格 T-04 / N-06）；空间不足时仍先压缩面包屑，保留「裁左侧、当前目录可见」的溢出行为（N-03 / N-07）
- **活动面板无高亮提示**：双面板下没有任何「我在操作哪边」的视觉反馈——原方案是面板顶部 2pt 强调色色条，但它先于工具栏 `addSubview`，被工具栏完全遮住，从未显示过。改为整块操作区 1.5pt 强调色内描边（规格新增 W-08），点击该面板任一控件（工具栏 / 列表 / 网格 / 详情栏）即切换；激活不再依赖「选中变化」回调，点击空白区、已选中行也能正确切换
- **列表选中框满宽直角**：选中高亮直接 `bounds.fill()`，与分组标题行、窗格边界齐平相接，视觉上像一条色带而不是选中框。改为左右内缩 4pt + 5pt 圆角（访达样式，规格 C-04 补充）
- **详情栏空态图标**：未选择文件时显示半透明蓝色 `tray.full.fill` 托盘，观感差；且图标走异步工作区回调，失败或未返回时永远残留旧占位。空态改为同步显示灰色 `folder` 符号，与「未选择文件」占位文本同一视觉层级（规格 §10）

### 新增与变更

- **浏览标签页**（#7）：每个操作区顶部新增浏览器式标签条（32pt）。标签 = 一次独立浏览会话（路径 / 返回栈 / 排序 / 视图模式 / 分组 / 标签筛选），支持 `+` 新建、`×` 关闭、点击切换、拖动排序、跨左右面板拖动、⌘T / ⌘W，侧栏「在新标签页中打开」同步接通；系统窗口标签废弃（`tabbingMode = .disallowed`），最后一个标签时 ⌘W 退回关窗（规格 T-01 / T-08）
- **发光边缘二次调软**（#6）：去掉实心芯线，改为 12 层同心描边（1.5→13pt）连续衰减，深色 ×1.2 / 浅色 ×0.9（W-08）
- **单/双窗口切换**（#3）：侧栏顶部红绿灯右侧新增按钮（双窗 `rectangle.split.2x1` / 单窗 `rectangle`）。单窗保留当前活动面板并占满操作区，最小宽度 1060 → 760；状态写入 `single_pane_mode`，启动恢复；单窗下分隔线拖拽自动禁用，避免把隐藏面板拖出来（规格 W-07 / W-09）
- **活动面板改为发光边缘**（#6）：由 1.5pt 硬描边改为三层圆角描边羽化（7pt@10% / 3.5pt@20% / 1.2pt@55%），深色模式增强、浅色减弱；「增强对比度」开启时降级为 2pt 实线（规格 W-08）
- **侧栏「位置」分区**（#4）：删除窗口左下角的设备浮层卡片，设备改为侧栏第三个分区，排在「标签」上方；行高 28pt、卷图标 20pt、卷名 13pt、可用空间 11pt 右对齐，点击在活动面板打开挂载点，卷挂载/卸载自动刷新（规格新增 B-06b，M-04 同日废止）
- **侧栏三区标题对齐**（#5）：位置 / 标签改用与「个人收藏」同一套分区标题视图（11pt medium、行高 22、相对行左缘 6pt），并抵消 NSOutlineView 组行额外 16pt 缩进，三区标题实测同 x（规格 B-02 / B-07）

### 维护

- **构建脚本默认不再重链接 Rust dylib**：`build-rust.sh` 的 Xcode ld 重链接产物能通过 Mach-O 校验、集成测试也过，但装进应用后 `ff_list_dir` 全部 10s 超时（换回 cargo 原始 dylib 立即恢复）。默认改为直接复制 cargo 产物，需要验证 LINKEDIT 对齐时用 `FF_RELINK=1` 显式开启
- **软件包全面改名 FlowFinder**：`.app`、Xcode target、Swift 模块、测试 target、工程目录、脚本、CI、文档里不再出现 `FlowFinderNative`。产物为 `FlowFinder.app` / 可执行 `FlowFinder` / 模块 `FlowFinder` / 测试 target `FlowFinderTests`；bundle id 保持 `com.flowfinder.native` 不变（避免用户偏好与 TCC 权限丢失）
- **侧栏品牌区改版**：移除 32pt 应用图标，仅保留应用名称，名称下方显示版本号 `0.7.9 (7901)`；品牌区高度 56 → 44（规格 B-03）
- **仓库整理**：删除 101 个失效跟踪文件（`.omo/`、`docs/superpowers/`、`MIGRATION_*`、`release-notes/`、旧验收/开发说明、误入库的 `libflowfinder_core_relinked.dylib`）与约 530MB 可再生构建缓存；仓库 2.3G → 1.8G。历史内容仍可在 Git 历史中追溯
- **交接文档重写**（`docs/HANDOVER.md`）：按「大改前基线」重组，补代码地图、架构数据流、设计两类基准、构建/测试/发布三个环境事实、已知债务表与改造顺序建议

---

## [0.7.9-b1] — 2026-10-17

> **第一个面向普通用户的测试版**（beta 1）。版本号 0.7.9 / 构建 7901。
> 设计方向的唯一来源是 `docs/DESIGN-SPEC.md`，产品定义见 `docs/PRODUCT.md`，
> 验收口径见 `docs/ACCEPTANCE.md`。
>
> 本次交付：发行链路打通 + 设计方向收口 + 五条核心旅程打通 + 工程债清理。
> （内部曾按 V0.8.0 规划，发版号回落到 0.7.9 系列，故旧文档标题仍见 0.8.0。）

### 发行链路（P0）
- **Release 构建恢复**：`cargo build --release` 此前在 macOS 27 + Homebrew rustc 1.96.1 下必然失败（fat LTO 让 proc-macro dylib 产出 `mis-aligned LINKEDIT string pool`，`serde_derive` 无法 dlopen）。改 `[profile.release] lto = "thin"` 后通过，保留绝大部分跨 crate 优化
- **dylib 重链接根治**：`build-rust.sh` 的 Xcode ld 重链接缺 `-framework CoreServices`，导致 FSEventStream 符号未定义、长期回退到未对齐的 rust-lld 产物。补齐后重链接真正成功，导出 66 个 `ff_*` 符号，`dlopen` 验证通过
- **打包恢复 Release**：`package-beta.sh` 从 Debug 改回 Release（此前因上述构建失败被迫降级）
- **版本号单一真源**：`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 收敛到 Xcode 工程一处（0.7.9 / 7901），`scripts/lib-version.sh` 供打包脚本与 `make version` 读取，不再有三处硬编码
- **构建产物移出版本库**：`Libraries/*.a` / `*.dylib` 不再入库（此前每次构建产生 41MB 二进制 diff）
- **Makefile 重写**：原 `swift build` 目标对 Xcode 工程无效。新目标：`make build / release / demo / beta / test / version / warnings`

### 设计系统（P0 → 同日收口）
- **字体令牌单一来源**：`FFDesign.Text`（17 / 15 / 13 / 13m / 13sb / 12 / 11sb / 11 / 10 / mono12）。曾并存的 `FFDesign.Typography`（10 / 11 / 11sb / 13sb）已删除，原档位由 `baseSemibold` / `captionEmphasis` 承接，映射后渲染零变化
- **原子组件收口**：`FFComponents.swift` 只留 `FFPanelView`（设备浮层实体卡片）；零引用的 `FFSectionHeaderView` / `FFEmptyStateView` / `FFSeparatorView` 已删除——空态实际由 `FFPaneStateOverlayView` 承担
- **设计预览窗口已删除**（原 ⌥⌘D / `--design-preview`）：它渲染的是被撤销的 ZCode 方向（中性遮罩选中态、36pt 工具栏），留着会让「现行设计是哪套」永远有第二个答案
- ⚠️ **设计基线已回退访达**：P0 曾移植 [zai-org/ZCode](https://github.com/zai-org/ZCode) 的「扁平、致密、以边框分层」并声明「不追求像素级克隆访达」。该结论**未经确认且与已确认的方向冲突，已于同日撤销**，令牌层于当晚一并清除。详见 `docs/DESIGN-SPEC.md`

### 复审修正（2026-10-17 晚，对照 DESIGN-SPEC 全量核查）

- **「选中」曾有四个色源**：列表交给 `NSTableView` 默认绘制（系统强调色=蓝），侧栏与网格取应用强调色 `FFAccent`，标签筛选又单独用 `controlAccentColor` 15%。用户把强调色改成红后，同一语义同时存在蓝与红。现三处统一 `FFAccent`，失焦统一 `unemphasizedSelectedContentBackgroundColor`
  - 机制根因：委托创建的 `NSTableRowView` 其 `selectionHighlightStyle` 默认为 `.none`，此时由 `NSTableView` 用系统色自绘，行视图的 `drawSelection` 覆写不生效。需显式设 `.regular`
- **网格选中改为实心强调色 + 白字**（原为 25% 透明底 + 黑字，与列表完全不同）
- **侧栏宽度止三处不一致**：规格 200 / 令牌 200 / 代码 220 → 统一默认 220，改 `FFSplitView` 可拖 160–280，宽度写入 `sidebar_width` 记忆
- **详情栏文件名 13 → 15 semibold**（`FFDesign.Text.lg`）
- **窗口最小尺寸 1000×700 → 1060×700**：1000 减去侧栏 160 后每侧只剩 420，与操作区 450 保底自相矛盾
- **J1 首次打开就能看到文件**：补 `NSDesktopFolderUsageDescription` / `NSDocumentsFolderUsageDescription` / `NSDownloadsFolderUsageDescription` / `NSRemovableVolumesUsageDescription` / `NSNetworkVolumesUsageDescription`。macOS 14+ 缺键时系统直接拒绝且不弹授权框
- **启动目录兜底**：新增 `FFStartupPath`，候选序列「设置 → 上次位置 → 桌面 → 主目录」取首个真实存在者；两侧路径持久化到 `last_left_path` / `last_right_path`
- **J3 全键盘找并打开**：搜索框内 ↓/↑ 把焦点交给文件视图并选中首/末项，Enter 打开当前结果。Enter 在列表内仍是重命名（访达语义），两者作用域分离
- **J5 遇到问题知道怎么办**：新增 `FFErrorText`，错误不再把 `Permission denied (os error 13)` 这类英文原样上屏；权限类错误附带「打开系统设置」直达「隐私与安全性 › 文件和文件夹」

### 布局基线回归（2026-10-17 裁定）

逐条核对 37 份历史设计文档后，确认 P0 后续的布局重排（`7fd5bb5`）推翻了 5 条已确认决策，已回退：

- **工具栏恢复双行 72pt**（v0.6.5 决策）：Row1 = 导航 + 刷新 + 面包屑，Row2 = 搜索 + 排序 + 分组 + 视图 + 工具。单行方案虽省 32pt 高度，但面包屑被压到约 130pt，排序分组被迫收进图标菜单
- **详情栏恢复浮层**（v0.6.9 决策）：圆角卡片覆盖在列表上方，四周 8pt 边距 + 阴影；新增**底部留白补偿**——列表按浮层高度在滚动内容底部预留空白，修掉"最后一行被盖住"的长期副作用
- **侧栏恢复无缝贴合**（v0.6.7 架构）：亚克力侧边栏直接贴内容区，内容区保留 1px 边框 + 超椭圆圆角，去掉 4pt 面板间隙与独立面板框
- **超椭圆圆角系统保留**（v0.6.9）：不再声明废除
- **设备面板保留实体卡片**（本轮唯一保留项）：`FFGlassView` → `FFPanelView(.card)`，理由为设备名与容量数字在半透明材质上可读性差
- **面包屑截断方向修复**：`contentStack` 由 `leading` 改 `trailing`，溢出时保留当前目录（访达行为），此前只能看到「磁盘 > 用户」这类前缀

### 需求基线（新增）

- 新增 `docs/REQUIREMENTS.md`：项目首份需求真源。含产品定义、按版本的需求演进史（v0.6.0 → v0.8.0-P1）、当前生效功能全集（10 个模块 90+ 条带来源与状态）、偏离登记、十项硬约束、发布门槛、变更控制规则

### 工程债（P0）
- **菜单 action 类型安全**：`FFCommon.swift` 18 处 `Selector("xxx:")` 字符串改为 `#selector(FFPaneActionsController.xxx(_:))`，方法改名即刻编译报错，不再静默失效；`MainMenu.swift` 响应链 selector 改 `NSSelectorFromString`
- **编译警告 96 → 52**（剩余集中在 `onModeChanged` 已废弃 API 与弱引用书写，随 P2 主题重构与布局重排一并清理）
- **调试日志复核**：`FFDebug.log` / `FFLog.debug` 均已由 `#if DEBUG` 包裹，Release 二进制内 `strings` 检索 `ff-debug.log` 命中 0；无裸 `print`

### 侧边栏收藏模块重设计 P1

### 结构性重构
- **侧边栏改为滚动容器**：`NSScrollView` + flipped documentView + 垂直内容栈，品牌区与底部工具行固定，中间内容整体滚动。收藏 20+ 项时不再溢出重叠
- **收藏改为分区模型**：单一 `NSOutlineView` 渲染「个人收藏」group row + 收藏项（P2 标签并入后为多分区），删除 `favoritesHeightConstraint` / `tagsHeightConstraint` 两条定高约束与 `updateFavoritesHeight` / `updateTagsHeight` 高度计算链
- **高度改内容驱动**：outline 用 `intrinsicContentSize`（分区标题 22 / 收藏行 28 / 空态行 26），`TagFlowView` 同样改 intrinsic 高度，消除「瞬态可变约束无解」的冲突来源

### 新功能
- **拖拽重排收藏**：内部拖拽使用独立粘贴板类型（`com.flowfinder.sidebar.favorite`），带系统插入指示线，顺序即时持久化
- **收藏右键菜单五项**：从边栏中移除 / 在新标签页中打开 / 在新窗口中打开 / 显示简介 / 上移 / 下移（边界项自动置灰）
- **失效收藏灰显保留**：后台去抖 500ms 校验路径存在性，失效项图标 40% 透明 + 次级文字色 + tooltip「找不到该文件夹」，点击/Enter 不导航；卷挂载/卸载通知触发重校验，外置卷重插自动恢复（不自动删除）
- **空态引导行**：收藏为空时显示「拖入文件夹以添加收藏」
- **键盘与无障碍**：↑↓ 在收藏项间移动（跳过分区标题）、Enter 导航；分区标题标记 `AXGroup`，行保留 `sidebarLabel`

### 修复
- **拖文件到收藏区语义明确**：外部拖入文件夹=添加收藏（不移动文件，防误操作，设计决策 D2 默认）
- **点击收藏不再被自己重排打断**：程序化恢复选中时抑制导航通知（`suppressSelectionNotification`）

### 测试
- 新增 `SidebarFavoritesStoreTests`（17 项）：顺序重排（含 childIndex 语义/越界夹紧/空数组）、上移下移边界、UserDefaults 持久化往返、失效状态机（unknown 不算失效 / 恢复）、默认值播种与「用户清空后不回填」
- 测试基线：**Rust 200 tests / Swift XCTest 115 tests 全绿**（原 98 + 新增 17）
- `SidebarNavigationPosterTests` 适配分区模型：定位首条真实收藏行（首行为 group row，不可选中）

---

## [0.7.6] — 2026-08-28

> v0.7.5 发布后修复轮：界面稳定 + 弹窗可用性

### 界面稳定
- **AppKit 布局冲突清零**（修复前每次启动 28+ 条冲突日志）：
  - 工具面板 `NSGridView` 列宽改 defaultHigh 约束（`NSGridColumn.width` 的 required 约束在面板宽度变化瞬态必然无解）
  - 设备浮层折叠态清空设备行（AppKit 隐藏视图约束仍参与求解，折叠高 48 与行高 28 必然冲突）
  - 面包屑溢出按钮双高度约束（init 14pt 与外层 18pt 冲突）
  - 状态浮层重试按钮缺 `translatesAutoresizingMaskIntoConstraints`（autoresizing 强制宿主宽 62pt）
  - 侧边栏标签区定高 required → defaultHigh（异步修正前瞬态无解）
- **删除确认弹窗按钮可见性**：`FFModalSheet` 在 contentView 尺寸为 0 时量 `fittingSize` 导致窗口过矮（120pt vs 186pt），footer 按钮被裁出窗外；改为两段式测量 + footer 贴底 defaultHigh 兜底

### 弹窗会话
- **查重删除后「浏览...」失效修复**：`FFModalSheet` 用 `close()` 结束 sheet 会话，在 macOS 27 上使宿主窗口的下一个 `NSOpenPanel` sheet 静默无法弹出；改为 `beginSheetModal` 记录宿主、关闭统一走 `endSheet` 正规结束（惠及全部模态弹窗）

### 测试
- 新增 3 个 AppKit 回归测试：删除弹窗按钮可见性、sheet 脱离宿主、查重删除后浏览面板复现（完整操作序列端到端）
- 修复后基线：Rust 200 tests / Swift XCTest 73 tests 全绿，启动布局冲突日志 0

## [0.7.5] — 2026-08-14

> 安全加固 + 独立内容索引 + 测试与发布基建

### 🔒 安全与数据保护
- **批量重命名路径穿越修复**：`new_name` 专用文件名校验（拒绝 `/`、`\`、`..`、绝对路径、控制字符、空名）
- **批量/整理操作冲突策略**：目标已存在时默认拒绝，不再静默覆盖（`batch_rename` / `organize_by_date` / `organize_by_type`）
- **path_guard 全写入口接入**：复制/移动/删除/重命名/批量/并行操作均经路径安全校验
- **FSEvents 生命周期状态化**：`starting/active/failed/stopped` 状态机 + `ff_fsevents_status`，启动失败可观察（不再假成功）
- **取消隔离**：去重扫描/搜索按实例独立取消（`ff_scan_duplicates_ex` + `ff_cancel_scan_by_id`），全局取消标志移除

### ⚡ 性能与可靠
- **独立 SQLite FTS5 内容索引**：「内容包含」搜索改为后台可取消的索引查询（`content_index.sqlite` 独立于目录缓存，checkpoint 断点续建、增量失效、损坏自动备份重建）
- **删除/撤销/重做后台化**：不再阻塞主线程；`isDeleting` / `deleteFailedPaths` / `paneFileOperationChanged` 状态机
- **缓存并发修复**：SQLite WAL + busy_timeout + 连接池；空目录可缓存命中；缩略图清理节流
- **标签+搜索组合过滤修复**：同时激活时取交集
- **FFDebug 门控**：仅 DEBUG 编译生效 + 常驻句柄

### 🧪 测试与工程
- **可执行 Swift XCTest target**：`FlowFinderTests` shared scheme，`make swift-test` 走 xcodebuild（65+ tests）
- **FFI ABI/所有权锁定**：布局断言、回调借用契约、符号三方对比
- **任务生命周期测试**：提交→进度→取消→历史→清空全链路
- **fsevents 测试并发隔离**（12 处测试锁）

### 🎨 界面
- **主流程状态视图**：加载/空目录/错误+重试/删除进度统一呈现（`FFPaneStateOverlayView`）
- **删除确认统一**：菜单/右键/键盘/重复扫描共用 `DeleteConfirmDialog.confirmDelete`
- **搜索面板**：结果详情动态更新、窗口位置记忆（不再每次居中）
- **主流程无障碍**：VoiceOver 标签、键盘焦点、动态字体、reduced-motion、列表/网格交互一致
- **Pages 站**：375/768/1280 响应式修复、移动导航菜单、skip link、OG/canonical 元数据、对比度达标

---

## [0.7.4] — 2026-08-09

> 全量稳定性修复 + FSEvents 真实现

### 核心引擎（Rust Core）
- **文件监听重写**：占位轮询 → 真实 FSEventStream（事件驱动 + 300ms 去抖）
- **任务历史清理**：`ff_task_clear_history`，「清除已完成」按钮真正生效
- **设置键名对齐**：`appearance_mode` ↔ `appearance.theme` 互通

### 修复
- 重命名拦截含 `/` 文件名；删除失败项保留并展示
- 搜索竞态修复（代次校验）；主题跟随修复
- 对话框统一键盘交互（Enter/Esc/自动聚焦）；标签药丸流式换行
- 设置页快捷键真实生效；`SettingsActionTarget` 泄漏修复
- 网格空格 QuickLook firstResponder 守卫；排序/面板激活双触发修复
- 删除死代码 `ProgressDialog`；重复扫描删除统一「不再询问」标志

---

## [0.7.2] — 2026-08-07

> 设置页全面大修 + 液态玻璃视觉重设计 + 撤销/重做与冲突处理修复

- **设置页全面大修**：侧边栏导航 + 分区卡片布局（SettingsWindowController/SettingsSectionView 重构）
- **液态玻璃视觉重设计**：DesignTokens/FFGlassView 层级与透明度体系重构
- **撤销/重做闭环修复**：反向注册补全、对称注册、统一串行队列、注册延后到文件操作完成（消除 ⌘Z→⌘⇧Z 竞态与循环失效）
- **复制/移动冲突弹窗**：替换/保留两者/跳过；部分失败时撤销数组对齐
- **QuickLook 修复**：空格键在 tableView 层拦截转发；修饰键捕获实现访达拖拽语义
- **详情栏**：动态高度、`.app` 版本号、两列均衡、路径点击交互
- **收藏夹自绘高亮 / 搜索栏弹性 / 玻璃裁剪与亮线 / 工具面板高度** 等三轮 7 项修复

---

## [0.7.0] — 2026-08-02

> 11 项 UI 修复批量

### ✨ 新增

#### 搜索栏
- **搜索栏宽度自适应**：搜索框弹性吸收面板剩余宽度，右侧图标贴最右排列

#### 详情栏
- **图片专属信息增强**：图片文件在详情栏显示分辨率、打印尺寸、文件大小、色彩空间、相机 EXIF 等信息；`.app` 应用增加版本号兜底显示

#### 液态玻璃
- **设备栏/工具面板适配液态玻璃**：设备栏与工具面板改用 FFGlassView 呈现，与操作区/详情栏视觉一致

### 🐛 Bug 修复

#### 侧边栏收藏夹
- **高亮条裁剪修复**：收藏夹高亮条不再被裁剪，完整显示
- **标题间距**：「我的收藏」标题与文件夹间距统一为 4pt
- **行距收紧**：收藏夹文件夹行距收紧，布局更紧凑

#### 工具栏
- **显示设置图标**：改用系统 SF Symbol `slider.horizontal.3`，深浅色模式自适应

#### 操作区
- **四列按比例平铺**：列宽采用 `sequentialColumnAutoresizingStyle` 按比例分配，移除横向滚动条

#### 工具面板
- **入口修复**：批量重命名选中 <2 项时弹出提示；查重扫描打开时序调整；卡片可点区域修复
- **3×3 网格布局**：工具面板改为 3×3 网格，关闭图标改灰色 xmark，查重图标换用 `doc.on.doc`，空位补占位方块

#### 拖拽
- **拖拽访达语义**：同盘拖拽 = 移动 / ⌘拖拽 = 复制；跨盘拖拽 = 复制 / ⌘拖拽 = 移动

#### 设置页
- **精简低频/重复设置**：删除 7 项低频或重复设置（侧边栏图标大小、减少透明度、缩略图缓存大小、连接超时、与工具栏重复三项），统一卡片间距 12pt

### ♻️ 重构

#### QuickLook
- **常驻 responder 挂接**：QuickLook 改用常驻 responder 方式挂接，`MainWindowController` 实现 `QLPreviewPanelController`，替代此前临时插入/移除 responder 链的方案

---

## [0.6.9] — 2026-08-01

> UI 细节精细化修复 + QuickLook 预览修复

### ✨ 新增

#### 超椭圆圆角系统
- **SquircleView 工具类**：新建 `SquircleView.swift`，通过 `CGPath` 绘制超椭圆（superellipse）路径实现 iOS 风格的平滑圆角，替代标准 `cornerRadius`。应用到操作区容器（16pt）、详情栏浮层（12pt）、搜索框组件（8pt）等所有圆角位置

#### 文件夹显示配置菜单
- **文件夹配置按钮**：搜索栏后方的工具菜单改为文件夹显示配置菜单（`slider.horizontal.3` 图标），包含显示/隐藏隐藏文件、文件标签、文件后缀、系统文件四项开关，菜单文案根据当前状态动态切换并带勾选标记
- **新建文件夹**：菜单底部保留新建文件夹入口
- **显示配置联动**：`showHiddenFiles`/`showSystemFiles` 在数据层过滤文件列表（PaneState.applyDisplayFilter），`showFileTags`/`showFileExtensions` 在展示层控制视图刷新

#### 工具选择覆盖页
- **ToolOverlayView**：新建 `ToolOverlayView.swift`，点击侧边栏工具按钮后在当前激活操作区覆盖显示工具选择页。大方块网格布局（2列），每个工具包含 48pt 大图标 + 名称 + 介绍，右上角关闭按钮，Esc 键可关闭。查重扫描和批量重命名可用，AI 打标/AI 整理标记为 Beta 置灰

### 🐛 Bug 修复

#### QuickLook 预览
- **QuickLook 完全不可用修复**：`QuickLookPreviewPanel` 基类从 `NSObject` 改为 `NSResponder`，实现 `QLPreviewPanelController` informal protocol 方法（`acceptsPreviewPanelControl`/`beginPreviewPanelControl`/`endPreviewPanelControl`），通过 responder chain 插入/移除使 QLPreviewPanel 能正确找到 controller。空格键预览、方向键切换、Esc 关闭、再次空格切换均已修复

#### 侧边栏
- **收藏夹间距修复**：「我的收藏」标题与收藏夹文件夹列表间距从 12pt 改为 4pt，与标签区间距一致
- **收藏夹对齐修复**：收藏夹文件夹图标最左边缘与「我的收藏」标题文字最左边缘对齐，消除缩进

#### 操作区
- **背景覆盖修复**：操作区白色背景（夜间黑色）正确覆盖顶部工具栏区域（导航栏 + 搜索框 + 路径栏）
- **1px 边框**：操作区增加 1px 边框（日间浅灰 `NSColor.separatorColor` / 夜间深灰 `#3A3A3A`）
- **分割线移除**：移除侧边栏与操作区之间、两个操作区之间的分割线（`dividerThickness` 返回 0）
- **拖动渐变亮线**：拖动调整操作区宽度时，仅在鼠标位置显示从中心向两端渐变的垂直亮线（`CAGradientLayer`），不再显示操作区蓝色边框

#### 详情栏
- **浮层化改造**：详情栏从操作区容器内部底部改为浮层覆盖在文件列表上方，文件列表始终占满操作区全高，不因详情栏展开而缩短。四周留 8pt 边距，增加阴影（`shadowOpacity = 0.15`、`shadowRadius = 8`）强化浮动层次，圆角 12pt

#### 文件名布局
- **双行布局**：列表视图和网格视图中，有标签的文件显示双行（上方文件名、下方标签药丸），无标签文件单行显示。列表视图动态行高（有标签 48pt / 无标签 26pt），关闭标签显示时统一单行高度

---

## [0.6.8] — 2026-07-31

> 侧边栏交互修复 + 主题切换稳定性提升

### 🐛 Bug 修复

#### 侧边栏
- **收藏夹焦点框修复**：点击收藏夹文件夹时整个模块外不再出现蓝色焦点框。通过重写 `FFFNoDisclosureOutlineView.canBecomeKeyView` 返回 `false`，彻底阻止 NSOutlineView 获得键盘焦点，同时保留行选中高亮（`.sourceList` 样式）不变
- **收藏夹完整显示**：移除收藏夹区域的外层 `NSScrollView` 容器，收藏夹高度根据文件夹数量自适应，所有文件夹完整列出无需滚动；标签模块随之下移，仅在触底时才出现滚动条
- **标签同步修复**：修复 `FileListView` 和 `FileGridView` 中通知名称不匹配的问题（`FileListTagsChanged` → `FileTagsDidChange`），新增标签现在能自动同步到侧边栏标签模块
- **标签药丸样式**：标签模块统一使用胶囊形状药丸 + 颜色圆点样式，背景为标签颜色的浅色底（非高亮 0.12 / 高亮 0.22 透明度），与收藏夹文件夹图标左边缘对齐

#### 主题
- **日间/夜间模式切换修复**：修复 `FFDesign.isDark` 依赖 `NSApp.effectiveAppearance`（延迟更新）导致主题切换时玻璃效果读取旧值的问题，改用 `ThemeManager.shared.resolvedIsDark`（基于已立即更新的 `currentMode`），确保切换时所有 `FFGlassView` 实例的 tint/噪声/高光/内阴影同步刷新
- **夜间模式窗口外观修复**：修复 `MainWindowController` 中窗口外观被强制设为 `nil` 导致夜间模式无法生效的问题，改为跟随 `NSApp.appearance`

#### 详情栏
- **展开按钮修复**：修复详情栏展开按钮（chevron）被 `compactView` 和 `expandedView` 遮挡导致无法点击的问题，重新排列视图层级确保按钮可交互

#### 右键菜单
- **列表视图剪切按钮**：列表视图右键菜单补充缺失的「剪切」菜单项，与网格视图右键菜单完全一致
- **移动到废纸篓红色标注**：右键菜单中「移动到废纸篓」菜单项文字标为红色，与访达行为一致

#### 其他
- **全局撤销栈**：修复 `UndoManager` 未正确集成到窗口响应链导致 Cmd+Z 无效的问题
- **显示简介功能**：修复通知链不完整导致「显示简介」无法打开自定义文件信息窗口的问题

---

## [0.6.0-alpha] — 2026-07-21

> 🎉 FlowFinder 首个原生版本发布！从 Tauri + React 完整重构为 Swift & AppKit + Rust Core 架构。

### ✨ 新功能

#### 核心架构
- **Swift & AppKit 原生 UI**：完全重写 UI 层，使用 NSTableView、NSCollectionView、NSSplitView、NSMenu 原生组件
- **Rust Core FFI 桥接**：Rust Core 编译为 cdylib，通过 C ABI 暴露接口，Swift 通过 Bridging Header 调用
- **NSVisualEffectView 毛玻璃**：系统级毛玻璃材质，自动跟随深浅色主题，替代 WebView CSS backdrop-filter

#### 文件浏览
- **双栏布局**：左右独立导航，NSSplitView 可拖拽分隔条
- **统一工具栏**：后退 / 前进 / 上一级、面包屑路径、正则搜索栏、视图切换按钮，嵌入标题栏
- **双视图模式**：表格视图（NSTableView，可拖列宽 + 点击排序）+ 网格视图（NSCollectionView + 缩略图）
- **文件详情栏**：选中文件时底部显示缩略图、类型、大小、修改日期、标签等信息
- **隐藏 / 系统文件显示**：隐藏文件灰色文字，系统保护文件红色文字，可切换显示

#### 跨面板文件操作
- **复制到对侧面板**：⌘⇧C 一键复制选中文件到对侧面板当前目录
- **移动到对侧面板**：⌘⇧X 一键移动选中文件到对侧面板当前目录
- **在对侧面板打开**：右键菜单在文件夹上可直接在对侧面板打开该目录
- **冲突自动解决**：同名文件自动追加「副本 N」后缀
- **面板激活**：点击面板任意空白区域即激活该面板，无需键盘 Tab 切换

#### 原生右键菜单
- **FileListView 右键菜单**：打开、复制、剪切、粘贴、跨面板操作、重命名、删除、新建文件夹
- **FileGridView 右键菜单**：与 FileListView 一致的完整右键菜单
- **菜单栏快捷键**：完整的 ⌘C / ⌘X / ⌘V / ⌘⇧C / ⌘⇧X / ⌘N / Delete 等快捷键支持

#### macOS 原生体验
- **Quick Look 预览**：QLPreviewPanel 原生浮动预览，空格键触发
- **混合缩略图引擎**：QLThumbnailGenerator + SQLite 缓存，P0/P1 双队列优先级
- **Spotlight 搜索**：NSMetadataQuery 异步搜索 + Channel 流式推送结果
- **FSEvents 实时监控**：文件系统变更自动刷新目录列表
- **getattrlistbulk 批量读取**：单次系统调用获取目录全部元数据，性能提升 10-30 倍
- **clonefile CoW 复制**：APFS 卷零拷贝文件复制，瞬时完成
- **原生拖拽**：NSDraggingSource/Destination，同卷移动、跨卷复制、Cmd 键切换

#### 侧边栏
- **个人收藏**：任意文件夹可拖拽添加到收藏夹
- **存储设备**：磁盘分组显示，自动排除系统隐藏卷，支持 SMB/UNC 网络挂载
- **标签管理**：标签分类树，颜色圆点标识，AI 标签与 macOS 原生标签双向同步
- **可折叠区段**：所有区段可折叠，状态持久化

#### 高级功能
- **BLAKE3 重复文件检测**：三阶段检测（大小分组 → 部分哈希 → 完整哈希），实时进度流
- **AI 智能打标**：支持 OpenAI / Claude / Ollama / 自定义 API，隐私隔离（仅发送文件名 + 扩展名）
- **任务调度中心**：统一管理复制 / 移动 / 删除 / 查重任务，支持暂停 / 恢复 / 取消
- **SMB 网络共享**：渐进式加载、LRU 目录缓存、rayon 并行操作、断连自动重连
- **设置面板**：通用设置、外观主题（深色 / 浅色 / 跟随系统）、AI 模型配置

### 🚀 性能提升

| 指标 | 原版（Tauri） | 新版（Native） | 提升 |
|------|--------------|----------------|------|
| 目录列表（冷） | ~15-30 ms | ~0.5-1.0 ms | 10-30x |
| 目录列表（热） | ~5-10 ms | ~0.2-0.5 ms | 10-20x |
| 内存占用 | ~50-100 MB | ~20-30 MB | 2-3x |
| 启动时间 | ~2-3s | ~0.5s | 4-6x |
| 二进制大小 | ~80-100 MB | ~15-20 MB | 5-6x |

### 🏗️ 架构变更

- UI 层从 React 19 + WebView 重写为 Swift 5.9 + AppKit
- 文件列表从 react-virtual 重写为 NSTableView + NSCollectionView
- 缩略图从 Rust FFI 重写为 QLThumbnailGenerator（Swift 原生）
- QuickLook 从 Swift Bridge 中转重写为 QLPreviewPanel 单例直调
- 搜索从 Tauri Commands 重写为 SearchBridge + SpotlightBridge
- 拖拽从 HTML5 重写为 NSDraggingSource/Destination
- 毛玻璃从 CSS backdrop-filter 重写为 NSVisualEffectView

### 📦 下载

| 文件 | 大小 | 架构 | 说明 |
|------|------|------|------|
| `FlowFinder-0.6.0-alpha.dmg` | ~1.7 MB | Apple Silicon | DMG 安装镜像 |
| `FlowFinder-0.6.0-alpha.zip` | ~1.2 MB | Apple Silicon | ZIP 压缩包（含 .app） |
| `libflowfinder_core.dylib` | — | Apple Silicon | Rust Core 动态库（开发用） |
| `ff_ffi.h` | — | — | FFI C 头文件（开发用） |

### ⚠️ 已知限制

- 仅支持 Apple Silicon 架构（Intel Mac 未充分测试）
- 当前为 alpha 版本，可能存在未发现的 Bug
- 部分 UI 动画仍在优化中
- 全局撤销 / 重做栈尚未完整实现
- 批量重命名 UI 尚在开发中

### 📝 完整重构历史

早期 Tauri → 原生的迁移与各轮重设计记录已从工作树移除，需要追溯时翻 Git 历史（2026-10-18 之前的提交）。

---

## 版本号规则

FlowFinder 采用以下版本号规则：

- **0.x.0-alpha** / **0.x.0-beta**：开发预览版，功能可能不完整
- **0.x.0**：稳定版，核心功能完整
- **1.0.0**：正式发布版，通过全面测试

无重大架构变更时，后续版本依次递增（0.6.1、0.6.2 ...）。
