# FlowFinder UI 修复批量（11 项）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复用户提出的 11 项 FlowFinder UI 问题（收藏夹/搜索栏/图标/列宽/玻璃效果/工具面板/QuickLook/拖拽/设置页/详情栏）。

**Architecture:** 全部为 Swift & AppKit 侧修改，Rust Core 无改动。每项改动集中在单一文件或相邻文件，修改后用 `xcodebuild` Debug 构建验证，逐任务提交。

**Tech Stack:** Swift 5.9+ / AppKit / Xcode Beta（macOS 26 SDK）/ FFGlassView / NSTableView / NSGridView / QLPreviewPanel

## Global Constraints

- 构建前必须设置 `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`
- 所有 UI 文案与代码注释使用简体中文
- 项目根目录：`/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native`
- 构建命令（每任务使用）：
  ```bash
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
  xcodebuild -project FlowFinderNative/FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Debug build 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
  ```
- 每个任务末尾 commit（`git add <改动文件> && git commit -m "<信息>"`）；不 `git add` 构建产物（`FlowFinderNative/FlowFinderNative/Libraries/*.a/.dylib` 保持现状不动）
- 删除设置项时**不删除** UserDefaults 底层键（保留已存配置）
- FFGlassView `.panel` 实例预算 `FFDesign.Glass.maxGlassInstances = 8`，新增 panel 前先确认不会超预算（当前 2×2 工具面板 + 设备面板替换后数量不变）
- 部署目标 macOS 12.0，新 API 加 `#available` 守卫；`NSGlassEffectView` 需 macOS 26.0+（FFGlassView 内部已处理）

---

### Task 1: 侧边栏收藏夹修复（#1）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/SidebarView.swift:287`（标题→列表间距）
- Modify: `FlowFinderNative/FlowFinderNative/UI/SidebarView.swift:375`（intercellSpacing 行距）
- Modify: `FlowFinderNative/FlowFinderNative/UI/SidebarView.swift:566-571`（updateFavoritesHeight 高度计算）

**Interfaces:**
- Consumes: `favoritesDataSource.favoriteCount: Int`（已存在）
- Produces: `updateFavoritesHeight()` 内部修正，无签名变化

- [ ] **Step 1: 修正高度计算（含行距）**

将 `SidebarView.swift:566-571` 的 `updateFavoritesHeight()` 替换为：

```swift
private func updateFavoritesHeight() {
    // 收藏夹行高 28pt + 垂直行距 2pt（intercellSpacing.height），末行无行距
    let rowHeight: CGFloat = 28
    let interSpacing: CGFloat = 2
    let count = favoritesDataSource.favoriteCount
    let height = CGFloat(count) * rowHeight + CGFloat(max(count - 1, 0)) * interSpacing
    favoritesHeightConstraint.constant = max(height, 28)
}
```

- [ ] **Step 2: 收紧标题→列表间距**

将 `SidebarView.swift:287` 的约束 `favoritesOutlineView.topAnchor.constraint(equalTo: favoritesTitleLabel.bottomAnchor, constant: 12)` 中的 `constant: 12` 改为 `constant: 4`（与标签区标题间距一致）。

- [ ] **Step 3: 收紧行距**

将 `SidebarView.swift:375` 的 `ov.intercellSpacing = NSSize(width: 0, height: 4)` 改为：

```swift
// 行间距：水平无间距，垂直 2pt，贴近访达侧边栏紧凑节奏
ov.intercellSpacing = NSSize(width: 0, height: 2)
```

- [ ] **Step 4: Debug 构建**

运行 Global Constraints 中的构建命令。Expected: `BUILD SUCCEEDED`（或至少无 error:）。

- [ ] **Step 5: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/SidebarView.swift
git commit -m "fix: 侧边栏收藏夹高亮裁剪+标题间距+行距修复"
```

**人工验证点：** 收藏夹 ≥5 项时末行选中高亮完整显示不被裁剪；标题与列表间距 4pt；行距明显收紧。

---

### Task 2: 搜索栏自适应 + 显示设置图标修复（#2 #3）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/PaneToolbar.swift:173-174`（搜索框弹性）
- Modify: `FlowFinderNative/FlowFinderNative/UI/PaneToolbar.swift:199-201`（显示设置按钮图标）
- Modify: `FlowFinderNative/FlowFinderNative/UI/PaneToolbar.swift:261-287`（删除 makeDisplaySettingsIcon）

**Interfaces:**
- Consumes: `createNavButton(systemSymbol:action:) -> NSButton`（已存在，PaneToolbar.swift:230）
- Produces: `toolsButton` 使用系统图标 `slider.horizontal.3`；`makeDisplaySettingsIcon()` 被删除

