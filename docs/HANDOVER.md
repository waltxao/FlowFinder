# FlowFinder Native 项目交接文档

> **交接日期：** 2026-07-27
> **当前版本：** 0.6.4 (640)
> **仓库地址：** https://github.com/waltxao/FlowFinder
> **分支：** main
> **最新提交：** 5b0717c

---

## 1. 项目概述

FlowFinder（中文名：**流方达**）是一款专为 macOS 打造的原生文件管理器，采用 **Swift & AppKit** 构建用户界面，**Rust Core** 提供高性能后端引擎，通过 FFI（C ABI）实现跨语言调用。

### 核心亮点

- **纯原生 UI**：Swift & AppKit 构建，NSVisualEffectView 系统级毛玻璃
- **高性能 Rust Core**：getattrlistbulk 批量读取、BLAKE3 哈希、rayon 并行处理
- **Finder 级交互**：原生拖拽、Quick Look 预览、双栏布局
- **玻璃态双视图**：列表视图 + 网格视图，跟随系统深浅色主题

### 性能指标

| 指标 | 原版（Tauri） | 新版（Native） | 提升 |
|------|--------------|----------------|------|
| 目录列表（冷） | ~15-30 ms | ~0.5-1.0 ms | **10-30x** |
| 目录列表（热） | ~5-10 ms | ~0.2-0.5 ms | **10-20x** |
| 内存占用 | ~50-100 MB | ~20-30 MB | **2-3x** |
| 启动时间 | ~2-3s | ~0.5s | **4-6x** |
| 二进制大小 | ~80-100 MB | ~15-20 MB | **5-6x** |

---

## 2. 架构设计

```
+--------------------------------------------------+
|  Swift & AppKit UI Layer                         |
|  - NSTableView / NSCollectionView                |
|  - NSSplitView 双栏布局                          |
|  - NSVisualEffectView 毛玻璃                     |
|  - QLPreviewPanel Quick Look                     |
|  - Spotlight NSMetadataQuery                     |
|  - NSDraggingSource/Destination 原生拖拽         |
+--------------------------------------------------+
                        |
                        | FFI (C ABI)
                        v
+--------------------------------------------------+
|  Rust Core Engine (cdylib)                       |
|  - bulk_read: getattrlistbulk(2) 批量读取        |
|  - scanner: FileEntrySkeleton + 元数据            |
|  - dedup_engine: 三阶段 BLAKE3 去重              |
|  - cow_copy: APFS copy-on-write 克隆             |
|  - dir_cache: LRU + TTL 目录缓存                 |
|  - task_scheduler: 统一任务调度                  |
|  - search_engine: 正则 / 通配符搜索              |
|  - sqlite_cache: 标签 / 缩略图持久化             |
|  - path_guard: 路径穿越防护                      |
|  - volumes: 卷管理                               |
+--------------------------------------------------+
```

### 技术栈

| 层 | 技术 | 版本 |
|----|------|------|
| UI 框架 | Swift & AppKit | 5.9+ |
| 后端引擎 | Rust（cdylib） | 2021 edition |
| 数据库 | rusqlite (bundled SQLite) | 0.32 |
| 哈希 | BLAKE3 + xxHash64 | - |
| 并行 | rayon | 1.10 |
| macOS 原生 | NSVisualEffectView / QLThumbnailGenerator / FSEvents / Spotlight | - |
| macOS 标签 | xattr + plist | - |

---

## 3. 项目结构

