import AppKit
import Combine

// MARK: - FFOpaqueContainerView

/// 实体背景容器：背景色由 layer.backgroundColor 提供（各窗口控制器自行设置动态色）。
/// 注意：isOpaque 必须返回 false——isOpaque=true 会告知 AppKit「本视图内容不变，可缓存」，
/// 主题切换时系统会跳过该视图及子树的自动重绘，导致深色模式下窗口内容不跟随（视觉不变）。
/// 背景色跟随主题由各窗口在 .appearanceChanged 时重设 layer.backgroundColor 保证。
class FFOpaqueContainerView: NSView {
    override var isOpaque: Bool { return false }
}

// MARK: - FFNotificationNames

/// 统一管理所有自定义 Notification.Name 常量
/// 消除散布在各文件中的字符串字面量
/// 注意：fileList* 系列通知定义在 FileListView.swift 的 extension 中，此处仅补充未定义的
extension Notification.Name {
    // 窗口/视图相关
    static let openSettings = Notification.Name("OpenSettings")
    static let refreshHiddenFiles = Notification.Name("refreshHiddenFiles")
    static let appearanceChanged = Notification.Name("AppearanceChanged")
    // v0.6.9: 文件夹显示配置变更通知
    static let refreshFileTags = Notification.Name("refreshFileTags")
    static let refreshFileExtensions = Notification.Name("refreshFileExtensions")
    static let refreshSystemFiles = Notification.Name("refreshSystemFiles")

    // 任务相关
    static let taskProgressUpdated = Notification.Name("TaskProgressUpdated")
    static let taskCompleted = Notification.Name("TaskCompleted")

    // 标签相关
    static let fileListAddTag = Notification.Name("FileListAddTag")
    // 文件内容变更（重命名等数量不变的操作）→ 列表/网格强制刷新
    static let fileListContentChanged = Notification.Name("FileListContentChanged")

    // SMB 网络卷断连重连
    static let smbVolumeDisconnected = Notification.Name("SMBVolumeDisconnected")
    static let smbVolumeReconnected = Notification.Name("SMBVolumeReconnected")
    static let smbVolumeReconnectFailed = Notification.Name("SMBVolumeReconnectFailed")

    // 快捷键设置变更（设置页录制保存后广播；MainMenu 监听后刷新菜单快捷键）
    static let shortcutsChanged = Notification.Name("FFShortcutsChanged")
}

// MARK: - FFUserDefaultsKeys

/// 统一管理所有 UserDefaults key 常量
/// 消除散布在各文件中的字符串字面量
enum FFUserDefaultsKeys {
    static let showHiddenFiles = "show_hidden_files"
    static let themeMode = "appearance_mode"
    // v0.6.9: 文件夹显示配置
    static let showFileTags = "show_file_tags"
    static let showFileExtensions = "show_file_extensions"
    static let showSystemFiles = "show_system_files"

    // 设置页：通用
    static let startupLocation = "startup_location"
    static let checkUpdateOnStartup = "check_update_on_startup"
    static let defaultViewMode = "default_view_mode"
    static let confirmFileOperations = "confirm_file_operations"
    static let defaultFileBehavior = "default_file_behavior"
    // 设置页：文件管理
    static let folderFirstSort = "folder_first_sort"
    static let keepSelectionPosition = "keep_selection_position"
    // 设置页：SMB
    static let smbDefaultDomain = "smb_default_domain"
    static let smbAutoReconnect = "smb_auto_reconnect"
    // 设置页：快捷键（MainMenu 读取并应用到菜单项）
    static let shortcutNewFolder = "shortcut_new_folder"
    static let shortcutOpenFile = "shortcut_open_file"
    static let shortcutCloseWindow = "shortcut_close_window"
    static let shortcutCopy = "shortcut_copy"
    static let shortcutCut = "shortcut_cut"
    static let shortcutPaste = "shortcut_paste"
    static let shortcutSelectAll = "shortcut_select_all"
    static let shortcutTrash = "shortcut_trash"
    static let shortcutUndo = "shortcut_undo"
    static let shortcutRedo = "shortcut_redo"
    static let shortcutListView = "shortcut_list_view"
    static let shortcutGridView = "shortcut_grid_view"
    static let shortcutRefresh = "shortcut_refresh"
    static let shortcutSearch = "shortcut_search"
    static let shortcutDuplicateScan = "shortcut_duplicate_scan"
    static let shortcutTaskPanel = "shortcut_task_panel"
    static let shortcutQuicklook = "shortcut_quicklook"
    static let shortcutDuplicate = "shortcut_duplicate"
    static let shortcutConnectServer = "shortcut_connect_server"
    static let shortcutPreferences = "shortcut_preferences"
    // 标签（侧边栏/设置页/标签弹窗共享存储）
    static let sidebarTags = "SidebarTags"

