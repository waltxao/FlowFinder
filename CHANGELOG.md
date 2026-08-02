# 变更日志

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/) 规范。

---

## [0.7.0] — 未发版

> 11 项 UI 修复批量

### ✨ 新增

#### 搜索栏
- **搜索栏宽度自适应**：搜索框弹性吸收面板剩余宽度，右侧图标贴最右排列

#### 详情栏
- **图片专属信息增强**：图片文件在详情栏显示分辨率、打印尺寸、文件大小、色彩空间、相机 EXIF 等信息；`.app` 应用增加版本号兜底显示

#### 液态玻璃
- **设备栏/工具面板适配液态玻璃**：设备栏与工具面板改用 FFGlassView 呈现，与操作区/详情栏视觉一致

### 🐛 Bug 修复

#### 侧边栏收藏夹
- **高亮条裁剪修复**：收藏夹高亮条不再被裁剪，完整显示
- **标题间距**：「我的收藏」标题与文件夹间距统一为 4pt
- **行距收紧**：收藏夹文件夹行距收紧，布局更紧凑

#### 工具栏
- **显示设置图标**：改用系统 SF Symbol `slider.horizontal.3`，深浅色模式自适应

#### 操作区
- **四列按比例平铺**：列宽采用 `sequentialColumnAutoresizingStyle` 按比例分配，移除横向滚动条

#### 工具面板
- **入口修复**：批量重命名选中 <2 项时弹出提示；查重扫描打开时序调整；卡片可点区域修复
- **3×3 网格布局**：工具面板改为 3×3 网格，关闭图标改灰色 xmark，查重图标换用 `doc.on.doc`，空位补占位方块

#### 拖拽
- **拖拽访达语义**：同盘拖拽 = 移动 / ⌘拖拽 = 复制；跨盘拖拽 = 复制 / ⌘拖拽 = 移动

#### 设置页
- **精简低频/重复设置**：删除 7 项低频或重复设置（侧边栏图标大小、减少透明度、缩略图缓存大小、连接超时、与工具栏重复三项），统一卡片间距 12pt

### ♻️ 重构

#### QuickLook
- **常驻 responder 挂接**：QuickLook 改用常驻 responder 方式挂接，`MainWindowController` 实现 `QLPreviewPanelController`，替代此前临时插入/移除 responder 链的方案

---

## [0.6.9] — 2026-08-01

> UI 细节精细化修复 + QuickLook 预览修复

### ✨ 新增

#### 超椭圆圆角系统
- **SquircleView 工具类**：新建 `SquircleView.swift`，通过 `CGPath` 绘制超椭圆（superellipse）路径实现 iOS 风格的平滑圆角，替代标准 `cornerRadius`。应用到操作区容器（16pt）、详情栏浮层（12pt）、搜索框组件（8pt）等所有圆角位置

#### 文件夹显示配置菜单
- **文件夹配置按钮**：搜索栏后方的工具菜单改为文件夹显示配置菜单（`slider.horizontal.3` 图标），包含显示/隐藏隐藏文件、文件标签、文件后缀、系统文件四项开关，菜单文案根据当前状态动态切换并带勾选标记
- **新建文件夹**：菜单底部保留新建文件夹入口
- **显示配置联动**：`showHiddenFiles`/`showSystemFiles` 在数据层过滤文件列表（PaneState.applyDisplayFilter），`showFileTags`/`showFileExtensions` 在展示层控制视图刷新

#### 工具选择覆盖页
- **ToolOverlayView**：新建 `ToolOverlayView.swift`，点击侧边栏工具按钮后在当前激活操作区覆盖显示工具选择页。大方块网格布局（2列），每个工具包含 48pt 大图标 + 名称 + 介绍，右上角关闭按钮，Esc 键可关闭。查重扫描和批量重命名可用，AI 打标/AI 整理标记为 Beta 置灰

### 🐛 Bug 修复

#### QuickLook 预览
- **QuickLook 完全不可用修复**：`QuickLookPreviewPanel` 基类从 `NSObject` 改为 `NSResponder`，实现 `QLPreviewPanelController` informal protocol 方法（`acceptsPreviewPanelControl`/`beginPreviewPanelControl`/`endPreviewPanelControl`），通过 responder chain 插入/移除使 QLPreviewPanel 能正确找到 controller。空格键预览、方向键切换、Esc 关闭、再次空格切换均已修复

#### 侧边栏
- **收藏夹间距修复**：「我的收藏」标题与收藏夹文件夹列表间距从 12pt 改为 4pt，与标签区间距一致
- **收藏夹对齐修复**：收藏夹文件夹图标最左边缘与「我的收藏」标题文字最左边缘对齐，消除缩进

#### 操作区
- **背景覆盖修复**：操作区白色背景（夜间黑色）正确覆盖顶部工具栏区域（导航栏 + 搜索框 + 路径栏）
- **1px 边框**：操作区增加 1px 边框（日间浅灰 `NSColor.separatorColor` / 夜间深灰 `#3A3A3A`）
- **分割线移除**：移除侧边栏与操作区之间、两个操作区之间的分割线（`dividerThickness` 返回 0）
- **拖动渐变亮线**：拖动调整操作区宽度时，仅在鼠标位置显示从中心向两端渐变的垂直亮线（`CAGradientLayer`），不再显示操作区蓝色边框