- [ ] **Step 1: 让搜索框弹性吸收剩余宽度**

将 `PaneToolbar.swift:173-174` 替换为：

```swift
searchContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
// 弹性：搜索框 hugging 设为最低（1），row2 中任何剩余宽度都分配给搜索框，
// 右侧图标簇（排序/分组/视图切换/显示设置）因默认 hugging 更高而保持固有宽度并贴最右。
searchContainer.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
```

同时在 `PaneToolbar.swift:180-186`（sortPopup/groupPopup 创建处）追加：

```swift
// 防止下拉菜单被横向拉伸：保持固有宽度，剩余宽度全部给搜索框
sortPopup.setContentHuggingPriority(.defaultHigh, for: .horizontal)
groupPopup.setContentHuggingPriority(.defaultHigh, for: .horizontal)
```

- [ ] **Step 2: 显示设置按钮改用系统图标**

将 `PaneToolbar.swift:199-201` 替换为：

```swift
// v0.6.9+: 文件夹显示配置按钮，使用系统 SF Symbol「slider.horizontal.3」
// 模板色自动适配浅/深色，与其他导航按钮视觉统一
toolsButton = createNavButton(systemSymbol: "slider.horizontal.3", action: #selector(showFolderOptionsMenu))
```

- [ ] **Step 3: 删除自绘图标方法**

删除 `PaneToolbar.swift:259-287` 的 `makeDisplaySettingsIcon()` 整个方法（含上方注释行）。

- [ ] **Step 4: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/PaneToolbar.swift
git commit -m "fix: 搜索栏宽度自适应+显示设置图标改系统符号"
```

**人工验证点：** 窗口拉宽时搜索框变宽、右侧图标贴操作区最右；窗口缩窄时搜索框优先收缩（不小于 120pt）；显示设置图标为三横滑杆样式，深浅色模式自动变色。

---

### Task 3: 操作区四列平铺无横向滚动条（#4）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileListView.swift:626`（hasHorizontalScroller）
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileListView.swift:649-651`（过期注释）
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileListView.swift:672`（columnAutoresizingStyle）

**Interfaces:**
- Consumes: 现有四列 `NSTableColumn`（名称 240 / 修改日期 130 / 类型 100 / 大小 70，minWidth 合计 250）
- Produces: 无签名变化；列宽模式从 last-column-only 改为 sequential

- [ ] **Step 1: 改为四列按比例伸缩（无滚动条）**

将 `FileListView.swift:672` 的 `tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle` 改为：

```swift
// 四列按比例伸缩：任何窗口宽度下列宽总和 = 操作区可用宽，永不出现横向滚动条。
// 名称列初始占比最大（240/540 ≈ 44%），窗口变化时获得最多增量，视觉上名称列弹性最大（仿访达）。
tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
```

- [ ] **Step 2: 关闭横向滚动条**

将 `FileListView.swift:626` 的 `scrollView.hasHorizontalScroller = true` 改为 `false`。

- [ ] **Step 3: 修正过期注释**

将 `FileListView.swift:648-651` 的注释替换为：

```swift
// 列宽模式：sequentialColumnAutoresizingStyle（四列按比例伸缩，无横向滚动条）。
// 用户仍可手动拖拽列头分隔条调整各列宽度。
```

