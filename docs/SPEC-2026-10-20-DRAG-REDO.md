# SPEC · 标签拖拽重做（路线 B · 全能力）

> 日期：2026-10-20 · 分支：`feat/v0.9-overhaul` · 状态：**已实现（自动化验证通过；人工手感 / 60fps 采样待复验）**
> 关联：`HANDOVER.md` §1.6、`REQUIREMENTS-LEDGER.md` R-01/R-13、`SPEC-2026-10-20.md` §1.12–§1.14、`CHANGELOG.md` 未发版段

---

## 0. 决策记录（本轮已确认）

| # | 决策 | 结论 |
|---|---|---|
| D-1 | 重做路线 | **B · 全能力重做**：同窗口 + 跨窗口 + 拆双栏 + 拖出新窗全部保留 |
| D-2 | 窗口内无法解析区域 | **回原位 + 无效反馈**，不新建窗口 |
| D-3 | 另一个单栏窗口的操作区 | **拆成双栏**，目标窗口原有标签完整保留在另一侧 |
| D-4 | 源面板只剩一个标签 | **允许拖出**；源面板折叠/源窗口关闭；没有其它窗口时保持无窗口，Dock 点击重开 |
| D-5 | 性能门槛 | **严格 60fps**：连续拖 3 秒，主线程单次阻塞 <16ms，帧间隔 p95 <16.7ms |
| D-6 | 拖动反馈 | **轻量反馈**：完整胶囊浮层 + 2px 插入线；不做源标签变淡、不做半透明填充；落点用 1px 描边 |

---

## 1. 背景与根因

用户实测反馈两件事：**拖标签/拖窗口严重卡顿**；**标签拖拽被改废，不知道该怎么调**。
审查后确认这不是手感问题，而是三处结构问题叠加。

### 1.1 行为根因

1. **单栏落点走错侧**：`MainWindowController.operationSide(near:)` 在单栏时直接 `return activePane`，没有按指针左右半区判定（`MainWindowController.swift:1175`）。拖到右半区，高亮与新面板仍可能出在左边。
2. **兄弟标签被清空**：`acceptTabIntoPane()` 用 `newStore.replaceAll([session])` 覆盖活动面板（`MainWindowController+Tabs.swift:199`）；单栏拖入时原面板的其它标签全部丢失。这是数据丢失。
3. **测试绕过真实链路**：应用内自检 ③ 直接调用 `acceptTab(session, into: .paneContent(window: self, side: .right))`（`MainWindowController+Tabs.swift:407`），不经过 `operationSide()`；129 项全绿也测不到真实落点侧。

### 1.2 性能根因

1. **插入线走 Auto Layout**：`showInsertionIndicator(atIndex:)` 每事件修改 `centerX` 约束（`PaneTabs.swift:565–583`），使整个窗口布局失效。
2. **布局级联到列重算**：`FileListView.layout()` 每次布局都异步调度 `applyColumnFit()`（`FileListView.swift:1652`），后者可能 `rebuildColumns()` / `reloadData()`（`:1147`、`:1047`）。一次真实拖动采样中，主线程非空闲样本 82 个，其中 61 个落在 `FileListView.layout` 链路（约 74%）。
3. **每事件全窗口 hitTest**：`computeDropTarget()` 遍历所有窗口，对每个窗口 `contentView.hitTest` 并沿祖先链解析区域（`FFPaneDrag.swift:476–502`）。
4. **每事件浮层/高亮更新**：`moveGhost()` 每事件 `setFrameOrigin` + `orderFrontRegardless`（`:536–541`）；`showHighlight()` 每事件 `needsDisplay`（`:550–586`）。
5. **窗口拖动绕过系统合并**：`window.isMovable = false` 后由 `setFrameOrigin` 逐事件移动（`:354`）；窗口非不透明、整窗 `NSVisualEffectView` 背景模糊，每移动一次都要重新合成。
6. **状态发射引发双列表重载**：`updatePaneUI()` 每次 `$state` 发射都 reload 左右列表，并同步调用 `attributesOfFileSystem` 取磁盘空间（`MainWindowController.swift:1848`、`:1864`）。
7. **监视器泄漏**：每个窗口各装一个 `leftMouseDown` 监视器，`deinit` 不移除（`:786`、`:1226`）。

### 1.3 历史漂移

