# FlowFinder 二轮修复（10 项）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 v0.7.0 用户实测暴露的 8 项遗留问题 + 2 项新问题（撤销栈/文件冲突）。

**Architecture:** 全部 Swift & AppKit 侧；T10 冲突检测优先 Swift 层解决（不改 Rust 语义）。每任务构建 + 交付用户实测确认后才算完成。

**Tech Stack:** Swift 5.9+ / AppKit / FFGlassView / NSOutlineView / NSTableView / QLPreviewPanel / UndoManager / NSAlert

## Global Constraints

- 构建前必须 `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`
- 所有 UI 文案与代码注释使用简体中文
- 项目根目录：`/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native`
- 构建命令：
  ```bash
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
  xcodebuild -project FlowFinderNative/FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Debug build 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
  ```
- 每任务末尾 commit（`git add <改动文件> && git commit -m "<信息>"`）；**不 git add 构建产物**（`FlowFinderNative/FlowFinderNative/Libraries/*.a/.dylib`，构建后如变脏需 `git checkout --` 恢复）
- 部署目标 macOS 12.0，新 API 加 `#available` 守卫；`NSGlassEffectView` 需 macOS 26.0+（FFGlassView 内部已处理）
- FFGlassView `.panel` 实例预算 `maxGlassInstances = 8`
- **验收标准（关键）：每任务完成后构建 Debug 版本，交付用户实测对应功能，用户反馈通过才算完成**

---

### Task 1: 收藏夹选中高亮修复（T1）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/SidebarView.swift:42-63`（FFFNoDisclosureOutlineView）
- Modify: `FlowFinderNative/FlowFinderNative/UI/SidebarView.swift:366-390`（makeOutlineView）
- Modify: `FlowFinderNative/FlowFinderNative/UI/SidebarView.swift:566-573`（updateFavoritesHeight）

**Interfaces:**
- Consumes: `favoritesDataSource.favoriteCount: Int`
- Produces: 无签名变化；高亮范围、间距、常量共享

- [ ] **Step 1: 移除 canBecomeKeyView 阻断，恢复标准蓝色高亮**

`SidebarView.swift:46-50` 当前：

```swift
    // 彻底禁用焦点环：阻止 outlineView 成为 key view，
    // 消除点击收藏夹项目时整个模块外出现的蓝色边框（focusRingType=.none 在部分场景下仍会绘制）
    override var canBecomeKeyView: Bool {
        return false
    }
```

替换为：

```swift
    // 恢复 canBecomeKeyView=true：使 outlineView 能成为 key view，
    // NSTableRowView 选中绘制走标准强调蓝色（而非 de-emphasized 灰色），
    // 解决"高亮未完全包裹内容/颜色过淡"问题。焦点环由 focusRingType=.none 抑制。
    override var canBecomeKeyView: Bool {
        return true
    }
```

- [ ] **Step 2: 提取共享行高/间距常量**

在 `SidebarView.swift` 类内新增：

```swift
    // MARK: - 收藏夹布局常量（updateFavoritesHeight 与 makeOutlineView 共享，避免魔法数字重复）
    private let favoritesRowHeight: CGFloat = 28
    private let favoritesRowSpacing: CGFloat = 2
```

- [ ] **Step 3: makeOutlineView 使用共享常量**

将 `SidebarView.swift:370-375` 改为：

```swift
        // 收藏夹项目行高 28pt
        ov.rowHeight = favoritesRowHeight
        // 任务 F1: 收藏夹贴左边缘（Finder 风格，无缩进）
        ov.indentationPerLevel = 0
        // 行间距：水平无间距，垂直 2pt 间距，保证行间留白
        ov.intercellSpacing = NSSize(width: 0, height: favoritesRowSpacing)
```

- [ ] **Step 4: updateFavoritesHeight 使用共享常量**

将 `SidebarView.swift:566-573` 改为：

```swift
    private func updateFavoritesHeight() {
        // 收藏夹行高 + 垂直行距（intercellSpacing.height），末行无行距
        let count = favoritesDataSource.favoriteCount
        let height = CGFloat(count) * favoritesRowHeight + CGFloat(max(count - 1, 0)) * favoritesRowSpacing
        favoritesHeightConstraint.constant = max(height, favoritesRowHeight)
    }
```

- [ ] **Step 5: 高亮覆盖验证（frameOfCell 检查）**

`frameOfCell`（SidebarView.swift:52-62）将第一列 cell 移到 x=0 并加宽。验证：若高亮背景仍比内容窄（row 高亮由 rowView 绘制、应铺满整行），无需改动此方法。构建后人工确认。

- [ ] **Step 6: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。

- [ ] **Step 7: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/SidebarView.swift
git commit -m "fix: 收藏夹选中高亮恢复标准蓝色+共享行距常量"
```

**人工验证点（交付用户）：** 选中收藏夹项时整行（图标+文字）被标准蓝色高亮完整包裹；相邻选中无白色缝隙；≥5 项末行高亮完整。

---

### Task 2: 搜索栏图标贴右（T2）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/PaneToolbar.swift:125-230`（setupRow2）

**Interfaces:**
- Consumes: `searchContainer`（FFGlassView）、`sortPopup`/`groupPopup`/`listViewButton`/`gridViewButton`/`toolsButton`
- Produces: row2 中搜索框与图标簇之间插入弹性 spacer

- [ ] **Step 1: 在图标簇前插入弹性 spacer**

在 `PaneToolbar.swift` setupRow2 中，row2 的 views 数组（203-210 行附近）改为：

```swift
        // 弹性 spacer：占据搜索框与图标簇之间的剩余空间，
        // 使右侧图标簇（排序/分组/视图切换/显示设置）恒贴操作区最右端。
        let flexibleSpacer = NSView()
        flexibleSpacer.translatesAutoresizingMaskIntoConstraints = false
        flexibleSpacer.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
        flexibleSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row2 = NSStackView(views: [
            searchContainer,
            sortPopup,
            groupPopup,
            listViewButton, gridViewButton,
            toolsSeparator,
            flexibleSpacer,
            toolsButton,
        ])
```

