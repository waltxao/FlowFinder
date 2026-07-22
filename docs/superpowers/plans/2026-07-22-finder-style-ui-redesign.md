# FlowFinder UI 重设计 - 访达风格 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 FlowFinder 的 UI 全面对齐 macOS Finder 风格，包括玻璃透明度调整、原生图标、圆角遮罩、面包屑导航、可展开详情面板、药丸标签、设备进度条等 10 项改动。

**Architecture:** 保留现有 NSGlassEffectView 玻璃底层，新建 3 个可复用组件（GlassSectionMaskView、BreadcrumbBar、ExpandableDetailsBar），增量修改 SidebarView、PaneToolbar、FileListView、MainWindowController。

**Tech Stack:** Swift / AppKit / macOS 26+ (NSGlassEffectView) / Xcode Beta

## Global Constraints

- 部署目标: macOS 26.0
- 构建: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release -destination 'platform=macOS' build`
- 代码签名: `codesign --force --deep --sign -`
- 所有文件路径基于: `/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/`

---

### Task 1: 窗口间距调整

**Files:**
- Modify: `UI/MainWindowController.swift` (windowDidLoad 方法)

**Interfaces:**
- Consumes: 无
- Produces: 窗口距顶部 8-10pt 间距

- [ ] **Step 1: 在 windowDidLoad 中添加窗口位置调整**

在 `windowDidLoad()` 方法中，`setupUI()` 调用之后添加：

```swift
// 窗口距顶部保留 8pt 间距，避免贴菜单栏
if let window = window {
    var frame = window.frame
    let screenHeight = NSScreen.main?.frame.height ?? 900
    let topGap: CGFloat = 8
    frame.origin.y = screenHeight - frame.size.height - topGap
    window.setFrame(frame, display: true)
}
```

- [ ] **Step 2: 构建验证**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative" && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native" && git add -A && git commit -m "fix: 窗口距顶部8pt间距"
```

---

### Task 2: 双栏 99% 不透明遮罩

**Files:**
- Modify: `UI/MainWindowController.swift` (createPaneContainer 方法)

**Interfaces:**
- Consumes: 无
- Produces: paneSplitView 区域有 99% 不透明背景层

- [ ] **Step 1: 在 createPaneContainer 中添加不透明背景层**

在 `createPaneContainer(side:)` 方法中，找到 `container.layer?.backgroundColor = NSColor.clear.cgColor` 并替换为：

```swift
container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.99).cgColor
container.layer?.cornerRadius = 8
container.layer?.masksToBounds = true
```

- [ ] **Step 2: 构建验证**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative" && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native" && git add -A && git commit -m "feat: 双栏内容区99%不透明遮罩"
```

---

### Task 3: GlassSectionMaskView 新建

**Files:**
- Create: `UI/GlassSectionMaskView.swift`

**Interfaces:**
- Consumes: 无
- Produces: `GlassSectionMaskView` 类，属性: `cornerRadius: CGFloat`, `maskColor: NSColor`

- [ ] **Step 1: 创建 GlassSectionMaskView 类**

创建文件 `UI/GlassSectionMaskView.swift`：

```swift
import AppKit

/// 侧边栏区域圆角遮罩视图
/// 为每个 sidebar section（收藏夹、标签、存储设备）提供半透明圆角背景
class GlassSectionMaskView: NSView {

    /// 圆角半径（默认 8pt）
    var cornerRadius: CGFloat = 8 {
        didSet {
            layer?.cornerRadius = cornerRadius
        }
    }

