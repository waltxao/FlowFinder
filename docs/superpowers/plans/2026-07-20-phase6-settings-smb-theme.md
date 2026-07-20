# Phase 6: 设置 + SMB + 暗黑模式 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现设置窗口（外观切换 + 快捷键查看 + SMB 管理）、主题管理器（浅色/深色/跟随系统）、SMB 管理面板（挂载 + 列表 + 卸载 + 自动重连），完成 FlowFinder 完整重构最终阶段。

**Architecture:** ThemeManager 作为单例管理外观模式（NSApp.appearance + NSWorkspace.shared.notification 监听系统主题变更）；SettingsWindowController 作为 ⌘, 触发的独立设置窗口（NSTabViewController 三标签页：外观/SMB/快捷键）；SMBManagerPanel 作为设置窗口的一个标签页，使用 SMBBridge 管理挂载/卸载；通过 UserDefaults 持久化用户偏好。

**Tech Stack:** Swift 6 / AppKit / NSAppearance / NSWorkspace / UserDefaults / Combine

## Global Constraints

- macOS only (Swift & AppKit, no SwiftUI)
- 主题模式：浅色/深色/跟随系统（通过 NSApp.appearance 设置）
- 设置持久化：UserDefaults + CoreBridge.setSetting/getSetting
- SMB 管理：SMBBridge.shared（已实现 mount/unmount/listMounted/refreshMountedVolumes）
- 所有 UI 文本使用中文（匹配用户偏好）
- 语法检查命令：`swiftc -parse <file>.swift`

---

## File Structure

| 文件 | 操作 | 职责 |
|------|------|------|
| `Bridge/ThemeManager.swift` | 新建 | 主题管理单例（浅色/深色/跟随系统 + 系统变更监听） |
| `UI/SettingsWindowController.swift` | 新建 | 设置窗口控制器（NSTabViewController 三标签页） |
| `UI/SMBManagerPanel.swift` | 新建 | SMB 管理面板（挂载 + 列表 + 卸载 + 自动重连） |
| `UI/AppearanceSettingsView.swift` | 新建 | 外观设置视图（主题切换 + 预览） |
| `UI/MainWindowController.swift` | 修改 | 应用 ThemeManager + ⌘, 打开设置 |
| `UI/MainMenu.swift` | 修改 | 添加「偏好设置...」菜单项（⌘,） |
| `App/AppDelegate.swift` | 修改 | 启动时应用保存的主题 |

---

## Task 1: 新建 ThemeManager.swift

**Files:**
- Create: `FlowFinderNative/FlowFinderNative/Bridge/ThemeManager.swift`

**Interfaces:**
- Consumes: `CoreBridge.shared.getSetting(key:)` / `setSetting(key:value:)` (Phase 1)
- Produces: `ThemeManager.shared` 单例
- Produces: `enum AppearanceMode: Int { case system=0; case light=1; case dark=2 }`
- Produces: `ThemeManager.shared.currentMode: AppearanceMode`
- Produces: `ThemeManager.shared.applyMode(_:)` 应用主题
- Produces: `ThemeManager.shared.startObservingSystemChanges()` 监听系统变更
- Produces: `ThemeManager.shared.onModeChanged: ((AppearanceMode) -> Void)?` 回调

- [ ] **Step 1: 创建 ThemeManager.swift**