并补充约束（在 row2 约束激活区追加）：

```swift
        // spacer 最小宽度 8pt，确保搜索框与图标簇之间始终有间隔
        flexibleSpacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 8).isActive = true
```

- [ ] **Step 2: 调整搜索框 hugging 为默认低（250）而非最低（1）**

将 `PaneToolbar.swift:176` 的：

```swift
searchContainer.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 1), for: .horizontal)
```

改为：

```swift
// 搜索框 hugging 设为默认低（250）：与 spacer（1）配合，剩余宽度优先给 spacer 保证图标贴右，
// 搜索框在满足最小宽 120 的基础上适度变宽（用户确认的"搜索框变宽+图标贴右"双目标）
searchContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
```

- [ ] **Step 3: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/PaneToolbar.swift
git commit -m "fix: 搜索栏与图标簇间插入弹性spacer使图标贴右"
```

**人工验证点：** 窗口拉宽时右侧图标簇（排序/分组/视图/显示设置）始终贴操作区最右端；搜索框随窗口适度变宽（≥120）；窗口缩窄图标不被挤出。

---

### Task 3: 液态玻璃全面重做（T4）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/FFGlassView.swift`
- Modify: `FlowFinderNative/FlowFinderNative/UI/DesignTokens.swift:9-59`（Glass 令牌）
- Modify: `FlowFinderNative/FlowFinderNative/UI/ExpandableDetailsBar.swift:114-119`（移除手动 masksToBounds 补丁）
- Modify: `FlowFinderNative/FlowFinderNative/UI/PaneToolbar.swift:129-132`（移除手动 masksToBounds 补丁）

**Interfaces:**
- Consumes: `FFDesign.Glass.*` 令牌、`FFDesign.isDark`
- Produces: FFGlassView 内部统一处理装饰层圆角裁剪 + 描边 + 阴影；新增令牌 `borderLight/borderDark/shadowOpacity/shadowRadius`

- [ ] **Step 1: DesignTokens 新增液态玻璃描边/阴影令牌**

在 `DesignTokens.swift` 的 `enum Glass` 内追加：

```swift
        // 液态玻璃描边（1pt 细亮线，Apple Liquid Glass 规范）
        static let borderLight: NSColor = NSColor.white.withAlphaComponent(0.50)  // 日间亮边
        static let borderDark: NSColor = NSColor.white.withAlphaComponent(0.12)   // 夜间弱亮边

        // 液态玻璃底部阴影（与背景分离的深度层次）
        static let shadowOpacity: Float = 0.15
        static let shadowRadius: CGFloat = 10
        static let shadowOffset: CGSize = CGSize(width: 0, height: 2)

        // 圆角统一（面板 16 / 组件 10，替代现 10/8 混合）
        static let cornerRadiusPanel: CGFloat = 16
        static let cornerRadiusComponent: CGFloat = 10
```

在 `FFDesign` 主体追加便捷访问：

```swift
    /// 当前描边色（液态玻璃亮线，深浅色自适应）
    static var glassBorder: NSColor {
        isDark ? Glass.borderDark : Glass.borderLight
    }
```

- [ ] **Step 2: FFGlassView 装饰层统一圆角裁剪**

修改 `updateSublayerFrames()`（FFGlassView.swift:285-334），在 tint/noise frame 设置后追加圆角裁剪：

```swift
        // tint / 噪声：填满，且跟随圆角裁剪（消除圆角外方形灰边根因）
        tintLayer?.frame = bounds
        noiseLayer?.frame = bounds
        // 装饰层自身加圆角 + 裁剪：父层 masksToBounds=false 不裁剪 sublayer，
        // 需在装饰层上单独设置 cornerRadius 与 masksToBounds，使方形角不再从圆角外露出。
        for layer in [tintLayer, noiseLayer] {
            layer?.cornerRadius = cornerRadius
            layer?.masksToBounds = true
        }
```

同时移除现有两处调用方手动补丁：
- `ExpandableDetailsBar.swift:116-119`：删除 `glassBackground.layer?.masksToBounds = true` 一行及注释
- `PaneToolbar.swift:129-132`：删除 `searchContainer.layer?.masksToBounds = true` 一行及注释

- [ ] **Step 3: FFGlassView 加描边（亮线）**

在 `setup()`（FFGlassView.swift:99-105）中，`layer?.backgroundColor = NSColor.clear.cgColor` 之后追加：

```swift
        // 液态玻璃描边：1pt 细亮线（Apple Liquid Glass 规范），颜色随主题刷新
        layer?.borderWidth = 1
        layer?.borderColor = FFDesign.glassBorder.cgColor
```

在 `refreshAppearance()`（FFGlassView.swift:362-383）中追加：

```swift
        // 描边色随主题刷新
        layer?.borderColor = FFDesign.glassBorder.cgColor
```

- [ ] **Step 4: FFGlassView 加底部阴影**

在 `setup()` 的描边设置后追加：

```swift
        // 液态玻璃底部阴影：与背景分离的深度层次（面板/组件级）
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = FFDesign.Glass.shadowOpacity
        layer?.shadowRadius = FFDesign.Glass.shadowRadius
        layer?.shadowOffset = FFDesign.Glass.shadowOffset
```

在 `updateSublayerFrames()` 的 bounds 更新处追加 shadowPath（阴影跟随圆角）：

```swift
        // 阴影路径跟随圆角（避免阴影呈方形）
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
```

**注意：** `.window` 级 FFGlassView 是透明容器，不应加描边/阴影。在 `setup()` 的 switch 中，仅 `.panel`/`.component` 分支执行描边/阴影（将 Step 3/4 代码放入 `.panel` 与 `.component` 分支共用的小方法，或加 `if level != .window` 守卫）。

- [ ] **Step 5: 检查玻璃实例预算**

`.panel` 级实例数（终端审 4 个）不因本任务新增实例，仅改样式。无需调整。

