# FlowFinder Native 迁移计划

> **版本**: 0.2.0-plan  
> **日期**: 2026-07-17  
> **状态**: 草案 — 待团队评审  

---

## 1. 概述

### 1.1 项目背景

FlowFinder Native 是将原 Tauri + React 架构的文件管理器重构为 **Swift AppKit UI + Rust Core Engine** 的 Native macOS 应用。当前 POC（Proof of Concept）已完成，验证了 FFI 桥接、目录列表、基础 UI 框架的可行性。

### 1.2 已完成 POC（子项目 #0）

| 组件 | 状态 | 说明 |
|------|------|------|
| FFI 桥接层 | ✅ 完成 | `ff_list_dir`, `ff_last_error`, `ff_free_string` |
| 目录列表 | ✅ 完成 | `getattrlistbulk(2)` 批量读取，10-30x 性能提升 |
| 基础 UI 框架 | ✅ 完成 | `MainWindowController`, `ContentView`, `FileListView`, `SidebarView` |
| 数据模型 | ✅ 完成 | `FileEntry`, `FileEntryViewModel` |
| 构建系统 | ✅ 完成 | `Makefile`, `Package.swift`, `build-rust.sh` |

### 1.3 迁移目标

将原 Tauri 应用中的 **10 个核心功能模块** 全部迁移到 Native 架构，其中 POC 已完成 1 个，剩余 **9 个子项目** 待迁移。

---

## 2. 子项目总览

### 2.1 子项目清单

| # | 子项目名称 | 优先级 | 估计工时 | 依赖 | 状态 |
|---|-----------|--------|---------|------|------|
| 0 | **POC: 基础框架** | — | 已完成 | — | ✅ |
| 1 | **文件操作** (Copy/Move/Delete) | P0 | 3 天 | POC #0 | ⏳ |
| 2 | **重复文件检测** | P0 | 4 天 | POC #0, #1 | ⏳ |
| 3 | **文件搜索与过滤** | P0 | 3 天 | POC #0 | ⏳ |
| 4 | **文件预览 (QuickLook)** | P0 | 2 天 | POC #0 | ⏳ |
| 5 | **目录缓存与 FSEvents 监听** | P1 | 3 天 | POC #0, #3 | ⏳ |
| 6 | **批量重命名与整理** | P1 | 3 天 | POC #0, #1 | ⏳ |
| 7 | **缩略图生成** | P1 | 4 天 | POC #0, #3 | ⏳ |
| 8 | **设置与配置** | P2 | 2 天 | POC #0, #5 | ⏳ |
| 9 | **任务调度器** | P2 | 3 天 | POC #0, #1, #6 | ⏳ |
| 10 | **卷管理与健康检查** | P2 | 2 天 | POC #0, #5 | ⏳ |

### 2.2 优先级定义

- **P0 (Critical)**: 核心功能，无此功能应用不可用。必须在 MVP 阶段完成。
- **P1 (High)**: 重要功能，显著提升用户体验。在 P0 完成后立即开始。
- **P2 (Medium)**: 增强功能，可延后实现。在 P1 完成后安排。

### 2.3 依赖关系图

```
POC #0 (基础框架)
    │
    ├──► #1 文件操作 ─────┬──► #2 重复文件检测
    │                     │
    ├──► #3 搜索过滤 ─────┼──► #5 目录缓存/FSEvents
    │                     │         │
    ├──► #4 QuickLook ────┤         ├──► #8 设置配置
    │                     │         │
    │                     └──► #6 批量重命名 ──► #9 任务调度器
    │
    └──► #7 缩略图 ───────► (依赖 #3 搜索结果展示)

#10 卷管理 ───────────────► (依赖 #5 缓存状态)
```

---

## 3. 各子项目详细规划

---

### 子项目 #1: 文件操作 (File Operations)

**优先级**: P0  
**估计工时**: 3 天  
**依赖**: POC #0