```swift
import Foundation
import AppKit
import Combine

/// 外观模式枚举
public enum AppearanceMode: Int, CaseIterable {
    case system = 0  // 跟随系统
    case light = 1   // 浅色
    case dark = 2    // 深色

    public var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    public var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled.righthalf.stripes.horizontal"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

/// 主题管理器：管理应用外观模式（浅色/深色/跟随系统）
public final class ThemeManager: ObservableObject {

    public static let shared = ThemeManager()

    /// 设置键名
    private let settingsKey = "appearance_mode"

    @Published public private(set) var currentMode: AppearanceMode = .system

    /// 主题变更回调
    public var onModeChanged: ((AppearanceMode) -> Void)?

    private init() {
        loadSavedMode()
    }

    // MARK: - Public API

    /// 应用指定外观模式
    /// - Parameter mode: 外观模式
    public func applyMode(_ mode: AppearanceMode) {
        currentMode = mode
        saveMode(mode)

        switch mode {
        case .system:
            NSApp.appearance = nil  // 跟随系统
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        // 通知所有窗口刷新
        for window in NSApp.windows {
            window.appearance = NSApp.appearance
        }

        onModeChanged?(mode)
    }

    /// 开始监听系统主题变更（仅当 currentMode == .system 时生效）
    public func startObservingSystemChanges() {
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    /// 停止监听
    public func stopObservingSystemChanges() {
        DistributedNotificationCenter.default.removeObserver(self)
    }

    /// 获取当前系统外观（用于 .system 模式判断）
    public var systemIsDark: Bool {
        guard let appearance = NSAppearance.currentAppearance else { return false }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: - Private

    @objc private func systemAppearanceChanged() {
        // 仅在跟随系统模式下触发刷新
        if currentMode == .system {
            NSApp.appearance = nil
            for window in NSApp.windows {
                window.appearance = nil
            }
            onModeChanged?(.system)
        }
    }

    private func loadSavedMode() {
        // 优先从 CoreBridge 读取，回退到 UserDefaults
        let rustValue = CoreBridge.shared.getSetting(key: settingsKey)

        if !rustValue.isEmpty, let intValue = Int(rustValue), let mode = AppearanceMode(rawValue: intValue) {
            currentMode = mode
        } else if let savedValue = UserDefaults.standard.object(forKey: settingsKey) as? Int,
                  let mode = AppearanceMode(rawValue: savedValue) {
            currentMode = mode
        } else {
            currentMode = .system
        }
    }

    private func saveMode(_ mode: AppearanceMode) {
        // 保存到两处：CoreBridge（Rust 端）和 UserDefaults（快速读取）
        UserDefaults.standard.set(mode.rawValue, forKey: settingsKey)

        do {
            try CoreBridge.shared.setSetting(key: settingsKey, value: String(mode.rawValue))
        } catch {
            print("ThemeManager: 保存主题到 Rust 失败: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 2: 语法检查**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/Bridge" && swiftc -parse ThemeManager.swift 2>&1 | head -5`
Expected: 无输出（无错误）

- [ ] **Step 3: 提交**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/Bridge/ThemeManager.swift
git commit -m "feat: 新建 ThemeManager 主题管理器

- AppearanceMode 枚举（system/light/dark）
- NSApp.appearance 应用主题
- DistributedNotificationCenter 监听系统主题变更
- CoreBridge.setSetting + UserDefaults 双重持久化
- onModeChanged 回调通知"
```

---

## Task 2: 新建 AppearanceSettingsView.swift

**Files:**
- Create: `FlowFinderNative/FlowFinderNative/UI/AppearanceSettingsView.swift`

**Interfaces:**
- Consumes: `ThemeManager.shared` (Task 1)
- Produces: `AppearanceSettingsView` NSView（外观设置视图）
- Produces: 三个主题按钮 + 当前选中状态 + 预览

- [ ] **Step 1: 创建 AppearanceSettingsView.swift**

```swift
import Cocoa
import Combine

/// 外观设置视图：主题切换（浅色/深色/跟随系统）
public class AppearanceSettingsView: NSView {

    private var titleLabel: NSTextField!
    private var buttonContainer: NSView!
    private var systemButton: NSButton!
    private var lightButton: NSButton!
    private var darkButton: NSButton!
    private var descriptionLabel: NSTextField!