| 提交 | 模型 |
|---|---|
| `4b6af4c` 基线 | 标签级 `NSDraggingSession`；同窗口重排/并入/单栏拆分 |
| `ed53175` R1 | 改成面板级；“单面板单标签 = 拖窗口” |
| `03b304a` R2 | 标签当把手，仍搬整块面板 |
| `fd3be81` R3 | 决策表 |
| `25d94c0` R4 | 改回标签级 + 跨窗口；单栏落点 bug 从这里进入 |
| `f0228b2` / `d9f1135` R5 | 手势仲裁、落点语义；`operationSide` 没有同步改 |
| R6（未提交） | 回归修复；未触碰 `operationSide` 与布局级联 |

结论：同一套手势在五次改向里换了三种对象（面板 / 标签 / 窗口拖动），文档、代码、自检各说各话。本轮先建立稳定的语义基线，再动实现。

---

## 2. 目标与非目标

### 2.1 目标

- **全能力**：同窗口重排/并入/拆双栏，跨窗口并入/拆双栏/新建窗全部保留。
- **零数据丢失**：任何落点都不丢标签；源面板搬空才折叠/关窗。
- **严格 60fps**：见 §5。
- **可测**：落点决策是纯函数，真实 UI 链路有测试；自检不再绕过 `operationSide()`。
- **轻量反馈**：见 §6。

### 2.2 非目标

- 面板切换“真位移”（单独一轮）。
- 标签条视觉重设计、列表列/主题改动。
- 目标窗口置前、吸附动画、触觉反馈等额外花活。
- 改 Rust core / 文件操作。

---

## 3. 行为规则（唯一真相源）

设源标签来自窗口 W1、面板 S、索引 i。指针屏幕坐标 P。

### 3.1 落点表

| # | 落点 | 决策 | 结果 |
|---|---|---|---|
| 1 | W1 的 S 标签条 | `reorder` | 按指针与标签中线插入；末尾空白追加；不新建面板 |
| 2 | W1 的另一侧标签条 | `merge` | 插入该侧；源面板保留其余标签 |
| 3 | W1 操作区（双栏）的 L/R | `merge` | 并入落点侧末尾；激活被拖标签 |
| 4 | W1 操作区（单栏），指针在左/右半 | `split` | 被拖标签成为落点侧新面板；原面板保留**其余全部**标签；窗口变双栏 |
| 5 | W2 的标签条 | `merge` | 按指针在目标标签左/右半插入；末尾空白追加 |
| 6 | W2 操作区（双栏）的 L/R | `merge` | 并入落点侧末尾；目标窗口激活该侧 |
| 7 | W2 操作区（单栏） | `split` | W2 拆双栏；被拖标签成为落点侧新面板；W2 原有标签完整留在另一侧 |
| 8 | 所有 FlowFinder 窗口之外 | `newWindow` | 新建单栏窗口，只含被拖标签；位置在松手点附近并钳制到屏幕内 |
| 9 | 窗口内无法解析区域 | `returnToSource` | 标签回原位；禁止光标 + 淡出；不新建窗口 |
| 10 | 拖动中按 Esc | `returnToSource` | 浮层淡出；不做任何落点动作 |
| 11 | 源面板最后一个标签拖出 | `merge` / `newWindow` + **源空处置** | 决策本身仍是并入或新建窗；上层在落地后计算源面板是否为空：双栏折叠该面板，单栏关闭源窗口；无其它窗口时保持无窗口 |

### 3.2 边界规则

1. **同窗口单栏、只剩一个标签、拖回自己面板**：决策 `returnToSource`（不拆出一个空面板）。
2. **目标单栏只有占位标签（空面板）**：决策 `merge`，被拖标签填回该面板；不拆双栏。
3. **目标单栏有 ≥1 个真实标签**：决策 `split`，原有标签完整保留在另一侧。
4. **双栏拖回源面板同一侧的操作区**：决策 `returnToSource`（操作区不是重排区）。
5. **源面板被搬空**：双栏 → 折叠该面板并切到另一侧；单栏 → 关闭窗口；若这是最后一个窗口，不自动补窗口。
6. **无窗口状态**：`AppDelegate.applicationShouldHandleReopen` 创建一个新窗口；Dock 点击可恢复。
7. **另一个 App 的窗口**：不属于任何 FlowFinder 窗口，按规则 8 处理（新建窗口）；不向其它 App 发拖放。
8. **无效落点判定优先于“窗口外”**：指针在某个 FlowFinder 窗口的 frame 内，但不在标签条/操作区内 → `returnToSource`，即使该区域没有声明区域。