#### 描述
实现文件和目录的复制、移动、删除、重命名操作。利用 Rust core 中的 `cow_copy` 模块实现 APFS Copy-on-Write 克隆，跨卷时自动回退到标准复制。

#### Rust FFI 接口

```rust
// 复制文件/目录
#[no_mangle]
pub extern "C" fn ff_copy_file(
    src: *const c_char,
    dst: *const c_char,
    callback: FFProgressCallback,
    user_data: *mut c_void,
) -> c_int;

// 移动文件/目录（同卷重命名，跨卷复制+删除）
#[no_mangle]
pub extern "C" fn ff_move_file(
    src: *const c_char,
    dst: *const c_char,
    callback: FFProgressCallback,
    user_data: *mut c_void,
) -> c_int;

// 删除文件/目录（支持回收站）
#[no_mangle]
pub extern "C" fn ff_delete_file(
    path: *const c_char,
    to_trash: bool,
) -> c_int;

// 重命名文件/目录
#[no_mangle]
pub extern "C" fn ff_rename_file(
    path: *const c_char,
    new_name: *const c_char,
) -> c_int;
```

#### Swift UI 组件

- `FileOperationManager`: 文件操作管理器（单例）
- `FileContextMenu`: 右键上下文菜单（NSMenu）
- `ProgressPanel`: 操作进度面板（NSPanel）
- `TrashConfirmationDialog`: 删除确认对话框

#### 数据模型

- `FileOperationProgress`: 进度数据模型
- `FileOperationResult`: 操作结果模型
- `FileOperationType`: 操作类型枚举（copy/move/delete/rename）

#### 测试要求

- [ ] Rust: `cow_copy` 同卷克隆测试
- [ ] Rust: 跨卷复制回退测试
- [ ] Rust: 目录递归复制测试
- [ ] Swift: 文件操作 UI 流程测试
- [ ] Swift: 撤销/重做集成测试
- [ ] 集成: 大文件复制性能基准测试

---

### 子项目 #2: 重复文件检测 (Duplicate Detection)

**优先级**: P0  
**估计工时**: 4 天  
**依赖**: POC #0, #1

#### 描述
三阶段重复文件检测引擎的 Native 迁移：按大小分组 → 部分哈希（MD5，头4KB+尾4KB）→ 完整哈希确认。支持实时进度流和取消操作。

#### Rust FFI 接口

```rust
// 启动重复文件扫描
#[no_mangle]
pub extern "C" fn ff_dedup_scan(
    paths: *const *const c_char,
    path_count: usize,
    callback: FFDedupCallback,
    user_data: *mut c_void,
) -> c_int;

// 取消正在进行的扫描
#[no_mangle]
pub extern "C" fn ff_dedup_cancel() -> c_int;

// 删除重复文件组中的指定文件
#[no_mangle]
pub extern "C" fn ff_dedup_delete_file(
    path: *const c_char,
    to_trash: bool,
) -> c_int;
```

#### Swift UI 组件

- `DedupScanPanel`: 扫描配置面板（选择目录、选项）
- `DedupResultView`: 结果展示视图（重复组列表）
- `DuplicateGroupCard`: 单个重复组卡片
- `DedupProgressView`: 扫描进度指示器

#### 数据模型

- `DuplicateFile`: 重复文件模型
- `DuplicateGroup`: 重复组模型
- `DedupScanConfig`: 扫描配置模型
- `DedupProgress`: 扫描进度模型

#### 测试要求

- [ ] Rust: 空目录扫描测试
- [ ] Rust: 取消令牌测试
- [ ] Rust: 三阶段哈希正确性测试
- [ ] Swift: 扫描 UI 流程测试
- [ ] Swift: 结果展示交互测试
- [ ] 集成: 10,000+ 文件扫描性能测试

---

### 子项目 #3: 文件搜索与过滤 (Search & Filter)

**优先级**: P0  
**估计工时**: 3 天  
**依赖**: POC #0