#### 详情栏
- **浮层化改造**：详情栏从操作区容器内部底部改为浮层覆盖在文件列表上方，文件列表始终占满操作区全高，不因详情栏展开而缩短。四周留 8pt 边距，增加阴影（`shadowOpacity = 0.15`、`shadowRadius = 8`）强化浮动层次，圆角 12pt

#### 文件名布局
- **双行布局**：列表视图和网格视图中，有标签的文件显示双行（上方文件名、下方标签药丸），无标签文件单行显示。列表视图动态行高（有标签 48pt / 无标签 26pt），关闭标签显示时统一单行高度

---

## [0.6.8] — 2026-07-31

> 侧边栏交互修复 + 主题切换稳定性提升

### 🐛 Bug 修复

#### 侧边栏
- **收藏夹焦点框修复**：点击收藏夹文件夹时整个模块外不再出现蓝色焦点框。通过重写 `FFFNoDisclosureOutlineView.canBecomeKeyView` 返回 `false`，彻底阻止 NSOutlineView 获得键盘焦点，同时保留行选中高亮（`.sourceList` 样式）不变
- **收藏夹完整显示**：移除收藏夹区域的外层 `NSScrollView` 容器，收藏夹高度根据文件夹数量自适应，所有文件夹完整列出无需滚动；标签模块随之下移，仅在触底时才出现滚动条
- **标签同步修复**：修复 `FileListView` 和 `FileGridView` 中通知名称不匹配的问题（`FileListTagsChanged` → `FileTagsDidChange`），新增标签现在能自动同步到侧边栏标签模块
- **标签药丸样式**：标签模块统一使用胶囊形状药丸 + 颜色圆点样式，背景为标签颜色的浅色底（非高亮 0.12 / 高亮 0.22 透明度），与收藏夹文件夹图标左边缘对齐

#### 主题
- **日间/夜间模式切换修复**：修复 `FFDesign.isDark` 依赖 `NSApp.effectiveAppearance`（延迟更新）导致主题切换时玻璃效果读取旧值的问题，改用 `ThemeManager.shared.resolvedIsDark`（基于已立即更新的 `currentMode`），确保切换时所有 `FFGlassView` 实例的 tint/噪声/高光/内阴影同步刷新
- **夜间模式窗口外观修复**：修复 `MainWindowController` 中窗口外观被强制设为 `nil` 导致夜间模式无法生效的问题，改为跟随 `NSApp.appearance`

#### 详情栏
- **展开按钮修复**：修复详情栏展开按钮（chevron）被 `compactView` 和 `expandedView` 遮挡导致无法点击的问题，重新排列视图层级确保按钮可交互

#### 右键菜单
- **列表视图剪切按钮**：列表视图右键菜单补充缺失的「剪切」菜单项，与网格视图右键菜单完全一致
- **移动到废纸篓红色标注**：右键菜单中「移动到废纸篓」菜单项文字标为红色，与访达行为一致

#### 其他
- **全局撤销栈**：修复 `UndoManager` 未正确集成到窗口响应链导致 Cmd+Z 无效的问题
- **显示简介功能**：修复通知链不完整导致「显示简介」无法打开自定义文件信息窗口的问题

---

## [0.6.0-alpha] — 2026-07-21

> 🎉 FlowFinder 首个原生版本发布！从 Tauri + React 完整重构为 Swift & AppKit + Rust Core 架构。

### ✨ 新功能

#### 核心架构
- **Swift & AppKit 原生 UI**：完全重写 UI 层，使用 NSTableView、NSCollectionView、NSSplitView、NSMenu 原生组件
- **Rust Core FFI 桥接**：Rust Core 编译为 cdylib，通过 C ABI 暴露接口，Swift 通过 Bridging Header 调用
- **NSVisualEffectView 毛玻璃**：系统级毛玻璃材质，自动跟随深浅色主题，替代 WebView CSS backdrop-filter

#### 文件浏览
- **双栏布局**：左右独立导航，NSSplitView 可拖拽分隔条
- **统一工具栏**：后退 / 前进 / 上一级、面包屑路径、正则搜索栏、视图切换按钮，嵌入标题栏
- **双视图模式**：表格视图（NSTableView，可拖列宽 + 点击排序）+ 网格视图（NSCollectionView + 缩略图）
- **文件详情栏**：选中文件时底部显示缩略图、类型、大小、修改日期、标签等信息
- **隐藏 / 系统文件显示**：隐藏文件灰色文字，系统保护文件红色文字，可切换显示

