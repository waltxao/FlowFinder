# FlowFinder 二轮 UI 修复批量设计文档（10 项）

> 日期：2026-08-02
> 版本：v0.7.0 → v0.7.1（本轮修复后发版）
> 状态：已批准
> 范围：Swift & AppKit 侧 + Rust Core 侧少量改动（冲突检测）

## 背景

v0.7.0 的 11 项修复经用户实测后，8 项"依旧有问题"，另发现 2 项新问题。逐项代码核查确认：部分修复未生效是**确定性代码 bug**（如 .app 版本号被目录判断短路、液态玻璃装饰层漏修）、部分是**事件链路断点**（空格键被表格吃掉、拖拽 Command 判断失效）、部分是**布局意图与预期不符**。经逐项澄清，全部方案获用户批准。

> 流程反思：上轮验证止步于"构建通过 + 代码审查"，未做运行时验证。本轮每个功能实现后构建可运行版本交付用户实测，反馈通过才完成任务。

---

## 1. 收藏夹选中高亮未包裹内容（T1）

**现状根因**（探查确认）
- `FFFNoDisclosureOutlineView.canBecomeKeyView = false`（SidebarView.swift:48-50）导致 outlineView 永不成为 first responder，`NSTableRowView` 选中绘制永远走 de-emphasized 灰色路径——高亮极淡、视觉上"未包裹"。
- `intercellSpacing.height = 2` 制造行间 2pt 缝隙，相邻选中不连续。
- `updateFavoritesHeight` 与 `makeOutlineView` 的 28/2 数值重复维护（T1 遗留 Minor）。

**方案**
- 移除 `canBecomeKeyView = false`（恢复 `true`），使选中走系统标准蓝色强调路径；焦点环问题由 `focusRingType = .none`（已有）+ 不设 `allowsEmptySelection` 冲突兜底处理。
- 验证高亮覆盖：确认 cell 内容（图标 leading=0 / 文字 trailing）均在行内，必要时调整 `frameOfCell` 偏移逻辑让 cell 铺满整行宽。
- 行距：`intercellSpacing.height` 保持 2 但高度计算与绘制范围一致（高亮按行框绘制，2pt 缝隙是 NSOutlineView 标准行为——若用户仍嫌不连续则改为 0）。
- 提取共享常量 `favoritesRowHeight: CGFloat = 28` / `favoritesRowSpacing: CGFloat = 2`，`updateFavoritesHeight` 与 `makeOutlineView` 共用，消除魔法数字重复。

**验收**：选中收藏夹时整行（图标+文字）被标准蓝色高亮完整包裹；相邻选中无白色缝隙；≥5 项末行高亮完整。

## 2. 搜索栏自适应 + 图标贴右（T2）

**现状**：搜索框 hugging=1 弹性吸收剩余宽度（v0.7.0 已实现），但用户观察"图标没有贴右/铺满"，根因为布局意图确认：用户要"搜索框变宽 + 图标贴右"。

**方案**
- row2 的 NSStackView 中，在图标簇（排序/分组/视图/显示设置）前插入弹性 spacer（`NSView` + `setContentHuggingPriority(1)`），搜索框与图标簇之间留弹性空间——搜索框变宽时 spacer 吸收剩余，图标簇恒贴最右。
- 实测验证：窗口拉宽图标始终在操作区右缘；窗口缩窄搜索框优先收缩（min 120pt）图标不被挤掉。

**验收**：任意窗口宽度下右侧图标簇贴操作区最右端。

## 3. 液态玻璃全面重做（T4）

**现状根因**（探查确认）
- `FFGlassView` 装饰层（tint/noise/highlight/innerShadow）为方形 CALayer，父层 `masksToBounds=false` 不裁剪 sublayer → 圆角外露方形角（"灰边"）。
- 上轮修复仅在两处调用方手动补 `masksToBounds=true`（PaneToolbar searchContainer、ExpandableDetailsBar glassBackground），设备面板（MainWindowController createDevicePanel）与工具面板（ToolPanelView.setupUI）漏掉。
- 整体质感为手绘拼装，未达 Apple Liquid Glass 设计语言标准。