#### 描述
实现文件名搜索、内容过滤、高级搜索条件（大小、日期、类型）。集成 macOS Spotlight 作为可选搜索后端。

#### Rust FFI 接口

```rust
// 文件名搜索（支持通配符和正则）
#[no_mangle]
pub extern "C" fn ff_search_files(
    root_path: *const c_char,
    pattern: *const c_char,
    options: *const FFFSearchOptions,
    callback: FFSearchCallback,
    user_data: *mut c_void,
) -> c_int;

// 停止搜索
#[no_mangle]
pub extern "C" fn ff_search_cancel() -> c_int;

// 高级过滤（大小/日期/类型）
#[no_mangle]
pub extern "C" fn ff_filter_entries(
    entries: *const FFEntryRef,
    entry_count: usize,
    filter: *const FFFFilterCriteria,
    callback: FFEntryCallback,
    user_data: *mut c_void,
) -> c_int;
```

#### Swift UI 组件

- `SearchBar`: 搜索栏（NSSearchField）
- `SearchResultsView`: 搜索结果视图
- `FilterPanel`: 高级过滤面板
- `SpotlightSearchBridge`: Spotlight 集成桥接

#### 数据模型

- `SearchQuery`: 搜索查询模型
- `SearchResult`: 搜索结果模型
- `FilterCriteria`: 过滤条件模型
- `SearchOptions`: 搜索选项模型

#### 测试要求

- [ ] Rust: 文件名匹配测试（通配符/正则）
- [ ] Rust: 大小/日期过滤测试
- [ ] Swift: 搜索栏 UI 测试
- [ ] Swift: Spotlight 集成测试
- [ ] 集成: 100,000+ 文件搜索性能测试

---

### 子项目 #4: 文件预览 (QuickLook Integration)

**优先级**: P0  
**估计工时**: 2 天  
**依赖**: POC #0

#### 描述
集成 macOS QuickLook 框架（QLPreviewPanel），支持空格键预览文件。同时支持自定义预览器（文本、图片、PDF）。

#### Rust FFI 接口

```rust
// 获取文件 MIME 类型和预览建议
#[no_mangle]
pub extern "C" fn ff_get_file_info(
    path: *const c_char,
    out_info: *mut FFFileInfo,
) -> c_int;

// 读取文件前 N 字节（用于文本预览）
#[no_mangle]
pub extern "C" fn ff_read_file_head(
    path: *const c_char,
    max_bytes: usize,
    out_buffer: *mut c_char,
    out_size: *mut usize,
) -> c_int;
```

#### Swift UI 组件

- `QuickLookPreviewController`: QLPreviewPanel 控制器
- `CustomTextPreview`: 自定义文本预览器
- `PreviewCoordinator`: 预览协调器（管理预览状态）

#### 数据模型

- `FilePreviewInfo`: 文件预览信息模型
- `PreviewType`: 预览类型枚举

#### 测试要求

- [ ] Swift: QuickLook 面板显示测试
- [ ] Swift: 多种文件类型预览测试
- [ ] Swift: 空格键触发测试
- [ ] 集成: 大文件预览性能测试

---

### 子项目 #5: 目录缓存与 FSEvents 监听 (Directory Cache & FSEvents)

**优先级**: P1  
**估计工时**: 3 天  
**依赖**: POC #0, #3

#### 描述
实现 LRU 目录列表缓存（5秒 TTL，500条目容量），以及 FSEvents 文件系统监听，自动刷新变更的目录。

#### Rust FFI 接口

```rust
// 缓存管理
#[no_mangle]
pub extern "C" fn ff_cache_invalidate(path: *const c_char) -> c_int;

#[no_mangle]
pub extern "C" fn ff_cache_clear() -> c_int;

#[no_mangle]
pub extern "C" fn ff_cache_stats(out_stats: *mut FFCacheStats) -> c_int;

// FSEvents 注册/注销
#[no_mangle]
pub extern "C" fn ff_fsevents_register(
    path: *const c_char,
    callback: FFFSEventCallback,
    user_data: *mut c_void,
    out_token: *mut u64,
) -> c_int;

#[no_mangle]
pub extern "C" fn ff_fsevents_unregister(token: u64) -> c_int;
```