- [ ] **Step 6: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`（注意：`NSColor` 在 `FFGlassView.swift` 已有 `import AppKit`，`FFDesign` 在 DesignTokens.swift）。

- [ ] **Step 7: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/FFGlassView.swift FlowFinderNative/FlowFinderNative/UI/DesignTokens.swift FlowFinderNative/FlowFinderNative/UI/ExpandableDetailsBar.swift FlowFinderNative/FlowFinderNative/UI/PaneToolbar.swift
git commit -m "feat: 液态玻璃全面重做（统一圆角裁剪/亮线描边/底部阴影）"
```

**人工验证点：** 设备卡片、工具面板、搜索框、详情栏均无方形灰边；所有玻璃面板视觉一致（圆角/亮线/阴影统一）；深浅色切换全部自动刷新。

---

### Task 4: 工具面板点击打不开（T5）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/ToolOverlayView.swift:255-283`（ToolPanelView 卡片点击闭包）
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift:1043-1096`（createToolPanel 的 action 时序）

**Interfaces:**
- Consumes: `ToolPanelCardView` 点击 → `onTap`；`DuplicateScanWindowController.shared.showWindow()`；`menuBatchRename(_:)`
- Produces: 点击后延迟关面板（先执行 action，再关）；窗口打开置前

- [ ] **Step 1: ToolPanelView 卡片点击延迟关面板**

将 `ToolOverlayView.swift:255-283` 中卡片构建循环改为：

```swift
        // 构建工具卡片，每行 3 列，不足 3 个补灰色占位方块
        var rowViews: [NSView] = []
        for tool in tools {
            let card = ToolPanelCardView(tool: tool) { [weak self] in
                tool.action?()
                // 延迟关闭面板：确保工具窗口先弹出（同步 showWindow 在 onClose 前执行，
                // 但面板收起动画与窗口弹出竞争时可能打断窗口显示，改为下一轮 runloop 关闭）
                DispatchQueue.main.async {
                    self?.onClose?()
                }
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

- [ ] **Step 2: 查重扫描 action 确保窗口置前**

将 `MainWindowController.swift:1048-1053` 的查重 action 改为：

```swift
                action: { [weak self] in
                    guard let self = self else { return }
                    let wc = DuplicateScanWindowController.shared
                    wc.showWindow()
                    wc.window?.makeKeyAndOrderFront(nil)
                    if #available(macOS 14.0, *) {
                        NSApp.activate()
                    } else {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
```

- [ ] **Step 3: 批量重命名 action 保持 + 窗口置前**

将 `MainWindowController.swift:1059-1080` 的批量重命名 action 中 `self.menuBatchRename(nil)` 改为：

```swift
                    self.menuBatchRename(nil)
                    // 确保批量重命名窗口置前（menuBatchRename 内部 showWindow 后可能未置前）
                    if let batchWindow = BatchRenameWindowController.shared.window {
                        batchWindow.makeKeyAndOrderFront(nil)
                    }
```

- [ ] **Step 4: ToolPanelCardView 点击视觉反馈**

在 `ToolOverlayView.swift` ToolPanelCardView 的 `setupUI` 末尾（点击手势添加处）追加按下态反馈：

```swift
        // 点击视觉反馈：按下时卡片背景变深，松开恢复（解决"点了没反馈"）
        if onTap != nil {
            let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
            addGestureRecognizer(click)
            let hover = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(hover)
        }
```

并给 ToolPanelCardView 添加 hover 处理：

```swift
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let hover = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(hover)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
```

- [ ] **Step 5: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/ToolOverlayView.swift FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift
git commit -m "fix: 工具面板点击延迟关面板+窗口置前+悬停反馈"
```

**人工验证点：** 点击"查重扫描"弹出扫描窗口且面板随后收起；点击"批量重命名"（≥2 选中）弹出重命名窗口；点击有悬停/按下反馈。

---

### Task 5: QuickLook 空格键修复（T6）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileListView.swift:633`（tableView 子类化）
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileGridView.swift`（collectionView 空格拦截，若适用）
- Modify: `FlowFinderNative/FlowFinderNative/UI/QuickLookPreviewView.swift`（如需，验证）

**Interfaces:**
- Consumes: `.fileListRequestQuickLook` 通知（object nil, userInfo ["side": side]）
- Produces: `FFQuickLookTableView`（NSTableView 子类）在 keyDown 拦截空格转发通知

- [ ] **Step 1: 新建 FFQuickLookTableView 子类**

在 `FileListView.swift` 文件顶部（import 之后）新增：

```swift
// MARK: - FFQuickLookTableView

/// 拦截空格键的 NSTableView 子类：
/// first responder 是 NSTableView 时，空格键事件到达 tableView.keyDown 即被
/// interpretKeyEvents 消耗，不会冒泡到 FileListView.keyDown——QuickLook 无法触发
/// （问题 6 根因）。此子类在 keyDown 拦截空格并发送通知转发给 MainWindowController。
final class FFQuickLookTableView: NSTableView {
    /// 空格键触发 QuickLook 通知（userInfo 携带 side）
    var onSpaceKey: ((String) -> Void)?
    /// 当前所属面板标识（left/right）
    var side: String = "left"

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags
        if event.keyCode == 49 && modifiers.isEmpty {
            // 空格：发送通知触发 QuickLook（不消费事件，让 FileListView.keyDown 兜底链路也走）
            onSpaceKey?(side)
            return
        }
        super.keyDown(with: event)
    }
}
```

- [ ] **Step 2: tableView 改用子类并接线**

将 `FileListView.swift:633` 的 `tableView = NSTableView()` 改为：

```swift
        let qlTableView = FFQuickLookTableView()
        qlTableView.side = getSide()
        qlTableView.onSpaceKey = { [weak self] side in
            NotificationCenter.default.post(name: .fileListRequestQuickLook, object: nil, userInfo: ["side": side])
        }
        tableView = qlTableView
```

- [ ] **Step 3: 网格视图空格拦截（若网格也可选中）**

检查 `FileGridView.swift` 是否有 `keyDown`（探查未确认）。若网格视图的 collectionView 是 first responder 时空格也被吃，参照 Task 5 Step 1 为网格创建对应子类或直接覆写 FileGridView.keyDown（若其已存在）。实施者需先 grep `FileGridView.swift` 的 `keyDown`/`acceptsFirstResponder`；若网格不可键盘选中（无 firstResponder 需求），跳过本步并在报告中说明。

- [ ] **Step 4: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/FileListView.swift
git commit -m "fix: QuickLook 空格键在 tableView 层拦截转发"
```

**人工验证点：** 列表视图选中文件按空格稳定弹出 QuickLook；Esc 关闭；方向键切换；重开后正常。若列表生效而网格不生效，报告说明。

---

### Task 6: 拖拽访达语义（T7）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileListView.swift:2116-2130`（isMoveOperation）
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileGridView.swift:1652-1665`（isMoveOperation）

**Interfaces:**
- Consumes: `isSameVolume(srcPath:destPath:)`（已存在）、`viewModel?.currentPath`
- Produces: 实例属性 `lastDragModifierFlags: NSEvent.ModifierFlags = []`；`draggingUpdated` 覆写捕获 modifier

- [ ] **Step 1: FileListView 捕获拖拽中修饰键**

在 `FileListView.swift` 的 Drag and Drop 扩展（2093-2139）中新增属性与回调：

```swift
extension FileListView {
    /// 拖拽进行中最后一次读取的修饰键（用于 ⌘ 判断，问题 7 根因修复：
    /// validateDrop 回调中 NSApp.currentEvent 不可靠，需在 draggingUpdated 中持续捕获）
    private var lastDragModifierFlags: NSEvent.ModifierFlags = []

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let event = NSApp.currentEvent {
            lastDragModifierFlags = event.modifierFlags
        }
        return []
    }

    public override func draggingEnded(_ sender: NSDraggingInfo) {
        lastDragModifierFlags = []
    }
}
```

**注意：** `FileListView` 是否收到 `draggingUpdated` 取决于它是否是拖拽目标注册者。tableView 是实际目标（`registerForDraggedTypes` 在 tableView 上）。若 FileListView 收不到 draggingUpdated，改在 `tableView(_:validateDrop:)` 与 `tableView(_:acceptDrop:)` 两个回调中都读取 `NSApp.currentEvent?.modifierFlags` 并写入 `lastDragModifierFlags`（这两个回调至少会各触发一次，比只读一次可靠）。实施者需先验证 FileListView 是否能收到 draggingUpdated（可在两处同时写入，双保险）。

- [ ] **Step 2: isMoveOperation 改读 lastDragModifierFlags**

将 `FileListView.swift:2116-2130` 的 isMoveOperation 替换为：

```swift
    /// 判断是否为移动操作（访达语义）：
    /// 同盘 + 无修饰键 = 移动；同盘 + ⌘ = 复制
    /// 跨盘 + 无修饰键 = 复制；跨盘 + ⌘ = 移动
    /// - Parameter destPath: 真实拖放目标路径（拖到文件夹行时为该文件夹路径，否则当前目录）
    private func isMoveOperation(_ sender: NSDraggingInfo, destPath: String? = nil) -> Bool {
        // 读取拖拽过程中捕获的修饰键（比 NSApp.currentEvent 在回调中可靠）
        let commandPressed = lastDragModifierFlags.contains(.command)

        // 源与目标卷判定
        let dest = destPath ?? viewModel?.currentPath
        guard let dest = dest, !dest.isEmpty else { return false }
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let srcPath = urls.first?.path else { return false }
        let sameVolume = isSameVolume(srcPath: srcPath, destPath: dest)

        // ⌘ 按下时反转默认行为（复制↔移动切换，访达语义）
        return commandPressed ? !sameVolume : sameVolume
    }