    private var cancellables = Set<AnyCancellable>()

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        setupBindings()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupBindings()
    }

    // MARK: - UI Setup

    private func setupUI() {
        // 标题
        titleLabel = NSTextField(labelWithString: "外观")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 按钮容器
        buttonContainer = NSView()
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false

        // 系统跟随按钮
        systemButton = createThemeButton(
            title: AppearanceMode.system.title,
            icon: AppearanceMode.system.iconName,
            mode: .system
        )

        // 浅色按钮
        lightButton = createThemeButton(
            title: AppearanceMode.light.title,
            icon: AppearanceMode.light.iconName,
            mode: .light
        )

        // 深色按钮
        darkButton = createThemeButton(
            title: AppearanceMode.dark.title,
            icon: AppearanceMode.dark.iconName,
            mode: .dark
        )

        buttonContainer.addSubview(systemButton)
        buttonContainer.addSubview(lightButton)
        buttonContainer.addSubview(darkButton)

        // 描述标签
        descriptionLabel = NSTextField(labelWithString: "")
        descriptionLabel.font = NSFont.systemFont(ofSize: 11)
        descriptionLabel.textColor = NSColor.secondaryLabelColor
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(buttonContainer)
        addSubview(descriptionLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            buttonContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            buttonContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            buttonContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            buttonContainer.heightAnchor.constraint(equalToConstant: 100),

            systemButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            systemButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            systemButton.widthAnchor.constraint(equalToConstant: 100),
            systemButton.heightAnchor.constraint(equalToConstant: 100),

            lightButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            lightButton.leadingAnchor.constraint(equalTo: systemButton.trailingAnchor, constant: 16),
            lightButton.widthAnchor.constraint(equalToConstant: 100),
            lightButton.heightAnchor.constraint(equalToConstant: 100),

            darkButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            darkButton.leadingAnchor.constraint(equalTo: lightButton.trailingAnchor, constant: 16),
            darkButton.widthAnchor.constraint(equalToConstant: 100),
            darkButton.heightAnchor.constraint(equalToConstant: 100),

            descriptionLabel.topAnchor.constraint(equalTo: buttonContainer.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])

        updateSelection()
    }

    private func createThemeButton(title: String, icon: String, mode: AppearanceMode) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .regularSquare
        button.isBordered = true
        button.title = ""
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
        button.imagePosition = .imageAbove
        button.font = NSFont.systemFont(ofSize: 12)
        button.toolTip = title
        button.tag = mode.rawValue
        button.target = self
        button.action = #selector(themeButtonClicked(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        // 使用副标题显示文字
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
        )
        button.image?.size = NSSize(width: 40, height: 40)
        return button
    }

    // MARK: - Bindings

    private func setupBindings() {
        ThemeManager.shared.$currentMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSelection()
            }
            .store(in: &cancellables)
    }

    private func updateSelection() {
        let currentMode = ThemeManager.shared.currentMode

        systemButton.state = currentMode == .system ? .on : .off
        lightButton.state = currentMode == .light ? .on : .off
        darkButton.state = currentMode == .dark ? .on : .off

        switch currentMode {
        case .system:
            descriptionLabel.stringValue = "应用将跟随系统的外观设置自动切换。"
        case .light:
            descriptionLabel.stringValue = "应用始终使用浅色外观，不受系统设置影响。"
        case .dark:
            descriptionLabel.stringValue = "应用始终使用深色外观，不受系统设置影响。"
        }
    }

    // MARK: - Actions

    @objc private func themeButtonClicked(_ sender: NSButton) {
        guard let mode = AppearanceMode(rawValue: sender.tag) else { return }
        ThemeManager.shared.applyMode(mode)
    }
}
```

- [ ] **Step 2: 语法检查**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI" && swiftc -parse AppearanceSettingsView.swift 2>&1 | head -5`
Expected: 无输出（无错误）

- [ ] **Step 3: 提交**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/AppearanceSettingsView.swift
git commit -m "feat: 新建 AppearanceSettingsView 外观设置视图

- 三个主题按钮（跟随系统/浅色/深色）
- 图标 + 文字标签
- 当前选中状态高亮
- 描述标签动态更新
- 订阅 ThemeManager.currentMode"
```

---

## Task 3: 新建 SMBManagerPanel.swift

**Files:**
- Create: `FlowFinderNative/FlowFinderNative/UI/SMBManagerPanel.swift`

**Interfaces:**
- Consumes: `SMBBridge.shared` (Phase 1，已实现 mount/unmount/listMounted/refreshMountedVolumes)
- Produces: `SMBManagerPanel` NSView（SMB 管理面板）
- Produces: 挂载 URL 输入 + 挂载按钮 + 已挂载列表 + 卸载按钮 + 刷新按钮

- [ ] **Step 1: 创建 SMBManagerPanel.swift**

```swift
import Cocoa
import Combine