#### Swift UI 组件

- `FSEventsManager`: FSEvents 管理器（Swift 侧）
- `CacheStatusIndicator`: 缓存状态指示器（工具栏）
- `DirectoryWatcher`: 目录监听协调器

#### 数据模型

- `CacheStats`: 缓存统计模型
- `FSEvent`: 文件系统事件模型
- `DirectoryWatchConfig`: 监听配置模型

#### 测试要求

- [ ] Rust: LRU 缓存命中/淘汰测试
- [ ] Rust: TTL 过期测试
- [ ] Swift: FSEvents 事件接收测试
- [ ] Swift: 缓存自动刷新测试
- [ ] 集成: 频繁导航缓存性能测试

---

### 子项目 #6: 批量重命名与整理 (Batch Rename & Organize)

**优先级**: P1  
**估计工时**: 3 天  
**依赖**: POC #0, #1

#### 描述
实现批量重命名（模式替换、序号添加、大小写转换）和自动整理（按日期/类型/大小自动分类文件到子目录）。

#### Rust FFI 接口

```rust
// 批量重命名
#[no_mangle]
pub extern "C" fn ff_batch_rename(
    paths: *const *const c_char,
    path_count: usize,
    pattern: *const c_char,
    replacement: *const c_char,
    options: *const FFRenameOptions,
    callback: FFProgressCallback,
    user_data: *mut c_void,
) -> c_int;

// 自动整理文件
#[no_mangle]
pub extern "C" fn ff_auto_organize(
    source_path: *const c_char,
    strategy: *const c_char,  // "date", "type", "size"
    callback: FFProgressCallback,
    user_data: *mut c_void,
) -> c_int;
```

#### Swift UI 组件

- `BatchRenamePanel`: 批量重命名面板
- `OrganizePanel`: 自动整理配置面板
- `RenamePreviewView`: 重命名预览视图

#### 数据模型

- `RenameRule`: 重命名规则模型
- `RenamePreview`: 重命名预览模型
- `OrganizeStrategy`: 整理策略模型

#### 测试要求

- [ ] Rust: 批量重命名正确性测试
- [ ] Rust: 自动整理策略测试
- [ ] Swift: 重命名预览 UI 测试
- [ ] Swift: 撤销/重做集成测试

---

### 子项目 #7: 缩略图生成 (Thumbnail Generation)

**优先级**: P1  
**估计工时**: 4 天  
**依赖**: POC #0, #3

#### 描述
异步缩略图生成与缓存。支持图片、视频、PDF 缩略图。使用 Rust 进行文件类型检测，Swift 调用 CoreImage/AVFoundation 生成缩略图。

#### Rust FFI 接口

```rust
// 获取缩略图元数据（尺寸、格式）
#[no_mangle]
pub extern "C" fn ff_thumbnail_info(
    path: *const c_char,
    out_info: *mut FFThumbnailInfo,
) -> c_int;

// 检查文件是否需要缩略图
#[no_mangle]
pub extern "C" fn ff_needs_thumbnail(path: *const c_char) -> bool;
```

#### Swift UI 组件

- `ThumbnailGenerator`: 缩略图生成器（Swift，使用 CoreImage）
- `ThumbnailCache`: 缩略图缓存管理
- `ThumbnailGridView`: 缩略图网格视图（替代列表视图）
- `ThumbnailLoader`: 异步缩略图加载器

#### 数据模型

- `ThumbnailInfo`: 缩略图信息模型
- `ThumbnailCacheEntry`: 缓存条目模型
- `ThumbnailRequest`: 缩略图请求模型

#### 测试要求