    /// 遮罩颜色（默认半透明白色，根据明暗模式自适应）
    var maskColor: NSColor = NSColor.windowBackgroundColor.withAlphaComponent(0.5) {
        didSet {
            layer?.backgroundColor = maskColor.cgColor
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = maskColor.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
    }
}
```

- [ ] **Step 2: 将文件添加到 Xcode 项目**

在 `project.pbxproj` 中添加文件引用（或通过 Xcode 自动检测）。

- [ ] **Step 3: 构建验证**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative" && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native" && git add -A && git commit -m "feat: 新建 GlassSectionMaskView 圆角遮罩组件"
```

---

### Task 4: 侧边栏三个区域包裹 GlassSectionMaskView

**Files:**
- Modify: `UI/SidebarView.swift`

**Interfaces:**
- Consumes: `GlassSectionMaskView` (from Task 3)
- Produces: 侧边栏三个区域各自有独立圆角遮罩

- [ ] **Step 1: 在 SidebarView 中用 GlassSectionMaskView 包裹三个区域的 scrollView**

找到 `mainScrollView` 和 `deviceScrollView` 的创建位置。为每个 scrollView 添加 GlassSectionMaskView 作为容器：

在 `setupViews()` 方法中，将 `mainScrollView` 和 `deviceScrollView` 各自放入一个 `GlassSectionMaskView` 中，然后将 maskView 添加到主视图。

```swift
// 为收藏夹+标签区域创建圆角遮罩容器
let mainMaskView = GlassSectionMaskView()
mainMaskView.translatesAutoresizingMaskIntoConstraints = false
mainMaskView.addSubview(mainScrollView)

// 为设备区域创建圆角遮罩容器
let deviceMaskView = GlassSectionMaskView()
deviceMaskView.translatesAutoresizingMaskIntoConstraints = false
deviceMaskView.addSubview(deviceScrollView)
```

更新 AutoLayout 约束，使 maskView 填充各自的区域，scrollView 填充 maskView。

- [ ] **Step 2: 构建验证**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative" && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native" && git add -A && git commit -m "feat: 侧边栏三个区域独立圆角遮罩"
```

---

### Task 5: BreadcrumbBar 新建 + 从 PaneToolbar 拆分

**Files:**
- Create: `UI/BreadcrumbBar.swift`
- Modify: `UI/PaneToolbar.swift` (移除面包屑相关代码)
- Modify: `UI/MainWindowController.swift` (createPaneContainer 中添加 BreadcrumbBar)

**Interfaces:**
- Consumes: 当前路径 (通过 delegate 或 notification)
- Produces: `BreadcrumbBar` 类，属性: `path: String`, delegate: `BreadcrumbBarDelegate`

- [ ] **Step 1: 创建 BreadcrumbBar 类**

创建文件 `UI/BreadcrumbBar.swift`：

```swift
import AppKit

protocol BreadcrumbBarDelegate: AnyObject {
    func breadcrumbBar(_ bar: BreadcrumbBar, didSelectPath path: String)
}

/// 路径面包屑导航栏
/// 显示当前路径，每段可点击跳转
class BreadcrumbBar: NSView {

    weak var delegate: BreadcrumbBarDelegate?

    /// 当前路径
    private(set) var path: String = "" {
        didSet {
            updateBreadcrumbs()
        }
    }