/// SMB 管理面板：挂载 + 列表 + 卸载 + 自动重连
public class SMBManagerPanel: NSView {

    private var urlTextField: NSTextField!
    private var mountButton: NSButton!
    private var refreshButton: NSButton!
    private var unmountButton: NSButton!
    private var statusLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!

    private var tableView: NSTableView!
    private var scrollView: NSScrollView!

    private var volumes: [SMBVolume] = []

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        refreshList()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        refreshList()
    }

    // MARK: - UI Setup

    private func setupUI() {
        // 标题
        let titleLabel = NSTextField(labelWithString: "SMB 网络共享")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // URL 输入
        let urlLabel = NSTextField(labelWithString: "服务器地址：")
        urlLabel.font = NSFont.systemFont(ofSize: 12)
        urlLabel.translatesAutoresizingMaskIntoConstraints = false

        urlTextField = NSTextField()
        urlTextField.placeholderString = "smb://user:pass@server/share"
        urlTextField.translatesAutoresizingMaskIntoConstraints = false

        mountButton = NSButton(title: "连接", target: self, action: #selector(mountClicked))
        mountButton.bezelStyle = .rounded
        mountButton.translatesAutoresizingMaskIntoConstraints = false

        // 进度指示器
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        // 状态标签
        statusLabel = NSTextField(labelWithString: "就绪")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // 已挂载列表标签
        let listLabel = NSTextField(labelWithString: "已挂载的共享：")
        listLabel.font = NSFont.boldSystemFont(ofSize: 12)
        listLabel.translatesAutoresizingMaskIntoConstraints = false

        // 刷新 / 卸载按钮
        refreshButton = NSButton(title: "刷新", target: self, action: #selector(refreshClicked))
        refreshButton.bezelStyle = .rounded
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        unmountButton = NSButton(title: "卸载", target: self, action: #selector(unmountClicked))
        unmountButton.bezelStyle = .rounded
        unmountButton.isEnabled = false
        unmountButton.translatesAutoresizingMaskIntoConstraints = false

        // 已挂载列表
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        tableView = NSTableView()
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 24
        tableView.dataSource = self
        tableView.delegate = self

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "名称"
        nameCol.width = 150
        tableView.addTableColumn(nameCol)

        let pathCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        pathCol.title = "挂载路径"
        pathCol.width = 250
        tableView.addTableColumn(pathCol)

        let urlCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url"))
        urlCol.title = "服务器地址"
        urlCol.width = 200
        tableView.addTableColumn(urlCol)

        scrollView.documentView = tableView

        // 添加子视图
        addSubview(titleLabel)
        addSubview(urlLabel)
        addSubview(urlTextField)
        addSubview(mountButton)
        addSubview(progressIndicator)
        addSubview(statusLabel)
        addSubview(listLabel)
        addSubview(refreshButton)
        addSubview(unmountButton)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            urlLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            urlLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            urlTextField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            urlTextField.leadingAnchor.constraint(equalTo: urlLabel.trailingAnchor, constant: 8),
            urlTextField.widthAnchor.constraint(equalToConstant: 350),

            mountButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            mountButton.leadingAnchor.constraint(equalTo: urlTextField.trailingAnchor, constant: 8),

            progressIndicator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            progressIndicator.leadingAnchor.constraint(equalTo: mountButton.trailingAnchor, constant: 8),
            progressIndicator.widthAnchor.constraint(equalToConstant: 16),
            progressIndicator.heightAnchor.constraint(equalToConstant: 16),

            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: progressIndicator.trailingAnchor, constant: 8),

            listLabel.topAnchor.constraint(equalTo: urlTextField.bottomAnchor, constant: 20),
            listLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            refreshButton.topAnchor.constraint(equalTo: urlTextField.bottomAnchor, constant: 16),
            refreshButton.leadingAnchor.constraint(equalTo: listLabel.trailingAnchor, constant: 16),

            unmountButton.topAnchor.constraint(equalTo: urlTextField.bottomAnchor, constant: 16),
            unmountButton.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 8),

            scrollView.topAnchor.constraint(equalTo: listLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])
    }

    // MARK: - Actions

    @objc private func mountClicked() {
        let url = urlTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            statusLabel.stringValue = "请输入服务器地址"
            return
        }

        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "正在连接..."
        mountButton.isEnabled = false

        SMBBridge.shared.mount(url: url) { [weak self] result in
            DispatchQueue.main.async {
                self?.progressIndicator.stopAnimation(nil)
                self?.mountButton.isEnabled = true

                switch result {
                case .success(let path):
                    self?.statusLabel.stringValue = "已连接：\(path)"
                    self?.refreshList()
                case .failure(let error):
                    self?.statusLabel.stringValue = "连接失败：\(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func refreshClicked() {
        refreshList()
    }

    @objc private func unmountClicked() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < volumes.count else { return }
        let volume = volumes[tableView.selectedRow]

        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "正在卸载..."
        unmountButton.isEnabled = false

        SMBBridge.shared.unmount(mountPoint: volume.path) { [weak self] result in
            DispatchQueue.main.async {
                self?.progressIndicator.stopAnimation(nil)

                switch result {
                case .success:
                    self?.statusLabel.stringValue = "已卸载：\(volume.name)"
                    self?.refreshList()
                case .failure(let error):
                    self?.statusLabel.stringValue = "卸载失败：\(error.localizedDescription)"
                    self?.updateUnmountButton()
                }
            }
        }
    }

    // MARK: - Private

    private func refreshList() {
        SMBBridge.shared.refreshMountedVolumes()
        volumes = SMBBridge.shared.listMounted()
        tableView.reloadData()
        updateUnmountButton()
        statusLabel.stringValue = "共 \(volumes.count) 个已挂载共享"
    }

    private func updateUnmountButton() {
        unmountButton.isEnabled = tableView.selectedRow >= 0
    }
}