- [ ] **Step 4: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/FileListView.swift
git commit -m "fix: 操作区四列按比例平铺+移除横向滚动条"
```

**人工验证点：** 默认窗口宽度下四列铺满操作区；把窗口缩到最小（1000pt）四列仍完整显示无横向滚动条；名称列随窗口变化伸缩最明显。

---

### Task 4: 设备栏/工具面板液态玻璃（#5）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift:746-788`（createDevicePanel）
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift:456-460`（toolPanelView 实体背景）
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift:889-895`（refreshDevicePanelBackground）
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift`（devicePanel / toolPanelView 属性类型声明，搜索 `private var devicePanel` / `private var toolPanelView` 位置）

**Interfaces:**
- Consumes: `FFGlassView(level:cornerRadius:material:glassStyle:)`（FFGlassView.swift:75），`operationAreaBackgroundColor()`（已存在）
- Produces: `createDevicePanel() -> FFGlassView`；`devicePanel: FFGlassView?` / `toolPanelView: FFGlassView?`

- [ ] **Step 1: 查找属性声明并改类型**

搜索 `private var devicePanel` 与 `private var toolPanelView` 的声明行，把类型 `NSView?` 改为 `FFGlassView?`。

- [ ] **Step 2: createDevicePanel 改用 FFGlassView**

将 `MainWindowController.swift:746-753` 的 `createDevicePanel()` 开头改为：

```swift
private func createDevicePanel() -> FFGlassView {
    let panel = FFGlassView(level: .panel, cornerRadius: 8)
    panel.translatesAutoresizingMaskIntoConstraints = false
    // 液态玻璃：FFGlassView 自带主题刷新（内部监听外观变化），
    // 与侧边栏玻璃质感统一；子视图不被裁剪（不设置 masksToBounds）
```

删除原 `NSView()` / `panel.wantsLayer = true` / `panel.layer?.backgroundColor = operationAreaBackgroundColor().cgColor` / `panel.layer?.cornerRadius = 8` 四行（FFGlassView 内部已处理）。

- [ ] **Step 3: toolPanelView 改用 FFGlassView**

将 `MainWindowController.swift:456-459` 替换为：

```swift
toolPanelView = createToolPanel()
toolPanelView?.translatesAutoresizingMaskIntoConstraints = false
toolPanelView?.isHidden = true
```

（删除 `wantsLayer` / `layer?.backgroundColor = operationAreaBackgroundColor().cgColor` 两行；`ToolPanelView` 自身 `setupUI` 中 `wantsLayer = true` 与 `layer?.cornerRadius = 8` 保留，圆角由 FFGlassView 统一——注意：若 FFGlassView 已设圆角，`ToolPanelView.layer?.cornerRadius = 8` 重复设置无副作用，可保留。）

- [ ] **Step 4: 精简 refreshDevicePanelBackground**

将 `MainWindowController.swift:889-895` 的 `refreshDevicePanelBackground()` 替换为：

```swift
/// 任务 F11-1+: 设备/工具面板背景由 FFGlassView 自动响应主题，此方法保留为空
/// （调用点仍存在，避免改通知回调链；FFGlassView 内部已处理深浅色刷新）
private func refreshDevicePanelBackground() {}
```

- [ ] **Step 5: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift
git commit -m "fix: 设备栏与工具面板适配液态玻璃"
```

**人工验证点：** 设备卡片与侧边栏玻璃质感一致；切换深/浅色模式设备栏自动刷新；工具面板与设备栏互斥显示仍正常。

---

### Task 5: 工具面板 3×3 + 关闭图标 + 查重图标 + 入口修复（#6 #7）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/ToolOverlayView.swift:57`（ToolOverlayView 关闭按钮）
- Modify: `FlowFinderNative/FlowFinderNative/UI/ToolOverlayView.swift:80`（旧覆盖页每行 2→3）
- Modify: `FlowFinderNative/FlowFinderNative/UI/ToolOverlayView.swift:236-245, 247-291`（ToolPanelView 关闭按钮 + 网格）
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift:1046, 1059-1061`（查重图标 + 批量重命名入口）

**Interfaces:**
- Consumes: `ToolOverlayView.ToolItem`（已存在）、`DuplicateScanWindowController.shared.showWindow()`、`menuBatchRename(_:)`
- Produces: `ToolPanelView` 网格每行 3 列 + 占位方块；关闭按钮用 `xmark` 图标

- [ ] **Step 1: ToolOverlayView 关闭按钮改灰色 xmark 图标**

将 `ToolOverlayView.swift:54-59` 替换为：

```swift
let closeButton = NSButton()
closeButton.bezelStyle = .inline
closeButton.isBordered = false
closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
closeButton.imagePosition = .imageOnly
closeButton.contentTintColor = .secondaryLabelColor
closeButton.target = self
closeButton.action = #selector(closeClicked)
closeButton.translatesAutoresizingMaskIntoConstraints = false
backgroundView.addSubview(closeButton)
```

- [ ] **Step 2: ToolOverlayView（旧覆盖页）每行 3 列**

将 `ToolOverlayView.swift:80` 的 `if rowViews.count >= 2 {` 改为 `if rowViews.count >= 3 {`。并在 Step 3 同样处理。列宽循环（93-95）保持 `numberOfColumns` 动态（自动覆盖 3 列）。

- [ ] **Step 3: ToolPanelView 关闭按钮 + 3 列网格 + 占位 + 列宽**

将 `ToolOverlayView.swift:236-245`（ToolPanelView 的 closeButton 创建）替换为：

```swift
let closeButton = NSButton()
closeButton.bezelStyle = .inline
closeButton.isBordered = false
closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
closeButton.imagePosition = .imageOnly
closeButton.contentTintColor = .secondaryLabelColor
closeButton.target = self
closeButton.action = #selector(closeClicked)
closeButton.translatesAutoresizingMaskIntoConstraints = false
addSubview(closeButton)
```

将 `ToolOverlayView.swift:254-270`（构建工具卡片循环）替换为：

```swift
// 构建工具卡片，每行 3 列，不足 3 个补灰色占位方块
var rowViews: [NSView] = []
for (idx, tool) in tools.enumerated() {
    let card = ToolPanelCardView(tool: tool) { [weak self] in
        tool.action?()
        self?.onClose?()
    }
    rowViews.append(card)
    if rowViews.count >= 3 {
        gridContainer.addRow(with: rowViews)
        rowViews = []
    }
}
// 末行不足 3 个时补占位（灰色方块，无交互）
if !rowViews.isEmpty {
    while rowViews.count < 3 {
        rowViews.append(makePlaceholderCard())
    }
    gridContainer.addRow(with: rowViews)
}
```

在 `ToolPanelView` 类内新增占位卡片工厂方法：

```swift
/// 灰色占位方块（3×3 网格末行补齐，无交互）
private func makePlaceholderCard() -> NSView {
    let placeholder = NSView()
    placeholder.wantsLayer = true
    placeholder.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
    placeholder.layer?.cornerRadius = 8
    placeholder.translatesAutoresizingMaskIntoConstraints = false
    return placeholder
}
```

在 `ToolPanelView` 类内新增列宽布局（3 列等分可用宽度，修复卡片可点区域塌缩——#6 根因之一）：

```swift
/// 3 列等分网格宽度：NSGridView 默认列宽由内容自适应，卡片无 intrinsic size 会塌缩到 0，
/// 导致点击区域不可命中（问题 6/7 根因）。每次布局时显式设置列宽。
public override func layout() {
    super.layout()
    let availableWidth = bounds.width - 24  // 左右内边距各 12
    let colWidth = max((availableWidth - 2 * 12) / 3, 40)  // 列间距 12
    for i in 0..<gridContainer.numberOfColumns {
        gridContainer.column(at: i).width = colWidth
    }
}
```

注意：`gridContainer` 目前是 `setupUI()` 局部变量，需提升为 `ToolPanelView` 的存储属性 `private var gridContainer: NSGridView!`，并在 setupUI 中赋值。

- [ ] **Step 4: 查重图标更换 + 批量重命名入口加提示**

在 `MainWindowController.swift:1046` 将 `icon: "rectangle.dashed"` 改为 `icon: "doc.on.doc"`（重叠文档，表意"找重复"）。

将 `MainWindowController.swift:1059-1061` 的批量重命名 action 替换为：

```swift
action: { [weak self] in
    guard let self = self else { return }
    let selected = self.activePaneViewModel.selectedFiles
    guard selected.count >= 2 else {
        // 与侧边栏/工具栏入口一致：选中不足 2 个时明确提示，不再静默无反应
        let alert = NSAlert()
        alert.messageText = "批量重命名"
        alert.informativeText = "请至少选中 2 个文件后再使用批量重命名。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        if let window = self.window { alert.beginSheetModal(for: window) { _ in } }
        return
    }
    self.menuBatchRename(nil)
}
```

- [ ] **Step 5: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。若报 `gridContainer` 未初始化（Step 3 提升属性后），确认 setupUI 中先 `gridContainer = NSGridView()` 再使用。

- [ ] **Step 6: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/ToolOverlayView.swift FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift
git commit -m "fix: 工具面板3列网格+灰色关闭图标+查重图标+入口修复"
```

**人工验证点：** 工具面板一排 3 个（2 行：4 工具 + 2 占位）；关闭按钮为灰色 × 图标；查重图标为重叠文档；点击"查重扫描"能打开扫描窗口；"批量重命名"在选中 <2 个文件时弹提示、选中 ≥2 个时正常打开。

---

### Task 6: QuickLook 预览修复（#8）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/QuickLookPreviewView.swift:48-70`（togglePreview 移除 responder 临时插入）
- Modify: `FlowFinderNative/FlowFinderNative/UI/QuickLookPreviewView.swift:92-126`（responder chain 方法不再被调用，可删除或保留注释说明）
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift`（新增 QLPreviewPanelController informal protocol 实现）

**Interfaces:**
- Consumes: `QuickLookPreviewPanel.shared`（单例，已存在）、`MainWindowController`（NSWindowController 子类，天然位于 window 的 responder chain：window → windowController）
- Produces: `MainWindowController.acceptsPreviewPanelControl/beginPreviewPanelControl/endPreviewPanelControl`；`QuickLookPreviewPanel.togglePreview(files:currentIndex:targetWindow:)` 签名不变

- [ ] **Step 1: togglePreview 不再临时插入 responder chain**

将 `QuickLookPreviewView.swift:48-70` 的 `togglePreview` 替换为：

```swift
public func togglePreview(files: [String], currentIndex: Int, targetWindow: NSWindow? = nil) {
    self.previewFiles = files
    self.currentIndex = max(0, min(currentIndex, max(0, files.count - 1)))

    guard let panel = previewPanel else { return }

    if panel.isVisible {
        panel.currentPreviewItemIndex = self.currentIndex
        panel.reloadData()
    } else {
        // 控制器由 MainWindowController 常驻实现（beginPreviewPanelControl 中设置 dataSource/delegate），
        // 不再临时插入 responder chain（旧方案在 firstResponder 变化时静默失败，问题 8 根因）。
        // 此处提前设置 dataSource/delegate，与 begin 中的设置幂等。
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 2: close() 移除 responder chain 操作**

将 `QuickLookPreviewView.swift:73-80` 的 `close()` 替换为：

```swift
public func close() {
    if let panel = previewPanel {
        panel.orderOut(nil)
        panel.dataSource = nil
        panel.delegate = nil
    }
}
```

`insertIntoResponderChain` / `removeFromResponderChain`（92-126）与 `targetWindow` / `savedNextResponder` 属性不再使用——删除或保留均可（建议删除方法体引用以免编译警告；若删除，一并删除 `targetWindow`、`savedNextResponder` 两个属性和 `updateFiles` 中无关引用。最小改动：保留方法但不再调用，Swift 对未调用 private 方法仅发警告不报错，可保留）。

- [ ] **Step 3: MainWindowController 常驻实现 QLPreviewPanelController**

在 `MainWindowController.swift` 中新增（放在 Quick Look 相关方法附近，如 `handleQuickLook()` 之后）：

```swift
// MARK: - QLPreviewPanelController（常驻 responder，问题 8 修复）

/// 常驻实现 QLPreviewPanelController informal protocol：
/// MainWindowController 位于 window 的 responder chain（window → windowController），
/// QLPreviewPanel 显示时沿链自动找到本控制器，无需临时插入/移除 responder。
extension MainWindowController {
    public override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return true
    }

    public override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = QuickLookPreviewPanel.shared
        panel.delegate = QuickLookPreviewPanel.shared
        panel.currentPreviewItemIndex = QuickLookPreviewPanel.shared.currentIndex
    }

    public override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
```

**注意：** 若 MainWindowController 已有同名 override 或该类不直接继承 NSResponder（NSWindowController 继承链：NSWindowController → NSResponder），此 extension 中的 `override` 关键字需保持。若编译报 "method does not override"，改用不带 `override` 的实现并确认类继承 NSResponder。

- [ ] **Step 4: 暴露 currentIndex 访问**

`QuickLookPreviewPanel.currentIndex` 目前是 `private var`。改为 `public private(set) var currentIndex: Int = 0`，供 MainWindowController 的 beginPreviewPanelControl 读取。

- [ ] **Step 5: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/QuickLookPreviewView.swift FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift
git commit -m "fix: QuickLook 改用常驻 responder 挂接"
```

**人工验证点：** 选中文件按空格稳定弹出 QuickLook；Esc 关闭；方向键切换前后文件；关闭后再按空格重新打开正常；窗口切换焦点后再按空格仍可用。

---

### Task 7: 拖拽区分按键与磁盘（#9）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileListView.swift:2101-2119`（isMoveOperation 重写）
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileListView.swift:1722-1744`（validateDrop 传目标路径）
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileListView.swift:1771`（acceptDrop 传 destPath）
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileGridView.swift:1648-1665`（isMoveOperation 同步重写）
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileGridView.swift`（validate/accept 调用点，搜索 `isMoveOperation(info)`）

**Interfaces:**
- Consumes: `isSameVolume(srcPath:destPath:)`（已存在，两文件各一份）
- Produces: `isMoveOperation(_:destPath:)` 新增可选参数；访达语义四分支

- [ ] **Step 1: 重写 FileListView.isMoveOperation**

将 `FileListView.swift:2101-2119` 替换为：

```swift
extension FileListView {
    /// 判断是否为移动操作（访达语义）：
    /// 同盘 + 无修饰键 = 移动；同盘 + ⌘ = 复制
    /// 跨盘 + 无修饰键 = 复制；跨盘 + ⌘ = 移动
    /// - Parameter destPath: 真实拖放目标路径（拖到文件夹行时为该文件夹路径，否则当前目录）
    private func isMoveOperation(_ sender: NSDraggingInfo, destPath: String? = nil) -> Bool {
        // 直接读取当前按键状态（比依赖 draggingSourceOperationMask 的间接过滤更可靠）
        // 注意：若 validateDrop 回调中 NSApp.currentEvent 为 nil，回退到 Cmd 未按下（默认行为）
        let commandPressed = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false

        // 源与目标卷判定
        let dest = destPath ?? viewModel?.currentPath
        guard let dest = dest, !dest.isEmpty else { return false }
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let srcPath = urls.first?.path else { return false }
        let sameVolume = isSameVolume(srcPath: srcPath, destPath: dest)

        // ⌘ 按下时反转默认行为（复制↔移动切换，访达语义）
        return commandPressed ? !sameVolume : sameVolume
    }
}
```

- [ ] **Step 2: validateDrop 传入真实目标路径**

将 `FileListView.swift:1722-1744` 中所有 `isMoveOperation(info)` 调用改为传入目标路径。目标路径计算：`.on` 且目标为文件夹行时用 `entry.path`，否则用 `viewModel?.currentPath ?? ""`。替换后的 validateDrop：

```swift
public func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
    // 检查拖拽内容是否包含文件 URL
    guard let items = info.draggingPasteboard.pasteboardItems, !items.isEmpty else { return [] }
    for item in items {
        guard item.types.contains(.fileURL) else { continue }
        // 计算本次判定使用的目标路径（拖到文件夹行上 → 该文件夹；否则 → 当前目录）
        var destPath = viewModel?.currentPath ?? ""
        if dropOperation == .on, row < displayRows.count {
            let displayRow = displayRows[row]
            if !displayRow.isHeader, displayRow.fileIndex < viewModel?.files.count ?? 0 {
                let entry = viewModel!.files[displayRow.fileIndex]
                if entry.isDirectory {
                    destPath = entry.path
                }
            }
        }
        // 判断目标位置：.on 拖到文件夹行上 → 移入文件夹；.above 拖到行间/空白 → 移到当前目录
        if dropOperation == .on, row < displayRows.count {
            let displayRow = displayRows[row]
            if !displayRow.isHeader, displayRow.fileIndex < viewModel?.files.count ?? 0 {
                let entry = viewModel!.files[displayRow.fileIndex]
                // 仅文件夹行允许 .on（移入文件夹）；文件行/标题行回退为 .above
                if entry.isDirectory {
                    return isMoveOperation(info, destPath: destPath) ? .move : .copy
                }
            }
            // 拖到文件行/标题行上 → 改为 .above，避免歧义
            tableView.setDropRow(row, dropOperation: .above)
            return isMoveOperation(info, destPath: destPath) ? .move : .copy
        }
        return isMoveOperation(info, destPath: destPath) ? .move : .copy
    }
    return []
}
```

- [ ] **Step 3: acceptDrop 传入 destPath**

将 `FileListView.swift:1771` 的 `let isMove = isMoveOperation(info)` 改为：

```swift
let isMove = isMoveOperation(info, destPath: destPath)
```

（`destPath` 已在 acceptDrop 中计算，见 1758-1768。）

- [ ] **Step 4: FileGridView 同步重写**

将 `FileGridView.swift:1648-1665` 的 `isMoveOperation` 替换为与 Step 1 完全相同的实现（含 `destPath` 参数）。然后搜索 FileGridView 中所有 `isMoveOperation(info)` 调用点（探查：1519-1548 的 validate/perform），按 Step 2/3 同样的规则传入真实目标路径（网格目标路径即 `viewModel?.currentPath`；若网格支持拖到文件夹缩略图上，取该文件夹路径，否则用当前目录）。

- [ ] **Step 5: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/FileListView.swift FlowFinderNative/FlowFinderNative/UI/FileGridView.swift
git commit -m "fix: 拖拽区分按键与磁盘（访达语义）"
```

**人工验证点（用户需配合实测）：**
- 同盘拖拽无按键 = 移动；同盘按住 ⌘ = 复制
- 跨盘（如拖到外接硬盘/U盘）拖拽无按键 = 复制；按住 ⌘ = 移动
- 列表视图与网格视图行为一致

**风险说明：** 若实测发现 `NSApp.currentEvent?.modifierFlags` 在 validateDrop 中读不到 Command 键（返回 nil），实施者需改方案：在 FileListView/FileGridView 中 override `draggingUpdated(_:)` 捕获 `NSApp.currentEvent?.modifierFlags` 存为实例属性 `lastDragModifierFlags`，`isMoveOperation` 改读该属性（默认空）。此方案已预留接口（`commandPressed` 单点计算）。

---

### Task 8: 设置页精简与布局理顺（#10）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/SettingsWindowController.swift:441-464`（外观-显示 section 删除）
- Modify: `FlowFinderNative/FlowFinderNative/UI/SettingsWindowController.swift:494-537`（文件管理-与工具栏重复三项删除）
- Modify: `FlowFinderNative/FlowFinderNative/UI/SettingsWindowController.swift:539-550`（缓存 section 删除）
- Modify: `FlowFinderNative/FlowFinderNative/UI/SettingsWindowController.swift:611-620`（SMB 连接超时删除）
- Modify: `FlowFinderNative/FlowFinderNative/UI/SettingsWindowController.swift`（各处 stack spacing 20→12）

**Interfaces:**
- Consumes: `SettingsSectionView` / `SettingsRowView` 工厂方法（已存在）
- Produces: 无签名变化；分栏式结构保持不变（`selectSection` 已实现"每屏一个分类"）

- [ ] **Step 1: 外观区删除"显示"section**

将 `SettingsWindowController.swift:441-464`（buildAppearanceSection 中的 `displaySection` 定义到 `registerForSearch` 一行）整体删除。`buildAppearanceSection` 的 stack 改为：

```swift
let stack = NSStackView(views: [themeSection, accentSection])
```

- [ ] **Step 2: 文件管理区删除与工具栏重复的三项 + 缓存 section**

将 `SettingsWindowController.swift:494-537` 中 `showExtRow`、`showTagsRow`、`hideSystemRow` 三块定义与 `registerForSearch` 中的对应行删除（保留 `folderFirstRow`、`keepSelectionRow`），`registerForSearch` 改为：

```swift
registerForSearch(sortSection, rows: [folderFirstRow, keepSelectionRow])
```

将 `SettingsWindowController.swift:539-550`（`cacheSection` 定义 + `registerForSearch`）整体删除。`buildFileManageSection` 的 stack 改为：

```swift
let stack = NSStackView(views: [sortSection])
```

- [ ] **Step 3: SMB 区删除连接超时**

将 `SettingsWindowController.swift:611-619`（`timeoutRow` 定义）删除，`registerForSearch` 改为：

```swift
registerForSearch(configSection, rows: [domainRow, autoReconnectRow])
```

- [ ] **Step 4: 统一 stack 间距为 12**

将所有 `buildXXXSection` 末尾的 `stack.spacing = 20` 改为 `stack.spacing = 12`（共 6 处：general/appearance/fileManage/tagManage/smb/shortcuts/about 的 stack 均存在该行）。SMB section 中 `stack = NSStackView(views: [configSection, smbPanel])` 同步改。

- [ ] **Step 5: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/SettingsWindowController.swift
git commit -m "refactor: 设置页精简低频项+统一卡片间距"
```

**人工验证点：** 设置窗口左侧 7 个分类导航正常切换；外观区只有"主题""强调色"；文件管理区只剩"智能排序""保留选择位置"；SMB 区无连接超时滑杆；卡片间距紧凑统一；搜索过滤仍生效。

---

### Task 9: 详情栏图片类型专属信息 + .app 版本号（#11）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/ExpandableDetailsBar.swift:873-921`（gatherImageInfo 增强）
- Modify: `FlowFinderNative/FlowFinderNative/UI/ExpandableDetailsBar.swift:862`（.app 判定兜底）

**Interfaces:**
- Consumes: `kCGImagePropertyPixelWidth/Height/DPIWidth/DPIHeight/TIFFDictionary/ExifDictionary`（ImageIO），`ByteCountFormatter`（Foundation）
- Produces: `gatherImageInfo` 返回行增加「尺寸」「文件大小」；`.app` 判定增加路径后缀兜底

- [ ] **Step 1: 增强 gatherImageInfo**

将 `ExpandableDetailsBar.swift:873-921` 的 `gatherImageInfo` 替换为：

```swift
private func gatherImageInfo(url: URL, path: String) -> [(String, String)] {
    var result: [(String, String)] = []

    // 使用 ImageIO 一次性读取所有图片属性（分辨率 / DPI / 色彩空间 / 色彩深度 / EXIF）
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
        return result
    }

    // 分辨率 + 打印/显示尺寸（按 DPI 换算厘米，访达同款）
    // 用 NSNumber 显式取值，兼容 HEIC/WebP 等属性结构（比 as? Int 桥接更稳）
    let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
    let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
    if let w = width, let h = height, w > 0, h > 0 {
        result.append(("分辨率", "\(w) × \(h) 像素"))
        // DPI 缺省按 72 计算（访达默认行为）；有元数据则用之
        let dpiW = (props[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let dpiH = (props[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 72
        let cmW = Double(w) / max(dpiW, 1) * 2.54
        let cmH = Double(h) / max(dpiH, 1) * 2.54
        result.append(("尺寸", String(format: "%.1f × %.1f 厘米", cmW, cmH)))
    }

    // 文件大小（访达图片详情必显示）
    if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
       let size = attrs[.size] as? NSNumber {
        result.append(("文件大小", ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)))
    }

    // 色彩空间（kCGImagePropertyColorSpace 在新版 SDK 中不可用，使用字符串字面量兜底）
    if let cs = props["ColorSpace" as CFString] as? String, !cs.isEmpty {
        result.append(("色彩空间", cs))
    }
    // 色彩深度（同上）
    if let bps = (props["BitsPerSample" as CFString] as? NSNumber)?.intValue, bps > 0 {
        result.append(("色彩深度", "\(bps) 位"))
    }

    // TIFF 字典：相机制造商与型号
    if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
        if let make = tiff[kCGImagePropertyTIFFMake] as? String {
            result.append(("相机制造商", make))
        }
        if let model = tiff[kCGImagePropertyTIFFModel] as? String {
            result.append(("相机型号", model))
        }
    }

    // EXIF 字典：焦距 / 光圈 / ISO
    if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
        if let focal = (exif[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue {
            result.append(("焦距", "\(Int(focal)) mm"))
        }
        if let aperture = (exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue {
            result.append(("光圈", "f/\(String(format: "%.1f", aperture))"))
        }
        if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let iso = isoArray.first {
            result.append(("ISO", "ISO \(iso.intValue)"))
        }
    }

    return result
}
```

- [ ] **Step 2: .app 判定加路径后缀兜底**

将 `ExpandableDetailsBar.swift:862-864` 替换为：

```swift
// .app 是 bundle，个别路径下 fileExtension 可能为空，追加路径后缀兜底
if ext == "app" || entry.path.hasSuffix(".app") {
    return gatherAppInfo(path: entry.path)
}
```

`gatherAppInfo`（986 行起）已读取 `CFBundleShortVersionString`（版本）与 `CFBundleVersion`（内部版本），无需改动。

- [ ] **Step 3: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/ExpandableDetailsBar.swift
git commit -m "feat: 详情栏图片尺寸/文件大小信息+.app版本号兜底"
```

**人工验证点：** 选中一张照片（含 EXIF）展开详情 → 显示分辨率、尺寸（厘米）、文件大小、色彩空间/深度、相机信息；选中 .app 应用文件 → 显示版本号与内部版本。

---

### Task 10: 全量构建验证 + 交接文档更新

**Files:**
- Verify: 全部 11 项改动文件
- Modify: `/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-handover/flowfinder-handover.html`（更新交接文档）
- Modify: `CHANGELOG.md`（追加未发版条目，可选）

**Interfaces:**
- Consumes: 前 9 个任务全部完成的代码

- [ ] **Step 1: Release 双构建**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
xcodebuild -project FlowFinderNative/FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release build 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
```

Expected: `BUILD SUCCEEDED`（Debug 已在各任务验证）。

- [ ] **Step 2: 更新交接文档**

编辑 `/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-handover/flowfinder-handover.html`：
- 在版本历史表追加一行：`v0.7.0（未发版）— 2026-08-02 — 11 项 UI 修复（收藏夹/搜索栏/列宽/玻璃/工具面板/QuickLook/拖拽/设置页/详情栏）`
- 在"待办事项"中移除已完成的 6 项 P1（若其中部分在本次完成：路径栏同级跳转未包含在本次 11 项中，保留；ProgressDialog 死代码保留；网格视图 appearance 同步未含，保留）——**仅标注本次 11 项对应内容的完成状态**，其余待办保留
- 在"已实现功能清单"补充本次改动（如 QuickLook 常驻挂接、拖拽访达语义）

- [ ] **Step 3: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add CHANGELOG.md  # 如修改
git commit -m "docs: 更新交接文档（11 项 UI 修复）" --allow-empty
```

交接文档位于仓库外（flowfinder-handover 目录），单独处理：编辑后无需 git 提交（该目录是否受版本控制由用户决定）。

- [ ] **Step 4: 汇总人工验证清单交付用户**

向用户列出全部 11 项的人工验证点（各任务中"人工验证点"汇总），运行应用逐项确认。

---

## Self-Review 记录

- **规格覆盖：** 11 项 → Task 1-9 一一对应（#1→T1，#2#3→T2，#4→T3，#5→T4，#6#7→T5，#8→T6，#9→T7，#10→T8，#11→T9），T10 为构建+文档收尾。✅
- **占位符扫描：** 无 TBD/TODO；每步含具体代码或精确修改点。唯一说明性风险项（Task 7 的 currentEvent fallback）已给出替代方案。✅
- **类型一致性：** `isMoveOperation(_:destPath:)` 在 T7 两文件统一签名；`FFGlassView(level:cornerRadius:)` 与 PaneToolbar 既有用法一致；`QuickLookPreviewPanel.shared.currentIndex` 由 private 改 public private(set)（T6 Step 4 已注明）。✅