    private let scrollView = NSScrollView()
    private let containerStackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        containerStackView.orientation = .horizontal
        containerStackView.spacing = 4
        containerStackView.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        containerStackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = containerStackView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerStackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
        ])
    }

    func setPath(_ path: String) {
        self.path = path
    }

    private func updateBreadcrumbs() {
        // 清除旧视图
        containerStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let components = path.split(separator: "/").map(String.init)
        var currentPath = ""

        for (index, component) in components.enumerated() {
            if index > 0 {
                currentPath += "/"
            }
            currentPath += component

            // 添加分隔符
            if index > 0 {
                let chevron = NSTextField(labelWithString: "")
                chevron.font = NSFont.systemFont(ofSize: 11, weight: .regular)
                let chevronImage = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
                let chevronImageView = NSImageView(image: chevronImage ?? NSImage())
                chevronImageView.contentTintColor = .secondaryLabelColor
                chevronImageView.translatesAutoresizingMaskIntoConstraints = false
                chevronImageView.widthAnchor.constraint(equalToConstant: 8).isActive = true
                chevronImageView.heightAnchor.constraint(equalToConstant: 8).isActive = true
                containerStackView.addArrangedSubview(chevronImageView)
            }

            // 添加路径段按钮
            let button = NSButton(title: component, target: self, action: #selector(pathClicked(_:)))
            button.bezelStyle = .inline
            button.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 20).isActive = true
            button.identifier = NSUserInterfaceItemIdentifier(currentPath)
            containerStackView.addArrangedSubview(button)
        }
    }

    @objc private func pathClicked(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        delegate?.breadcrumbBar(self, didSelectPath: path)
    }
}
```

- [ ] **Step 2: 在 createPaneContainer 中添加 BreadcrumbBar**

在 `MainWindowController.swift` 的 `createPaneContainer(side:)` 方法中，在 toolbar 之前添加：

```swift
let breadcrumbBar = BreadcrumbBar()
breadcrumbBar.translatesAutoresizingMaskIntoConstraints = false
breadcrumbBar.delegate = self
```

在 AutoLayout 中：breadcrumbBar 在顶部，toolbar 在 breadcrumbBar 下方。

- [ ] **Step 3: 从 PaneToolbar 中移除面包屑相关代码**

移除 PaneToolbar 中的 `breadcrumbScrollView`、`breadcrumbContainerStackView` 及相关方法。将路径更新逻辑转移到 BreadcrumbBar 的 `setPath()` 调用。

- [ ] **Step 4: 在 MainWindowController 中实现 BreadcrumbBarDelegate**

```swift
extension MainWindowController: BreadcrumbBarDelegate {
    func breadcrumbBar(_ bar: BreadcrumbBar, didSelectPath path: String) {
        // 找到对应的 pane 并导航到该路径
        // 根据 bar 所属的 pane 执行导航
    }
}
```

- [ ] **Step 5: 构建验证**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative" && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native" && git add -A && git commit -m "feat: BreadcrumbBar 面包屑导航 + 从 PaneToolbar 拆分"
```

---

### Task 6: 侧边栏标签药丸样式

**Files:**
- Modify: `UI/SidebarView.swift` (标签 cell 渲染)

**Interfaces:**
- Consumes: 无
- Produces: 标签显示为药丸圆角 + 彩色小圆点

- [ ] **Step 1: 修改标签 cell 的 viewFor 渲染**

在 `SidebarDataSourceBase` 的 `outlineView(_:viewFor:item:)` 方法中，找到 `.tag(let tag)` case，替换为药丸样式：

```swift
case .tag(let tag):
    // 药丸背景视图
    let pillBg = NSView()
    pillBg.wantsLayer = true
    pillBg.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
    pillBg.layer?.cornerRadius = 10

    let pillStack = NSStackView()
    pillStack.orientation = .horizontal
    pillStack.spacing = 4
    pillStack.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)

    // 彩色小圆点
    let dot = NSView()
    dot.wantsLayer = true
    dot.layer?.backgroundColor = tag.color.cgColor
    dot.layer?.cornerRadius = 4
    dot.translatesAutoresizingMaskIntoConstraints = false
    dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
    dot.heightAnchor.constraint(equalToConstant: 8).isActive = true

    // 标签文字
    let label = NSTextField(labelWithString: tag.name)
    label.font = NSFont.systemFont(ofSize: 11)
    label.textColor = .labelColor

    pillStack.addArrangedSubview(dot)
    pillStack.addArrangedSubview(label)
    pillBg.addSubview(pillStack)
    // ... 设置约束
```