### 3.3 落点几何定义

- **标签条**：`PaneTabStripView` 的 bounds，外扩 20pt 仍算条内；条内按指针与每个标签中线的位置决定插入索引。
- **操作区半区**：从操作区左缘到中线为左半，中线到右缘为右半；双栏时 L/R 是两个面板，单栏时 L/R 是同一个面板的左右半。
- **操作区**：整个面板卡片，含工具栏、列表、详情栏与四周留白；落在卡片内即按操作区处理。
- **无效区**：侧栏、红绿灯、标题条空白（非标签条矩形）、“+”按钮。
- **调宽把手**：拖动标签时按所在操作区处理（不触发调宽），不视为无效区。
- **标签内的关闭“×”**：按所在标签处理，不做无效区。
- **窗口外**：不在任何已注册 `MainWindowController` 的 window frame 内。

---

## 4. 架构

### 4.1 四层

```
FFPaneDragController 会话状态（idle / pending / reorder / dragOut / windowDrag）
        ↓
FFDropResolver（纯函数，唯一落点决策）
        ↑
FFDragGeometryCache（每窗口几何缓存）
        ↓
FFDragOverlay（轻量反馈，不参与 Auto Layout）
```

#### 4.1.1 会话状态（`FFPaneDragController` 持有）

不单独建 `FFDragSession` 文件；会话状态由控制器现有的 `Mode` + `sourceRef` / `latestPointer` / `currentDecision` 承载。阶段固定为：

- `idle`
- `pendingTab`（mouseDown 标签，未超阈值）
- `reordering`（缓冲内，更新插入线）
- `draggingTab`（出缓冲，浮层 + resolver）
- `draggingWindow`（标题/侧栏空白）
- `pressing`（面板按压反馈）

转移：
- mouseDown 标签 → `pendingTab`
- 超过 4pt 且在缓冲内 → `reordering`
- 出缓冲 → `draggingTab`
- mouseDown 标题/侧栏空白 → `draggingWindow`
- mouseUp / Esc / app 失焦 → `idle`

#### 4.1.2 `FFDropResolver`

纯函数，输入：

```swift
enum PaneSide: Hashable, CaseIterable { case left, right }

struct FFDragSource {
    let windowID: ObjectIdentifier
    let side: PaneSide
    let index: Int
}

struct FFTabStripGeometry {
    let rect: CGRect              // 屏幕坐标（标签条本体，不含缓冲）
    let tabRects: [CGRect]        // 每个标签的屏幕矩形，用于左右半插入
}

struct FFPaneGeometry {
    let rect: CGRect              // 整个面板卡片（含工具栏/列表/详情/留白）
    let realTabCount: Int         // 0 = 只剩占位
}

struct FFWindowDropGeometry {
    let windowID: ObjectIdentifier
    let frame: CGRect             // 屏幕坐标
    let isSinglePane: Bool
    let activePane: PaneSide
    let tabStrips: [PaneSide: FFTabStripGeometry]
    let paneContents: [PaneSide: FFPaneGeometry]
    let invalidRects: [CGRect]    // 侧栏、红绿灯、标题条空白、“+”
}

enum FFDropDecision: Equatable {
    case reorder(windowID: ObjectIdentifier, side: PaneSide, index: Int)
    case merge(windowID: ObjectIdentifier, side: PaneSide, index: Int?)
    case split(windowID: ObjectIdentifier, dropSide: PaneSide)
    case newWindow
    case returnToSource
}
```

`FFDropResolver.resolve(source:pointer:geometries:)` 按 §3 返回决策。所有分支必须穷举；不得依赖 AppKit 视图。

#### 4.1.3 `FFDragGeometryCache`

每个窗口维护一份 `FFWindowDropGeometry`，在以下时机重建：
- `NSWindow.didMoveNotification` / `didResizeNotification`
- `NSWindow.didEndLiveResizeNotification`
- 分栏位置变化、侧栏显隐、单双栏切换
- 标签条刷新、标签增删/重排
- 窗口创建/关闭

缓存矩形统一用**屏幕坐标**，拖动中只做矩形 `contains`，不再 `contentView.hitTest`。多窗口重叠时按 `NSApp.orderedWindows` 从前到后排序，落点取最上面的窗口。