**方案（全面重做，参考 Apple Liquid Glass 规范）**
- **FFGlassView 内部统一裁剪**：装饰层 sublayer 加 `cornerRadius` 与父层一致并 `masksToBounds=true`（仅裁剪装饰层本身，不裁剪业务子视图——保持现有"子视图不被裁剪"的既有决策）。删掉调用方的手动补丁，改为内部自动处理。
- **质感升级参数**（DesignTokens 统一定义）：
  - 圆角：面板级 16pt、组件级 10pt（替代现 8/12 混合）
  - 描边高光：1pt 细亮线（日间 rgba(255,255,255,0.5) / 夜间 rgba(255,255,255,0.12)），沿圆角边缘绘制
  - 阴影：面板级 `shadowOpacity 0.15 / radius 10 / offset (0,2)`，强化与背景的分离层次
  - 色调：保留现有 tint（浅色 0.05 / 深色 0.10）但降低噪点强度，更通透
- **覆盖范围**：侧边栏、操作区工具栏、搜索框、详情栏浮层、设备面板、工具面板全部统一到该参数体系；ThemeManager 切换时同步刷新（沿用 `FFGlassView.refreshAllInstances()` 机制）。
- 保留架构决策：容器用 cornerRadius，装饰元素用 SquircleMaskedView；`maxGlassInstances = 8` 预算约束下控制新增实例数。

**验收**：任何玻璃面板无方形灰边；深浅色切换全部自动刷新；视觉一致性（圆角/描边/阴影统一）。

## 4. 工具面板点击打不开（T5）

**现状根因候选**（探查确认）：查重 + 批量重命名均打不开，指向点击手势链路问题；面板列宽约 50pt 过窄、可点区域小；`tool.action?()` 后立即 `onClose?()` 可能打断窗口打开。

**方案**
- `ToolPanelView` 列宽改为按面板实际宽度等分（3 列），卡片可点区域最大化；点击给明确视觉反馈（按下态变深）。
- 查重扫描：action 中先确保 `DuplicateScanWindowController.shared.showWindow()` 执行成功（窗口弹出），再关面板——调整为"延迟关闭"（`DispatchQueue.main.async` 包裹 onClose）。
- 批量重命名：选中 ≥2 直接 `menuBatchRename(nil)`；选中 <2 弹提示（保留 v0.7.0 实现）；同样延迟关闭面板。
- 两个工具 action 统一为"先执行、后关面板"。

**验收**：点击查重扫描弹出扫描窗口；点击批量重命名（≥2 选中）弹出重命名窗口、（<2）弹提示；点击有视觉反馈。

## 5. QuickLook 空格预览（T6）

**现状根因**（探查确认）：first responder 是 NSTableView，空格键被表格 `interpretKeyEvents` 消耗，到不了 `FileListView.keyDown`/`MainWindowController.keyDown`。

**方案**
- 在 `FileListView` / `FileGridView` 的 tableView 层拦截空格：为 tableView 设置 `keyDown` 拦截（通过 NSTableView 子类或 `performKeyEquivalent`），空格（keyCode 49、无修饰键、未在编辑态）时发送 `.fileListRequestQuickLook` 通知。
- 保留 MainWindowController.keyDown 兜底（选中态非空才响应）。
- 预览面板挂接沿用 v0.7.0 常驻 responder 方案（MainWindowController QLPreviewPanelController），不再改动。

**验收**：列表/网格中选中文件按空格稳定弹出 QuickLook；Esc 关闭；方向键切换；重开后正常。

## 6. 拖拽访达语义（T7）

**现状根因**（探查确认）：`NSApp.currentEvent?.modifierFlags` 在 validateDrop/acceptDrop 回调中不可靠（可能 nil 或非拖拽事件），⌘ 判断恒 false，四分支语义失效。