    // 任务 T12: 删除确认"不再询问"开关（全入口统一读取；勾选后跳过确认弹窗直接执行）
    static let deleteConfirmDisabled = "delete_confirm_disabled"
}

// MARK: - FFAccent（应用级强调色源）

/// 应用级强调色：替代 NSColor.controlAccentColor（系统色，AppKit 不允许应用层覆盖）。
/// 由设置页「强调色」写入 UserDefaults key "accent_color"（hex 字符串），FFAccent.current 读取并广播刷新。
/// 全应用所有「强调色」UI 引用统一改为 FFAccent.current，这样设置改动即可全应用即时生效。
/// 默认值 "#0a84ff"（系统强调色蓝），与 macOS 默认一致。
enum FFAccent {
    /// UserDefaults key（hex 字符串，如 "#bf5af2"）
    static let storageKey = "accent_color"
    /// 默认强调色（系统蓝）
    static let defaultHex = "#0a84ff"

    /// 当前强调色。每次读取都从 UserDefaults 取最新值，保证设置改动即时生效。
    static var current: NSColor {
        let hex = UserDefaults.standard.string(forKey: storageKey) ?? defaultHex
        return NSColor(hex: hex) ?? .controlAccentColor
    }

    /// 当前 hex 字符串（供 UI 颜色选择器高亮选中项）
    static var currentHex: String {
        UserDefaults.standard.string(forKey: storageKey) ?? defaultHex
    }

    /// 设置新强调色并广播刷新全应用。
    /// 由设置页「强调色」颜色选择器调用。
    static func set(hex: String) {
        UserDefaults.standard.set(hex, forKey: storageKey)
        NotificationCenter.default.post(name: .accentColorChanged, object: nil, userInfo: ["hex": hex])
    }
}

extension Notification.Name {
    /// 强调色变更通知（由 FFAccent.set 广播，监听者收到后刷新 UI）
    static let accentColorChanged = Notification.Name("FFAccentColorChanged")
}

// MARK: - FFPaneMenuBuilder（列表/网格视图共享右键菜单）

/// 统一构建文件面板右键菜单：FileListView 与 FileGridView 共用同一套菜单结构与 action
/// （架构统一：两种视图只是排列方式不同，右键操作完全一致）。
/// 所有 item 的 action 用 Selector 字符串引用，target 传入 FFPaneActionsController
/// （v0.7.3 起两个视图的操作统一委托给控制器实现，运行时按 selector 分派到控制器）。
enum FFPaneMenuBuilder {

