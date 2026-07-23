# FlowFinder Native 代码审计与下一步开发计划 Spec

## Why

FlowFinder Native (v0.6.0-alpha) 经过从 Tauri+React 到 Swift+AppKit 的完整重构，以及访达风格 UI 重设计后，需要进行一次系统性代码审计，对照设计文档确认功能完成度，并制定下一步开发计划，以推进到 v0.6.0 稳定版或 v0.7.0。

## What Changes

本次为纯审计与计划制定，不产生代码变更。输出为：
- 一份完整的功能差距清单（已完成/部分完成/未开始）
- 一份分优先级的下一步开发计划

## Impact

- Affected specs: `2026-07-20-complete-rewrite-design.md`, `2026-07-22-finder-style-ui-redesign.md`
- Affected code: 全项目（Swift UI 层 + Bridge 层 + Rust Core + FFI）

## 审计结果总览

### 总体完成度

| 层级 | 已完成 | 部分完成 | 未开始 | 完成率 |
|------|--------|---------|--------|--------|
| Rust Core (6项) | 2 | 3 | 1 | 58% |
| Bridge 层 (9项) | 6 | 3 | 0 | 83% |
| UI 层 Phase 2-6 (20项) | 16 | 4 | 0 | 90% |
| UI 重设计 10项需求 | 9 | 1 | 0 | 95% |
| **合计 (45项)** | **33** | **11** | **1** | **82%** |

### 已完成的核心功能 (33项)

#### Rust Core
- blake3 哈希迁移（dedup_engine + scanner + thumbnails）
- SQLite 缓存模块实现（sqlite_cache.rs，含完整 CRUD + 单元测试）
- Rayon 并行操作模块实现（parallel_ops.rs，含并行复制/移动/删除 + 单元测试）

#### Bridge 层
- SearchBridge 搜索回调（FFSearchResult 解析 + 流式结果推送）
- SearchBridge 重复扫描回调（FFDuplicateGroup 解析）
- SpotlightBridge（NSMetadataQuery 封装）
- SMBBridge（NetFSMountURLSync 挂载/卸载/检测）
- ThumbnailManager（QLThumbnailGenerator + LRU 内存缓存 + 磁盘缓存）
- TagBridge（xattr 读写 com.flowfinder.tags）

#### UI 层
- FileEntry 数据模型（全字段：id/fileExtension/isHidden/isSystemProtected/isSymlink/creationDate/tags）
- PaneState（sort/filter/selectedFiles 有序数组）
- MainWindowController（双面板布局/活跃面板切换/DetailsBar 绑定）
- PaneToolbar（排序/分组 NSPopUpButton + 视图切换）
- FileListView（4列/多选/列头排序/拖拽源+目标/右键菜单）
- ExpandableDetailsBar（收起/展开/预览图标/元数据）
- MainMenu（File/Edit/View/Go/Tools/Window/Help 全套菜单 + 快捷键路由）
- QuickLookPreviewView（QLPreviewPanel + 方向键切换）
- ThumbnailManager（QLThumbnailGenerator + LRU 缓存 + 磁盘缓存）
- SearchPanelController（双模式 Rust/Spotlight + 结果列表 + 双击定位）
- DuplicateScanView（目录选择/进度/分组结果/批量删除）
- TaskProgressBar（底部固定/当前任务进度/可取消）
- TaskPanelWindowController（⌘0 打开/任务列表）
- SettingsWindowController（外观/SMB/快捷键三标签页）
- AppearanceSettingsView（浅色/深色/跟随系统）
- ThemeManager（NSAppearance 切换 + 持久化 + 系统监听）

#### UI 重设计 10 项需求
- 需求1: 玻璃透明度（侧边栏液态玻璃 + 双栏99%不透明遮罩）
- 需求2: ExpandableDetailsBar 可展开详情面板
- 需求3: 全部使用访达原生系统图标
- 需求4: 单击选中（蓝色高亮）双击打开
- 需求6: BreadcrumbBar 面包屑导航（可点击跳转）
- 需求7: 窗口距顶部8pt间距
- 需求8: 设备栏半透明圆角遮罩 + 动态高度
- 需求9: 空间进度条 + 可用空间文字
- 需求10: 药丸标签样式 + 彩色小圆点