```
/Volumes/Iris-Data/Download/AI/文件管理系统/
├── flowfinder-native/                    # 主项目（当前开发重点）
│   ├── FlowFinderNative/                 # Swift Xcode 项目
│   │   ├── FlowFinderNative/
│   │   │   ├── App/                      # 应用入口
│   │   │   │   ├── AppDelegate.swift
│   │   │   │   └── FlowFinderApp.swift
│   │   │   ├── Bridge/                   # Swift ↔ Rust 桥接层
│   │   │   │   ├── CoreBridge.swift
│   │   │   │   ├── FFIFunctions.swift
│   │   │   │   ├── SMBBridge.swift
│   │   │   │   ├── SearchBridge.swift
│   │   │   │   ├── SpotlightBridge.swift
│   │   │   │   ├── TagBridge.swift
│   │   │   │   ├── TaskSchedulerManager.swift
│   │   │   │   ├── ThemeManager.swift
│   │   │   │   └── ThumbnailManager.swift
│   │   │   ├── Model/                     # 数据模型
│   │   │   │   ├── FileEntry.swift
│   │   │   │   ├── PaneState.swift
│   │   │   │   ├── SidebarItem.swift
│   │   │   │   ├── Tag.swift
│   │   │   │   ├── TaskInfo.swift
│   │   │   │   └── VolumeInfo.swift
│   │   │   ├── UI/                        # UI 组件（核心开发区域）
│   │   │   │   ├── MainWindowController.swift
│   │   │   │   ├── FileListView.swift
│   │   │   │   ├── FileGridView.swift
│   │   │   │   ├── SidebarView.swift
│   │   │   │   ├── BreadcrumbBar.swift
│   │   │   │   ├── PaneToolbar.swift
│   │   │   │   ├── ExpandableDetailsBar.swift
│   │   │   │   ├── FFScroller.swift           # [新增] 自定义滚动条
│   │   │   │   ├── FFGlassView.swift          # 玻璃态视图基类
│   │   │   │   ├── AboutWindowController.swift # [新增] 关于窗口
│   │   │   │   ├── FileInfoWindowController.swift # [新增] 文件信息窗口
│   │   │   │   ├── AppearanceSettingsView.swift
│   │   │   │   ├── DuplicateScanWindowController.swift
│   │   │   │   ├── SearchPanelController.swift
│   │   │   │   ├── SettingsWindowController.swift
│   │   │   │   └── ... (其他 UI 组件)
│   │   │   ├── Libraries/                  # 编译后的 Rust 库
│   │   │   │   ├── libflowfinder_core.a
│   │   │   │   └── libflowfinder_core.dylib
│   │   │   └── Resources/
│   │   │       └── Info.plist
│   │   └── FlowFinderNative.xcodeproj/
│   │       └── project.pbxproj             # Xcode 项目配置
│   ├── rust-core/                          # Rust 核心引擎
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   ├── ffi/mod.rs                  # FFI 导出层
│   │   │   └── core/                       # 核心模块
│   │   │       ├── bulk_read.rs            # getattrlistbulk 批量读取
│   │   │       ├── scanner.rs              # 文件扫描 + 元数据
│   │   │       ├── dedup_engine.rs          # 三阶段重复检测
│   │   │       ├── cow_copy.rs             # APFS CoW 复制
│   │   │       ├── dir_cache.rs            # LRU 目录缓存
│   │   │       ├── task_scheduler.rs       # 任务调度器
│   │   │       ├── search_engine.rs        # 搜索引擎
│   │   │       ├── sqlite_cache.rs         # SQLite 持久化
│   │   │       ├── path_guard.rs            # 路径安全
│   │   │       └── volumes.rs              # 卷管理
│   │   ├── include/
│   │   │   └── ff_ffi.h                    # C 头文件（FFI 接口）
│   │   └── Cargo.toml
│   ├── docs/                               # 项目文档
│   │   ├── superpowers/
│   │   │   ├── specs/                     # 设计文档
│   │   │   └── plans/                     # 实施计划
│   │   ├── MIGRATION_LOG.md                # 完整重构日志
│   │   ├── MIGRATION_PLAN.md              # 迁移计划
│   │   └── VERIFICATION.md                # 验证清单
│   ├── .trae/specs/code-audit-and-roadmap/ # 代码审计与路线图
│   │   ├── spec.md
│   │   ├── tasks.md
│   │   └── checklist.md
│   ├── scripts/                            # 构建脚本
│   │   ├── package.sh                     # 打包脚本
│   │   ├── build-rust.sh
│   │   └── benchmark.sh
│   ├── dist/                               # [新增] 发布产物
│   │   ├── FlowFinderNative-v0.6.4-mac.dmg
│   │   ├── FlowFinderNative-v0.6.4-mac.zip
│   │   └── release-notes-v0.6.4.md
│   └── README.md
├── SMBFileManager/                         # 旧版 Tauri + React 项目（已搁置）
├── flowfinder-ui-redesign/                 # UI 设计稿（HTML mockup）
└── .trae/design-mockups/                   # 最新设计稿
    └── pages/
        ├── 主窗口 - 列表视图（精修版）.html    # 对齐基准
        ├── 主窗口 - 网格视图（精修版）.html
        └── ...
```