- [ ] Swift: 图片缩略图生成测试
- [ ] Swift: 视频缩略图生成测试
- [ ] Swift: PDF 缩略图生成测试
- [ ] Swift: 缓存命中/失效测试
- [ ] 集成: 1000+ 缩略图生成性能测试

---

### 子项目 #8: 设置与配置 (Settings & Configuration)

**优先级**: P2  
**估计工时**: 2 天  
**依赖**: POC #0, #5

#### 描述
应用设置面板，包括通用设置、外观主题、快捷键配置、高级选项。使用 SwiftUI 设置场景或自定义 NSPanel。

#### Rust FFI 接口

```rust
// 设置持久化（Rust 侧提供跨平台配置存储）
#[no_mangle]
pub extern "C" fn ff_settings_get(
    key: *const c_char,
    out_value: *mut c_char,
    max_len: usize,
) -> c_int;

#[no_mangle]
pub extern "C" fn ff_settings_set(
    key: *const c_char,
    value: *const c_char,
) -> c_int;

#[no_mangle]
pub extern "C" fn ff_settings_reset(key: *const c_char) -> c_int;
```

#### Swift UI 组件

- `SettingsWindowController`: 设置窗口控制器
- `GeneralSettingsView`: 通用设置视图
- `AppearanceSettingsView`: 外观设置视图
- `ShortcutSettingsView`: 快捷键设置视图
- `AdvancedSettingsView`: 高级设置视图

#### 数据模型

- `AppSettings`: 应用设置模型
- `ThemeSettings`: 主题设置模型
- `ShortcutConfig`: 快捷键配置模型

#### 测试要求

- [ ] Swift: 设置读写测试
- [ ] Swift: 主题切换测试
- [ ] Swift: 快捷键注册测试
- [ ] 集成: 设置持久化跨会话测试

---

### 子项目 #9: 任务调度器 (Task Scheduler)

**优先级**: P2  
**估计工时**: 3 天  
**依赖**: POC #0, #1, #6

#### 描述
后台任务队列管理，支持批量文件操作的排队、暂停、恢复、取消。任务包括：复制、移动、删除、重命名、整理、重复检测。

#### Rust FFI 接口

```rust
// 任务队列管理
#[no_mangle]
pub extern "C" fn ff_task_submit(
    task_type: *const c_char,
    params: *const c_char,  // JSON 序列化参数
    out_task_id: *mut u64,
) -> c_int;

#[no_mangle]
pub extern "C" fn ff_task_cancel(task_id: u64) -> c_int;

#[no_mangle]
pub extern "C" fn ff_task_pause(task_id: u64) -> c_int;

#[no_mangle]
pub extern "C" fn ff_task_resume(task_id: u64) -> c_int;

#[no_mangle]
pub extern "C" fn ff_task_status(
    task_id: u64,
    out_status: *mut FFTaskStatus,
) -> c_int;

#[no_mangle]
pub extern "C" fn ff_task_list(
    callback: FFTaskCallback,
    user_data: *mut c_void,
) -> c_int;
```

#### Swift UI 组件

- `TaskSchedulerPanel`: 任务调度器面板
- `TaskItemView`: 单个任务项视图
- `TaskProgressRing`: 任务进度环形指示器
- `TaskConsoleView`: 任务日志控制台

#### 数据模型

- `TaskItem`: 任务项模型
- `TaskStatus`: 任务状态枚举
- `TaskQueue`: 任务队列模型
- `TaskProgress`: 任务进度模型

#### 测试要求

- [ ] Rust: 任务提交/取消测试
- [ ] Rust: 任务暂停/恢复测试
- [ ] Rust: 并发任务执行测试
- [ ] Swift: 任务队列 UI 测试
- [ ] Swift: 任务进度更新测试
- [ ] 集成: 100+ 任务队列性能测试

---

### 子项目 #10: 卷管理与健康检查 (Volume Management & Health)

**优先级**: P2  
**估计工时**: 2 天  
**依赖**: POC #0, #5

