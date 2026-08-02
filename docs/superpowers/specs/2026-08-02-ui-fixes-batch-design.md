# FlowFinder UI 修复批量设计文档（11 项）

> 日期：2026-08-02
> 版本：v0.6.9+（未发版）
> 状态：已批准
> 范围：全部为 Swift & AppKit 侧修改，Rust Core 无改动（无需重建 rust-core）

## 背景

用户对当前 v0.6.9+ 未发版版本提出 11 项修复/实现意见，涵盖界面细节、功能修复、页面重设计。经逐项探查与澄清，全部方案已获用户批准。本文档记录每项的现状、方案与改动点，作为实现依据。

---

## 1. 收藏夹：选中高亮被裁剪、标题间距不协调、行距过大

**现状**（`UI/SidebarView.swift`）
- `updateFavoritesHeight()` 用 `count × 28` 计算容器高度，但实际行距为 `rowHeight 28 + intercellSpacing 4 = 32`，末行高亮框底部被裁掉。
- "我的收藏"标题与列表间距 12pt，与标签区（4pt）节奏不一致。
- 行距 `intercellSpacing.height = 4` 视觉偏大。

**方案**
- 高度计算改为 `count × rowHeight + (count - 1) × intercellSpacing.height`。
- 标题→列表间距 12pt 改为 4pt（与标签区一致）。
- `intercellSpacing.height` 从 4 收紧为 2，贴近访达侧边栏节奏。

## 2. 搜索栏宽度自适应 + 右侧按钮贴最右

**现状**（`UI/PaneToolbar.swift`）
- 搜索框为自定义组合（FFGlassView + 图标 + NSTextField），仅有 ≥120 最小宽约束，无弹性宽度。
- 右侧图标簇（列表/网格/显示设置）随 stack 移动，无法保证贴操作区最右。

**方案**
- 给搜索容器加弹性宽度约束（`hugging = .defaultLow` 已具备，补充明确的"拉伸吸收剩余空间"约束）。
- 右侧图标簇用 spacer 或 trailing 锚定操作区最右侧：窗口越宽搜索框越宽，缩小时搜索框优先收缩（最小 120）。

## 3. 显示设置图标：自绘位图改为系统 SF Symbol

**现状**
- `makeDisplaySettingsIcon()` 手绘合成图（eye + gearshape 徽章），`isTemplate = false` + 创建时固定色烘焙，深色模式不跟随，视觉权重与其他图标不一致。

**方案**
- 删除 `makeDisplaySettingsIcon()`，改用系统 SF Symbol `slider.horizontal.3`，模板色，随外观自动适配。
- 按钮样式与其他导航按钮统一（`createNavButton` 路径）。

## 4. 操作区四列平铺、无横向滚动条

**现状**（`UI/FileListView.swift`）
- 四列固定宽（名称 240/日期 130/类型 100/大小 70），仅末列自动拉伸；窗口窄时出现横向滚动条（`hasHorizontalScroller = true`）。
- line 649 注释"不设置 columnAutoresizingStyle"与 line 672 实际代码矛盾（过期注释）。

**方案**
- 名称列改为弹性（吸收剩余宽度），修改日期/类型/大小按内容定宽；四列总和恒等于操作区可用宽，任何窗口宽度无横向滚动条。
- `hasHorizontalScroller = false`。
- 修正过期注释，统一 `columnAutoresizingStyle` 语义。

## 5. 设备区适配液态玻璃

**现状**（`UI/MainWindowController.swift`）
- `devicePanel` / `toolPanelView` 为普通 NSView + 实体背景色，与侧边栏玻璃质感不一致；未监听主题通知（夜间切换不刷新）。

**方案**
- `devicePanel` / `toolPanelView` 改用 `FFGlassView`（.panel 风格），与侧边栏玻璃统一。
- 监听 `.appearanceChanged` 通知同步刷新（与 ThemeManager 现有广播机制一致）。
- 注意 `FFDesign.Glass.maxGlassInstances = 8` 的实例预算。