    /// 构建右键菜单
    /// - Parameters:
    ///   - target: 接收 action 的对象（通常为 FFPaneActionsController，需实现全部 selector）
    ///   - isLeft: 当前面板是否为左侧（决定"移动到/复制到另一面板"箭头方向）
    ///   - tagsSubmenu: 标签二级菜单（nil 则不添加标签项）
    static func buildMenu(for target: AnyObject, isLeft: Bool, tagsSubmenu: NSMenu?) -> NSMenu {
        let menu = NSMenu()

        // v0.7.4 修订 2：撤销/重做项（默认隐藏，有可撤销/重做操作时由 menuNeedsUpdate 显示）
        // 标题动态更新为"撤销 X"/"重做 X"，如"撤销删除"、"重做删除"
        // tag 100=撤销, 101=重做（用 tag 识别避免标题变化后匹配失败）
        let undoItem = menu.addItem(withTitle: "撤销", action: Selector("undoFromMenu:"), keyEquivalent: "z")
        undoItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "撤销")
        undoItem.isHidden = true
        undoItem.tag = 100
        let redoItem = menu.addItem(withTitle: "重做", action: Selector("redoFromMenu:"), keyEquivalent: "Z")
        redoItem.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "重做")
        redoItem.isHidden = true
        redoItem.tag = 101
        menu.addItem(.separator())

        // 1. 打开
        menu.addItem(withTitle: "打开", action: Selector("openSelected:"), keyEquivalent: "")
        // 2. 分隔线
        menu.addItem(.separator())
        // 3. 复制
        let copyItem = menu.addItem(withTitle: "复制", action: Selector("copySelected:"), keyEquivalent: "c")
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制")
        // 4. 剪切
        let cutItem = menu.addItem(withTitle: "剪切", action: Selector("cutSelected:"), keyEquivalent: "x")
        cutItem.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "剪切")
        // 5. 粘贴
        let pasteItem = menu.addItem(withTitle: "粘贴", action: Selector("pasteSelected:"), keyEquivalent: "v")
        pasteItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "粘贴")
        // 6. 分隔线
        menu.addItem(.separator())
        // 7. 移动到另一面板（箭头方向随面板）
        let moveItem = menu.addItem(withTitle: "移动到另一面板", action: Selector("moveToOtherPane:"), keyEquivalent: "")
        moveItem.image = NSImage(systemSymbolName: isLeft ? "arrow.right" : "arrow.left",
                                 accessibilityDescription: "移动到另一面板")
        // 8. 复制到另一面板
        let copyOtherItem = menu.addItem(withTitle: "复制到另一面板", action: Selector("copyToOtherPane:"), keyEquivalent: "")
        copyOtherItem.image = NSImage(systemSymbolName: isLeft ? "arrow.right.square" : "arrow.left.square",
                                      accessibilityDescription: "复制到另一面板")
        // 9. 在对侧面板打开（仅文件夹，由 menuNeedsUpdate 动态显示）
        let openOtherItem = menu.addItem(withTitle: "在对侧面板打开", action: Selector("openInOtherPane:"), keyEquivalent: "")
        openOtherItem.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "在对侧面板打开")
        openOtherItem.isHidden = true
        // 10. 分隔线
        menu.addItem(.separator())
        // 11. 重命名
        let renameItem = menu.addItem(withTitle: "重命名", action: Selector("renameSelected:"), keyEquivalent: "")
        renameItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "重命名")
        // 12. 移到废纸篓（红色文字）
        let deleteItem = menu.addItem(withTitle: "移到废纸篓", action: Selector("deleteSelected:"), keyEquivalent: "\u{7F}")
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "移到废纸篓")
        let redAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
        deleteItem.attributedTitle = NSAttributedString(string: "移到废纸篓", attributes: redAttrs)
        // 13. 分隔线
        menu.addItem(.separator())
        // 14. 新建文件夹
        let newFolderItem = menu.addItem(withTitle: "新建文件夹", action: Selector("createDirectory:"), keyEquivalent: "n")
        newFolderItem.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "新建文件夹")
        // 15. 用所选项目新建文件夹（选中数量在 menuNeedsUpdate 中动态更新标题）
        // v0.7.4 项 6：标题 "用所选 X 个项目新建文件夹"，X 由 updateMainMenu 填充
        let folderFromSelectionItem = menu.addItem(
            withTitle: "用所选项目新建文件夹",
            action: Selector("createFolderFromSelection:"),
            keyEquivalent: ""
        )
        folderFromSelectionItem.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "用所选项目新建文件夹")
        folderFromSelectionItem.isHidden = true  // 无选中时隐藏，由 updateMainMenu 控制
        // 16. 分隔线
        menu.addItem(.separator())
        // 17. 添加到我的收藏
        let favItem = menu.addItem(withTitle: "添加到我的收藏", action: Selector("addToFavorites:"), keyEquivalent: "")
        favItem.image = NSImage(systemSymbolName: "star", accessibilityDescription: "添加到我的收藏")
        // 18. 标签（二级菜单）
        if let tagsSubmenu = tagsSubmenu {
            let tagsItem = menu.addItem(withTitle: "标签", action: nil, keyEquivalent: "")
            tagsItem.image = NSImage(systemSymbolName: "tag", accessibilityDescription: "标签")
            tagsItem.submenu = tagsSubmenu
        }
        // 19. AI 自动打标签
        let aiTagItem = menu.addItem(withTitle: "AI 自动打标签", action: Selector("generateAITags:"), keyEquivalent: "")
        aiTagItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI 自动打标签")
        // 20. 查重扫描
        let dupItem = menu.addItem(withTitle: "查重扫描", action: Selector("duplicateScan:"), keyEquivalent: "")
        dupItem.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "查重扫描")
        // 21. 分隔线
        menu.addItem(.separator())
        // 22. 显示简介
        let infoItem = menu.addItem(withTitle: "显示简介", action: Selector("showInfoMenu:"), keyEquivalent: "i")
        infoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "显示简介")

        // 设置 target 与快捷键修饰键（与访达一致：⌘N 新建文件夹用 ⇧⌘N）
        for item in menu.items where item.action != nil {
            item.target = target
            if item.keyEquivalent == "n" {
                item.keyEquivalentModifierMask = [.command, .shift]
            } else if !item.keyEquivalent.isEmpty {
                item.keyEquivalentModifierMask = .command
            }
        }
        return menu
    }
}