- [ ] **Step 2: 构建验证**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative" && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native" && git add -A && git commit -m "feat: 标签药丸样式 + 彩色小圆点"
```

---

### Task 7: 存储设备栏进度条 + 动态高度

**Files:**
- Modify: `UI/SidebarView.swift` (设备 cell 渲染 + 高度计算)

**Interfaces:**
- Consumes: `DeviceItem` 的 `totalSize` 和 `freeSize`
- Produces: 每个设备显示水平进度条 + 可用空间文字，设备栏动态高度

- [ ] **Step 1: 修改设备 cell 渲染，添加进度条和文字**

在 `SidebarDataSourceBase` 的 `outlineView(_:viewFor:item:)` 方法中，找到 `.device(let dev)` case，添加进度条：

```swift
case .device(let dev):
    // 主行: 图标 + 名称
    // 副行: 进度条 + 可用空间文字
    let deviceStack = NSStackView()
    deviceStack.orientation = .vertical
    deviceStack.spacing = 2

    // 上行: 图标 + 名称
    let topRow = NSStackView()
    topRow.orientation = .horizontal
    topRow.spacing = 6
    let icon = NSImageView()
    icon.image = NSImage(systemSymbolName: deviceIconName(dev), accessibilityDescription: nil)
    icon.contentTintColor = .secondaryLabelColor
    icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 14).isActive = true
    let nameField = NSTextField(labelWithString: dev.name)
    nameField.font = NSFont.systemFont(ofSize: 11)
    topRow.addArrangedSubview(icon)
    topRow.addArrangedSubview(nameField)

    // 进度条
    let progress = NSProgressIndicator()
    progress.minValue = 0
    progress.maxValue = 1
    let usedRatio = dev.totalSize > 0 ? Double(dev.totalSize - dev.freeSize) / Double(dev.totalSize) : 0
    progress.doubleValue = usedRatio
    progress.style = .bar
    progress.controlSize = .small
    progress.translatesAutoresizingMaskIntoConstraints = false
    progress.heightAnchor.constraint(equalToConstant: 4).isActive = true

    // 可用空间文字
    let freeText = formatFreeSpace(dev.freeSize)
    let freeLabel = NSTextField(labelWithString: freeText)
    freeLabel.font = NSFont.systemFont(ofSize: 9)
    freeLabel.textColor = .tertiaryLabelColor

    deviceStack.addArrangedSubview(topRow)
    deviceStack.addArrangedSubview(progress)
    deviceStack.addArrangedSubview(freeLabel)
```

- [ ] **Step 2: 添加格式化辅助方法**

```swift
private func formatFreeSpace(_ bytes: UInt64) -> String {
    if bytes == 0 { return "" }
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useTB]
    formatter.countStyle = .file
    return "\(formatter.string(fromByteCount: Int64(bytes))) 可用"
}
```

- [ ] **Step 3: 更新动态高度计算**

在 `refreshDevices()` 方法中更新 `deviceHeightConstraint`，考虑每个设备现在需要 3 行高度（图标行 + 进度条行 + 文字行）：

```swift
let rowHeight: CGFloat = 52  // 图标行20 + 进度条行8 + 文字行12 + 间距8 + padding
let headerHeight: CGFloat = 24
deviceHeightConstraint.constant = headerHeight + CGFloat(deviceCount * Int(rowHeight))
```

- [ ] **Step 4: 构建验证**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative" && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native" && git add -A && git commit -m "feat: 设备栏进度条 + 可用空间文字 + 动态高度"
```

---

### Task 8: 原生图标全面替换

**Files:**
- Modify: `UI/SidebarView.swift` (收藏夹位置图标)

**Interfaces:**
- Consumes: 无
- Produces: 侧边栏收藏夹使用真实位置图标

- [ ] **Step 1: 修改收藏夹图标为 NSWorkspace 真实图标**

在 `SidebarDataSourceBase` 的 `outlineView(_:viewFor:item:)` 方法中，找到 `.favorite(let fav)` case，替换图标获取方式：

```swift
case .favorite(let fav):
    textField.stringValue = fav.name
    // 使用 NSWorkspace 获取真实位置图标
    let workspaceIcon = NSWorkspace.shared.icon(forFile: fav.path)
    workspaceIcon.size = NSSize(width: 16, height: 16)
    imageView.image = workspaceIcon
```

