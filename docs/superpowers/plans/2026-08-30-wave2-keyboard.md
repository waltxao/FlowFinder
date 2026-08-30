# Wave 2 实现计划 — 键盘优先工作流 + Finder 互通

> **执行方式：** 单实现子代理 + 独立审查。审计依据：`.superpowers/audit/menu-shortcuts-focus.md`（含 file:line）；补充证据：`.superpowers/audit/drag-gestures-scroll.md`（剪贴板互通）、`.superpowers/audit/08-settings-shortcuts.png`（快捷键设置页截图：录制器 UI 已存在 20 项）。
> **设计依据：** 蓝图 `docs/superpowers/specs/2026-08-30-native-experience-blueprint.md` §2。

## Global Constraints

- 简体中文注释；不新增文件；pbxproj 不碰；Libraries/* 不提交。
- 每项改动后 `make swift-test > /tmp/ff-w2.log 2>&1`（落盘判读），保持 94/94。
- 用户偏好红线：所有 UI 文案简体中文；不改变既有可用功能的行为（只增不破）。
- 快捷键判定统一用「纯修饰键」语义：`event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command` 模式（替换 `contains(.command)` 的过松判定处）。
- 剪贴板互通约定：写 `NSPasteboard.general` 用 `.fileURL`（每个选中项一个 URL）+ 保留内部 `clipboardItems` 双写；粘贴侧优先读 general 的 fileURLs（非空则用），回退内部记录（剪切语义仍由内部跟踪）。

## Task 1: ⌘C/X/V 系统剪贴板互通 + 文本编辑分流（menu P0-2）

**Files:** `UI/MainWindowController+MenuActions.swift:70-82`（menuCopy/Cut/Paste）、`MainMenu.swift:54-56`
**要求：**
1. menuCopy/menuCut：内部 clipboardItems 双写之外，将选中项 fileURL 写入 `NSPasteboard.general`（clearContents + writeObjects([NSURL...])）。
2. menuPaste：优先读 general 的 fileURLs（`getObjects`），有则按外部文件粘贴（复制进当前目录，复用既有跨面板粘贴的落盘+进度模式）；为空回退内部 clipboardItems（内部移动/复制语义不变）。
3. 文本编辑分流：菜单项 selector 改为标准 `copy:`/`cut:`/`paste:`/`selectAll:`（MainMenu.swift:54-56 + 右键菜单 FFCommon.swift 对应项），在 MainWindowController 实现 `@objc func copy(_:)` 等：若 firstResponder 是 NSTextView/NSTextField（可编辑）则转发给它（`NSApp.sendAction(#selector(NSText.copy(_:))...)`），否则执行文件操作。剪切同理（文本框内 cut 走标准）。**验收红线：搜索框/重命名弹窗内 ⌘C/X/V/Z/A 必须是文本编辑，列表焦点时才是文件操作。**

## Task 2: 快捷键自定义生效化（menu P0-3）

**Files:** `UI/MainWindowController.swift:1394-1440`（keyDown/monitor 硬编码区）、`FFPaneActionsController.swift:241-256`、`SettingsWindowController.swift:1019-1053`、`App/MainMenu.swift:126-195`
**要求：**
1. 新增统一读取：`ShortcutCenter.current(_ key:) -> (keyCode: UInt, modifiers: UInt)?`（读既有 UserDefaults 键，默认值回退）。
2. 以下硬编码改读设置（默认值 = 现行为）：Space(49)/Enter(36)/Del(51)/⌘D/⌘O/⌘↑/⌘↓（monitor 与 keyDown 两处）；⌘1/⌘2 保持（视图切换已有菜单绑定，也改读设置统一）。
3. `shortcut_quicklook`/`shortcut_duplicate` 录制后由 ShortcutCenter 消费（与 keyDown 比对）。
4. 设置页快捷键区补「恢复默认」按钮（清空全部 shortcut_* 键 + 广播）。
5. 菜单 keyEquivalent 展示跟随设置（applyShortcutSettings 已有，扩展到新消费项的菜单展示如 ⌘D/QuickLook 入口——若菜单无对应项则跳过展示，仅运行时消费）。
**红线：** 改键位后旧键不再触发、新键立即生效（.shortcutsChanged 广播链）。

## Task 3: 死菜单修复 + 菜单完整性补缺（menu P0-4/P1）

**Files:** `App/MainMenu.swift:33-34,122-123`、`UI/MainWindowController+MenuActions.swift:675-677,612-630`、`MainMenu.swift:59,87,101`
**要求：**
1. ⌘⇧N 新窗口：实现真多窗口（`MainWindowController()` 新实例 + showWindow；AppDelegate.mainWindowController 改为数组或仅作首窗引用——最小改动：AppDelegate 持 `[NSWindowController]` 或新开窗口独立持有自身；验证双窗口并存可用（列目录独立、关闭互不影响））。若实现中发现架构性阻塞（如全局单例强耦合），报告 BLOCKED 并回退为「移除菜单项」，不许做假实现。
2. 显示隐藏文件：`menuToggleHiddenFiles` 接通真实状态翻转（找 PaneToolbar.swift:403-407 的实现路径复用；状态存 UserDefaults + 刷新两面板）。
3. 帮助菜单：FlowFinder 帮助 → 打开 https://github.com/waltxao/FlowFinder（NSWorkspace.shared.open）；键盘快捷键 → 打开设置窗口并选中快捷键分类。
4. 重命名菜单项：改调 beginInlineRename（与 Enter 一致），keyEquivalent 设为 "\r"（展示 Enter）或 F2（keyCode 120 若实现）——二选一，与 Task 2 的键位系统对齐。
5. ⌥⌘C 拷贝路径：编辑菜单 + 右键菜单（FFCommon.swift 菜单构造）各加「拷贝路径」，写 general pasteboard（多选时每行一个路径）。
6. ⌘F 分流：⌘F → 聚焦活动面板搜索框（PaneToolbar 搜索框 makeFirstResponder）；全局搜索面板改绑 ⌘⇧F（工具菜单搜索项同步）。
7. ⌘D 菜单入口：编辑菜单加「复制选中项 ⌘D」（读 Task 2 的键位设置展示）。
8. QuickLook 面板内 Space 关闭（QuickLookPreviewView.swift:178-214 补 keyCode 49）。
9. 「上一级」菜单补展示热键 ⌘↑；编辑菜单 Undo/Redo 标题本地化为「撤销」「重做」（动态标题逻辑保留）。

## Task 4: 焦点流转 + 真值源统一（menu P0-1/P2）

**Files:** `UI/MainWindowController.swift`（keyViewLoop 构建）、`UI/PaneToolbar.swift:143-157,148`、`UI/BreadcrumbBar.swift:471,579,644`、`UI/FileListView.swift`/`FileGridView.swift`
**要求：**
1. 建立每个面板的 keyViewLoop：搜索框 → 排序 → 分组 → 视图分段 → 列表/网格（当前视图）→（Tab 到另一面板首控件）。窗口级 nextKeyView 首尾相接成环。Tab/⇧Tab 走系统 keyViewLoop（SELECT 行为验证：文本框内 Tab 仍缩进/离焦正常）。
2. activatePane（MainWindowController.swift:1683-1693）同步 `makeFirstResponder` 到对应面板的列表/网格视图，消除「焦点面板 ≠ activePane」双真值源（menu 审计 §15）。
3. 焦点可见性：PaneToolbar.swift:148 搜索框与 BreadcrumbBar 三处 focusRingType .none 改为默认（.default），键盘焦点可见。
4. 验收：Tab 从左列表出发可依次到达：左搜索→左控件→右列表→右搜索→…成环；⇧Tab 反向；点击右面板后 ⌘C 作用于右面板选中项。

## Task 5: 全量验证

- `make swift-test` 94/94（回归重点：FFPaneActionsController 相关、菜单校验逻辑）。
- 手动冒烟清单（写进报告）：⌘C→Finder 粘贴；Finder 复制→本应用粘贴；文本框 ⌘C 是文本复制；改 Space 键位后立即生效+恢复默认；Tab 成环；⌘F 聚焦搜索框；F2/Enter 内联重命名；⌥⌘C 拷贝路径；QL 内 Space 关闭；双窗口并存（若 Task 3.1 实现新窗口）。

## 审查要点（审查者用）

- Task 1：NSPasteboard 双写不丢内部语义；粘贴外部文件的落盘路径正确（复制到当前目录）；文本分流在所有可编辑控件生效（搜索框/重命名/批量重命名/文件说明）。
- Task 2：所有改键路径走统一 ShortcutCenter；默认值 = 现行为（不改键的用户零感知）；.shortcutsChanged 即时生效。
- Task 3：新窗口（若实现）无全局状态互踩；死菜单全部有真实 action。
- Task 4：keyViewLoop 无断环；makeFirstResponder 不破坏既有滚轮/选中行为；focusRing 恢复后视觉可接受。
- 全局：不新增文件；测试基线 94；简体中文注释。
