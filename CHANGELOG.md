# 变更日志

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/) 规范。

---

## [0.7.6] — 2026-08-28

> v0.7.5 发布后修复轮：界面稳定 + 弹窗可用性

### 界面稳定
- **AppKit 布局冲突清零**（修复前每次启动 28+ 条冲突日志）：
  - 工具面板 `NSGridView` 列宽改 defaultHigh 约束（`NSGridColumn.width` 的 required 约束在面板宽度变化瞬态必然无解）
  - 设备浮层折叠态清空设备行（AppKit 隐藏视图约束仍参与求解，折叠高 48 与行高 28 必然冲突）
  - 面包屑溢出按钮双高度约束（init 14pt 与外层 18pt 冲突）
  - 状态浮层重试按钮缺 `translatesAutoresizingMaskIntoConstraints`（autoresizing 强制宿主宽 62pt）
  - 侧边栏标签区定高 required → defaultHigh（异步修正前瞬态无解）
- **删除确认弹窗按钮可见性**：`FFModalSheet` 在 contentView 尺寸为 0 时量 `fittingSize` 导致窗口过矮（120pt vs 186pt），footer 按钮被裁出窗外；改为两段式测量 + footer 贴底 defaultHigh 兜底

### 弹窗会话
- **查重删除后「浏览...」失效修复**：`FFModalSheet` 用 `close()` 结束 sheet 会话，在 macOS 27 上使宿主窗口的下一个 `NSOpenPanel` sheet 静默无法弹出；改为 `beginSheetModal` 记录宿主、关闭统一走 `endSheet` 正规结束（惠及全部模态弹窗）

### 测试
- 新增 3 个 AppKit 回归测试：删除弹窗按钮可见性、sheet 脱离宿主、查重删除后浏览面板复现（完整操作序列端到端）
- 修复后基线：Rust 200 tests / Swift XCTest 73 tests 全绿，启动布局冲突日志 0

## [0.7.5] — 2026-08-14

> 安全加固 + 独立内容索引 + 测试与发布基建

### 🔒 安全与数据保护
- **批量重命名路径穿越修复**：`new_name` 专用文件名校验（拒绝 `/`、`\`、`..`、绝对路径、控制字符、空名）
- **批量/整理操作冲突策略**：目标已存在时默认拒绝，不再静默覆盖（`batch_rename` / `organize_by_date` / `organize_by_type`）
- **path_guard 全写入口接入**：复制/移动/删除/重命名/批量/并行操作均经路径安全校验
- **FSEvents 生命周期状态化**：`starting/active/failed/stopped` 状态机 + `ff_fsevents_status`，启动失败可观察（不再假成功）
- **取消隔离**：去重扫描/搜索按实例独立取消（`ff_scan_duplicates_ex` + `ff_cancel_scan_by_id`），全局取消标志移除

### ⚡ 性能与可靠
- **独立 SQLite FTS5 内容索引**：「内容包含」搜索改为后台可取消的索引查询（`content_index.sqlite` 独立于目录缓存，checkpoint 断点续建、增量失效、损坏自动备份重建）
- **删除/撤销/重做后台化**：不再阻塞主线程；`isDeleting` / `deleteFailedPaths` / `paneFileOperationChanged` 状态机
- **缓存并发修复**：SQLite WAL + busy_timeout + 连接池；空目录可缓存命中；缩略图清理节流
- **标签+搜索组合过滤修复**：同时激活时取交集
- **FFDebug 门控**：仅 DEBUG 编译生效 + 常驻句柄

### 🧪 测试与工程
- **可执行 Swift XCTest target**：`FlowFinderNativeTests` shared scheme，`make swift-test` 走 xcodebuild（65+ tests）
- **FFI ABI/所有权锁定**：布局断言、回调借用契约、符号三方对比
- **任务生命周期测试**：提交→进度→取消→历史→清空全链路
- **fsevents 测试并发隔离**（12 处测试锁）

### 🎨 界面
- **主流程状态视图**：加载/空目录/错误+重试/删除进度统一呈现（`FFPaneStateOverlayView`）
- **删除确认统一**：菜单/右键/键盘/重复扫描共用 `DeleteConfirmDialog.confirmDelete`
- **搜索面板**：结果详情动态更新、窗口位置记忆（不再每次居中）
- **主流程无障碍**：VoiceOver 标签、键盘焦点、动态字体、reduced-motion、列表/网格交互一致
- **Pages 站**：375/768/1280 响应式修复、移动导航菜单、skip link、OG/canonical 元数据、对比度达标

---

## [0.7.4] — 2026-08-09

> 全量稳定性修复 + FSEvents 真实现

### 核心引擎（Rust Core）
- **文件监听重写**：占位轮询 → 真实 FSEventStream（事件驱动 + 300ms 去抖）
- **任务历史清理**：`ff_task_clear_history`，「清除已完成」按钮真正生效
- **设置键名对齐**：`appearance_mode` ↔ `appearance.theme` 互通

### 修复
- 重命名拦截含 `/` 文件名；删除失败项保留并展示
- 搜索竞态修复（代次校验）；主题跟随修复
- 对话框统一键盘交互（Enter/Esc/自动聚焦）；标签药丸流式换行
- 设置页快捷键真实生效；`SettingsActionTarget` 泄漏修复
- 网格空格 QuickLook firstResponder 守卫；排序/面板激活双触发修复
- 删除死代码 `ProgressDialog`；重复扫描删除统一「不再询问」标志

---

## [0.7.2] — 2026-08-07

> 设置页全面大修 + 液态玻璃视觉重设计 + 撤销/重做与冲突处理修复

- **设置页全面大修**：侧边栏导航 + 分区卡片布局（SettingsWindowController/SettingsSectionView 重构）
- **液态玻璃视觉重设计**：DesignTokens/FFGlassView 层级与透明度体系重构
- **撤销/重做闭环修复**：反向注册补全、对称注册、统一串行队列、注册延后到文件操作完成（消除 ⌘Z→⌘⇧Z 竞态与循环失效）
- **复制/移动冲突弹窗**：替换/保留两者/跳过；部分失败时撤销数组对齐
- **QuickLook 修复**：空格键在 tableView 层拦截转发；修饰键捕获实现访达拖拽语义
- **详情栏**：动态高度、`.app` 版本号、两列均衡、路径点击交互
- **收藏夹自绘高亮 / 搜索栏弹性 / 玻璃裁剪与亮线 / 工具面板高度** 等三轮 7 项修复

---

## [0.7.0] — 2026-08-02

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
