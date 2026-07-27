# UI 差异修复实施计划（0.6.4 → 0.6.5）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复用户截图反馈的 9 项 UI 差异，使界面与设计稿一致。

**Architecture:** 基于现有 FlowFinderNative Swift/AppKit 代码，调整侧边栏、路径栏、滚动条、选中视觉、三栏布局、应用图标位置、夜间模式切换等 9 处。不引入新依赖，仅修改现有 Swift 文件 + 新建 2 个小文件（FFScroller.swift、AboutWindowController.swift）。

**Tech Stack:** Swift 5 / AppKit / NSVisualEffectView / NSSplitView / NSTableView / NSOutlineView / NSScroller / SF Symbols

## Global Constraints

- 平台：macOS 14+（仅 macOS，放弃 Windows）
- 语言：所有 UI 文案与代码注释使用简体中文
- 设计令牌：圆角 12pt、卡片间距 8pt、应用图标 32pt
- 玻璃材质：NSVisualEffectView(.underWindowBackground) 一体化
- 选中视觉：NSTableView 标准选中（蓝底白字），不使用自定义文字色
- 主题：light/dark 二态（移除 system 自动跟随）

---

## 任务清单

### Task 1: S1 — 自定义 NSScroller 子类（全局细滚动条）

**Files:**
- Create: `FlowFinderNative/FlowFinderNative/UI/FFScroller.swift`
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileListView.swift`（scrollView.verticalScroller 替换）
- Modify: `FlowFinderNative/FlowFinderNative/UI/SidebarView.swift`（makeScrollView 替换）
- Modify: `FlowFinderNative/FlowFinderNative/App/AppDelegate.swift`（移除 UserDefaults overlay 设置）

**Interfaces:**
- Produces: `FFScroller` 类（继承 NSScroller），通过 `scrollerStyle = .overlay` + 自定义绘制实现细滚动条

- [ ] **Step 1: 创建 FFScroller.swift**

```swift
import AppKit

/// 自定义细滚动条：透明轨道 + 半透明圆角 thumb（macOS overlay 风格）
/// 不依赖 NSUserDefaults AppleShowScrollBars，显式控制样式
class FFScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollerStyle = .overlay
        controlSize = .mini
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        scrollerStyle = .overlay
        controlSize = .mini
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    override func draw(_ dirtyRect: NSRect) {
        // 透明轨道，不绘制背景
        NSColor.clear.setFill()
        dirtyRect.fill()

        // 绘制 thumb：半透明圆角矩形
        let thumbRect = rect(forPart: .thumb)
        guard !thumbRect.isEmpty else { return }

        let path = NSBezierPath(roundedRect: thumbRect.insetBy(dx: 2, dy: 2),
                                xRadius: 3, yRadius: 3)
        NSColor.labelColor.withAlphaComponent(0.3).setFill()
        path.fill()
    }

    override func setFloatValue(_ aFloat: Float, knobProportion: CGFloat) {
        super.setFloatValue(aFloat, knobProportion: knobProportion)
        needsDisplay = true
    }
}
```

- [ ] **Step 2: AppDelegate 移除 UserDefaults overlay 设置**

在 `applicationDidFinishLaunching` 中删除：
```swift
UserDefaults.standard.set("overlay", forKey: "AppleShowScrollBars")
```

- [ ] **Step 3: FileListView.swift 强制使用 FFScroller**

在 `setupUI()` 中 `scrollView = NSScrollView()` 之后添加：
```swift
scrollView.verticalScroller = FFScroller()
scrollView.horizontalScroller = FFScroller()
scrollView.scrollerStyle = .overlay
```

- [ ] **Step 4: SidebarView.swift makeScrollView 强制使用 FFScroller**

在 `makeScrollView()` 中 `sv.hasVerticalScroller = true` 之后添加：
```swift
sv.verticalScroller = FFScroller()
sv.scrollerStyle = .overlay
```

- [ ] **Step 5: 构建验证**

```bash
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native
xcodebuild -project FlowFinderNative/FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Debug build 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

---

### Task 2: F1 — 收藏夹贴左边缘（Finder 风格无缩进）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/SidebarView.swift:233-246`（makeOutlineView）

- [ ] **Step 1: 修改 makeOutlineView 缩进为 0**