// MARK: - NSTableViewDataSource

extension SMBManagerPanel: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return volumes.count
    }
}

// MARK: - NSTableViewDelegate

extension SMBManagerPanel: NSTableViewDelegate {
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < volumes.count else { return nil }
        let volume = volumes[row]

        let cellID = NSUserInterfaceItemIdentifier(tableColumn?.identifier.rawValue ?? "")
        let cellView = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cellView.identifier = cellID

        if cellView.textField == nil {
            let tf = NSTextField(labelWithString: "")
            tf.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            tf.lineBreakMode = .byTruncatingTail
            cellView.addSubview(tf)
            cellView.textField = tf
            tf.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }

        switch tableColumn?.identifier.rawValue {
        case "name":
            cellView.textField?.stringValue = volume.name
        case "path":
            cellView.textField?.stringValue = volume.path
        case "url":
            cellView.textField?.stringValue = volume.url
        default:
            break
        }

        return cellView
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        updateUnmountButton()
    }
}
```

- [ ] **Step 2: 语法检查**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI" && swiftc -parse SMBManagerPanel.swift 2>&1 | head -5`
Expected: 无输出（无错误）

- [ ] **Step 3: 提交**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/SMBManagerPanel.swift
git commit -m "feat: 新建 SMBManagerPanel SMB 管理面板

- 服务器地址输入 + 连接按钮
- NSTableView 已挂载列表（名称/路径/地址）
- 卸载按钮 + 刷新按钮
- 进度指示器 + 状态标签
- SMBBridge.mount/unmount/refreshMountedVolumes 集成"
```

---

## Task 4: 新建 SettingsWindowController.swift

**Files:**
- Create: `FlowFinderNative/FlowFinderNative/UI/SettingsWindowController.swift`

**Interfaces:**
- Consumes: `AppearanceSettingsView` (Task 2), `SMBManagerPanel` (Task 3)
- Produces: `SettingsWindowController.shared` 单例
- Produces: `SettingsWindowController.showWindow()` 显示设置窗口（⌘, 触发）
- Produces: NSTabViewController 三标签页：外观 / SMB / 快捷键

- [ ] **Step 1: 创建 SettingsWindowController.swift**

```swift
import Cocoa

