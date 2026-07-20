# 跨面板文件操作 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 FlowFinder 原生版本添加跨面板文件操作（复制/移动到对侧面板、在对侧面板打开文件夹），并修复右键菜单失效问题。

**Architecture:** 通过 NotificationCenter 在 FileListView 右键菜单与 MainWindowController 之间路由操作；MainWindowController 作为中央协调器，使用已有 `leftPaneViewModel/rightPaneViewModel` 双面板模型执行跨面板复制/移动/导航。重名冲突采用 "副本" 后缀策略。

**Tech Stack:** Swift 6 / AppKit / NotificationCenter / CoreBridge FFI

## Global Constraints

- macOS 独占平台，使用 NSMenu 作为右键菜单
- 文件操作通过 CoreBridge.shared 调用 Rust FFI（copyFile/moveFile）
- 所有 UI 操作必须在主线程执行（DispatchQueue.main.async）
- 通知名称使用 Notification.Name 扩展，遵循现有 fileListDidCopy 命名模式
- 面板标识通过 NSView.identifier 的 rawValue（"left"/"right"）传递
- 重名冲突使用 "副本" 后缀（参照 Finder 行为）
- 构建命令：`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Debug build`

---

### Task 1: 修复右键菜单失效 + 接线面板切换激活

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift:264-269`（setupNotifications）
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift:165-246`（createPaneContainer，添加点击激活）
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift:454-457`（activatePane，添加通知发送）

**Interfaces:**
- Consumes: FileListView 现有的 `fileListDidCopy/Cut/Paste` 通知（带 `userInfo: ["side": String]`）
- Produces: 右键复制/剪切/粘贴功能可用；面板点击切换 activePane；新增 `Notification.Name.paneDidActivate` 通知

- [ ] **Step 1: 在 setupNotifications 中订阅剪贴板通知**

在 `MainWindowController.swift` 的 `setupNotifications()` 方法（行 264-269）中，添加对 `fileListDidCopy/Cut/Paste` 的订阅：

```swift
private func setupNotifications() {
    NotificationCenter.default.addObserver(
        self, selector: #selector(handleSidebarDirectorySelected(_:)),
        name: .sidebarDidSelectDirectory, object: nil
    )
    // 订阅 FileListView 右键菜单通知
    NotificationCenter.default.addObserver(
        self, selector: #selector(handleFileListCopy(_:)),
        name: .fileListDidCopy, object: nil
    )
    NotificationCenter.default.addObserver(
        self, selector: #selector(handleFileListCut(_:)),
        name: .fileListDidCut, object: nil
    )
    NotificationCenter.default.addObserver(
        self, selector: #selector(handleFileListPaste(_:)),
        name: .fileListDidPaste, object: nil
    )
}
```

- [ ] **Step 2: 添加通知处理方法**

在 `MainWindowController.swift` 的 `menuCopy/menuCut/menuPaste` 方法附近（行 535 之后），添加通知处理方法：

```swift
@objc private func handleFileListCopy(_ notification: Notification) {
    guard let side = notification.userInfo?["side"] as? String else { return }
    let vm = side == "left" ? leftPaneViewModel : rightPaneViewModel
    clipboardItems = vm.selectedFiles.map { $0.path }
    clipboardOperation = .copy
    activatePane(side == "left" ? .left : .right)
}

@objc private func handleFileListCut(_ notification: Notification) {
    guard let side = notification.userInfo?["side"] as? String else { return }
    let vm = side == "left" ? leftPaneViewModel : rightPaneViewModel
    clipboardItems = vm.selectedFiles.map { $0.path }
    clipboardOperation = .cut
    activatePane(side == "left" ? .left : .right)
}