## 6. 工具面板：查重扫描 / 批量重命名打不开

**现状**（`UI/ToolOverlayView.swift` + `UI/MainWindowController.swift`）
- 批量重命名入口走 `menuBatchRename(nil)`：选中 <2 时 `guard` 静默 return + 面板立即收起 → "点一下没反应"。
- 查重扫描接线理论通畅，但点击后 `onClose` 立即收起面板，若窗口打开异常（force-unwrap 崩溃被吞）表现为打不开；且卡片可点区域依赖未设列宽的 NSGridView，存在塌缩隐患。

**方案**
- 批量重命名：面板入口与侧边栏/工具栏入口一致，选中 <2 时弹 NSAlert 提示"请先选中至少 2 个文件"。
- 查重扫描：调整顺序为"先执行打开窗口、成功后再收起面板"，窗口打开异常时保留面板并输出日志；为 `ToolPanelView` 网格设置明确列宽，修复卡片可点区域塌缩。
- 打开窗口前不提前收起面板（统一两个工具的时序）。

## 7. 工具面板：3×3 网格 + 灰色关闭图标 + 查重图标更换

**现状**（`UI/ToolOverlayView.swift` + `UI/MainWindowController.swift`）
- 两处 NSGridView 每行 2 列（旧版 ToolOverlayView:80、当前 ToolPanelView:262）。
- 关闭按钮用 emoji "❌"（两处）。
- 查重图标 `rectangle.dashed`。

**方案**
- 每行 3 列；当前 4 个工具占 2 行，不足 9 格用灰色占位方块补齐（`NSGridView` 占位 cell，低饱和背景，不可点击）。
- 关闭按钮改为 SF Symbol `xmark`，灰阶 `contentTintColor`（.secondaryLabelColor）。
- 查重图标改为 `doc.on.doc`（重叠文档，表意"找重复"）。

## 8. QuickLook 预览修复

**现状**（`UI/QuickLookPreviewView.swift`）
- responder chain 临时插入方案脆弱：依赖 `window.firstResponder` 非 nil，插入时机在 `makeKeyAndOrderFront` 之前，链状态扰动时找不到 controller 导致面板不显示；dataSource/delegate 在 toggle 与 begin 流程重复设置，存在时序竞争。

**方案**
- 改为常驻 responder 挂接：由稳定存在的 controller（MainWindowController 或其成员）在窗口生命周期内实现 `QLPreviewPanelController` informal protocol（acceptsPreviewPanelControl / begin / end），避免临时插入/移除 responder chain。
- 统一 dataSource/delegate 赋值时序，消除重复设置与关闭后再开为空的问题。
- 保留空格触发、Esc 关闭、方向键切换（不改变键位）。

## 9. 拖拽：区分按键与磁盘（访达语义）

**现状**（`UI/FileListView.swift` + `UI/FileGridView.swift`）
- `isMoveOperation` 仅依赖 `draggingSourceOperationMask` 推断：同盘无键=移动 ✓、跨盘无键=复制 ✓、同盘⌘=复制 ✓，但**跨盘+⌘=复制 ✗（期望移动）**。
- `destPath` 用 `viewModel?.currentPath` 而非真实拖放目标 `entry.path`；多选拖拽只取首项做卷比较。

**方案**
- 在 `validateDrop`/`acceptDrop` 中显式读取修饰键（`NSApp.currentEvent?.modifierFlags`），组合四分支：
  - 同盘 + 无修饰键 = 移动；同盘 + ⌘ = 复制
  - 跨盘 + 无修饰键 = 复制；跨盘 + ⌘ = 移动
- 卷判定改用真实拖放目标路径（文件夹行用 `entry.path`）。
- 多选时源路径以拖拽 session 的原始 source 路径集合为准（同卷判断取首个源，保留现有实现，注释说明）。
- 列表与网格两处 `isMoveOperation` 逻辑保持同步修改。