**方案**
- 在两个视图实现 `draggingUpdated(_:)`（或 `draggingEntered`），在**拖拽进行中**读取 `NSApp.currentEvent?.modifierFlags` 存入实例属性 `lastDragModifierFlags`（拖拽会话开始时重置）。
- `isMoveOperation` 改读 `lastDragModifierFlags.contains(.command)`，四分支语义（同盘拖=移动/⌘=复制；跨盘拖=复制/⌘=移动）真正生效。
- 列表与网格两处逻辑保持逐字一致；`isSameVolume`（statfs f_fsid）逻辑不变。
- 保留 v0.7.0 的 destPath 传递（文件夹行目标）。

**验收**：同盘拖动=移动、按住⌘=复制；跨盘拖动=复制、按住⌘=移动；列表/网格一致。

## 7. 设置页严重问题（T8）

**现状根因候选**（探查确认）：SMB 分区内嵌独立 `SMBManagerPanel`（仅 height≥220 约束）可能空白/异常；外观分区内嵌 `AppearanceSettingsView` 可能塌缩；分区切换重建有约束激活残留。

**方案**
- **SMB 分区**：排查 SMBManagerPanel 嵌入滚动容器后的约束冲突；必要时改为标准 `SettingsRowView` 行结构或给 panel 明确宽度约束，消除空白。
- **外观分区**：`AppearanceSettingsView` 嵌入行控件时给明确布局（宽度撑满、高度自适应），消除塌缩。
- **通用分区**：检查 `startupSection`/`fileOpsSection` 各行渲染，修正任何错位。
- **点击响应**：逐分区验证 toggle/popup/segmented/slider/color/textField/button 的 action 绑定。
- 保持 v0.7.0 精简后的设置项数量；`selectSection` 重建逻辑清理约束残留。

**验收**：7 个分区均可打开、内容完整无空白；控件对齐；每个设置项点击生效。

## 8. 详情栏（T9）

**现状根因**（探查确认）
- 图片专属信息被压缩截断：展开高度固定 210pt，图片 6-7 行约 100pt 超出可用区。
- .app 版本号死代码：`gatherFileInfo` 第一行 `if entry.isDirectory` 先命中（.app 是 bundle，isDir=true），`ext=="app"` 分支永远执行不到。
- 标签/说明列被挤到最右：locationField（完整路径）compression `.defaultLow` 撑宽 column1。

**方案**
- **展开高度自适应**：`expandedView` 高度改为按内容计算（`NSLayoutConstraint` 随内容变化），图片信息完整可见。
- **.app 分支顺序**：将 `.app` 判断提到 `isDirectory` 分支之前（`entry.path.hasSuffix(".app")` 优先），选中 .app 应用显示版本号/内部版本。
- **两列均衡**：column1（路径/通用信息）设最大宽度约束（如 55% 容器宽），column2（标签/说明/来源）不再被挤出；locationField 允许多行显示。
- **路径交互四项**（用户确认全要）：
  - 换行完整显示（`maximumNumberOfLines` 多行 + truncation 关闭）
  - 点击跳转所在文件夹：路径文字加点击手势 → 打开所在目录（`NSWorkspace` 或导航到父目录）
  - 右键复制路径：右键菜单"复制路径" → NSPasteboard
  - 蓝色区分：路径文字用 `systemBlue`（或可点击链接色），与其他信息区分

**验收**：图片详情完整显示（分辨率/尺寸/文件大小/色彩/相机）；.app 显示版本号；两列均衡；路径换行/点击跳转/右键复制/蓝色区分全部生效。

## 9. 全局撤销栈失效（新发现）

**现状根因候选**（探查确认）
- 剪贴板复制/粘贴（menuCopy/menuCut/menuPaste）不注册任何撤销。
- 文本控件（搜索框/重命名/快捷键录制）first responder 时 ⌘Z 被文本撤销抢占。
- 撤销闭包全部 `try?` 静默执行，与"静默覆盖"叠加时 undo 移回静默失败。