@objc private func handleFileListPaste(_ notification: Notification) {
    guard let side = notification.userInfo?["side"] as? String else { return }
    activatePane(side == "left" ? .left : .right)
    menuPaste(self)
}
```

- [ ] **Step 3: 增强 activatePane 方法**

修改 `activatePane` 方法（行 454-457），添加通知发送：

```swift
func activatePane(_ side: PaneSide) {
    activePane = side
    updateActivePaneVisual()
    NotificationCenter.default.post(name: .paneDidActivate, object: nil, userInfo: ["side": side == .left ? "left" : "right"])
}
```

- [ ] **Step 4: 在 Notification.Name 扩展中添加 paneDidActivate**

在 `MainWindowController.swift` 文件末尾的 Notification.Name 扩展中（或与现有通知名称一起），添加：

```swift
extension Notification.Name {
    static let paneDidActivate = Notification.Name("paneDidActivate")
}
```

- [ ] **Step 5: 在 createPaneContainer 中添加面板点击激活**

在 `MainWindowController.swift` 的 `createPaneContainer(side:)` 方法中（行 165-246），在 `return container` 之前添加点击手势识别器：

```swift
// 在 return container 之前添加
let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handlePaneClick(_:)))
clickGesture.identifier = NSUserInterfaceItemIdentifier(side == .left ? "left" : "right")
container.addGestureRecognizer(clickGesture)

return container
```

并添加手势处理方法（放在 activatePane 附近）：

```swift
@objc private func handlePaneClick(_ gesture: NSClickGestureRecognizer) {
    let side: PaneSide = gesture.identifier?.rawValue == "left" ? .left : .right
    activatePane(side)
}
```

- [ ] **Step 6: 构建验证**

运行构建命令验证编译通过：

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative
xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Debug build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: BUILD SUCCEEDED

- [ ] **Step 7: 提交**

```bash
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native
git add -A
git commit -m "fix: 修复右键菜单失效 + 接线面板切换激活

- setupNotifications 订阅 fileListDidCopy/Cut/Paste 通知
- 新增 handleFileListCopy/Cut/Paste 方法路由到对应面板
- activatePane 发送 paneDidActivate 通知
- createPaneContainer 添加点击手势识别器激活面板"
```

---

### Task 2: 新增「复制到对侧面板」「移动到对侧面板」右键菜单

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileListView.swift:143-166`（setupContextMenu 添加菜单项）
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileListView.swift:536-539`（Notification.Name 扩展）
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift`（新增通知处理方法 + 跨面板操作逻辑）

**Interfaces:**
- Consumes: FileListView 的 `clickedEntry` / `viewModel.selectedFiles` / `getSide()`
- Produces: `Notification.Name.fileListDidCopyToOther` / `fileListDidMoveToOther` 通知；MainWindowController 的 `performCrossPaneCopy(side:isMove:)` 方法

- [ ] **Step 1: 在 Notification.Name 扩展添加新通知名称**

在 `FileListView.swift` 文件末尾的 Notification.Name 扩展中（行 536-539），添加：

```swift
extension Notification.Name {
    static let fileListDidCopy = Notification.Name("fileListDidCopy")
    static let fileListDidCut = Notification.Name("fileListDidCut")
    static let fileListDidPaste = Notification.Name("fileListDidPaste")
    static let fileListDidCopyToOther = Notification.Name("fileListDidCopyToOther")
    static let fileListDidMoveToOther = Notification.Name("fileListDidMoveToOther")
    static let fileListDidOpenInOther = Notification.Name("fileListDidOpenInOther")
}
```

- [ ] **Step 2: 在 FileListView.setupContextMenu 添加跨面板菜单项**

修改 `FileListView.swift` 的 `setupContextMenu()` 方法（行 143-166），在 "新建文件夹" 之前添加跨面板操作菜单项：