#### 4.1.4 `FFDragOverlay`

- **浮层**：一个复用 `NSPanel`，拖动开始时对源标签做一次快照；之后只改 `frame`，不重复快照、不重复 `orderFront`。
- **插入线**：层-backed `NSView`，`translatesAutoresizingMaskIntoConstraints = true`，直接设 `frame`；不添加任何约束。
- **落点描边**：层-backed `NSView`，1px `FFAccent` 边框、无填充；直接设 `frame`。
- 所有 frame 更新包在 `CATransaction` 中并 `setDisableActions(true)`；目标未变化时不重绘。
- 不调用 `layoutSubtreeIfNeeded` / `needsDisplay` 于拖动路径。

### 4.2 帧调度

- 拖动期间启动一个 60Hz `Timer`（`.common` 模式），只保存最新指针；每帧执行一次 `resolve + overlay update`。
- 事件本身只更新 `latestPointer`，不做落点判定。
- 拖动结束/取消时立即停表。

### 4.3 窗口拖动

- `.window` / `.title` 空白区域：调用 `window.performDrag(with: event)`，走系统服务端拖动。
- **Spike 先行**：验证 `performDrag(with:)` 与本地标签监视器不冲突；若冲突，回退到 60Hz 合并的自管 `setFrameOrigin`（每帧最多一次）。
- 不再每事件 `setFrameOrigin`。

### 4.4 监视器与生命周期

- `FFPaneDragController` 保持 app 级单例。
- 每个窗口的 `mouseEventMonitor` 必须在一个统一的位置移除（`deinit` 或窗口关闭通知），不得泄漏。
- 不依赖 `addGlobalMonitorForEvents`（需要辅助功能权限，本机未授予）。鼠标归属依赖“不消费 mouseDown”；拖到窗口外松手的 mouseUp 用本地监视器验证；若实测收不到，再单独加带降级的兜底。

### 4.5 布局隔离

- `FileListView.layout()`：记录 `lastColumnFitWidth`；只有 `bounds.width` 变化 >0.5pt 时才调度 `applyColumnFit()`。
- `applyColumnFit()`：可见列集合未变化时只改列宽，不 `rebuildColumns()`；列宽未变化时不 `reloadData()`。
- `updatePaneUI()` 拆分：
  - 工具栏/面包屑：每次状态发射可更新。
  - 文件列表/网格：只在 `files` / `filteredFiles` / `selection` / `viewMode` 变化时 reload。
  - 磁盘可用空间：后台计算 + 按路径缓存；不在主线程每次同步 `attributesOfFileSystem`。
- `PaneTabStripView.refresh()` 不再同步 `layoutSubtreeIfNeeded()`；需要布局时交给下一帧。

### 4.6 清理

- `highlightSide(for:)`：删除或接入真实高亮。
- `canDragOut`：删除或接入真实约束（若最后标签允许拖出，则不需要）。
- 决策表中未消费的 `sidebarVisible` / `singlePane` 维度与 `.activateTab` / `.marqueeSelect` / `.handledByControl` 意图：本轮只保留实际使用的部分；删除死代码，避免再次误导。
- 更新文件头注释与 HANDOVER 中与实现不符的描述。

---

## 5. 性能验收（严格 60fps）

### 5.1 测试条件

- 机器：当前 macOS 27.2 / arm64。
- 窗口：双栏，左右各 3 个标签；左面板目录 ≥100 个文件。
- 动作：连续拖动 3 秒（条内重排 + 拖出到操作区 + 跨窗口各一轮）；窗口拖动 3 秒。
- 工具：`os_signpost` + Instruments Time Profiler；保留 `.trace` 或采样文本作为证据。

### 5.2 门槛

- 帧间隔 p95 <16.7ms。
- 主线程单次阻塞 <16ms。
- 拖动期采样中不出现 `FileListView.layout → applyColumnFit → rebuildColumns`。
- 每帧最多一次浮层 frame 更新；每帧最多一次落点解析。
- 不出现每事件 `setFrameOrigin`（窗口拖动走系统或帧调度）。

### 5.3 Signpost

在 `FFPaneDragController` 内加：
- `FFDrag.begin` / `FFDrag.end`
- `FFDrag.frame`（每帧一次）
- `FFDrag.decision`（落点变化时）
- `FFDrag.drop`（松手）