将 `ov.indentationPerLevel = 12` 改为：
```swift
ov.indentationPerLevel = 0
```

同时修改 cell 布局中的 leadingAnchor constant（第 544 行附近）：
```swift
imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6)
```
改为：
```swift
imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 0)
```

- [ ] **Step 2: 构建验证**（与 Task 1 Step 5 合并）

---

### Task 3: F2 — 排查收藏夹未显示根因

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/SidebarView.swift`（expandItem 调用）

**分析：**
当前代码第 208 行 `self.favoritesOutlineView.expandItem(SidebarSection.favorites)`，但 `FavoritesSidebarDataSource.outlineView(_:isItemExpandable:)` 在 `SidebarDataSourceBase` 中返回 `section != .favorites`（第 391 行），即收藏夹 section 不可展开。

**根因：** `isItemExpandable` 对 `.favorites` 返回 false，导致 `expandItem` 无效，子项不显示。

- [ ] **Step 1: 修改 isItemExpandable 让收藏夹可展开**

在 `SidebarDataSourceBase.outlineView(_:isItemExpandable:)` 中：
```swift
func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    if let section = item as? SidebarSection {
        return section == .favorites  // 收藏夹可展开
    }
    return false
}
```

- [ ] **Step 2: 构建验证**（合并）

---

### Task 4: L1 — 恢复 NSTableView 标准选中（蓝底白字）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileListView.swift`（移除 updateCellTextColor、tableViewSelectionDidChange 文字色切换）

- [ ] **Step 1: 移除 tableViewSelectionDidChange 中的文字色切换逻辑**

定位到 `tableViewSelectionDidChange` 方法，移除遍历可见行更新文字色的代码块，仅保留必要的状态更新：
```swift
func tableViewSelectionDidChange(_ notification: Notification) {
    let selected = tableView.selectedRowIndexes
    var files: [FileEntry] = []
    selected.enumerate { row, _ in
        if row < (viewModel?.state.files.count ?? 0),
           let file = viewModel?.state.files[row] {
            files.append(file)
        }
    }
    onSelectionChanged?(files)
    onActivatePane?()
}
```

- [ ] **Step 2: 移除 updateCellTextColor 私有方法**

删除整个 `private func updateCellTextColor(...)` 方法。

- [ ] **Step 3: 确保 selectionHighlightStyle 为默认 .regular**

在 `setupUI()` 中确认不设置 `selectionHighlightStyle = .none`（当前已是默认，仅需确认）。

- [ ] **Step 4: 构建验证**（合并）

---

### Task 5: B2 — 删除路径栏向下箭头（仅保留 chevron.right）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/BreadcrumbBar.swift`

**分析：** 当前代码已删除 BreadcrumbArrowButton，仅保留 BreadcrumbSeparatorButton（chevron.right）。需确认无残留向下箭头代码。

- [ ] **Step 1: 检查 BreadcrumbBar.swift 是否有 BreadcrumbArrowButton 残留**

搜索 `BreadcrumbArrowButton`，若存在则删除相关类定义与使用。

- [ ] **Step 2: 确认 chevron.right 分隔符点击弹出同级菜单**

确认 `siblingMenuClicked` 方法实现正确，点击分隔符弹出该层级同级目录下拉菜单。

- [ ] **Step 3: 构建验证**（合并）

---

### Task 6: B1 — 路径栏与 PaneToolbar 同行分区

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift:319-438`（createPaneContainer）

- [ ] **Step 1: 修改 createPaneContainer 布局为同行分区**

将 breadcrumbBar 和 toolbar 放入同一行的 NSStackView，PaneToolbar 占左侧 1/3，路径栏占右侧 2/3：

```swift
// 同行容器：PaneToolbar（左 1/3） | 分隔线 | BreadcrumbBar（右 2/3）
let toolbarRow = NSStackView()
toolbarRow.orientation = .horizontal
toolbarRow.spacing = 0
toolbarRow.alignment = .centerY
toolbarRow.translatesAutoresizingMaskIntoConstraints = false
toolbarRow.distribution = .fill

toolbar.widthAnchor.constraint(equalTo: toolbarRow.widthAnchor, multiplier: 0.33).isActive = true
breadcrumbBar.widthAnchor.constraint(equalTo: toolbarRow.widthAnchor, multiplier: 0.67).isActive = true