```swift
private func setupContextMenu() {
    let menu = NSMenu()

    menu.addItem(withTitle: "打开", action: #selector(openSelected(_:)), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(withTitle: "复制", action: #selector(copySelected(_:)), keyEquivalent: "c")
    menu.addItem(withTitle: "剪切", action: #selector(cutSelected(_:)), keyEquivalent: "x")
    menu.addItem(withTitle: "粘贴", action: #selector(pasteSelected(_:)), keyEquivalent: "v")
    menu.addItem(.separator())
    menu.addItem(withTitle: "复制到另一面板", action: #selector(copyToOtherPane(_:)), keyEquivalent: "")
    menu.addItem(withTitle: "移动到另一面板", action: #selector(moveToOtherPane(_:)), keyEquivalent: "")
    menu.addItem(withTitle: "在对侧面板打开", action: #selector(openInOtherPane(_:)), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(withTitle: "重命名", action: #selector(renameSelected(_:)), keyEquivalent: "")
    menu.addItem(withTitle: "删除", action: #selector(deleteSelected(_:)), keyEquivalent: "\u{7F}")
    menu.addItem(.separator())
    menu.addItem(withTitle: "新建文件夹", action: #selector(createDirectory(_:)), keyEquivalent: "n")

    for item in menu.items where item.action != nil {
        item.target = self
        if item.keyEquivalent == "n" {
            item.keyEquivalentModifierMask = [.command, .shift]
        } else if !item.keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = .command
        }
    }
    tableView.menu = menu
}
```

- [ ] **Step 3: 在 FileListView 添加跨面板菜单动作方法**

在 `FileListView.swift` 的 `createDirectory` 方法之后（行 250 附近），添加三个新的 @objc 方法：

```swift
@objc private func copyToOtherPane(_ sender: Any?) {
    NotificationCenter.default.post(name: .fileListDidCopyToOther, object: nil, userInfo: ["side": getSide()])
}

@objc private func moveToOtherPane(_ sender: Any?) {
    NotificationCenter.default.post(name: .fileListDidMoveToOther, object: nil, userInfo: ["side": getSide()])
}

@objc private func openInOtherPane(_ sender: Any?) {
    guard let entry = clickedEntry else { return }
    NotificationCenter.default.post(name: .fileListDidOpenInOther, object: nil, userInfo: ["side": getSide(), "path": entry.path])
}
```

- [ ] **Step 4: 在 setupNotifications 订阅新通知**

在 `MainWindowController.swift` 的 `setupNotifications()` 方法中，添加对新通知的订阅：

```swift
NotificationCenter.default.addObserver(
    self, selector: #selector(handleFileListCopyToOther(_:)),
    name: .fileListDidCopyToOther, object: nil
)
NotificationCenter.default.addObserver(
    self, selector: #selector(handleFileListMoveToOther(_:)),
    name: .fileListDidMoveToOther, object: nil
)
NotificationCenter.default.addObserver(
    self, selector: #selector(handleFileListOpenInOther(_:)),
    name: .fileListDidOpenInOther, object: nil
)
```

- [ ] **Step 5: 在 MainWindowController 添加跨面板操作方法**

在 `MainWindowController.swift` 的 `menuPaste` 方法之后（行 574 附近），添加跨面板操作核心方法：