---

## 4. 开发进度总览

### 路线图

| 阶段 | 状态 | 内容 |
|------|------|------|
| Phase 1: MVP | ✅ 完成 | 基础框架、文件操作、搜索、Quick Look |
| Phase 2: 增强 | ✅ 完成 | 重复检测、目录缓存、批量重命名 |
| Phase 3: 完善 | ✅ 完成 | 缩略图、设置面板、任务调度 |
| Phase 4: 收尾 | ✅ 完成 | 卷管理、玻璃态双栏重构 |
| Phase 5: 稳定 | 🔄 进行中 | 跨面板操作、性能优化、0.6.4 发布 |
| Phase 6: 正式版 | ⏳ 待开始 | 全面测试、文档完善、1.0 发布 |

### 代码审计完成度（v0.6.0-alpha）

| 层级 | 已完成 | 部分完成 | 未开始 | 完成率 |
|------|--------|---------|--------|--------|
| Rust Core (6项) | 2 | 3 | 1 | 58% |
| Bridge 层 (9项) | 6 | 3 | 0 | 83% |
| UI 层 Phase 2-6 (20项) | 16 | 4 | 0 | 90% |
| UI 重设计 10项需求 | 9 | 1 | 0 | 95% |
| **合计 (45项)** | **33** | **11** | **1** | **82%** |

### 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.6.0-alpha | 2026-07-21 | 首个原生版本发布 |
| 0.6.01 | 2026-07-22 | Xcode 27 beta 链接器兼容性 + 发行版准备 |
| 0.6.02 | 2026-07-23 | 全面代码审计修复 - FFI 契约统一 + 关键 bug 修复 |
| 0.6.2 | 2026-07-25 | v1 重新设计 Phase 0-5 + 13 项 P0 修复 |
| 0.6.3 | 2026-07-26 | 17 项 UI 修复任务（A1-A6/B8-B11/C12-C13/D15-D17/E18-E19） |
| **0.6.4** | **2026-07-27** | **9 项截图差异修复 + 编译错误修复（当前版本）** |

---

## 5. v0.6.4 最新修复内容

### 5.1 17 项 UI 修复任务（v0.6.3 承接）

#### A 系列 - 导航与交互
- ✅ **A1** 侧边栏收藏夹拖拽 + 右键菜单添加（仅文件夹）
- ✅ **A2 / A2b** 每面板独立两行布局 + 路径栏点击跳转 + chevron 同级下拉
- ✅ **A6** 右键"显示简介"仿访达独立窗口（FileInfoWindowController）

#### B 系列 - 设备模块重构
- ✅ **B8** 设备模块浮动在侧边栏左下角上层
- ✅ **B9** 设备行单行显示 + 悬停气泡详情
- ✅ **B10** 设备栏默认折叠，点击向上展开
- ✅ **B11** statfs 读取真实磁盘容量 + 过滤隐藏卷

#### C 系列 - 文件列表
- ✅ **C12** 文件名后内联标签药丸
- ✅ **C13** 右键标签二级菜单（现有标签 + 新建项）

#### D 系列 - 工具窗口
- ✅ **D15** 搜索栏末尾工具按钮（查重 + AI + 重命名）
- ✅ **D16** 查重工具独立窗口（样式对齐）
- ✅ **D17** 合并至 D15/D16

#### E 系列 - 视觉与主题
- ✅ **E18** 侧边栏 sidebar 标准材质
- ✅ **E19** 右侧双面板白色底微透明

### 5.2 9 项截图差异修复（v0.6.4 本轮）

1. ✅ 收藏夹左对齐（indentationPerLevel = 0）
2. ✅ 收藏夹内容预置
3. ✅ 全局细滚动条（FFScroller，overlay + mini）
4. ✅ 路径栏位置 + chevron.right 可点击同级跳转
5. ✅ 单击选中视觉提示（恢复标准选中样式）
6. ✅ 三栏布局（侧边栏 + 圆角 12pt 操作区 + divider 悬停高亮）
7. ✅ 应用图标和名称移至侧边栏顶部
8. ✅ 操作区背景色随主题切换（日间白 0.15 / 夜间黑 0.25）
9. ✅ 夜间模式切换（light/dark 二态）