只用于 Debug/性能构建，Release 不输出日志。

---

## 6. 视觉反馈（轻量）

| 状态 | 表现 |
|---|---|
| 条内重排 | 2px `FFAccent` 插入线；**不**让源标签变淡；不出现浮层 |
| 拖出缓冲 | 完整标签胶囊浮层（0.55 不透明度，带阴影）；抓取点保持指针在标签内的相对位置 |
| 操作区落点 | 1px `FFAccent` 描边，无填充；单栏拆分时描边标出将要出现的新面板半区 |
| 标签条落点 | 目标标签条 1px 描边；插入线按指针左右半显示 |
| 无效落点 | `operationNotAllowed` 光标；浮层降到 0.35；松手后淡出、标签回原位 |
| 跨窗口 | 目标窗口标签条/面板描边；**不**置前目标窗口 |
| Esc 取消 | 浮层淡出、源标签恢复、无落点动作 |
| 落地 | 浮层淡出；必要时短暂高亮新位置（≤120ms），不做弹跳 |

不使用源标签变淡、不使用半透明大面积填充、不做吸附动画。

---

## 7. 测试策略（TDD）

### 7.1 纯函数测试（新增）

`FFDropResolverTests` 至少覆盖：

- 同窗口标签条：左半/右半/末尾空白 → 正确索引。
- 同窗口另一侧标签条 → `merge`。
- 同窗口双栏：左/右操作区 → `merge` 对应侧。
- 同窗口单栏：左/右半 → `split` 对应侧；原面板标签保留。
- 另一窗口标签条：左/右半/末尾 → `merge` 正确索引。
- 另一窗口双栏：左/右 → `merge`。
- 另一窗口单栏：→ `split`；目标原有标签保留。
- 所有窗口外 → `newWindow`。
- 侧栏/红绿灯/工具栏/“+”/标题空白 → `returnToSource`。
- 同窗口单栏只剩一个标签、拖回自己 → `returnToSource`。
- 目标单栏只有占位 → `merge`（不拆）。
- 源最后一个标签拖出 → 决策为 `merge` / `newWindow`，上层根据源 store 是否为空执行折叠/关窗。
- 指针在窗口 frame 内但不在任何合法区 → `returnToSource`。

### 7.2 数据层测试

`PaneTabsStore` / `MainWindowController+Tabs`：

- `takeTabOut` 后兄弟标签完整。
- 单栏拆双栏：源面板保留其余标签；新面板只含被拖标签。
- 目标单栏拆双栏：目标原有标签完整保留在另一侧。
- 源面板搬空：双栏折叠、单栏关窗。
- 最后一个窗口关闭后不自动补窗口；`applicationShouldHandleReopen` 能创建新窗口。
- 占位标签在真实标签进入时被替换，不残留。

### 7.3 真实 UI 链路测试

在 XCTest 中创建真实 `MainWindowController`（`showImmediately: false`），构造双栏/单栏场景，走 `FFDropResolver → accept` 的完整链路：

- 单栏拖到右半 → 右面板出现被拖标签，左面板保留其余标签。
- 另一窗口单栏拖入 → 目标拆双栏，原有标签保留。
- 无效落点 → 不新建窗口，标签回原位。
- 跨窗口标签条 → 按指针半区插入。
- 最后标签拖出 → 源窗口关闭。

**禁止**再出现“直接传 `side:` 绕过 `operationSide()`”的测试写法。

### 7.4 性能结构测试

- 插入线视图：`translatesAutoresizingMaskIntoConstraints == true`，且 `constraints` 中无自身定位约束。
- `FileListView.layout()` 在宽度不变时不调度 `applyColumnFit()`（用测试专用 spy/counter）。
- 拖动一次完整会话，断言没有触发 `rebuildColumns()`（测试专用计数）。
- 性能门槛本身用 Instruments 采样人工验收，不做不稳定的 CI 时间断言。

### 7.5 应用内自检

- 更新 `runDragSelfTest`：使用真实 `FFDropResolver` + `operationSide`，不再直接传 `side:`。
- 新增：无效落点、目标单栏拆双栏、最后标签拖出、跨窗口指针半区插入。
- 保持原有六步 PASS；更新断言总数与文档。

### 7.6 TDD 顺序