```

- [ ] **Step 3: FileGridView 同步**

`FileGridView.swift` 已有 `draggingUpdated` override（1519-1523），在其中捕获修饰键存入 `lastDragModifierFlags` 属性；`draggingEnded` 复位。`isMoveOperation`（1652-1665）改为与 Step 2 相同实现（读 lastDragModifierFlags）。

- [ ] **Step 4: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/FileListView.swift FlowFinderNative/FlowFinderNative/UI/FileGridView.swift
git commit -m "fix: 拖拽拖拽过程捕获修饰键实现访达语义"
```

**人工验证点：** 同盘拖动=移动、按住⌘=复制；跨盘拖动=复制、按住⌘=移动；列表/网格一致。**特别测试：按住⌘拖到一半松开⌘再松鼠标**——行为应与光标提示一致。

---

### Task 7: 设置页严重问题（T8）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/SettingsWindowController.swift`
- Modify: `FlowFinderNative/FlowFinderNative/UI/SettingsSectionView.swift`
- Modify: `FlowFinderNative/FlowFinderNative/UI/AppearanceSettingsView.swift`（如塌缩）
- Modify: `FlowFinderNative/FlowFinderNative/UI/SMBManagerPanel.swift`（如空白）

**Interfaces:**
- Consumes: `SettingsSectionView`/`SettingsRowView` 工厂方法、`SMBManagerPanel`、`AppearanceSettingsView`
- Produces: 各分区布局修复；无签名变化

- [ ] **Step 1: SMB 分区修复（panel 嵌入滚动容器的约束冲突）**

`SettingsWindowController.swift` buildSMBSection（514-555）中 `smbPanel` 当前只有 `heightAnchor >= 220`，嵌入 stack → scroll 容器。修复：给 panel 明确宽度（= stack 宽度）约束：

```swift
        let smbPanel = SMBManagerPanel(frame: .zero)
        smbPanel.translatesAutoresizingMaskIntoConstraints = false
        smbPanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        // 修复：SMBManagerPanel 内部含 scrollView，需明确宽度撑满 stack，
        // 否则嵌入滚动容器后约束冲突导致分区空白
        smbPanel.widthAnchor.constraint(equalToConstant: 420).isActive = true
        smbPanel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
```