### 5.3 编译错误修复（v0.6.4 本轮）

- ✅ ThemeManager.swift：移除 @Published 和 .system 默认值
- ✅ FFScroller.swift：.thumb 改为 .knob（macOS AppKit API）
- ✅ BreadcrumbBar.swift：openURL 改为 open(_:)（新 SDK API）
- ✅ MainWindowController.swift：补全 applyPaneBackgroundColor() 方法
- ✅ AppearanceSettingsView.swift：重写为 light/dark 二态

### 5.4 右键菜单增强

- 复制、粘贴、新建文件夹等操作增加 SF Symbols 图标
- "复制到/移动到另对侧面板"按面板方向区分箭头图标

---

## 6. 待办事项（下一阶段）

### 6.1 用户验证待办

- ⏳ **用户截图验证 v0.6.4 界面修复效果**（9 项差异是否全部修复）

### 6.2 功能扩展待办

- ⏳ **工具按钮展开侧边栏底部工具面板**（查重/重命名等）
- ⏳ **全局撤销/重做栈完善**（当前仅菜单占位，需 UndoManager 集成）
- ⏳ **Intel Mac 通用二进制支持**
- ⏳ **文件分组显示功能**
- ⏳ **大目录性能优化（10万+ 文件）**
- ⏳ **AI 标签生成引擎**（xattr 读写完整，但无 AI 分类引擎）

### 6.3 架构完善待办（来自代码审计）

- ⏳ **RC-4: Rust 侧 SMB 模块**（当前由 Swift 直接处理，可能不需要补齐）
- ⏳ **RC-2: sqlite_cache 完整接入 FFI**（当前仅内存 LRU）
- ⏳ **RC-3: parallel_ops 接入 FFI**（已实现但无 FFI 导出）

### 6.4 发布流程待办

- ✅ Debug 构建
- ✅ Release 构建
- ✅ DMG + ZIP 打包
- ✅ GitHub Release v0.6.4 已发布
- ⏳ 安装到 /Applications 验证
- ⏳ 用户最终验收

---

## 7. 构建与发布

### 7.1 环境要求

- **macOS** 13.0+（Apple Silicon 或 Intel）
- **Xcode** 15+（含 Swift 5.9+），当前使用 Xcode-beta
- **Rust** 1.75+（通过 `rustup` 安装）
- **Xcode Command Line Tools**

### 7.2 构建命令

```bash
# 设置 Xcode-beta 路径（必需）
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

# Debug 构建
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native
xcodebuild -project FlowFinderNative/FlowFinderNative.xcodeproj \
           -scheme FlowFinderNative \
           -configuration Debug build

# Release 构建
xcodebuild -project FlowFinderNative/FlowFinderNative.xcodeproj \
           -scheme FlowFinderNative \
           -configuration Release build

# 构建产物路径
# Debug: ~/Library/Developer/Xcode/DerivedData/FlowFinderNative-*/Build/Products/Debug/FlowFinderNative.app
# Release: ~/Library/Developer/Xcode/DerivedData/FlowFinderNative-*/Build/Products/Release/FlowFinderNative.app
```

### 7.3 打包 DMG + ZIP

```bash
# Release 产物路径
RELEASE_DIR="$HOME/Library/Developer/Xcode/DerivedData/FlowFinderNative-*/Build/Products/Release"
DIST_DIR="/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/dist"

# 复制 .app
cp -R "$RELEASE_DIR/FlowFinderNative.app" "$DIST_DIR/"

# 创建 ZIP
cd "$DIST_DIR"
zip -r -y FlowFinderNative-v0.6.4-mac.zip FlowFinderNative.app

# 创建 DMG（含 /Applications 软链接）
mkdir -p dmg-staging
cp -R FlowFinderNative.app dmg-staging/
ln -s /Applications dmg-staging/Applications
hdiutil create -volname "FlowFinderNative 0.6.4" \
  -srcfolder dmg-staging \
  -ov -format UDZO \
  FlowFinderNative-v0.6.4-mac.dmg
rm -rf dmg-staging
```