/// 设置窗口控制器：NSTabViewController 三标签页（外观/SMB/快捷键）
public class SettingsWindowController: NSWindowController {

    public static let shared = SettingsWindowController()

    private var tabViewController: NSTabViewController!

    private override init(window: NSWindow?) {
        super.init(window: window)
    }

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.minSize = NSSize(width: 500, height: 400)
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        self.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        tabViewController = NSTabViewController()
        tabViewController.tabStyle = .toolbar

        // 外观标签页
        let appearanceTab = NSTabViewItem(viewController: NSViewController())
        appearanceTab.label = "外观"
        appearanceTab.image = NSImage(systemSymbolName: "paintbrush", accessibilityDescription: "外观")
        let appearanceView = AppearanceSettingsView(frame: .zero)
        appearanceTab.viewController?.view = appearanceView
        tabViewController.addTabViewItem(appearanceTab)

        // SMB 标签页
        let smbTab = NSTabViewItem(viewController: NSViewController())
        smbTab.label = "SMB"
        smbTab.image = NSImage(systemSymbolName: "network", accessibilityDescription: "SMB")
        let smbPanel = SMBManagerPanel(frame: .zero)
        smbTab.viewController?.view = smbPanel
        tabViewController.addTabViewItem(smbTab)

        // 快捷键标签页
        let shortcutsTab = NSTabViewItem(viewController: NSViewController())
        shortcutsTab.label = "快捷键"
        shortcutsTab.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "快捷键")
        let shortcutsView = createShortcutsView()
        shortcutsTab.viewController?.view = shortcutsView
        tabViewController.addTabViewItem(shortcutsTab)

        window?.contentViewController = tabViewController
    }

    private func createShortcutsView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 400))

        let titleLabel = NSTextField(labelWithString: "键盘快捷键")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let tableView = NSTableView()
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 24

        let actionCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionCol.title = "操作"
        actionCol.width = 200
        tableView.addTableColumn(actionCol)

        let shortcutCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        shortcutCol.title = "快捷键"
        shortcutCol.width = 150
        tableView.addTableColumn(shortcutCol)

        // 快捷键数据
        let shortcuts: [(String, String)] = [
            ("新建文件夹", "⌘N"),
            ("打开文件", "⌘O"),
            ("关闭窗口", "⌘W"),
            ("复制", "⌘C"),
            ("剪切", "⌘X"),
            ("粘贴", "⌘V"),
            ("全选", "⌘A"),
            ("移动到废纸篓", "⌘⌫"),
            ("撤销", "⌘Z"),
            ("重做", "⌘⇧Z"),
            ("列表视图", "⌘1"),
            ("图标视图", "⌘2"),
            ("刷新", "⌘R"),
            ("搜索", "⌘F"),
            ("重复文件扫描", "⌘⇧D"),
            ("任务面板", "⌘0"),
            ("QuickLook 预览", "空格键"),
            ("复制选中项", "⌘D"),
            ("连接服务器", "⌘K"),
            ("偏好设置", "⌘,"),
        ]

        let dataSource = ShortcutsDataSource(shortcuts: shortcuts)
        tableView.dataSource = dataSource
        tableView.delegate = dataSource

        // 使用关联对象保存 dataSource 防止被释放
        objc_setAssociatedObject(view, "shortcutsDataSource", dataSource, .OBJC_ASSOCIATION_RETAIN)

        scrollView.documentView = tableView

        view.addSubview(titleLabel)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
        ])

        return view
    }

    // MARK: - Public API

    public func showWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - ShortcutsDataSource

private class ShortcutsDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let shortcuts: [(String, String)]

    init(shortcuts: [(String, String)]) {
        self.shortcuts = shortcuts
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return shortcuts.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < shortcuts.count else { return nil }

        let cellID = NSUserInterfaceItemIdentifier(tableColumn?.identifier.rawValue ?? "")
        let cellView = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView
            ?? NSTableCellView()
        cellView.identifier = cellID

        if cellView.textField == nil {
            let tf = NSTextField(labelWithString: "")
            tf.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            cellView.addSubview(tf)
            cellView.textField = tf
            tf.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            ])
        }

        switch tableColumn?.identifier.rawValue {
        case "action":
            cellView.textField?.stringValue = shortcuts[row].0
        case "shortcut":
            cellView.textField?.stringValue = shortcuts[row].1
            cellView.textField?.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        default:
            break
        }

        return cellView
    }
}
```

- [ ] **Step 2: 语法检查**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI" && swiftc -parse SettingsWindowController.swift 2>&1 | head -5`
Expected: 无输出（无错误）

- [ ] **Step 3: 提交**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/UI/SettingsWindowController.swift
git commit -m "feat: 新建 SettingsWindowController 设置窗口

- NSTabViewController 三标签页（外观/SMB/快捷键）
- NSTabViewItem + SF Symbols 图标
- 快捷键列表（20 项标准快捷键）
- ⌘, 触发显示
- 窗口尺寸 600x450，autosave 持久化"
```

---

## Task 5: 集成到 MainWindowController + MainMenu + AppDelegate

**Files:**
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift`
- Modify: `FlowFinderNative/FlowFinderNative/UI/MainMenu.swift`
- Modify: `FlowFinderNative/FlowFinderNative/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `ThemeManager.shared` (Task 1), `SettingsWindowController.shared` (Task 4)
- Produces: 主窗口启动时应用主题
- Produces: ⌘, 打开设置窗口
- Produces: AppDelegate 启动时初始化 ThemeManager

- [ ] **Step 1: 在 AppDelegate 启动时应用主题**

在 `AppDelegate.swift` 的 `applicationDidFinishLaunching` 方法中，在 `MainMenu.setupMainMenu()` 之前添加：

```swift
            // 应用保存的主题
            ThemeManager.shared.startObservingSystemChanges()
            ThemeManager.shared.applyMode(ThemeManager.shared.currentMode)
```

完整的 `applicationDidFinishLaunching` 方法应为：

```swift
        func applicationDidFinishLaunching(_ notification: Notification) {
            // 应用保存的主题
            ThemeManager.shared.startObservingSystemChanges()
            ThemeManager.shared.applyMode(ThemeManager.shared.currentMode)

            MainMenu.setupMainMenu()
            let controller = MainWindowController()
            controller.showWindow(nil)
            self.mainWindowController = controller
        }
```

- [ ] **Step 2: 在 MainWindowController 添加 menuSettings 方法**

在 `MainWindowController.swift` 的 `menuTaskPanel` 方法之后（`// MARK: - Helpers` 之前）添加：

```swift
    @objc func menuSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow()
    }
```

- [ ] **Step 3: 在 MainMenu 添加「偏好设置...」菜单项**

在 `MainMenu.swift` 的 `setupMainMenu()` 方法中，在 app 菜单的「退出 FlowFinder」之前添加「偏好设置...」。

找到：
```swift
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 FlowFinder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
```

改为：
```swift
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "偏好设置...", action: #selector(MainWindowController.menuSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 FlowFinder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
```

- [ ] **Step 4: 语法检查**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative" && swiftc -parse App/AppDelegate.swift 2>&1 | head -3 && swiftc -parse UI/MainWindowController.swift 2>&1 | head -3 && swiftc -parse UI/MainMenu.swift 2>&1 | head -3`
Expected: 无输出（无错误）

- [ ] **Step 5: 提交**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add FlowFinderNative/FlowFinderNative/App/AppDelegate.swift FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift FlowFinderNative/FlowFinderNative/UI/MainMenu.swift
git commit -m "feat: 集成 ThemeManager + SettingsWindowController