（若 SMBManagerPanel 内部 scrollView 与固定宽度冲突，实施者改为在 SMBManagerPanel 内部检查约束并给出最小/等宽处理；验证结果优先于本代码。若仍空白，报告需附诊断。）

- [ ] **Step 2: 外观分区修复（AppearanceSettingsView 塌缩）**

`buildAppearanceSection`（412-450）的 `themeRow.setControl(appearanceView)` 中，`AppearanceSettingsView` 按钮容器高 100pt 宽 100×3。修复：给 appearanceView 明确尺寸：

```swift
        let appearanceView = AppearanceSettingsView(frame: .zero)
        appearanceView.translatesAutoresizingMaskIntoConstraints = false
        // 修复：AppearanceSettingsView 无 intrinsic size，嵌入 SettingsRowView 的
        // controlContainer（无宽度约束）时塌缩。给明确高度与最小宽度。
        appearanceView.heightAnchor.constraint(equalToConstant: 112).isActive = true
        appearanceView.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
```

- [ ] **Step 3: 逐分区点测修复（探索性）**

构建 Debug 版本运行，逐分区（通用/外观/文件管理/标签/网络存储/快捷键/关于）点击验证：
- 各分区能正常打开、内容完整无空白
- 每个设置项（toggle/popup/segmented/slider/color/textField/button）点击有正确响应
- 发现断裂点（如某 action 未接线、约束冲突导致控件不可见）就地修复

**本步为探索性修复**：实施者需在报告中列出实际修复的每个断点及 file:line。已知候选断点：
- `SettingsRowView.setControl` 的 controlContainer 无宽度约束（SettingsSectionView.swift:69-94），导致无 intrinsic size 的控件塌缩
- `makeScrollContainer` 的 contentInsets top 20 与 stack spacing 叠加导致首行偏移

- [ ] **Step 4: Debug 构建 + 运行验证**

运行构建命令。Expected: `BUILD SUCCEEDED`。运行应用逐分区确认。

- [ ] **Step 5: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/SettingsWindowController.swift FlowFinderNative/FlowFinderNative/UI/SettingsSectionView.swift FlowFinderNative/FlowFinderNative/UI/AppearanceSettingsView.swift FlowFinderNative/FlowFinderNative/UI/SMBManagerPanel.swift
git commit -m "fix: 设置页分区空白/塌缩/交互修复"
```

**人工验证点：** 7 个分区均可打开、内容完整；控件对齐；每个设置项点击生效。

---

### Task 8: 详情栏修复（T9）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/ExpandableDetailsBar.swift`

**Interfaces:**
- Consumes: `gatherFileInfo`/`gatherImageInfo`/`gatherAppInfo`、`entry.path`
- Produces: 展开高度动态计算；`.app` 分支提前；两列均衡；locationField 交互（换行/点击跳转/右键复制/蓝色）

- [ ] **Step 1: .app 判断提到 isDirectory 之前**

将 `gatherFileInfo`（846-870）改为：

```swift
    private func gatherFileInfo(entry: FileEntry) -> [(String, String)] {
        let url = URL(fileURLWithPath: entry.path)
        let ext = entry.fileExtension.lowercased()

        // .app 是 bundle（isDir=true），必须先于 isDirectory 分支判断，
        // 否则永远命中目录分支、版本号永远不显示（问题 9 根因）
        if ext == "app" || entry.path.hasSuffix(".app") {
            return gatherAppInfo(path: entry.path)
        }
        if entry.isDirectory {
            return gatherFolderInfo(path: entry.path)
        }
        if isImageExtension(ext) {
            return gatherImageInfo(url: url, path: entry.path)
        }
        if isVideoExtension(ext) {
            return gatherVideoInfo(url: url)
        }
        if isAudioExtension(ext) {
            return gatherAudioInfo(url: url)
        }
        if isDocumentExtension(ext) {
            return gatherDocumentInfo(url: url, ext: ext)
        }
        return []
    }
```

- [ ] **Step 2: 展开高度动态计算**

将 `applyExpandedState`（440-464）中的固定高度改为动态：

```swift
    private func applyExpandedState(animated: Bool) {
        let newHeight = isExpanded ? computedExpandedHeight() : collapsedHeight
        heightConstraint.constant = newHeight
        compactView.isHidden = isExpanded
        expandedView.isHidden = !isExpanded

        let symbol = isExpanded ? "chevron.down" : "chevron.up"
        chevronButton.image = NSImage(systemSymbolName: symbol,
                                      accessibilityDescription: isExpanded ? "收起" : "展开")

        if isExpanded { loadThumbnail() }

        let performLayout = { [weak self] in
            self?.window?.layoutIfNeeded()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                performLayout()
            }
        } else {
            performLayout()
        }
    }

    /// 展开态高度：基础 192pt（图标 96 + 两列信息约 6 行）+ 文件类型专属信息高度
    /// 图片/视频信息行多时按行数扩展，确保完整显示（问题 9 根因：固定 210 截断图片信息）
    private func computedExpandedHeight() -> CGFloat {
        var extra: CGFloat = 0
        if let entry = entry {
            let infoRows = gatherFileInfo(entry: entry).count
            let rowsInTwoCols = (infoRows + 1) / 2
            if rowsInTwoCols > 4 {
                // 基准容纳 4 行（两列），超出部分每行 +16pt
                extra = CGFloat(rowsInTwoCols - 4) * 16
            }
        }
        return 192 + extra
    }
```

并在 `refresh()` 的 `updateFileTypeSpecificInfo(entry:)` 调用后追加高度刷新：

```swift
        // 文件类型专属信息（分辨率 / EXIF / 时长 / 编码 等）
        updateFileTypeSpecificInfo(entry: entry)
        // 动态高度：信息行数变化时更新展开高度（行数多时更高，避免截断）
        if isExpanded {
            heightConstraint.constant = computedExpandedHeight()
        }
```

- [ ] **Step 3: 两列均衡（column1 限宽）**