#### 描述
管理已挂载的卷/磁盘，显示卷信息（容量、使用情况、文件系统类型），检测卷健康状态（只读、断开连接、空间不足）。

#### Rust FFI 接口

```rust
// 卷信息查询
#[no_mangle]
pub extern "C" fn ff_volume_list(
    callback: FFVolumeCallback,
    user_data: *mut c_void,
) -> c_int;

#[no_mangle]
pub extern "C" fn ff_volume_info(
    path: *const c_char,
    out_info: *mut FFVolumeInfo,
) -> c_int;

// 健康检查
#[no_mangle]
pub extern "C" fn ff_volume_health_check(
    path: *const c_char,
    out_health: *mut FFVolumeHealth,
) -> c_int;
```

#### Swift UI 组件

- `VolumeListView`: 卷列表视图（Sidebar 集成）
- `VolumeStatusBanner`: 卷状态横幅（顶部警告栏）
- `VolumeInfoPanel`: 卷信息详情面板

#### 数据模型

- `VolumeInfo`: 卷信息模型
- `VolumeHealth`: 卷健康状态模型
- `VolumeStatus`: 卷状态枚举

#### 测试要求

- [ ] Rust: 卷列表查询测试
- [ ] Rust: 健康状态检测测试
- [ ] Swift: 卷状态 UI 更新测试
- [ ] Swift: 断开连接处理测试

---

## 4. FFI 接口变更总览

### 4.1 新增 FFI 函数（按子项目）

| 子项目 | 新增 FFI 函数 | 复杂度 |
|--------|--------------|--------|
| #1 文件操作 | `ff_copy_file`, `ff_move_file`, `ff_delete_file`, `ff_rename_file` | 中 |
| #2 重复检测 | `ff_dedup_scan`, `ff_dedup_cancel`, `ff_dedup_delete_file` | 高 |
| #3 搜索过滤 | `ff_search_files`, `ff_search_cancel`, `ff_filter_entries` | 中 |
| #4 QuickLook | `ff_get_file_info`, `ff_read_file_head` | 低 |
| #5 缓存/FSEvents | `ff_cache_*`, `ff_fsevents_register/unregister` | 高 |
| #6 批量重命名 | `ff_batch_rename`, `ff_auto_organize` | 中 |
| #7 缩略图 | `ff_thumbnail_info`, `ff_needs_thumbnail` | 低 |
| #8 设置 | `ff_settings_get/set/reset` | 低 |
| #9 任务调度 | `ff_task_submit/cancel/pause/resume/status/list` | 高 |
| #10 卷管理 | `ff_volume_list`, `ff_volume_info`, `ff_volume_health_check` | 中 |

### 4.2 新增 C 结构体

```c
// 进度回调结构
typedef struct {
    uint64_t completed;
    uint64_t total;
    const char* current_file;
} FFProgressEvent;

// 搜索选项
typedef struct {
    bool case_sensitive;
    bool use_regex;
    uint64_t min_size;
    uint64_t max_size;
    int64_t modified_after;
    int64_t modified_before;
    const char* file_type;
} FFSearchOptions;

// 任务状态
typedef struct {
    uint64_t task_id;
    const char* task_type;
    const char* status;  // "pending", "running", "paused", "completed", "cancelled", "error"
    uint64_t completed;
    uint64_t total;
    const char* error_message;
} FFTaskStatus;

// 卷信息
typedef struct {
    const char* name;
    const char* mount_point;
    const char* fs_type;
    uint64_t total_bytes;
    uint64_t free_bytes;
    uint64_t used_bytes;
    bool is_removable;
    bool is_read_only;
} FFVolumeInfo;
```

### 4.3 回调类型定义