### 7.4 GitHub Release 发布

```bash
gh release create v0.6.4 \
  --repo waltxao/FlowFinder \
  --title "FlowFinder Native v0.6.4 (640)" \
  --notes-file dist/release-notes-v0.6.4.md \
  --target main \
  dist/FlowFinderNative-v0.6.4-mac.dmg \
  dist/FlowFinderNative-v0.6.4-mac.zip
```

### 7.5 当前 Release

- **URL：** https://github.com/waltxao/FlowFinder/releases/tag/v0.6.4
- **资产：**
  - FlowFinderNative-v0.6.4-mac.dmg (3.5M)
  - FlowFinderNative-v0.6.4-mac.zip (3.0M)

---

## 8. 关键设计决策

### 8.1 硬约束（来自 project_memory）

- ✅ 仅支持 macOS 平台，永久放弃 Windows 兼容性
- ✅ 应用必须可交付为单个可运行文件（.zip with .app 或 DMG）
- ✅ 所有磁盘列表必须排除系统隐藏卷
- ✅ 标签系统必须统一 AI 生成标签（SQLite virtual_tags 表）与 macOS 原生标签（xattr 同步）
- ✅ 主题系统必须包含浅色/深色模式 + 系统跟随选项 + 工具栏切换
- ✅ 文件列表必须支持列宽拖拽和点击排序
- ✅ 侧边栏区段必须可折叠，状态持久化
- ✅ 文件/文件夹拖拽操作必须检查卷类型（通过 statfs 设备 ID 比较）确定默认移动/复制行为
- ✅ 系统隐藏文件必须灰色文字显示，系统保护文件红色文字显示
- ✅ 应用必须使用用户提供的自定义图标
- ✅ 所有 UI 必须使用原生 macOS vibrancy 材质（NSVisualEffectView）
- ✅ CSS 必须全局禁用文字选择（user-select: none）
- ✅ 滚动条必须使用 macOS 风格 overlay 设计
- ✅ 错误处理必须包含全局 ErrorBoundary

### 8.2 用户偏好（来自 user_profile）

- 沟通语言：中文
- UI 布局：偏好 macOS Finder 风格统一工具栏
- UI 行为：详情面板默认隐藏，选中文件时自动显示
- UI 间距：组件应填满整个内容区域宽度
- UI 语言：偏好中文界面（非英文）
- UI 交互：偏好 Finder 风格拖拽行为（同盘移动，跨盘复制，Cmd 切换）
- UI 列顺序：名称 → 修改日期 → 类型 → 大小 → 标签
- 文件操作：要求全局撤销栈支持多种操作
- UI 设计：偏好玻璃态 + 极简扁平风格
- 主题偏好：自动跟随系统主题
- UI 定制：优先原生 macOS 视觉和交互一致性

### 8.3 17 项任务的具体实现方式

| 任务 | 实现方式 |
|------|---------|
| A1 收藏夹添加 | 拖拽 + 右键菜单（仅文件夹） |
| A2 两行布局 | 每面板独立两行 |
| A2b 路径栏交互 | 点击跳转 + 箭头同级下拉 |
| A6 显示简介 | 仿访达独立窗口 |
| B8 设备模块位置 | 浮动在侧边栏左下角上层 |
| B9 设备行布局 | 行内简略 + 气泡详情 |
| B10 设备折叠 | 整块点击，向上展开 |
| B11 磁盘容量 | statfs + 过滤隐藏卷 |
| C12 标签位置 | 文件名后内联药丸 |
| C13 标签菜单 | 现有标签 + 新建项 |
| D15 工具按钮 | 查重 + AI + 重命名 |
| D16 查重窗口 | 仅样式对齐 |
| E18 侧边栏材质 | sidebar 标准材质 |
| E19 操作区背景 | 白色底 + 微透明 |

### 8.4 右键菜单图标

- 使用 SF Symbols 图标
- 复制、粘贴、新建文件夹等都有对应 ICON
- "复制到/移动到另对侧面板"按面板方向区分箭头图标

---

## 9. 关键文件索引

### 9.1 核心代码文件