```swift
@objc private func handleFileListCopyToOther(_ notification: Notification) {
    guard let side = notification.userInfo?["side"] as? String else { return }
    performCrossPaneOperation(side: side, isMove: false)
}

@objc private func handleFileListMoveToOther(_ notification: Notification) {
    guard let side = notification.userInfo?["side"] as? String else { return }
    performCrossPaneOperation(side: side, isMove: true)
}

@objc private func handleFileListOpenInOther(_ notification: Notification) {
    guard let side = notification.userInfo?["side"] as? String,
          let path = notification.userInfo?["path"] as? String else { return }
    let destVM: PaneViewModel = side == "left" ? rightPaneViewModel : leftPaneViewModel
    destVM.navigate(to: path)
    let destSide: PaneSide = side == "left" ? .right : .left
    activatePane(destSide)
}

/// 执行跨面板复制/移动操作
private func performCrossPaneOperation(side: String, isMove: Bool) {
    let sourceVM: PaneViewModel = side == "left" ? leftPaneViewModel : rightPaneViewModel
    let destVM: PaneViewModel = side == "left" ? rightPaneViewModel : leftPaneViewModel
    let destPath = destVM.currentPath

    let selectedFiles = sourceVM.selectedFiles
    guard !selectedFiles.isEmpty else { return }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        var successCount = 0
        var failedFiles: [(String, Error)] = []

        for entry in selectedFiles {
            let srcPath = entry.path
            let fileName = entry.name
            var dstPath = (destPath as NSString).appendingPathComponent(fileName)

            // 重名冲突检测 - 添加 "副本" 后缀
            if FileManager.default.fileExists(atPath: dstPath) {
                let ext = (fileName as NSString).pathExtension
                let nameWithoutExt = (fileName as NSString).deletingPathExtension
                var counter = 1
                let baseName = ext.isEmpty ? nameWithoutExt : "\(nameWithoutExt)"
                repeat {
                    let suffixName = ext.isEmpty ? "\(baseName) 副本 \(counter)" : "\(baseName) 副本 \(counter).\(ext)"
                    dstPath = (destPath as NSString).appendingPathComponent(suffixName)
                    counter += 1
                } while FileManager.default.fileExists(atPath: dstPath)
            }

            do {
                if isMove {
                    try CoreBridge.shared.moveFile(src: srcPath, dst: dstPath)
                } else {
                    try CoreBridge.shared.copyFile(src: srcPath, dst: dstPath)
                }
                successCount += 1
            } catch {
                failedFiles.append((fileName, error))
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 刷新双方面板
            sourceVM.refresh()
            destVM.refresh()

            // 显示错误（如果有）
            if !failedFiles.isEmpty {
                let fileNames = failedFiles.map { $0.0 }.joined(separator: ", ")
                self.showError(error: NSError(domain: "FlowFinder", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "\(failedFiles.count) 个文件操作失败: \(fileNames)"]))
            }
        }
    }
}
```

- [ ] **Step 6: 构建验证**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative
xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Debug build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: BUILD SUCCEEDED

- [ ] **Step 7: 提交**

```bash
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native
git add -A
git commit -m "feat: 新增跨面板复制/移动/在对侧打开右键菜单

- FileListView 右键菜单新增「复制到另一面板」「移动到另一面板」「在对侧面板打开」
- 新增 Notification.Name.fileListDidCopyToOther/MoveToOther/OpenInOther
- MainWindowController 新增 performCrossPaneOperation 核心方法
- 重名冲突自动添加「副本 N」后缀
- 操作完成后刷新双方面板"
```

---

### Task 3: 添加菜单栏快捷键 + 菜单项

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainMenu.swift:42-56`（编辑菜单添加跨面板项）
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift`（新增菜单 action 方法）

**Interfaces:**
- Consumes: MainWindowController 的 `leftPaneViewModel/rightPaneViewModel/activePane`
- Produces: `menuCopyToOther(_:)` / `menuMoveToOther(_:)` / `menuOpenInOther(_:)` 方法

- [ ] **Step 1: 在 MainMenu 编辑菜单添加跨面板菜单项**

修改 `MainMenu.swift` 的编辑菜单（行 42-56），在 "重命名" 之后添加跨面板操作：

```swift
// Edit menu
let editMenuItem = NSMenuItem()
mainMenu.addItem(editMenuItem)
let editMenu = NSMenu(title: "编辑")
editMenuItem.submenu = editMenu
editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
redo.keyEquivalentModifierMask = [.command, .shift]
editMenu.addItem(.separator())
editMenu.addItem(withTitle: "剪切", action: #selector(MainWindowController.menuCut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "复制", action: #selector(MainWindowController.menuCopy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "粘贴", action: #selector(MainWindowController.menuPaste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "全选", action: #selector(MainWindowController.menuSelectAll(_:)), keyEquivalent: "a")
editMenu.addItem(.separator())
editMenu.addItem(withTitle: "重命名", action: #selector(MainWindowController.menuRename(_:)), keyEquivalent: "")
editMenu.addItem(.separator())
editMenu.addItem(withTitle: "复制到另一面板", action: #selector(MainWindowController.menuCopyToOther(_:)), keyEquivalent: "c")
let copyToOtherItem = editMenu.items.last!
copyToOtherItem.keyEquivalentModifierMask = [.command, .shift]
editMenu.addItem(withTitle: "移动到另一面板", action: #selector(MainWindowController.menuMoveToOther(_:)), keyEquivalent: "x")
let moveToOtherItem = editMenu.items.last!
moveToOtherItem.keyEquivalentModifierMask = [.command, .shift]
editMenu.addItem(withTitle: "在对侧面板打开", action: #selector(MainWindowController.menuOpenInOther(_:)), keyEquivalent: "")
```