```c
// 进度回调
typedef void (*FFProgressCallback)(
    const FFProgressEvent* event,
    void* user_data
);

// 重复检测事件回调
typedef void (*FFDedupCallback)(
    const char* event_type,  // "progress", "group_found", "done", "error"
    const void* event_data,
    void* user_data
);

// 搜索回调
typedef void (*FFSearchCallback)(
    const FFEntryRef* entry,
    void* user_data
);

// FSEvents 回调
typedef void (*FFFSEventCallback)(
    const char* path,
    uint32_t flags,
    uint64_t event_id,
    void* user_data
);

// 任务回调
typedef void (*FFTaskCallback)(
    const FFTaskStatus* task,
    void* user_data
);

// 卷回调
typedef void (*FFVolumeCallback)(
    const FFVolumeInfo* volume,
    void* user_data
);
```

---

## 5. 数据模型映射

### 5.1 Rust Core → Swift UI 数据流

```
Rust Core                    FFI Layer                   Swift UI
─────────                    ─────────                   ────────
FileEntrySkeleton    ──►    FFEntryRef           ──►    FileEntry
DuplicateGroup       ──►    FFDedupEvent         ──►    DuplicateGroup
TaskItem             ──►    FFTaskStatus         ──►    TaskItem
VolumeInfo           ──►    FFVolumeInfo         ──►    VolumeInfo
CacheStats           ──►    FFCacheStats         ──►    CacheStats
```

### 5.2 新增 Swift 数据模型

| 模型 | 用途 | 来源 |
|------|------|------|
| `FileOperationProgress` | 文件操作进度 | Swift 定义 |
| `DuplicateFile` | 重复文件信息 | FFI 映射 |
| `DuplicateGroup` | 重复文件组 | FFI 映射 |
| `SearchQuery` | 搜索查询 | Swift 定义 |
| `SearchResult` | 搜索结果 | FFI 映射 |
| `FilePreviewInfo` | 预览信息 | FFI 映射 |
| `CacheStats` | 缓存统计 | FFI 映射 |
| `FSEvent` | 文件系统事件 | Swift 定义 |
| `RenameRule` | 重命名规则 | Swift 定义 |
| `OrganizeStrategy` | 整理策略 | Swift 定义 |
| `ThumbnailInfo` | 缩略图信息 | FFI 映射 |
| `AppSettings` | 应用设置 | Swift 定义 |
| `TaskItem` | 任务项 | FFI 映射 |
| `VolumeInfo` | 卷信息 | FFI 映射 |

---

## 6. 测试策略

### 6.1 测试层次

```
┌─────────────────────────────────────────┐
│  集成测试 (Integration Tests)            │
│  scripts/integration-test.sh            │
│  - FFI 端到端测试                        │
│  - UI 自动化测试                         │
│  - 性能基准测试                          │
├─────────────────────────────────────────┤
│  Swift 单元测试 (Swift Unit Tests)        │
│  Tests/FlowFinderNativeTests/            │
│  - UI 组件测试                          │
│  - 数据模型测试                         │
│  - 桥接层测试                           │
├─────────────────────────────────────────┤
│  Rust 单元测试 (Rust Unit Tests)          │
│  rust-core/src/*/tests                   │
│  - 核心逻辑测试                         │
│  - FFI 接口测试                         │
│  - 内存安全测试                         │
└─────────────────────────────────────────┘
```

### 6.2 各子项目测试覆盖目标

| 子项目 | Rust 测试 | Swift 测试 | 集成测试 | 目标覆盖率 |
|--------|----------|-----------|---------|-----------|
| #1 文件操作 | 8+ | 5+ | 3+ | 85% |
| #2 重复检测 | 6+ | 4+ | 2+ | 80% |
| #3 搜索过滤 | 6+ | 4+ | 2+ | 80% |
| #4 QuickLook | 2+ | 4+ | 2+ | 75% |
| #5 缓存/FSEvents | 6+ | 4+ | 2+ | 80% |
| #6 批量重命名 | 5+ | 4+ | 2+ | 80% |
| #7 缩略图 | 2+ | 6+ | 2+ | 75% |
| #8 设置 | 3+ | 4+ | 1+ | 70% |
| #9 任务调度 | 8+ | 5+ | 3+ | 85% |
| #10 卷管理 | 4+ | 3+ | 2+ | 75% |