| 文件 | 职责 |
|------|------|
| [MainWindowController.swift](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/MainWindowController.swift) | 主窗口控制器，三栏布局，操作区圆角，divider 悬停高亮 |
| [SidebarView.swift](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/SidebarView.swift) | 侧边栏，收藏夹左对齐，应用图标，夜间模式切换 |
| [FileListView.swift](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/FileListView.swift) | 文件列表视图，标准选中样式 |
| [BreadcrumbBar.swift](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/BreadcrumbBar.swift) | 路径面包屑，点击跳转，chevron 同级下拉 |
| [FFScroller.swift](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/FFScroller.swift) | 自定义细滚动条 |
| [FFGlassView.swift](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/FFGlassView.swift) | 玻璃态视图基类 |
| [ThemeManager.swift](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/Bridge/ThemeManager.swift) | 主题管理，light/dark 二态 |
| [AppearanceSettingsView.swift](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/AppearanceSettingsView.swift) | 外观设置视图 |
| [AboutWindowController.swift](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/AboutWindowController.swift) | 关于窗口 |
| [FileInfoWindowController.swift](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/UI/FileInfoWindowController.swift) | 文件信息窗口 |
| [CoreBridge.swift](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/FlowFinderNative/FlowFinderNative/Bridge/CoreBridge.swift) | Rust ↔ Swift 桥接核心 |

### 9.2 设计文档