// MARK: - FFPaneStateOverlayView（任务 T12：统一加载/空/错误/操作状态视图）

/// 面板状态呈现模式。
enum FFPaneOverlayMode: Equatable {
    case content        // 正常内容，overlay 隐藏
    case loading        // 加载中（列表为空时全屏）
    case empty          // 空状态（全屏）
    case error          // 错误（列表为空时全屏，否则顶部横幅）
    case operation      // 删除/撤销/重做进行中（顶部横幅，不遮挡列表）
}

/// 错误/空状态下的"重试"语义。
enum FFPaneRetryKind: Equatable {
    case none           // 无重试
    case reload         // 重新加载目录（refresh）
    case deleteRetry    // 重试删除失败项（deleteSelected，失败项仍保留在选中集）
}

/// 面板状态 → 呈现描述（纯函数，由 PaneState 真值驱动，不复制业务状态）。
struct FFPaneStateDescriptor: Equatable {
    let mode: FFPaneOverlayMode
    let isFullScreen: Bool
    let iconName: String
    let title: String
    let subtitle: String
    let showsSpinner: Bool
    let showsRetry: Bool
    let retryKind: FFPaneRetryKind

    /// 由 PaneState 计算呈现描述。优先级：删除中 > 错误 > 加载 > 空 > 内容。
    /// - 删除中：顶部横幅进度（不遮挡列表）
    /// - 错误 + 列表为空：全屏错误 + 重试
    /// - 错误 + 列表非空（删除部分失败）：顶部横幅 + 重试删除失败项
    /// - 加载 + 列表为空：全屏加载
    /// - 列表为空：区分首次无路径 / 搜索无结果 / 标签筛选 / 文件夹为空
    static func make(from state: PaneState) -> FFPaneStateDescriptor {
        if state.isDeleting {
            let count = state.selectedFiles.count
            return FFPaneStateDescriptor(
                mode: .operation, isFullScreen: false,
                iconName: "arrow.triangle.2.circlepath",
                title: count > 0 ? "正在删除 \(count) 个项目…" : "正在处理文件操作…",
                subtitle: "操作在后台执行，完成后列表自动更新",
                showsSpinner: true, showsRetry: false, retryKind: .none
            )
        }

        if let error = state.error {
            if state.files.isEmpty {
                let retryKind: FFPaneRetryKind = state.deleteFailedPaths.isEmpty ? .reload : .deleteRetry
                return FFPaneStateDescriptor(
                    mode: .error, isFullScreen: true, iconName: "exclamationmark.triangle",
                    title: "无法加载此文件夹", subtitle: error,
                    showsSpinner: false, showsRetry: true, retryKind: retryKind
                )
            }
            let failedCount = state.deleteFailedPaths.count
            return FFPaneStateDescriptor(
                mode: .error, isFullScreen: false, iconName: "exclamationmark.triangle",
                title: failedCount > 0 ? "\(failedCount) 个项目删除失败" : "操作失败",
                subtitle: error,
                showsSpinner: false, showsRetry: true,
                retryKind: failedCount > 0 ? .deleteRetry : .reload
            )
        }

        if state.isLoading && state.files.isEmpty {
            return FFPaneStateDescriptor(
                mode: .loading, isFullScreen: true, iconName: "",
                title: "正在加载…", subtitle: "",
                showsSpinner: true, showsRetry: false, retryKind: .none
            )
        }

        if state.files.isEmpty {
            if state.path.isEmpty {
                return FFPaneStateDescriptor(
                    mode: .empty, isFullScreen: true, iconName: "sidebar.left",
                    title: "打开一个文件夹",
                    subtitle: "在侧边栏选择一个文件夹开始浏览",
                    showsSpinner: false, showsRetry: false, retryKind: .none
                )
            }
            if !state.searchQuery.isEmpty {
                return FFPaneStateDescriptor(
                    mode: .empty, isFullScreen: true, iconName: "magnifyingglass",
                    title: "未找到匹配项",
                    subtitle: "没有名称与「\(state.searchQuery)」匹配的项目",
                    showsSpinner: false, showsRetry: false, retryKind: .none
                )
            }
            if state.tagFilter != nil {
                return FFPaneStateDescriptor(
                    mode: .empty, isFullScreen: true, iconName: "tag",
                    title: "没有符合所选标签的项目",
                    subtitle: "移除标签筛选或选择其他标签",
                    showsSpinner: false, showsRetry: false, retryKind: .none
                )
            }
            return FFPaneStateDescriptor(
                mode: .empty, isFullScreen: true, iconName: "folder",
                title: "此文件夹为空",
                subtitle: "将文件拖到这里开始整理",
                showsSpinner: false, showsRetry: false, retryKind: .none
            )
        }

        return FFPaneStateDescriptor(
            mode: .content, isFullScreen: false, iconName: "",
            title: "", subtitle: "",
            showsSpinner: false, showsRetry: false, retryKind: .none
        )
    }
}