---

## 7. 风险与缓解策略

| 风险 | 影响 | 可能性 | 缓解策略 |
|------|------|--------|---------|
| FFI 接口频繁变更 | 高 | 中 | 定义稳定的 C ABI，版本化接口 |
| 内存泄漏（FFI 边界） | 高 | 中 | 严格的所有权规则，Valgrind/Instruments 检测 |
| 性能退化 | 高 | 低 | 每个子项目完成后运行 benchmark.sh |
| SwiftUI/AppKit 兼容性问题 | 中 | 中 | 优先使用 AppKit，SwiftUI 仅用于设置面板 |
| macOS 版本兼容性 | 中 | 低 | 持续在 macOS 13/14/15 上测试 |
| 团队 Swift/Rust 技能差距 | 中 | 中 | 代码审查配对，文档完善 |

---

## 8. 里程碑与时间表

### 8.1 阶段划分

| 阶段 | 时间 | 目标 | 交付子项目 |
|------|------|------|-----------|
| **Phase 1: MVP** | 第 1-2 周 | 核心文件管理功能 | #1, #3, #4 |
| **Phase 2: 增强** | 第 3-4 周 | 高级文件操作 | #2, #5, #6 |
| **Phase 3: 完善** | 第 5-6 周 | 用户体验优化 | #7, #8, #9 |
| **Phase 4: 收尾** | 第 7 周 | 系统级功能 | #10 |
| **Phase 5: 稳定** | 第 8 周 | 测试、优化、发布准备 | 全部 |

### 8.2 详细时间表

```
周 1:  [====#1====][==#3==]
       文件操作    搜索过滤

周 2:  [==#3==][====#4====]
       搜索过滤   QuickLook

周 3:  [====#2====][==#5==]
       重复检测   缓存/FSEvents

周 4:  [==#5==][====#6====]
       缓存      批量重命名

周 5:  [====#7====][==#8==]
       缩略图     设置

周 6:  [==#8==][====#9====]
       设置      任务调度

周 7:  [====#10====]
       卷管理

周 8:  [========测试优化发布准备========]
```

---

## 9. 相关文档

| 文档 | 路径 | 说明 |
|------|------|------|
| 验证清单 | `docs/VERIFICATION.md` | POC 验证结果 |
| 子项目模板 | `docs/SUBPROJECT_TEMPLATE.md` | 单个issue模板 |
| FFI 设计 | `rust-core/include/ff_ffi.h` | C 头文件 |
| 架构图 | `README.md` | 系统架构 |
| 构建指南 | `Makefile` | 构建指令 |

---

## 10. 附录

### 10.1 术语表

| 术语 | 说明 |
|------|------|
| FFI | Foreign Function Interface，跨语言调用接口 |
| CoW | Copy-on-Write，写时复制（APFS 特性） |
| FSEvents | macOS 文件系统事件通知 API |
| QLPreviewPanel | macOS QuickLook 预览面板 |
| LRU | Least Recently Used，最近最少使用缓存策略 |
| TTL | Time To Live，缓存存活时间 |
| P0/P1/P2 | 优先级等级（Critical/High/Medium） |

### 10.2 参考资源

- [macOS getattrlistbulk(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/getattrlistbulk.2.html)
- [Apple FSEvents API](https://developer.apple.com/documentation/coreservices/file_system_events)
- [QLPreviewPanel](https://developer.apple.com/documentation/quicklook/qlpreviewpanel)
- [Rust FFI Best Practices](https://doc.rust-lang.org/nomicon/ffi.html)
- [Swift Interacting with C APIs](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/interfacingwithc/)

---

*本文档由 FlowFinder Native 团队维护。如有问题，请提交 Issue 或联系团队。*