- [ ] **Step 2: 构建验证**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative" && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native" && git add -A && git commit -m "feat: 侧边栏收藏夹原生位置图标"
```

---

### Task 9: ExpandableDetailsBar 新建替换 DetailsBar

**Files:**
- Create: `UI/ExpandableDetailsBar.swift`
- Modify: `UI/MainWindowController.swift` (createPaneContainer 中替换 DetailsBar)
- Modify: `UI/MainWindowController.swift` (handleSelectionChanged 中更新详情)

**Interfaces:**
- Consumes: `FileEntry` (文件信息)
- Produces: `ExpandableDetailsBar` 类，属性: `isExpanded: Bool`, `entry: FileEntry?`

- [ ] **Step 1: 创建 ExpandableDetailsBar 类**

创建文件 `UI/ExpandableDetailsBar.swift`，实现：
- 收起状态：单行 (28pt) — 预览图标(24x24) + 文件名 + 大小
- 展开状态：面板 (120pt) — 大图标(48x48) + 文件名、类型、大小、创建日期、修改日期、权限、路径、标签
- 点击 chevron 按钮切换展开/收起，高度动画过渡

- [ ] **Step 2: 在 createPaneContainer 中替换 DetailsBar**

将 `DetailsBar()` 替换为 `ExpandableDetailsBar()`，更新 AutoLayout。

- [ ] **Step 3: 在 handleSelectionChanged 中更新 ExpandableDetailsBar**

```swift
func handleSelectionChanged(side: PaneSide, files: [FileEntry]) {
    // ... 现有逻辑
    let detailsBar = (side == .left ? leftPaneContainer : rightPaneContainer).subviews.first(where: { $0 is ExpandableDetailsBar }) as? ExpandableDetailsBar
    detailsBar?.update(with: files.first)
}
```

- [ ] **Step 4: 构建验证**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative" && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native" && git add -A && git commit -m "feat: ExpandableDetailsBar 可展开详情面板"
```

---

### Task 10: 单击选中修复

**Files:**
- Modify: `UI/FileListView.swift`

**Interfaces:**
- Consumes: 无
- Produces: 单击选中行（蓝色高亮），双击打开

- [ ] **Step 1: 确认 shouldSelectRow 返回 true**

在 `FileListView` 的 `NSTableViewDelegate` 实现中：

```swift
func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    return true
}
```

- [ ] **Step 2: 确认 tableViewSelectionDidChange 触发回调**

```swift
func tableViewSelectionDidChange(_ notification: Notification) {
    let selectedRow = tableView.selectedRow
    guard selectedRow >= 0, selectedRow < files.count else {
        onSelectionChanged?([])
        return
    }
    let selectedFile = files[selectedRow]
    onSelectionChanged?([selectedFile])
}
```

- [ ] **Step 3: 确认选中行高亮样式**

确保 tableView 使用系统默认选中高亮色：

```swift
tableView.selectionHighlightStyle = .regular
```

- [ ] **Step 4: 构建验证**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative" && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native" && git add -A && git commit -m "fix: 单击选中行+蓝色高亮"
```

---

### Task 11: 最终构建 + 截图验证 + 推送

**Files:**
- 无新文件修改

- [ ] **Step 1: Clean build**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative" && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release -destination 'platform=macOS' clean build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: 部署并截图**

```bash
pkill -f "FlowFinderNative" 2>/dev/null; sleep 2
APP_SRC="/Users/waltxao/Library/Developer/Xcode/DerivedData/FlowFinderNative-gfgoldtwzdwmclasnsgrovzztnzq/Build/Products/Release/FlowFinderNative.app"
APP_DST="/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/build/FlowFinderNative.app"
rsync -a --delete "$APP_SRC/" "$APP_DST/"
codesign --force --deep --sign - "$APP_DST"
xattr -cr "$APP_DST"
open "$APP_DST"
sleep 6
screencapture -x /tmp/ff_final_redesign.png
```

- [ ] **Step 3: Push to GitHub**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native" && git push origin main
```

- [ ] **Step 4: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native" && git add -A && git commit -m "feat: UI重设计完成 - 访达风格"
```