/// 面板状态浮层视图：全屏（loading/empty/error）+ 顶部横幅（operation/删除部分失败）。
/// 由 PaneState 真值驱动：自行订阅 viewModel.$state（主线程），状态回 content 时隐藏。
/// 不遮挡列表布局——浮层是独立叠加层，列表布局与约束不受任何状态切换影响。
final class FFPaneStateOverlayView: NSView {

    weak var viewModel: PaneViewModel? {
        didSet {
            cancellable?.cancel()
            guard let viewModel = viewModel else {
                apply(FFPaneStateDescriptor.make(from: PaneState()))
                return
            }
            cancellable = viewModel.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.apply(FFPaneStateDescriptor.make(from: state))
                }
            apply(FFPaneStateDescriptor.make(from: viewModel.state))
        }
    }

    private var cancellable: AnyCancellable?
    private let fullStack = NSStackView()
    private let fullSpinner = NSProgressIndicator()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    private let bannerView = NSView()
    private let bannerSpinner = NSProgressIndicator()
    private let bannerIcon = NSImageView()
    private let bannerLabel = NSTextField(labelWithString: "")
    private let bannerSubtitle = NSTextField(labelWithString: "")
    private let bannerRetryButton = NSButton(title: "重试", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        apply(FFPaneStateDescriptor.make(from: PaneState()))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        apply(FFPaneStateDescriptor.make(from: PaneState()))
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        fullSpinner.style = .spinning
        fullSpinner.controlSize = .regular
        fullSpinner.isDisplayedWhenStopped = false
        fullSpinner.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = NSColor.secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = NSColor.secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 3
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        retryButton.bezelStyle = .rounded
        retryButton.controlSize = .small
        retryButton.font = NSFont.systemFont(ofSize: 11)
        retryButton.target = self
        retryButton.action = #selector(retryTapped)

        fullStack.orientation = .vertical
        fullStack.alignment = .centerX
        fullStack.spacing = 8
        fullStack.translatesAutoresizingMaskIntoConstraints = false
        fullStack.addArrangedSubview(fullSpinner)
        fullStack.addArrangedSubview(iconView)
        fullStack.addArrangedSubview(titleLabel)
        fullStack.addArrangedSubview(subtitleLabel)
        fullStack.addArrangedSubview(retryButton)

        bannerView.wantsLayer = true
        bannerView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.98).cgColor
        bannerView.translatesAutoresizingMaskIntoConstraints = false

        bannerSpinner.style = .spinning
        bannerSpinner.controlSize = .small
        bannerSpinner.isDisplayedWhenStopped = false
        bannerSpinner.translatesAutoresizingMaskIntoConstraints = false

        bannerIcon.imageScaling = .scaleProportionallyDown
        bannerIcon.contentTintColor = NSColor.systemYellow
        bannerIcon.translatesAutoresizingMaskIntoConstraints = false

        bannerLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        bannerLabel.textColor = NSColor.labelColor
        bannerLabel.lineBreakMode = .byTruncatingTail
        bannerLabel.translatesAutoresizingMaskIntoConstraints = false

        bannerSubtitle.font = NSFont.systemFont(ofSize: 10)
        bannerSubtitle.textColor = NSColor.secondaryLabelColor
        bannerSubtitle.lineBreakMode = .byTruncatingMiddle
        bannerSubtitle.translatesAutoresizingMaskIntoConstraints = false

        bannerRetryButton.bezelStyle = .rounded
        bannerRetryButton.controlSize = .small
        bannerRetryButton.font = NSFont.systemFont(ofSize: 10)
        bannerRetryButton.target = self
        bannerRetryButton.action = #selector(retryTapped)

        bannerView.addSubview(bannerSpinner)
        bannerView.addSubview(bannerIcon)
        bannerView.addSubview(bannerLabel)
        bannerView.addSubview(bannerSubtitle)
        bannerView.addSubview(bannerRetryButton)

        addSubview(fullStack)
        addSubview(bannerView)

        NSLayoutConstraint.activate([
            fullStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            fullStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            fullStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            fullStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            fullSpinner.widthAnchor.constraint(equalToConstant: 24),
            fullSpinner.heightAnchor.constraint(equalToConstant: 24),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            bannerView.topAnchor.constraint(equalTo: topAnchor),
            bannerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            bannerSpinner.leadingAnchor.constraint(equalTo: bannerView.leadingAnchor, constant: 12),
            bannerSpinner.centerYAnchor.constraint(equalTo: bannerView.centerYAnchor, constant: -8),
            bannerIcon.leadingAnchor.constraint(equalTo: bannerView.leadingAnchor, constant: 12),
            bannerIcon.centerYAnchor.constraint(equalTo: bannerView.centerYAnchor, constant: -8),
            bannerIcon.widthAnchor.constraint(equalToConstant: 14),
            bannerIcon.heightAnchor.constraint(equalToConstant: 14),

            bannerLabel.leadingAnchor.constraint(equalTo: bannerSpinner.trailingAnchor, constant: 8),
            bannerLabel.trailingAnchor.constraint(lessThanOrEqualTo: bannerRetryButton.leadingAnchor, constant: -8),
            bannerLabel.topAnchor.constraint(equalTo: bannerView.topAnchor, constant: 6),

            bannerSubtitle.leadingAnchor.constraint(equalTo: bannerLabel.leadingAnchor),
            bannerSubtitle.trailingAnchor.constraint(lessThanOrEqualTo: bannerRetryButton.leadingAnchor, constant: -8),
            bannerSubtitle.topAnchor.constraint(equalTo: bannerLabel.bottomAnchor, constant: 1),
            bannerSubtitle.bottomAnchor.constraint(equalTo: bannerView.bottomAnchor, constant: -6),

            bannerRetryButton.trailingAnchor.constraint(equalTo: bannerView.trailingAnchor, constant: -12),
            bannerRetryButton.centerYAnchor.constraint(equalTo: bannerView.centerYAnchor),
        ])
    }

    /// 应用状态描述：全屏/横幅二选一，content 时整体隐藏。
    private func apply(_ descriptor: FFPaneStateDescriptor) {
        FFDebug.log("[STATE-OVERLAY] mode=\(descriptor.mode) title=\(descriptor.title) showsRetry=\(descriptor.showsRetry) isMainThread=\(Thread.isMainThread)")
        let showsFull = descriptor.mode != .content && descriptor.mode != .operation && descriptor.isFullScreen
        let showsBanner = descriptor.mode != .content && !showsFull

        isHidden = descriptor.mode == .content
        fullStack.isHidden = !showsFull
        bannerView.isHidden = !showsBanner

        if showsFull {
            if descriptor.mode == .loading {
                fullSpinner.isHidden = false
                fullSpinner.startAnimation(nil)
                iconView.isHidden = true
                subtitleLabel.isHidden = true
                retryButton.isHidden = true
            } else {
                fullSpinner.isHidden = true
                fullSpinner.stopAnimation(nil)
                iconView.isHidden = false
                iconView.image = NSImage(systemSymbolName: descriptor.iconName, accessibilityDescription: descriptor.title)
                subtitleLabel.isHidden = descriptor.subtitle.isEmpty
                subtitleLabel.stringValue = descriptor.subtitle
                retryButton.isHidden = !descriptor.showsRetry
            }
            titleLabel.stringValue = descriptor.title
        } else {
            fullSpinner.stopAnimation(nil)
            fullSpinner.isHidden = true
        }

        if showsBanner {
            bannerLabel.stringValue = descriptor.title
            bannerSubtitle.stringValue = descriptor.subtitle
            bannerSubtitle.isHidden = descriptor.subtitle.isEmpty
            bannerRetryButton.isHidden = !descriptor.showsRetry
            if descriptor.showsSpinner {
                bannerSpinner.isHidden = false
                bannerSpinner.startAnimation(nil)
                bannerIcon.isHidden = true
            } else {
                bannerSpinner.isHidden = true
                bannerSpinner.stopAnimation(nil)
                bannerIcon.isHidden = false
                bannerIcon.image = NSImage(systemSymbolName: descriptor.iconName, accessibilityDescription: descriptor.title)
            }
        } else {
            bannerSpinner.stopAnimation(nil)
            bannerSpinner.isHidden = true
        }
    }

    /// 命中穿透：仅保留"重试"按钮与顶部横幅的交互，其余区域穿透到下层列表。
    /// 全屏空/加载/错误状态下列表为空，穿透可保留空白区右键菜单（新建文件夹等）。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let hit = super.hitTest(point) else { return nil }
        if hit === retryButton || hit === bannerRetryButton { return hit }
        if hit === bannerView || hit.isDescendant(of: bannerView) { return hit }
        return nil
    }

    /// 重试：按描述符的重试语义分派（reload → refresh；deleteRetry → 重删失败项）。
    @objc private func retryTapped() {
        guard let viewModel = viewModel else { return }
        switch FFPaneStateDescriptor.make(from: viewModel.state).retryKind {
        case .reload:
            viewModel.refresh()
        case .deleteRetry:
            viewModel.deleteSelected()
        case .none:
            break
        }
    }
}