toolbarRow.addArrangedSubview(toolbar)
let divider = NSBox()
divider.boxType = .separator
divider.translatesAutoresizingMaskIntoConstraints = false
toolbarRow.addArrangedSubview(divider)
toolbarRow.addArrangedSubview(breadcrumbBar)

container.addSubview(toolbarRow)

NSLayoutConstraint.activate([
    toolbarRow.topAnchor.constraint(equalTo: container.topAnchor),
    toolbarRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
    toolbarRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    toolbarRow.heightAnchor.constraint(equalToConstant: 36),

    listView.topAnchor.constraint(equalTo: toolbarRow.bottomAnchor),
    // ... 其余不变
])
```

- [ ] **Step 2: 构建验证**（合并）

---

### Task 7: R1+R5 — 三栏布局调整 + divider 悬停高亮

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift:150-314`（setupUI）

- [ ] **Step 1: 修改操作区圆角为 12pt**

在 `createPaneContainer` 中：
```swift
container.layer?.cornerRadius = 12  // 原 8
```

- [ ] **Step 2: 修改 mainSplitView 和 paneSplitView divider 间距为 8pt**

通过 dividerStyle = .thin（1pt）+ sidebarView/paneContainer 的 leading/trailing padding 8pt 实现视觉间距。

- [ ] **Step 3: 添加 divider 悬停高亮（R5）**

为 paneSplitView 添加 NSTrackingArea，悬停时：
- divider 变 accent 色 3pt
- 左右卡片边缘 1pt accent 色边框

```swift
// 在 setupUI 中添加 divider 悬停检测
let dividerTrackingArea = NSTrackingArea(
    rect: paneSplitView.bounds,
    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
    owner: self,
    userInfo: nil
)
paneSplitView.addTrackingArea(dividerTrackingArea)

// 实现 mouseEntered/mouseExited
override func mouseEntered(with event: NSEvent) {
    // 高亮 divider + 卡片边缘
    paneSplitView.subviews.forEach { subview in
        if let container = subview as? NSView, container.layer != nil {
            container.layer?.borderWidth = 1
            container.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
    }
}

override func mouseExited(with event: NSEvent) {
    paneSplitView.subviews.forEach { subview in
        if let container = subview as? NSView, container.layer != nil {
            container.layer?.borderWidth = 0
        }
    }
}
```

注意：divider 本身的高亮通过 NSSplitViewDelegate 的 `splitView(_:additionalEffectiveRectOfDividerAt:)` 扩大热区。

- [ ] **Step 4: 构建验证**（合并）

---

### Task 8: R3 — 侧边栏顶部应用图标 + FlowFinder 文字

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/SidebarView.swift`（顶部添加 brandView）
- Create: `FlowFinderNative/FlowFinderNative/UI/AboutWindowController.swift`

- [ ] **Step 1: 创建 AboutWindowController.swift**

```swift
import AppKit

/// 关于 FlowFinder 独立窗口（仿 Finder 关于对话框）
class AboutWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "关于 FlowFinder"
        window.center()
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.image = NSImage(named: "AppIcon")
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: "FlowFinder")
        nameLabel.font = NSFont.boldSystemFont(ofSize: 17)
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let versionLabel = NSTextField(labelWithString: "版本 0.6.5 (650)")
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let copyrightLabel = NSTextField(labelWithString: "© 2026 FlowFinder")
        copyrightLabel.font = NSFont.systemFont(ofSize: 10)
        copyrightLabel.textColor = .tertiaryLabelColor
        copyrightLabel.alignment = .center
        copyrightLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(nameLabel)
        container.addSubview(versionLabel)
        container.addSubview(copyrightLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            nameLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            versionLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            copyrightLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 4),
            copyrightLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        ])

        window?.contentView = container
    }
}
```

- [ ] **Step 2: SidebarView 顶部添加 brandView**

在 `setupUI()` 开头（第 62 行之后）添加：

```swift
// R3: 侧边栏顶部应用图标 + FlowFinder 文字（红绿灯下方）
let brandView = NSView()
brandView.translatesAutoresizingMaskIntoConstraints = false
addSubview(brandView)