## 10. 设置页：分栏式重设计 + 删减低频项

**现状**（`UI/SettingsWindowController.swift` + `UI/SettingsSectionView.swift`）
- 左侧 180pt 分类侧栏（已有）+ 右侧单滚动容器堆叠 7 分区 33 行，密度高、空隙大。
- SMB 服务器列表裸放无卡片；「关于」卡片内嵌套信息行风格不一致。

**方案**
- 保持左侧分类导航，右侧改为**每次只显示一个分类**（切换分类刷新内容区），不再全部堆叠滚动。
- 删减 7 项低频/重复设置：
  - 外观：侧边栏图标大小（slider）、减少透明度（toggle）
  - 文件管理：缩略图缓存大小（slider）
  - SMB：连接超时（slider）
  - 文件管理与工具栏重复的三项显示开关（显示扩展名 / 显示标签 / 隐藏系统文件——保留操作区"显示设置"菜单入口）
- SMB 服务器列表纳入统一卡片组件；「关于」卡片风格与其余卡片统一。
- 快捷键分区保留全部键位（仅涉及布局，不删功能）。

## 11. 详情栏：图片类型专属信息 + .app 应用版本号

**现状**（`UI/ExpandableDetailsBar.swift`）
- `gatherImageInfo` 依赖 `CGImageSourceCopyPropertiesAtIndex`，键取用脆弱（字符串字面量、NSNumber 桥接），HEIC/WebP 等格式取不到，实际图片专属区基本为空。
- `gatherAppInfo` 读 Contents/Info.plist（存在），需确认详情栏对 .app 文件正常触发。

**方案**
- 图片类型专属信息显示四项：
  - 分辨率（像素宽×高）
  - 打印/显示尺寸（按 DPI 换算厘米，72dpi 为默认，有 DPI 元数据则用之）
  - 文件大小
  - 色彩空间（如 sRGB）/ 颜色深度（位深），及相机 EXIF（焦距、光圈、ISO，有则显示）
- 修复键读取：优先用 `kCGImageProperty*` 常量，兜底字符串字面量；兼容 HEIC/WebP 属性结构；ImageIO 读取保持主线程但失败降级为空（不阻塞 UI）。
- .app 文件：确认 `gatherAppInfo` 触发并显示 `CFBundleShortVersionString`（版本号）与 `CFBundleVersion`（Build），展示格式对齐访达"显示简介"。

---

## 改动文件清单

| 文件 | 涉及项 |
|---|---|
| `UI/SidebarView.swift` | #1、#5（侧边栏相关） |
| `UI/PaneToolbar.swift` | #2、#3 |
| `UI/FileListView.swift` | #4、#8、#9 |
| `UI/FileGridView.swift` | #9 |
| `UI/MainWindowController.swift` | #5、#6、#8（常驻 responder 挂接） |
| `UI/ToolOverlayView.swift` | #6、#7 |
| `UI/QuickLookPreviewView.swift` | #8 |
| `UI/SettingsWindowController.swift` | #10 |
| `UI/SettingsSectionView.swift` | #10 |
| `UI/ExpandableDetailsBar.swift` | #11 |
| `UI/DesignTokens.swift`（如需要） | #1、#5、#7 |

## 验证方式

1. `xcodebuild -project FlowFinderNative.xcodeproj -scheme FlowFinderNative -configuration Debug build`（需 `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`）。
2. `-configuration Release build` 双构建通过。
3. 运行应用逐项人工验证（用户配合反馈）。
4. 更新交接文档（handover html）。

## 非目标（YAGNI）

- 不新增工具（3×3 用占位方块补齐，不新增真实工具）。
- 不改 Rust Core / FFI（无 rust-core 改动）。
- 快捷键键位不改动，仅布局调整。
- 设置页删减的 7 项仅从 UI 移除，底层 UserDefaults 键保留（避免破坏已存配置）。