在 setupUI 的约束区（330-331 附近）追加：

```swift
            // 两列容器最小宽度，确保信息完整显示
            column1.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            column2.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            // 问题 9：限制第一列最大宽度（容器 60%），防止路径字段撑宽第一列
            // 把第二列（标签/文件说明/来源）挤出到右缘截断
            column1.widthAnchor.constraint(lessThanOrEqualTo: columnsContainer.widthAnchor, multiplier: 0.60),
```

- [ ] **Step 4: locationField 多行 + 蓝色 + 点击跳转 + 右键复制**

在 setupUI 中（190-191 附近）locationField 配置处改为：

```swift
        configureValue(locationField)
        // 问题 9：路径多行完整显示（换行而非截断），蓝色链接色区分可交互
        locationField.lineBreakMode = .byWordWrapping
        locationField.maximumNumberOfLines = 3
        locationField.cell?.wraps = true
        locationField.cell?.truncatesLastVisibleLine = false
        locationField.textColor = NSColor.systemBlue
        locationField.font = NSFont.systemFont(ofSize: 10)
        // 点击跳转所在文件夹
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(locationClicked))
        locationField.addGestureRecognizer(clickGesture)
        // 右键复制路径菜单
        let locationMenu = NSMenu()
        let copyItem = NSMenuItem(title: "复制路径", action: #selector(copyLocationPath), keyEquivalent: "")
        copyItem.target = self
        locationMenu.addItem(copyItem)
        locationField.menu = locationMenu
```

**注意：** `NSTextField(labelWithString:)` 默认 `isSelectable=false`，点击手势可正常附加。若 `cell?.wraps` 与 `maximumNumberOfLines` 组合后高度不足，可加 `locationField.heightAnchor.constraint(greaterThanOrEqualToConstant: 14).isActive = true` 于行容器内。

新增 action 方法（类内）：

```swift
    // MARK: - 路径交互（问题 9：点击跳转 / 右键复制）

    /// 点击路径：在访达中显示该文件所在文件夹（NSWorkspace 打开父目录并选中）
    @objc private func locationClicked() {
        guard let path = entry?.path else { return }
        let parent = (path as NSString).deletingLastPathComponent
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        _ = parent  // 保留：activateFileViewerSelecting 已在 Finder 中显示父目录并选中文件
    }

    /// 右键复制路径到剪贴板
    @objc private func copyLocationPath() {
        guard let path = entry?.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
```

- [ ] **Step 5: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。

- [ ] **Step 6: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/ExpandableDetailsBar.swift
git commit -m "feat: 详情栏动态高度+.app版本号修复+两列均衡+路径交互"
```

**人工验证点：** 图片详情完整显示（分辨率/尺寸/文件大小/色彩/相机）；.app 显示版本号；标签/说明列完整不被截断；路径多行显示、蓝色、点击跳转 Finder、右键复制路径。

---

### Task 9: 撤销栈修复（新发现 1）

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift:1725-1739`（menuCopy/menuCut/menuPaste）

**Interfaces:**
- Consumes: `ffUndoManager`（L186）、`activePaneViewModel`、`CoreBridge.shared.parallelCopy/parallelMove`
- Produces: menuPaste 注册撤销（复制→撤销删除目标；移动→撤销移回源）

- [ ] **Step 1: menuPaste 注册撤销**

在 `menuPaste`（1735）的异步执行块中，`success` 计算后、UI 刷新前注册撤销。修改 1772-1800 区域，在 `try? CoreBridge.shared.invalidateCache` 之后追加：

```swift
                // 问题 9：粘贴操作注册撤销（复制→删除目标；移动→移回源）
                // 计算目标路径（假设 srcs 都成功）
                let pastedDstPaths = srcs.map { src -> String in
                    let name = (src as NSString).lastPathComponent
                    return (destPath as NSString).appendingPathComponent(name)
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if success > 0 {
                        if isMove {
                            let pairs = zip(srcs, pastedDstPaths).map { (src: $0, dst: $1) }
                            self.ffUndoManager.registerUndo(withTarget: self) { ctrl in
                                ctrl.undoMoveBack(pairs: pairs)
                            }
                            self.ffUndoManager.setActionName("移动 \(success) 个项目")
                        } else {
                            // 复制：撤销 = 删除刚粘贴的目标
                            let dsts = pastedDstPaths
                            self.ffUndoManager.registerUndo(withTarget: self) { ctrl in
                                ctrl.undoDeleteCopied(dstPaths: dsts)
                            }
                            self.ffUndoManager.setActionName("复制 \(success) 个项目")
                        }
                    }
                }
```

- [ ] **Step 2: 新增 undo 辅助方法**

在 MainWindowController 内新增：

```swift
    // MARK: - 撤销辅助（问题 9）

    /// 撤销"移动"：把文件移回源位置
    func undoMoveBack(pairs: [(src: String, dst: String)]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for pair in pairs {
                try? CoreBridge.shared.moveFile(src: pair.dst, dst: pair.src)
            }
            DispatchQueue.main.async {
                self?.refreshPane(.left)
                self?.refreshPane(.right)
            }
        }
    }

    /// 撤销"复制"：删除刚粘贴的目标文件
    func undoDeleteCopied(dstPaths: [String]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for dst in dstPaths {
                try? CoreBridge.shared.deleteFile(path: dst)
            }
            DispatchQueue.main.async {
                self?.refreshPane(.left)
                self?.refreshPane(.right)
            }
        }
    }
```

- [ ] **Step 3: 审计其余撤销注册点**

检查已注册撤销的操作（拖拽 acceptDrop 1823/1843、跨面板 2134）是否都包含 `setActionName` 与界面刷新——已有（探查确认）。剪贴板复制/剪切本身不注册（菜单 Copy/Cut 仅设剪贴板，无副作用，无需撤销）。

- [ ] **Step 4: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`。

- [ ] **Step 5: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift
git commit -m "fix: 粘贴操作注册撤销"
```