### 部分完成的功能 (11项)

#### Rust Core (3项)

**RC-1. FFI 签名不一致**
- `ff_task_list` / `ff_volume_list` 回调签名已对齐
- `ff_task_submit` 参数与 `ff_ffi.h` 不一致（Rust: task_type+params_json, Header: name+description+priority+out_task_id）
- `ff_task_cancel` 类型不匹配（Rust: c_int, Header: const char*）
- `ff_volume_mount` 参数数量不匹配（Rust: 1参数, Swift 调用: 2参数）— **编译阻塞**
- `ff_volume_info` 模式不匹配（Rust: 回调式, Header: 输出参数式）

**RC-2. sqlite_cache 未接入 FFI**
- `sqlite_cache.rs` 完整实现但 `ff_cache_get`/`ff_cache_put` 实际调用 `dir_cache`（内存 LRU），未使用 SQLite 持久化缓存

**RC-3. parallel_ops 未接入 FFI**
- `parallel_ops.rs` 完整实现但无 FFI 导出，Swift 层无法调用 4 线程并行批量操作

#### Bridge 层 (3项)

**BR-1. 任务调度 API 不完整**
- `submitTask` 不返回 task ID（设计要求返回）
- `cancelTask` 用 Int32 而非设计的 u64

**BR-2. 卷管理 mountVolume 签名不匹配**
- `CoreBridge.swift:1221` 调用 `ff_volume_mount(cPath, cOptions)` 两参数
- `volumes.rs:539` 只接受一参数 — **会导致编译失败或运行时崩溃**

**BR-3. FSEvents 回调空壳**
- `fseventsCallback` 函数体为空（仅注释）
- `changeHandler` 闭包被丢弃（user_data 传 nil）
- `stopFSEventsWatcher` 硬编码 handle=0（不存储真实 handle）

#### UI 层 (4项)

**UI-1. FileGridView 拖拽未实现**
- FileListView 拖拽完整（NSDraggingSource + NSDraggingDestination）
- FileGridView 完全缺失拖拽（无 registerForDraggedTypes / NSDraggingSource / performDragOperation）

**UI-2. Enter 键行为偏差**
- 当前：Enter 用于打开文件/进入目录
- 设计要求：Enter 用于 inline rename（内联重命名）
- 重命名仅通过菜单/右键 NSAlert 弹窗实现

**UI-3. 侧边栏 CRUD UI 入口缺失**
- `addFavorite` / `addTag` / `removeTag` 方法存在但无 UI 触发入口
- 无法通过界面添加收藏夹或标签

**UI-4. 侧边栏区域遮罩未完全独立**
- 设计要求三个独立 GlassSectionMaskView（收藏夹/标签/存储设备）
- 实际仅两个（收藏夹+标签合并为一个，存储设备独立）

#### UI 重设计 (1项)

**RD-1. 内容遮罩区域独立性**（同 UI-4）

### 未开始的功能 (1项)

**RC-4. Rust 侧 SMB 模块缺失**
- 设计文档要求 `smb_mount.rs` + `ff_smb_mount`/`ff_smb_unmount`/`ff_smb_list` FFI
- 实际 SMB 能力完全由 Swift 层 `SMBBridge.swift`（NetFSMountURLSync）实现
- 架构决策变更：SMB 由 Swift 直接处理，不经过 Rust Core — **可能不需要补齐**

### 后续开发方向（来自 CHANGELOG 已知限制 + CONTINUE_DEV_PROMPT）

1. **全局撤销/重做栈** — 未开始（仅菜单占位 Selector(("undo:"))，无 UndoManager）
2. **批量重命名 UI** — 未开始
3. **Release 构建和 DMG 打包** — 部分完成（Makefile 支持 Release 编译，无 .app/.dmg 打包脚本）
4. **Intel Mac 通用二进制** — 未开始
5. **文件分组显示** — 未开始
6. **性能优化（大目录 10万+ 文件）** — 未验证
7. **AI 标签生成** — 未开始（xattr 读写完整，但无 AI 分类引擎）