1. 写 `FFDropResolverTests` 的失败测试（先覆盖已知 bug：单栏落点、兄弟标签保留、无效落点、目标单栏拆分）。
2. 实现纯 resolver → 全绿。
3. 接入几何缓存与真实窗口，写集成测试 → 红 → 绿。
4. 替换 overlay / 插入线，补结构测试。
5. 窗口拖动 spike → 绿/回退。
6. 性能采样 → 达标或继续优化。
7. 更新自检、文档、台账。

现有 190 条 XCTest 必须保持全绿。

---

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| `performDrag(with:)` 与标签监视器冲突 | 第一步 spike；失败回退 60Hz 合并自管拖动 |
| 跨窗口几何缓存过期 | 监听 didMove/didResize/分栏/标签变化；集成测试覆盖 |
| 拖到窗口外松手收不到 mouseUp | 不消费 mouseDown，保住鼠标归属；实测验证；必要时加带降级的全局监视器 |
| 无窗口状态后无法恢复 | `applicationShouldHandleReopen` + Dock 点击测试 |
| 性能测试不稳定 | 以结构测试 + Instruments 报告为准，不把时间断言放进 CI |
| 范围膨胀 | 非目标见 §2.2；真位移、标签条视觉重设计另开一轮 |

---

## 9. 计划改动的文件

| 文件 | 改动 |
|---|---|
| `UI/FFDropResolver.swift`（新） | 纯落点决策 + 几何/决策类型 |
| `UI/FFDragGeometryCache.swift`（新） | 每窗口屏幕坐标几何缓存，按窗口层级排序 |
| `UI/FFDragOverlay.swift`（新） | 轻量浮层、插入线、落点描边；不参与 Auto Layout |
| `UI/FFPaneDrag.swift` | 接入 resolver/overlay/帧调度；删除每事件 hitTest/日志；窗口拖动 spike |
| `UI/PaneTabs.swift` | 插入线改为无约束层；删除同步 `layoutSubtreeIfNeeded` |
| `UI/MainWindowController.swift` | 几何缓存、监视器清理、`updatePaneUI` 拆分、磁盘空间异步化 |
| `UI/MainWindowController+Tabs.swift` | 修正 `operationSide`、拆双栏保留标签、关窗/无窗口逻辑 |
| `UI/FileListView.swift` | 列重算宽度守卫、避免拖动期 rebuild |
| `UI/FFRegionResolver.swift` | 无效区域判定与 drop 区分类 |
| `App/AppDelegate.swift` | `applicationShouldHandleReopen` |
| `Tests/FlowFinderTests/FFDropResolverTests.swift`（新） | 纯函数穷举 |
| `Tests/FlowFinderTests/FFDragIntegrationTests.swift`（新） | 真实窗口链路 |
| `Tests/FlowFinderTests/FFDragPerformanceStructureTests.swift`（新） | 结构护栏 |
| `FlowFinder.xcodeproj/project.pbxproj` | 注册新源码/测试文件（独立 ID 段） |
| `docs/HANDOVER.md` / `REQUIREMENTS-LEDGER.md` / `CHANGELOG.md` | 实现后同步 |

---

## 10. 验收清单

- [x] `FFDropResolver` 全组合测试全绿（14 条，含 §7.1 所有分支）。
- [x] 单栏拖右半：右面板出现被拖标签，左面板保留其余全部标签（自检 ③ + 集成测试）。
- [x] 目标单栏拆双栏：目标原有标签完整保留（自检 ⑧ + 集成测试）。
- [x] 无效落点：不新建窗口，标签回原位（自检 ⑦ + 集成测试）。
- [x] 最后标签拖出：源面板折叠/关窗；无窗口时 Dock 可重开（自检 ⑨ + reopen 测试）。
- [x] 跨窗口标签条：按指针左/右半插入（自检 ⑩）。
- [x] 现有测试全绿：**190 条 XCTest，0 失败**。
- [x] 应用内自检更新并通过（真实 resolver，不绕过 `operationSide`）：**135 项，0 失败**。
- [ ] 连续拖动 3 秒：p95 <16.7ms，主线程单次阻塞 <16ms（**待人工拖拽 + Instruments/sample**）。
- [ ] 拖动期无 `FileListView.layout → applyColumnFit → rebuildColumns`（代码级守卫已加，**待真实拖拽采样确认**）。
- [ ] 窗口拖动无每事件 `setFrameOrigin`（原生 `performDrag` 已接，**待人工确认**；`FF_NATIVE_WINDOW_DRAG=0` 可回退）。
- [x] `HANDOVER.md` / 台账 / CHANGELOG 更新，自检数量按实测重写。