#### 跨面板文件操作
- **复制到对侧面板**：⌘⇧C 一键复制选中文件到对侧面板当前目录
- **移动到对侧面板**：⌘⇧X 一键移动选中文件到对侧面板当前目录
- **在对侧面板打开**：右键菜单在文件夹上可直接在对侧面板打开该目录
- **冲突自动解决**：同名文件自动追加「副本 N」后缀
- **面板激活**：点击面板任意空白区域即激活该面板，无需键盘 Tab 切换

#### 原生右键菜单
- **FileListView 右键菜单**：打开、复制、剪切、粘贴、跨面板操作、重命名、删除、新建文件夹
- **FileGridView 右键菜单**：与 FileListView 一致的完整右键菜单
- **菜单栏快捷键**：完整的 ⌘C / ⌘X / ⌘V / ⌘⇧C / ⌘⇧X / ⌘N / Delete 等快捷键支持

#### macOS 原生体验
- **Quick Look 预览**：QLPreviewPanel 原生浮动预览，空格键触发
- **混合缩略图引擎**：QLThumbnailGenerator + SQLite 缓存，P0/P1 双队列优先级
- **Spotlight 搜索**：NSMetadataQuery 异步搜索 + Channel 流式推送结果
- **FSEvents 实时监控**：文件系统变更自动刷新目录列表
- **getattrlistbulk 批量读取**：单次系统调用获取目录全部元数据，性能提升 10-30 倍
- **clonefile CoW 复制**：APFS 卷零拷贝文件复制，瞬时完成
- **原生拖拽**：NSDraggingSource/Destination，同卷移动、跨卷复制、Cmd 键切换

#### 侧边栏
- **个人收藏**：任意文件夹可拖拽添加到收藏夹
- **存储设备**：磁盘分组显示，自动排除系统隐藏卷，支持 SMB/UNC 网络挂载
- **标签管理**：标签分类树，颜色圆点标识，AI 标签与 macOS 原生标签双向同步
- **可折叠区段**：所有区段可折叠，状态持久化

#### 高级功能
- **BLAKE3 重复文件检测**：三阶段检测（大小分组 → 部分哈希 → 完整哈希），实时进度流
- **AI 智能打标**：支持 OpenAI / Claude / Ollama / 自定义 API，隐私隔离（仅发送文件名 + 扩展名）
- **任务调度中心**：统一管理复制 / 移动 / 删除 / 查重任务，支持暂停 / 恢复 / 取消
- **SMB 网络共享**：渐进式加载、LRU 目录缓存、rayon 并行操作、断连自动重连
- **设置面板**：通用设置、外观主题（深色 / 浅色 / 跟随系统）、AI 模型配置

### 🚀 性能提升

| 指标 | 原版（Tauri） | 新版（Native） | 提升 |
|------|--------------|----------------|------|
| 目录列表（冷） | ~15-30 ms | ~0.5-1.0 ms | 10-30x |
| 目录列表（热） | ~5-10 ms | ~0.2-0.5 ms | 10-20x |
| 内存占用 | ~50-100 MB | ~20-30 MB | 2-3x |
| 启动时间 | ~2-3s | ~0.5s | 4-6x |
| 二进制大小 | ~80-100 MB | ~15-20 MB | 5-6x |

### 🏗️ 架构变更

- UI 层从 React 19 + WebView 重写为 Swift 5.9 + AppKit
- 文件列表从 react-virtual 重写为 NSTableView + NSCollectionView
- 缩略图从 Rust FFI 重写为 QLThumbnailGenerator（Swift 原生）
- QuickLook 从 Swift Bridge 中转重写为 QLPreviewPanel 单例直调
- 搜索从 Tauri Commands 重写为 SearchBridge + SpotlightBridge
- 拖拽从 HTML5 重写为 NSDraggingSource/Destination
- 毛玻璃从 CSS backdrop-filter 重写为 NSVisualEffectView

### 📦 下载

| 文件 | 大小 | 架构 | 说明 |
|------|------|------|------|
| `FlowFinder-0.6.0-alpha.dmg` | ~1.7 MB | Apple Silicon | DMG 安装镜像 |
| `FlowFinder-0.6.0-alpha.zip` | ~1.2 MB | Apple Silicon | ZIP 压缩包（含 .app） |
| `libflowfinder_core.dylib` | — | Apple Silicon | Rust Core 动态库（开发用） |
| `ff_ffi.h` | — | — | FFI C 头文件（开发用） |

### ⚠️ 已知限制

- 仅支持 Apple Silicon 架构（Intel Mac 未充分测试）
- 当前为 alpha 版本，可能存在未发现的 Bug
- 部分 UI 动画仍在优化中
- 全局撤销 / 重做栈尚未完整实现
- 批量重命名 UI 尚在开发中

### 📝 完整重构历史

详见 [重构日志](docs/MIGRATION_LOG.md)。

---

## 版本号规则

FlowFinder 采用以下版本号规则：

- **0.x.0-alpha** / **0.x.0-beta**：开发预览版，功能可能不完整
- **0.x.0**：稳定版，核心功能完整
- **1.0.0**：正式发布版，通过全面测试

无重大架构变更时，后续版本依次递增（0.6.1、0.6.2 ...）。