**人工验证点：** 复制/粘贴后 ⌘Z 删除粘贴的文件；剪切/粘贴（移动）后 ⌘Z 文件移回原位置；拖拽复制/移动后 ⌘Z 同样有效；撤销后界面自动刷新。

---

### Task 10: 文件冲突提示（新发现 2）

**Files:**
- Create: `FlowFinderNative/FlowFinderNative/UI/ConflictResolver.swift`
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileListView.swift:1759-1787`（acceptDrop 集成）
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileGridView.swift`（performDragOperation 集成）
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift`（menuPaste 集成）

**Interfaces:**
- Consumes: `FileManager`、`NSAlert`、`CoreBridge.shared.parallelCopy/parallelMove`
- Produces: `enum ConflictResolution { case replace, keepBoth, skip }`；`ConflictResolver.resolveConflicts(srcPaths:destDir:window:applyToAll:) -> [String]`（返回需跳过的源；keepBoth 的源改名后并入返回）

- [ ] **Step 1: 新建 ConflictResolver.swift**

```swift
import Cocoa

// MARK: - ConflictResolver

/// 复制/移动冲突解决器（问题 10）
/// 目标目录存在同名文件时弹窗询问：替换 / 保留两者 / 跳过。
/// 批量时支持"应用于所有冲突"。
enum ConflictResolution {
    case replace      // 替换：覆盖同名目标
    case keepBoth     // 保留两者：源自动改名"名称 副本.扩展名"
    case skip         // 跳过：不处理该文件
}

enum ConflictResolver {

    /// 检查冲突并弹窗询问。
    /// - Returns: 处理后的源路径数组（keepBoth 的已改名；skip 的已剔除；replace 保持原路径）
    ///   - window: 弹窗依附窗口
    ///   - applyToAll: 用户是否勾选"应用于所有冲突"（后续冲突直接沿用首个选择）
    static func resolveConflicts(
        srcPaths: [String],
        destDir: String,
        window: NSWindow?,
        applyToAll: inout Bool
    ) -> [String] {
        var resolved: [String] = []
        var pendingApplyToAll = applyToAll
        var globalChoice: ConflictResolution?

        for src in srcPaths {
            let name = (src as NSString).lastPathComponent
            let dst = (destDir as NSString).appendingPathComponent(name)
            let conflict = FileManager.default.fileExists(atPath: dst)
            if !conflict {
                resolved.append(src)
                continue
            }

            // 冲突：决定策略
            var choice: ConflictResolution
            if pendingApplyToAll, let g = globalChoice {
                choice = g
            } else {
                choice = presentConflictDialog(name: name, window: window, applyToAll: &pendingApplyToAll)
                if pendingApplyToAll {
                    globalChoice = choice
                }
            }

            switch choice {
            case .replace:
                resolved.append(src)
            case .skip:
                break
            case .keepBoth:
                let renamed = uniqueDestination(srcPath: src, destDir: destDir)
                if let renamed = renamed {
                    resolved.append(renamed)
                }
            }
        }
        applyToAll = pendingApplyToAll
        return resolved
    }