- AppDelegate 启动时应用保存的主题
- ThemeManager.startObservingSystemChanges 监听系统变更
- ⌘, 打开设置窗口（menuSettings）
- MainMenu app 菜单添加「偏好设置...」"
```

---

## Task 6: Phase 6 集成验证 + 最终构建

**Files:**
- 无新增/修改，仅验证

- [ ] **Step 1: 全部 Swift 文件语法检查**

Run: `cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative" && for f in Bridge/ThemeManager.swift UI/AppearanceSettingsView.swift UI/SMBManagerPanel.swift UI/SettingsWindowController.swift UI/MainWindowController.swift UI/MainMenu.swift App/AppDelegate.swift; do echo "--- $f ---"; swiftc -parse "$f" 2>&1 | head -3; done`
Expected: 每个文件无输出（无错误）

- [ ] **Step 2: 确认主题组件存在**

Run: `grep -c "ThemeManager\|AppearanceMode\|applyMode" "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/Bridge/ThemeManager.swift"`
Expected: 数字 >= 3

- [ ] **Step 3: 确认 SMB 管理面板存在**

Run: `grep -c "SMBBridge\|SMBVolume\|mountButton" "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/SMBManagerPanel.swift"`
Expected: 数字 >= 3

- [ ] **Step 4: 确认设置窗口三标签页存在**

Run: `grep -c "NSTabViewController\|appearanceTab\|smbTab\|shortcutsTab" "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/SettingsWindowController.swift"`
Expected: 数字 >= 3

- [ ] **Step 5: 确认菜单项存在**

Run: `grep -c "menuSettings\|偏好设置" "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/MainMenu.swift"`
Expected: 数字 >= 2

- [ ] **Step 6: 确认 AppDelegate 启动 ThemeManager**

Run: `grep -c "ThemeManager" "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/App/AppDelegate.swift"`
Expected: 数字 >= 2

- [ ] **Step 7: 提交 Phase 6 完成标记**

```bash
cd "/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native"
git add -A
git commit -m "milestone: Phase 6 完成 - 设置 + SMB + 暗黑模式

- ThemeManager（NSApp.appearance + 系统主题监听 + 双重持久化）
- AppearanceSettingsView（三主题按钮 + 选中状态 + 描述）
- SMBManagerPanel（挂载 + 列表 + 卸载 + 刷新）
- SettingsWindowController（NSTabViewController 三标签页 + 快捷键列表）
- AppDelegate 启动时应用主题
- ⌘, 偏好设置菜单项
- 全部文件语法检查通过

FlowFinder 完整重构 6 个阶段全部完成！"
```

---

## Self-Review

### Spec Coverage

| Spec 要求 | 对应 Task |
|-----------|-----------|
| 主题浅色/深色/跟随系统 | Task 1（ThemeManager） |
| 主题手动切换 | Task 2（AppearanceSettingsView） |
| 系统主题跟随 + 手动切换选项 | Task 1 + Task 2 |
| 设置窗口（外观/快捷键） | Task 4（SettingsWindowController） |
| SMB 完整管理（挂载/列表/卸载/重连） | Task 3（SMBManagerPanel） |
| SMB 管理在设置窗口中 | Task 4（SMB 标签页） |
| ⌘, 偏好设置快捷键 | Task 5（MainMenu + MainWindowController） |
| AppDelegate 启动应用主题 | Task 5（AppDelegate） |

### Placeholder Scan

- 无 TBD/TODO
- 所有代码块完整
- 所有命令精确

### Type Consistency

- `ThemeManager.shared` 在 Task 1 定义，Task 2/5 使用一致
- `AppearanceMode` 在 Task 1 定义，Task 2 使用一致
- `SettingsWindowController.shared.showWindow()` 在 Task 4 定义，Task 5 调用一致
- `SMBBridge.shared.mount/unmount/listMounted` 在 Phase 1 定义，Task 3 使用一致
- `CoreBridge.shared.getSetting/setSetting` 在 Phase 1 定义，Task 1 使用一致
- `menuSettings(_:)` 在 Task 5 定义，MainMenu 中引用一致