- [ ] **Step 2: 在 MainWindowController 添加菜单 action 方法**

在 `MainWindowController.swift` 的 `menuPaste` 方法之后，添加菜单栏 action 方法（基于 activePane）：

```swift
@objc func menuCopyToOther(_ sender: Any?) {
    let side = activePane == .left ? "left" : "right"
    performCrossPaneOperation(side: side, isMove: false)
}

@objc func menuMoveToOther(_ sender: Any?) {
    let side = activePane == .left ? "left" : "right"
    performCrossPaneOperation(side: side, isMove: true)
}

@objc func menuOpenInOther(_ sender: Any?) {
    guard let entry = activePaneViewModel.selectedFiles.first,
          entry.isDirectory else { return }
    let destVM: PaneViewModel = activePane == .left ? rightPaneViewModel : leftPaneViewModel
    destVM.navigate(to: entry.path)
    activatePane(activePane == .left ? .right : .left)
}
```

- [ ] **Step 3: 构建验证**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative
xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Debug build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: 提交**

```bash
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native
git add -A
git commit -m "feat: 菜单栏新增跨面板操作菜单项 + 快捷键

- 编辑菜单新增「复制到另一面板」⌘⇧C
- 编辑菜单新增「移动到另一面板」⌘⇧X
- 编辑菜单新增「在对侧面板打开」
- MainWindowController 新增 menuCopyToOther/menuMoveToOther/menuOpenInOther"
```

---