let appIconView = NSImageView()
appIconView.image = NSImage(named: "AppIcon") ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
appIconView.imageScaling = .scaleProportionallyUpOrDown
appIconView.translatesAutoresizingMaskIntoConstraints = false
brandView.addSubview(appIconView)

let appNameLabel = NSTextField(labelWithString: "FlowFinder")
appNameLabel.font = NSFont.boldSystemFont(ofSize: 15)
appNameLabel.textColor = .labelColor
appNameLabel.translatesAutoresizingMaskIntoConstraints = false
brandView.addSubview(appNameLabel)

// 点击 brandView 弹出关于对话框
let brandClick = NSClickGestureRecognizer(target: self, action: #selector(showAboutWindow))
brandView.addGestureRecognizer(brandClick)

NSLayoutConstraint.activate([
    brandView.topAnchor.constraint(equalTo: topAnchor, constant: 32),  // 红绿灯下方
    brandView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
    brandView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
    brandView.heightAnchor.constraint(equalToConstant: 56),

    appIconView.leadingAnchor.constraint(equalTo: brandView.leadingAnchor),
    appIconView.centerYAnchor.constraint(equalTo: brandView.centerYAnchor),
    appIconView.widthAnchor.constraint(equalToConstant: 32),
    appIconView.heightAnchor.constraint(equalToConstant: 32),

    appNameLabel.leadingAnchor.constraint(equalTo: appIconView.trailingAnchor, constant: 8),
    appNameLabel.centerYAnchor.constraint(equalTo: brandView.centerYAnchor),
])
```

- [ ] **Step 3: 调整 favoritesMaskView 顶部约束**

将 `favoritesMaskView.topAnchor.constraint(equalTo: topAnchor, constant: padding)` 改为：
```swift
favoritesMaskView.topAnchor.constraint(equalTo: brandView.bottomAnchor, constant: padding)
```

- [ ] **Step 4: 添加 showAboutWindow 方法**

```swift
@objc private func showAboutWindow() {
    let aboutWC = AboutWindowController()
    aboutWC.showWindow(nil)
    aboutWC.window?.makeKeyAndOrderFront(nil)
}
```

- [ ] **Step 5: 构建验证**（合并）

---

### Task 9: T1+T2 — 夜间模式切换 + 设置 + 工具按钮

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/Bridge/ThemeManager.swift`（移除 system 模式，仅 light/dark）
- Modify: `FlowFinderNative/FlowFinderNative/UI/SidebarView.swift`（设备上方添加工具栏）

- [ ] **Step 1: ThemeManager 修改为二态**

将 `AppearanceMode` 枚举改为：
```swift
public enum AppearanceMode: Int, CaseIterable {
    case light = 1
    case dark = 2

    public var title: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    public var iconName: String {
        switch self {
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// 切换到另一态
    public var toggled: AppearanceMode {
        return self == .light ? .dark : .light
    }
}
```

在 `loadSavedMode` 中，若读到 `.system` 则回退到 `.light`：
```swift
private func loadSavedMode() {
    let rustValue = CoreBridge.shared.getSetting(key: settingsKey)
    if !rustValue.isEmpty, let intValue = Int(rustValue), let mode = AppearanceMode(rawValue: intValue) {
        currentMode = mode
    } else if let savedValue = UserDefaults.standard.object(forKey: settingsKey) as? Int,
              let mode = AppearanceMode(rawValue: savedValue) {
        currentMode = mode
    } else {
        // 根据 NSApp.effectiveAppearance 决定初始值
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        currentMode = isDark ? .dark : .light
    }
}
```

移除 `systemAppearanceChanged` 中的 `.system` 分支处理（改为始终刷新）。

- [ ] **Step 2: SidebarView 添加工具栏行（设备上方）**

在 `setupUI()` 中 deviceMaskView 创建之后、约束设置之前添加：

```swift
// T1: 工具栏行（夜间切换 + 设置 + 工具），位于设备上方
let toolBarRow = NSStackView()
toolBarRow.orientation = .horizontal
toolBarRow.spacing = 8
toolBarRow.alignment = .centerY
toolBarRow.distribution = .fillEqually
toolBarRow.translatesAutoresizingMaskIntoConstraints = false
addSubview(toolBarRow)

let themeToggleBtn = NSButton()
themeToggleBtn.bezelStyle = .inline
themeToggleBtn.isBordered = false
themeToggleBtn.image = NSImage(systemSymbolName: ThemeManager.shared.currentMode.iconName, accessibilityDescription: "切换主题")
themeToggleBtn.contentTintColor = .secondaryLabelColor
themeToggleBtn.target = self
themeToggleBtn.action = #selector(toggleTheme)
themeToggleBtn.translatesAutoresizingMaskIntoConstraints = false
toolBarRow.addArrangedSubview(themeToggleBtn)

let settingsBtn = NSButton()
settingsBtn.bezelStyle = .inline
settingsBtn.isBordered = false
settingsBtn.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置")
settingsBtn.contentTintColor = .secondaryLabelColor
settingsBtn.target = self
settingsBtn.action = #selector(openSettings)
settingsBtn.translatesAutoresizingMaskIntoConstraints = false
toolBarRow.addArrangedSubview(settingsBtn)

let toolBtn = NSButton()
toolBtn.bezelStyle = .inline
toolBtn.isBordered = false
toolBtn.image = NSImage(systemSymbolName: "hammer", accessibilityDescription: "工具")
toolBtn.contentTintColor = .secondaryLabelColor
toolBtn.target = self
toolBtn.action = #selector(toggleToolPanel)
toolBtn.translatesAutoresizingMaskIntoConstraints = false
toolBarRow.addArrangedSubview(toolBtn)

NSLayoutConstraint.activate([
    toolBarRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
    toolBarRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
    toolBarRow.bottomAnchor.constraint(equalTo: deviceMaskView.topAnchor, constant: -8),
    toolBarRow.heightAnchor.constraint(equalToConstant: 28),
])
```

- [ ] **Step 3: 添加 toggleTheme / openSettings / toggleToolPanel 方法**

```swift
@objc private func toggleTheme() {
    let newMode = ThemeManager.shared.currentMode.toggled
    ThemeManager.shared.applyMode(newMode)
    // 更新按钮图标
    if let btn = self.viewWithTag(1001) as? NSButton {
        btn.image = NSImage(systemSymbolName: newMode.iconName, accessibilityDescription: "切换主题")
    }
}

@objc private func openSettings() {
    // 打开设置窗口
    NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
}

@objc private func toggleToolPanel() {
    // TODO: 展开侧边栏底部工具面板（查重/重命名等）
}
```

注意：themeToggleBtn 需设置 `tag = 1001` 以便后续更新图标。

- [ ] **Step 4: 构建验证**（合并）

---

### Task 10: 构建验证 + 启动

- [ ] **Step 1: Debug 构建**

```bash
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native
xcodebuild -project FlowFinderNative/FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Debug build 2>&1 | tail -30
```
Expected: BUILD SUCCEEDED

- [ ] **Step 2: 修复编译错误（如有）**

- [ ] **Step 3: 启动应用验证**

```bash
# 先结束旧进程
pkill -f FlowFinderNative || true
sleep 1
# 启动 Debug 版本
open FlowFinderNative/build/Debug/FlowFinderNative.app
```

- [ ] **Step 4: 截图对比设计稿**

---

## Self-Review

**1. Spec coverage:**
- 需求 1（收藏夹左对齐）→ Task 2 ✓
- 需求 2（收藏夹内容）→ Task 3 ✓
- 需求 3（滚动条粗）→ Task 1 ✓
- 需求 4（路径栏 + 箭头 + 右键）→ Task 5 + Task 6 ✓
- 需求 5（单击选中）→ Task 4 ✓
- 需求 6（三栏布局 + 悬停高亮）→ Task 7 ✓
- 需求 7（应用图标位置）→ Task 8 ✓
- 需求 8（操作区背景色）→ 已实现（0.15/0.25），无需修改 ✓
- 需求 9（夜间模式切换）→ Task 9 ✓

**2. Placeholder scan:** 已检查，无 TBD/TODO（toggleToolPanel 标记 TODO 是已知待实现功能，非计划占位）。

**3. Type consistency:** ThemeManager.AppearanceMode.toggled 属性在 Task 9 Step 1 定义，Step 3 使用，名称一致。