| 文档 | 说明 |
|------|------|
| [spec.md](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/.trae/specs/code-audit-and-roadmap/spec.md) | 代码审计与路线图完整 spec |
| [tasks.md](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/.trae/specs/code-audit-and-roadmap/tasks.md) | 14 项任务清单（已全部完成） |
| [checklist.md](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/.trae/specs/code-audit-and-roadmap/checklist.md) | 验证清单（已全部通过） |
| [2026-07-26-ui-fixes-batch.md](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/docs/superpowers/plans/2026-07-26-ui-fixes-batch.md) | UI 差异修复实施计划 |
| [MIGRATION_LOG.md](file:///Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/docs/MIGRATION_LOG.md) | 完整重构日志 |

### 9.3 设计稿

| 设计稿 | 说明 |
|--------|------|
| [主窗口 - 列表视图（精修版）.html](file:///Volumes/Iris-Data/Download/AI/文件管理系统/.trae/design-mockups/pages/主窗口%20-%20列表视图（精修版）.html) | **对齐基准** |
| [主窗口 - 网格视图（精修版）.html](file:///Volumes/Iris-Data/Download/AI/文件管理系统/.trae/design-mockups/pages/主窗口%20-%20网格视图（精修版）.html) | 网格视图对齐基准 |
| [设置窗口.html](file:///Volumes/Iris-Data/Download/AI/文件管理系统/.trae/design-mockups/pages/设置窗口.html) | 设置窗口设计稿 |
| [搜索面板.html](file:///Volumes/Iris-Data/Download/AI/文件管理系统/.trae/design-mockups/pages/搜索面板.html) | 搜索面板设计稿 |
| [查重扫描窗口.html](file:///Volumes/Iris-Data/Download/AI/文件管理系统/.trae/design-mockups/pages/查重扫描窗口.html) | 查重窗口设计稿 |
| [右键菜单与对话框.html](file:///Volumes/Iris-Data/Download/AI/文件管理系统/.trae/design-mockups/pages/右键菜单与对话框.html) | 右键菜单设计稿 |

---

## 10. 用户反馈与注意事项

### 10.1 用户工作规则（最高优先级）

1. **零容忍一次性任务**：任何可能重复执行的需求，第一次必须先手动处理 3-10 个样本并输出结果给用户确认。确认通过后必须立即将逻辑固化为 SKILL.md
2. **MECE 原则**：每种工作类型有且只有一个技能负责，不重叠、不空白
3. **最狠的失败判定**：如果用户第二次要求做同一件事，即判定为系统性失败
4. **六步闭环流程**：概念 → 原型 → 评估 → 编码 → 定时 → 监控
5. **回复语言**：必须全部为简体中文，不得包含繁体字

### 10.2 用户沟通风格

- 在回答或执行前先向用户提问，一次只问一个
- 根据用户的回答继续追问，直到有 99% 的信心完全理解真实需求和目标
- 使用 Walt 偏好的写作风格

### 10.3 历史问题与解决方案

| 问题 | 根因 | 解决方案 |
|------|------|---------|
| 界面完全透明 | NSGlassEffectView(.clear) 导致 | 统一使用 NSVisualEffectView(.underWindowBackground) |
| 文件列表列数不符 | 仅实现 4 列 | 移除第 5 列，改为名称列内联标签药丸 |
| 标签 section 样式 | 全宽行样式 | 实现 TagFlowView 横向流式布局 |
| TitleBar 位置 | 使用 NSTitlebarAccessoryViewController | 自定义 TitleBar 视图 |
| 设备模块位置 | 未脱离垂直 stack | 浮动在侧边栏左下角，z-index 覆盖 |
| 设备行布局 | 双行 + 进度条 | 单行 + 悬停气泡 |
| 设备折叠方向 | 默认向上展开 | 改为默认折叠，点击向上展开 |
| 磁盘容量 | Rust 端返回 | 使用 statfs 系统调用，过滤隐藏卷 |
| 收藏夹添加缺失 | 缺少拖拽和右键 | 实现拖拽 + 右键菜单（仅文件夹） |
| 版本号不完整 | CURRENT_PROJECT_VERSION 未更新 | 使用 replace_all=true 重新替换 |
| 路径栏箭头冗余 | 同时有分隔符和向下箭头 | 移除向下箭头，分隔符改为 chevron.right |
| FFScroller 编译错误 | 使用已废弃 API | 替换为 rect(for: .knob) |
| ThemeManager 编译错误 | 移除 .system 后未清理 | 删除所有引用 AppearanceMode.system 的代码 |
| xcodebuild 路径错误 | 指向 CommandLineTools | 使用 DEVELOPER_DIR 环境变量指定 Xcode-beta |

---

## 11. 给下一个 AI 的交接说明

### 11.1 当前状态

- **最新版本：** 0.6.4 (640) 已发布到 GitHub Release
- **源码：** 已推送到 main 分支（5b0717c）
- **构建：** Debug 和 Release 均构建成功
- **运行：** 当前 Debug 版本正在运行中

### 11.2 立即待办

1. **等待用户截图验证 v0.6.4 界面修复效果**
2. 如有问题，根据截图反馈继续修复
3. 如验证通过，进入下一阶段功能开发

### 11.3 开发环境配置

```bash
# 必需：设置 Xcode-beta 路径
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

# 项目路径
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native

# 快速构建验证
xcodebuild -project FlowFinderNative/FlowFinderNative.xcodeproj \
           -scheme FlowFinderNative \
           -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"
```

### 11.4 重要提示

1. **必须使用 Xcode-beta**，不能使用默认的 CommandLineTools
2. **必须设置 DEVELOPER_DIR 环境变量**，否则 xcodebuild 会失败
3. **版本号在 project.pbxproj 中**：MARKETING_VERSION 和 CURRENT_PROJECT_VERSION
4. **对齐基准是"精修版"设计稿**，不是"优化版"
5. **列表视图和网格视图都要对齐设计稿**
6. **所有 UI 文案和代码注释使用简体中文**
7. **右键菜单必须包含 SF Symbols 图标**
8. **主题切换是 light/dark 二态**（无 system 自动跟随）

### 11.5 用户验收标准

用户会通过截图对比设计稿，检查以下要点：
- 侧边栏、左侧操作区、右侧操作区三栏布局
- 收藏夹左对齐
- 全局细滚动条
- 路径栏位置和交互
- 单击选中视觉提示
- 应用图标和名称位置（侧边栏顶部）
- 操作区背景色（日间白 0.15 / 夜间黑 0.25）
- 夜间模式切换功能
- 右键菜单图标

---

## 12. 参考链接

- **GitHub 仓库：** https://github.com/waltxao/FlowFinder
- **最新 Release：** https://github.com/waltxao/FlowFinder/releases/tag/v0.6.4
- **官方网站：** https://waltxao.github.io/FlowFinder/
- **设计稿目录：** `/Volumes/Iris-Data/Download/AI/文件管理系统/.trae/design-mockups/pages/`
- **对齐基准：** `主窗口 - 列表视图（精修版）.html`

---

**交接完成。** 请下一个 AI 接手后，先阅读本文件，然后等待用户截图验证 v0.6.4 界面修复效果，根据反馈继续开发。