---

## 11. 实现记录（2026-10-20）

### 11.1 新增/改动

| 文件 | 内容 |
|---|---|
| `UI/FFDropResolver.swift`（新） | 纯落点决策 + 几何/决策类型 + 14 条穷举测试 |
| `UI/FFDragGeometryCache.swift`（新） | 屏幕坐标几何缓存；按 `NSApp.orderedWindows` 前到后排序 |
| `UI/FFDragOverlay.swift`（新） | 完整胶囊浮层 + 1px 描边；frame-based，不参与 Auto Layout |
| `UI/FFPaneDrag.swift` | 接入 resolver/几何缓存/60Hz 帧调度；窗口拖动改 `performDrag`；删除每事件 hitTest 与 `[TAB]` 日志 |
| `UI/PaneTabs.swift` | 插入线改 frame-based；`FFAccent`；移除 `canDragOut` 死代码；`+` 按钮暴露无效区矩形 |
| `UI/MainWindowController.swift` | `operationSide` 单栏按半区；`dragGeometry()`；`FFPaneReloadPolicy`；磁盘空间异步缓存；监视器 deinit 清理 |
| `UI/MainWindowController+Tabs.swift` | 单栏拆双栏保留全部标签；自检 ③/⑦–⑩ 走真实 resolver；自检结束还原用户会话 |
| `UI/FileListView.swift` | 列重算宽度守卫；列集合变化时显式失效 |
| `UI/FFListColumns.swift` | `FFColumnFitPolicy.shouldFit` |
| `Model/PaneState.swift` | `PaneState` / `SortField` / `ViewMode` 加 Equatable |
| `App/AppDelegate.swift` | `applicationShouldHandleReopen` |
| 测试 | 新增 `FFDropResolverTests` 14、`FFDragGeometryCacheTests` 3、`FFDragIntegrationTests` 7、`FFDragPerformanceStructureTests` 4；总计 190 条 |

### 11.2 行为结果

- 单栏拖到右半区：新面板出在右侧；左面板保留 A/C；不再清空兄弟标签。
- 目标单栏拆双栏：目标原有标签完整留在另一侧。
- 无效落点（侧栏/红绿灯/标题空白/“+”）→ `returnToSource`，不新建窗口。
- 最后标签允许拖出；源面板折叠/关窗；无窗口时 Dock 点击重开。
- 跨窗口标签条：按指针在目标标签左/右半插入；末尾空白追加。

### 11.3 性能改动

- 插入线从 Auto Layout 约束改为 `frame`；拖动不再让整窗布局失效。
- `FileListView.layout` 只在宽度变化 >0.5pt 时调度 `applyColumnFit`；拖动期不再重建列。
- 拖动事件只更新最新指针；落点解析与浮层更新由 60Hz `FFDragFrameScheduler` 每帧一次。
- 几何在拖动开始时缓存一次，拖动中只做矩形判定；不再全窗口 `hitTest`。
- 窗口拖动默认走 `window.performDrag(with:)`；`FF_NATIVE_WINDOW_DRAG=0` 回退到 60Hz 合并自管拖动。
- `updatePaneUI` 只在内容字段变化时 reload；选中变化不再整表重建；磁盘空间后台读取 + 缓存。
- 每个窗口的鼠标/键盘监视器在 `deinit` 移除；`FFPaneDragController` 支持 `unregister`。

### 11.4 验证

- `make build`：BUILD SUCCEEDED。
- `make swift-test`：**190 条，0 失败**。
- `FF_SELFTEST=1`：**135 项，0 失败**。
  - 拖拽 10 步（①–⑩）+ 决策表 71 + 区域 7 + 行为 4 + 焊接 21 + 外壳 22。
- 合成鼠标事件在本机仍不可靠（光标/坐标被系统干扰），**真实拖拽手感与 60fps 采样未完成**。
- 窗口拖动原生 `performDrag` 已接并通过构建；合成事件无法可靠驱动窗口移动，**需人工在桌面副本上确认**。
- 回退开关：`FF_NATIVE_WINDOW_DRAG=0` 启动即走 60Hz 自管窗口拖动。