**方案**
- 为所有文件操作补齐撤销注册：复制粘贴（剪贴板操作）、批量重命名、跨面板操作等缺失项。
- 检查 ⌘Z 路由：确保焦点在文件列表（非文本编辑态）时 ⌘Z 走文件撤销（`undoManager.undo()`）；文本编辑态仍走文本撤销（系统默认）。
- 撤销执行失败时给出提示（不再静默）。

**验收**：复制/移动/删除/重命名/拖拽/粘贴后 ⌘Z 都能可靠撤销且界面刷新正确。

## 10. 文件冲突提示（新发现）

**现状根因**（探查确认）
- Rust 侧 `move_file`（rename 静默覆盖）、`parallel_ops::move_single`（rename 覆盖）、跨卷 copy fallback（fs::copy 覆盖）全部静默覆盖同名目标；同卷 copy 返回 EEXIST 被当普通失败处理。

**方案（弹窗询问+替换/副本/跳过，用户确认）**
- **预检查**：copy/move 前枚举目标目录，找出与源同名的冲突项。
- **冲突对话框**：发现冲突弹窗，提供三个选项：
  - **替换**：覆盖同名文件
  - **保留两者**：自动改名为"名称 副本.扩展名"（如 `文档 副本.pdf`，重名继续加序号）
  - **跳过**：跳过该文件
  - 批量时提供"应用于所有冲突"勾选（记住本次会话选择）
- **执行层**：Swift 侧在调用 Rust FFI 前处理冲突策略——"跳过"直接排除该源；"副本"先重命名源再操作；"替换"直接操作（Rust 侧行为不变，但预检查让用户知情）。
- Rust 侧不强制改动（保持现有覆盖语义），冲突决策收敛在 Swift 层。

**验收**：复制/移动遇到同名文件弹窗三选一；三种选择行为正确；批量冲突一次询问多次应用。

---

## 改动文件清单

| 文件 | 涉及项 |
|---|---|
| `UI/SidebarView.swift` | T1 收藏夹高亮 |
| `UI/PaneToolbar.swift` | T2 搜索栏/图标贴右、T4 玻璃 |
| `UI/FFGlassView.swift` + `UI/DesignTokens.swift` | T4 液态玻璃重做 |
| `UI/MainWindowController.swift` | T4 设备面板、T5 工具面板入口、T8 设置、T9 撤销 |
| `UI/ToolOverlayView.swift` | T4 工具面板玻璃、T5 点击链路 |
| `UI/FileListView.swift` + `UI/FileGridView.swift` | T6 空格拦截、T7 拖拽 modifier、T9 撤销 |
| `UI/QuickLookPreviewView.swift` | T6（仅验证，不大改） |
| `UI/SettingsWindowController.swift` + `UI/SettingsSectionView.swift` | T8 设置页 |
| `UI/ExpandableDetailsBar.swift` | T9 详情栏 |
| `Bridge/CoreBridge.swift` | T9 撤销、T10 冲突预检 |
| `rust-core`（如需要） | T10 冲突相关（优先 Swift 层解决） |

## 验证方式（关键改进）

1. 每项实现后 `xcodebuild Debug` 构建 + 运行应用，**交付用户实测**，该项反馈通过才标记完成。
2. 涉及运行的验证项（QuickLook/拖拽/工具面板/撤销/冲突弹窗）全部需用户实际操作确认。
3. 全部完成后升级版本号 v0.7.1，打 zip/dmg 安装包，更新交接文档与 CHANGELOG。

## 非目标（YAGNI）

- 不新增工具（工具面板维持 4 工具 + 占位）。
- 不改动设置项数量（保持 v0.7.0 精简后状态）。
- 不引入 SwiftUI 重写（保持 AppKit 架构）。
- 不实现跨窗口拖拽的撤销合并（维持现有 per-window UndoManager）。