    /// 生成不冲突的目标路径（"名称 副本.扩展名"，重名加序号）
    private static func uniqueDestination(srcPath: String, destDir: String) -> String? {
        let name = (srcPath as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension

        var candidate: String
        var index = 1
        repeat {
            let suffix = index == 1 ? "副本" : "副本 \(index)"
            candidate = ext.isEmpty
                ? (destDir as NSString).appendingPathComponent("\(base) \(suffix)")
                : (destDir as NSString).appendingPathComponent("\(base) \(suffix).\(ext)")
            index += 1
        } while FileManager.default.fileExists(atPath: candidate)
        return candidate
    }

    /// 冲突弹窗（NSAlert 三按钮 + 应用于所有 checkbox）
    private static func presentConflictDialog(name: String, window: NSWindow?, applyToAll: inout Bool) -> ConflictResolution {
        let alert = NSAlert()
        alert.messageText = "\(name) 已存在"
        alert.informativeText = "目标位置已存在同名文件。您想要如何处理？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "替换")
        alert.addButton(withTitle: "保留两者")
        alert.addButton(withTitle: "跳过")

        // "应用于所有冲突"复选框
        let checkbox = NSButton(checkboxWithTitle: "应用于所有冲突", target: nil, action: nil)
        checkbox.frame = NSRect(x: 0, y: 0, width: 180, height: 20)
        alert.accessoryView = checkbox

        if let window = window {
            alert.beginSheetModal(for: window) { response in
                // 模态闭包内无法同步返回；见下方 runModal 说明
            }
            // 注意：beginSheetModal 是异步的。为保持同步返回，此处改用 runModal
        }

        // 同步模态（避免改调用方为异步回调；后续可优化）
        let response: NSApplication.ModalResponse
        if let window = window, let sheetParent = window.sheetParent {
            response = alert.runModal()  // window 已是 sheet 时不套 sheet
        } else {
            response = alert.runModal()
        }
        applyToAll = checkbox.state == .on

        switch response {
        case .alertFirstButtonReturn:  return .replace
        case .alertSecondButtonReturn: return .keepBoth
        default:                       return .skip
        }
    }
}
```

**注意：** 上述 `presentConflictDialog` 中 `beginSheetModal` 与 `runModal` 混用是示意。**实施者需统一为一种模态方式**：若依附窗口存在用 `window.beginSheetModal` + 通过闭包异步返回，但该设计会让 `resolveConflicts` 变成异步——为最小侵入，实施者应使用**同步 `alert.runModal()`**（在依附窗口存在时直接 runModal，不套 sheet；或在调用前把窗口收起）。选择方案后修正代码并保持 `resolveConflicts` 同步返回 `[String]` 的接口不变。

- [ ] **Step 2: FileListView acceptDrop 集成**

在 `FileListView.swift` acceptDrop（1759-1787）中，`let isMove = isMoveOperation(info, destPath: destPath)` 之后、`DispatchQueue.global` 之前插入：

```swift
        // 问题 10：冲突预检与解决（替换/保留两者/跳过）
        var applyToAll = false
        let resolvedSrcs = ConflictResolver.resolveConflicts(
            srcPaths: srcs.map { $0.path },
            destDir: destPath,
            window: window,
            applyToAll: &applyToAll
        )
        guard !resolvedSrcs.isEmpty else { return true }
```

并将后续 `let srcs = urls.map { $0.path }`（1774）改为使用 `resolvedSrcs`：

```swift
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let srcs = resolvedSrcs
            ...
```

（keepBoth 返回的已是改名后的完整目标路径字符串，作为 src 传入 parallelCopy/parallelMove 会把"副本"文件复制过去——语义正确。实施者需确保 `resolvedSrcs` 的类型是 `[String]` 路径而非 URL，并相应调整后续 `srcs.map` 调用。）

- [ ] **Step 3: FileGridView + menuPaste 集成**

- FileGridView performDragOperation：参照 Step 2 相同模式插入冲突预检。
- MainWindowController menuPaste：`let srcs = clipboardItems` 之后插入冲突预检（同 Step 2）。

- [ ] **Step 4: Debug 构建**

运行构建命令。Expected: `BUILD SUCCEEDED`（新文件需加入 Xcode 工程——**重要**：若 Xcode 工程用文件系统同步组（PBXFileSystemSynchronizedRootGroup），新文件自动纳入；否则需手动加入 project.pbxproj。实施者先检查工程是否自动同步，若需手动添加，用 `xcodebuild` 报错提示缺失文件来确认）。

- [ ] **Step 5: Commit**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/ConflictResolver.swift FlowFinderNative/FlowFinderNative/UI/FileListView.swift FlowFinderNative/FlowFinderNative/UI/FileGridView.swift FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift
git commit -m "feat: 复制/移动冲突弹窗（替换/保留两者/跳过）"
```

**人工验证点：** 复制文件到含同名文件的目标 → 弹窗三选一；替换=覆盖；保留两者=生成"xxx 副本"；跳过=不动该文件；批量冲突勾选"应用于所有"后不再逐个询问。

---

### Task 11: 全量构建 + 发版 + 交接文档

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-handover/flowfinder-handover.html`
- Modify: `FlowFinderNative/FlowFinderNative.xcodeproj/project.pbxproj`（版本号 → 0.7.1/701）

**Interfaces:**
- Consumes: 前 10 个任务全部完成且用户实测通过

- [ ] **Step 1: 用户全量实测**

构建 Debug 版，交付用户验证全部 10 项。**所有项用户反馈通过后**才进入发版步骤。

- [ ] **Step 2: 版本号升级 0.7.1 (701)**

将 project.pbxproj 中 `MARKETING_VERSION = 0.7.0` → `0.7.1`，`CURRENT_PROJECT_VERSION = 700` → `701`（4 处：538/562/583/607 附近，replace_all）。

- [ ] **Step 3: Release 构建**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
xcodebuild -project FlowFinderNative/FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release build 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
```

Expected: `BUILD SUCCEEDED`。验证产物版本号 `defaults read <ReleaseApp>/Contents/Info CFBundleShortVersionString` = 0.7.1。

- [ ] **Step 4: 打包 zip + dmg**

```bash
DIST_DIR="/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/dist"
RELEASE_APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/FlowFinderNative-*/Build/Products/Release/FlowFinderNative.app | head -1)
rm -rf "$DIST_DIR/FlowFinderNative.app" "$DIST_DIR/FlowFinder-0.7.1.zip" "$DIST_DIR/FlowFinder-0.7.1.dmg"
cp -R "$RELEASE_APP" "$DIST_DIR/"
cd "$DIST_DIR"
zip -r -y -q FlowFinder-0.7.1.zip FlowFinderNative.app
mkdir -p dmg-staging && cp -R FlowFinderNative.app dmg-staging/ && ln -s /Applications dmg-staging/Applications
hdiutil create -volname "FlowFinder 0.7.1" -srcfolder dmg-staging -ov -format UDZO -quiet FlowFinder-0.7.1.dmg
rm -rf dmg-staging
unzip -t -q FlowFinder-0.7.1.zip && hdiutil verify -quiet FlowFinder-0.7.1.dmg
```

- [ ] **Step 5: CHANGELOG + 交接文档**

- CHANGELOG.md 顶部追加 `## [0.7.1] — 2026-08-02`（二轮 10 项修复摘要，emoji 分节）
- 交接文档：版本历史表追加 `0.7.1` 行；待办标注二轮 10 项完成；液态玻璃架构决策更新

- [ ] **Step 6: Commit + 收尾**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add CHANGELOG.md FlowFinderNative/FlowFinderNative.xcodeproj/project.pbxproj
git commit -m "release: v0.7.1 (701) 二轮 10 项修复发版"
git checkout -- FlowFinderNative/FlowFinderNative/Libraries/libflowfinder_core.a FlowFinderNative/FlowFinderNative/Libraries/libflowfinder_core.dylib 2>/dev/null || true
```

---

## Self-Review 记录

- **规格覆盖：** 10 项 → Task 1-10 一一对应（T1→Task1，T2→Task2，T4→Task3，T5→Task4，T6→Task5，T7→Task6，T8→Task7，T9→Task8，撤销→Task9，冲突→Task10），Task 11 收尾发版。✅
- **占位符扫描：** Task 7（设置页）Step 3 与 Task 10 的 sheet/runModal 说明为探索性步骤，已明确给出排查清单与决策边界，非 TBD。Task 5 Step 3（网格）标注"若适用"。✅
- **类型一致性：** `ConflictResolution` 枚举在 Task 10 定义并被 FileListView/FileGridView/menuPaste 使用；`lastDragModifierFlags` 在 Task 6 两文件统一定义；`computedExpandedHeight()` 在 Task 8 定义并被 refresh/applyExpandedState 调用；`undoMoveBack/undoDeleteCopied` 在 Task 9 定义并被 menuPaste 撤销闭包调用。✅