### Task 4: FileGridView 同步右键菜单 + 构建验证打包

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/FileGridView.swift`（添加与 FileListView 一致的右键菜单）
- Build: 完整 Debug + Release 构建验证
- Package: .zip + .dmg 打包

**Interfaces:**
- Consumes: FileGridView 现有的 `viewModel` / `onDoubleClick` / `onSelectionChanged`
- Produces: FileGridView 右键菜单与 FileListView 功能一致

- [ ] **Step 1: 为 FileGridView 添加右键菜单**

在 `FileGridView.swift` 的 `FileGridView` 类中，添加右键菜单支持。在 `setupUI()` 方法末尾（`NSLayoutConstraint.activate` 之后），添加：

```swift
private func setupContextMenu() {
    let menu = NSMenu()

    menu.addItem(withTitle: "打开", action: #selector(openSelected(_:)), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(withTitle: "复制", action: #selector(copySelected(_:)), keyEquivalent: "c")
    menu.addItem(withTitle: "剪切", action: #selector(cutSelected(_:)), keyEquivalent: "x")
    menu.addItem(withTitle: "粘贴", action: #selector(pasteSelected(_:)), keyEquivalent: "v")
    menu.addItem(.separator())
    menu.addItem(withTitle: "复制到另一面板", action: #selector(copyToOtherPane(_:)), keyEquivalent: "")
    menu.addItem(withTitle: "移动到另一面板", action: #selector(moveToOtherPane(_:)), keyEquivalent: "")
    menu.addItem(withTitle: "在对侧面板打开", action: #selector(openInOtherPane(_:)), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(withTitle: "重命名", action: #selector(renameSelected(_:)), keyEquivalent: "")
    menu.addItem(withTitle: "删除", action: #selector(deleteSelected(_:)), keyEquivalent: "\u{7F}")
    menu.addItem(.separator())
    menu.addItem(withTitle: "新建文件夹", action: #selector(createDirectory(_:)), keyEquivalent: "n")

    for item in menu.items where item.action != nil {
        item.target = self
        if item.keyEquivalent == "n" {
            item.keyEquivalentModifierMask = [.command, .shift]
        } else if !item.keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = .command
        }
    }
    collectionView.menu = menu
}
```

在 `setupUI()` 末尾调用 `setupContextMenu()`：

```swift
private func setupUI() {
    // ... 现有代码 ...
    NSLayoutConstraint.activate([
        scrollView.topAnchor.constraint(equalTo: topAnchor),
        scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
        scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    setupContextMenu()
}
```

- [ ] **Step 2: 为 FileGridView 添加菜单 action 方法**

在 `FileGridView.swift` 的 `FileGridView` 类中（`reloadData()` 方法之前），添加与 FileListView 一致的 action 方法：

```swift
private var clickedIndexPath: IndexPath? {
    let point = collectionView.convert(NSEvent.mouseLocation, from: nil)
    return collectionView.indexPathForItem(at: point)
}

private var clickedEntry: FileEntry? {
    guard let indexPath = clickedIndexPath,
          let viewModel = viewModel,
          indexPath.item < viewModel.files.count else { return nil }
    return viewModel.files[indexPath.item]
}

private func getSide() -> String {
    return identifier?.rawValue ?? "left"
}

@objc private func openSelected(_ sender: Any?) {
    guard let entry = clickedEntry else { return }
    if entry.isDirectory {
        onDoubleClick?(entry)
    } else {
        NSWorkspace.shared.openFile(entry.path)
    }
}

@objc private func copySelected(_ sender: Any?) {
    NotificationCenter.default.post(name: .fileListDidCopy, object: nil, userInfo: ["side": getSide()])
}

@objc private func cutSelected(_ sender: Any?) {
    NotificationCenter.default.post(name: .fileListDidCut, object: nil, userInfo: ["side": getSide()])
}

@objc private func pasteSelected(_ sender: Any?) {
    NotificationCenter.default.post(name: .fileListDidPaste, object: nil, userInfo: ["side": getSide()])
}

@objc private func copyToOtherPane(_ sender: Any?) {
    NotificationCenter.default.post(name: .fileListDidCopyToOther, object: nil, userInfo: ["side": getSide()])
}

@objc private func moveToOtherPane(_ sender: Any?) {
    NotificationCenter.default.post(name: .fileListDidMoveToOther, object: nil, userInfo: ["side": getSide()])
}

@objc private func openInOtherPane(_ sender: Any?) {
    guard let entry = clickedEntry else { return }
    NotificationCenter.default.post(name: .fileListDidOpenInOther, object: nil, userInfo: ["side": getSide(), "path": entry.path])
}

@objc private func renameSelected(_ sender: Any?) {
    guard let entry = clickedEntry else { return }
    let alert = NSAlert()
    alert.messageText = "重命名 \"\(entry.name)\""
    alert.informativeText = "输入新名称："
    alert.alertStyle = .informational
    alert.addButton(withTitle: "重命名")
    alert.addButton(withTitle: "取消")
    let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    textField.stringValue = entry.name
    alert.accessoryView = textField
    if let window = window {
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty, newName != entry.name else { return }
            self?.viewModel?.renameFile(entry.path, to: newName)
        }
    }
}

@objc private func deleteSelected(_ sender: Any?) {
    let entries = viewModel?.selectedFiles ?? []
    guard !entries.isEmpty else { return }
    let alert = NSAlert()
    alert.messageText = entries.count == 1 ? "删除\"\(entries[0].name)\"？" : "删除 \(entries.count) 个项目？"
    alert.informativeText = "此操作无法撤销。"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "删除")
    alert.addButton(withTitle: "取消")
    if let window = window {
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.viewModel?.deleteSelected()
        }
    }
}

@objc private func createDirectory(_ sender: Any?) {
    guard let currentPath = viewModel?.currentPath else { return }
    let alert = NSAlert()
    alert.messageText = "新建文件夹"
    alert.informativeText = "输入文件夹名称："
    alert.alertStyle = .informational
    alert.addButton(withTitle: "创建")
    alert.addButton(withTitle: "取消")
    let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    textField.stringValue = "未命名文件夹"
    textField.selectText(nil)
    alert.accessoryView = textField
    if let window = window {
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let folderName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !folderName.isEmpty else { return }
            let newPath = (currentPath as NSString).appendingPathComponent(folderName)
            do {
                try CoreBridge.shared.createDirectory(path: newPath)
                self?.viewModel?.refresh()
            } catch {
                let errAlert = NSAlert()
                errAlert.messageText = "错误"
                errAlert.informativeText = error.localizedDescription
                errAlert.alertStyle = .critical
                errAlert.addButton(withTitle: "好")
                errAlert.beginSheetModal(for: window) { _ in }
            }
        }
    }
}
```

- [ ] **Step 3: Debug 构建验证**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative
xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Debug build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: 提交**

```bash
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native
git add -A
git commit -m "feat: FileGridView 同步右键菜单与 FileListView 一致

- 新增 setupContextMenu 与 FileListView 完全一致的菜单结构
- 包含跨面板复制/移动/在对侧打开
- 包含重命名/删除/新建文件夹（带 sheet modal）
- clickedEntry 基于 indexPathForItem 实现"
```

---

### Task 5: Release 构建 + 打包

**Files:**
- Build: Release 配置
- Package: .zip + .dmg 输出到 `/Volumes/Iris-Data/Download/AI/文件管理系统/`

- [ ] **Step 1: 构建 Rust Core Release**

```bash
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/rust-core
cargo build --release 2>&1 | tail -5
```

Expected: `Finished release profile`

- [ ] **Step 2: 构建 Swift Release**

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative
xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Release build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: 复制 dylib + 修复 install name + 签名**

```bash
APP_PATH="/Users/waltxao/Library/Developer/Xcode/DerivedData/FlowFinderNative-gfgoldtwzdwmclasnsgrovzztnzq/Build/Products/Release/FlowFinderNative.app"
mkdir -p "$APP_PATH/Contents/Frameworks"
cp /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/rust-core/target/release/libflowfinder_core.dylib "$APP_PATH/Contents/Frameworks/"
install_name_tool -id @executable_path/../Frameworks/libflowfinder_core.dylib "$APP_PATH/Contents/Frameworks/libflowfinder_core.dylib"
# 修复主可执行文件的 dylib 引用
OLD_PATH=$(otool -L "$APP_PATH/Contents/MacOS/FlowFinderNative" | grep flowfinder | head -1 | awk '{print $1}')
if [ -n "$OLD_PATH" ]; then
  install_name_tool -change "$OLD_PATH" @executable_path/../Frameworks/libflowfinder_core.dylib "$APP_PATH/Contents/MacOS/FlowFinderNative"
fi
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --verbose "$APP_PATH" 2>&1 | head -2
```

Expected: `valid on disk` + `satisfies its Designated Requirement`

- [ ] **Step 4: 打包 .zip + .dmg**

```bash
APP_PATH="/Users/waltxao/Library/Developer/Xcode/DerivedData/FlowFinderNative-gfgoldtwzdwmclasnsgrovzztnzq/Build/Products/Release/FlowFinderNative.app"
OUTPUT_DIR="/Volumes/Iris-Data/Download/AI/文件管理系统"
cd "$(dirname "$APP_PATH")"
ditto -c -k --sequesterRsrc --keepParent FlowFinderNative.app "$OUTPUT_DIR/FlowFinderNative_v3.zip"
hdiutil create -volname "FlowFinderNative" -srcfolder "$APP_PATH" -ov -format UDZO "$OUTPUT_DIR/FlowFinderNative_v3.dmg" 2>&1 | tail -2
ls -lh "$OUTPUT_DIR/FlowFinderNative_v3.zip" "$OUTPUT_DIR/FlowFinderNative_v3.dmg"
```

Expected: 两个文件创建成功

- [ ] **Step 5: 最终提交**

```bash
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native
git add -A
git commit -m "build: Release 构建 + 打包 v3

- 跨面板复制/移动/在对侧打开功能完成
- 右键菜单修复 + 面板切换激活
- .zip + .dmg 打包完成"
```