// MARK: - T13: 文件条目无障碍标签（VoiceOver）

/// 文件条目无障碍标签组合纯函数（T13）。
/// 供 FileListView/FileGridView/SearchPanel 复用，保证朗读文本一致。
enum FileEntryAccessibility {
    /// 组合"文件名 + 类型 + 大小"的可读标签。
    static func label(for entry: FileEntry) -> String {
        var parts: [String] = [entry.name]
        parts.append(entry.kindDescription)
        if !entry.isDirectory {
            parts.append(entry.formattedSize)
        }
        return parts.joined(separator: "，")
    }

    /// 目录条目（侧边栏）标签：名称 + 选中状态后缀。
    static func sidebarLabel(name: String, isSelected: Bool) -> String {
        isSelected ? "\(name)，已选中" : name
    }

    /// 搜索结果的详情文本（选中搜索结果时展示）。
    static func searchResultLabel(_ result: FFSearchResult) -> String {
        var parts: [String] = [result.name]
        if result.size > 0 {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
            formatter.countStyle = .file
            parts.append(formatter.string(fromByteCount: Int64(result.size)))
        }
        return parts.joined(separator: "，")
    }
}

// MARK: - T13: reduced-motion 动画时长

/// 系统"减弱动态效果"开启时动画时长为 0（禁用动画）。
enum FFMotion {
    /// 返回系统 reduced-motion 感知的动画时长。
    static func animationDuration(_ proposed: TimeInterval) -> TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : proposed
    }
}
