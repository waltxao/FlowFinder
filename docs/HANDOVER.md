# FlowFinder Native 项目交接文档

> **交接日期：** 2026-08-01
> **当前版本：** 0.6.9 (690)
> **仓库地址：** https://github.com/waltxao/FlowFinder
> **分支：** main
> **最新提交：** v0.6.9（UI 细节精细化修复 + QuickLook 预览修复）
> **本地路径：** `/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native`

---

## 1. 项目概述

FlowFinder（中文名：**流方达**）是一款专为 macOS 打造的原生文件管理器，采用 **Swift & AppKit** 构建用户界面，**Rust Core** 提供高性能后端引擎，通过 FFI（C ABI）实现跨语言调用。

### 核心亮点

- **纯原生 UI**：Swift & AppKit 构建，NSVisualEffectView 系统级亚克力材质
- **高性能 Rust Core**：getattrlistbulk 批量读取、BLAKE3 哈希、rayon 并行处理
- **Finder 级交互**：原生拖拽、Quick Look 预览、双栏布局
- **双视图**：列表视图 + 网格视图，跟随系统深浅色主题

### 性能指标

| 指标 | 原版（Tauri） | 新版（Native） | 提升 |
|------|--------------|----------------|------|
| 目录列表（冷） | ~15-30 ms | ~0.5-1.0 ms | **10-30x** |
| 目录列表（热） | ~5-10 ms | ~0.2-0.5 ms | **10-20x** |
| 内存占用 | ~50-100 MB | ~20-30 MB | **2-3x** |
| 启动时间 | ~2-3s | ~0.5s | **4-6x** |
| 二进制大小 | ~80-100 MB | ~15-20 MB | **5-6x** |

---

## 2. 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.6.0-alpha | 2026-07-21 | 首个原生版本发布 |
| 0.6.01 | 2026-07-22 | Xcode 27 beta 链接器兼容性 |
| 0.6.02 | 2026-07-23 | 全面代码审计修复 |
| 0.6.2 | 2026-07-25 | v1 重新设计 Phase 0-5 |
| 0.6.3 | 2026-07-26 | 17 项 UI 修复任务 |
| **0.6.4** | **2026-07-27** | **9 项截图差异修复（首个 GitHub Release）** |
| **0.6.5** | **2026-07-27** | **仿访达 UI 重构（F2-F9）+ 全量巡检 P0** |
| **0.6.6** | **2026-07-28** | **仿访达完整重设计（F10-1~12，20 问题）** |
| **0.6.7** | **2026-07-29** | **全应用 UI 重设计（F11-1~12，核心架构转变）** |

---

## 3. 当前架构风格（v0.6.7 核心变化）

v0.6.7 经历了从"全透明玻璃"到"亚克力侧边栏 + 实体内容区"的重大架构转变。

| 区域 | 材质 | 说明 |
|------|------|------|
| 侧边栏 + 窗口边框 | 亚克力 vibrancy（`.sidebar`） | 访达标准材质 |
| 操作区（左右面板） | 实体背景（日间 #F5F5F5 / 夜间 #2D2D2D） | **v0.6.7 改为实体，解决透明度问题** |
| 所有子窗口 | 实体背景 | 移除 FFGlassView 透明材质 |

### 3.1 技术栈

| 层 | 技术 | 版本 |
|----|------|------|
| UI 框架 | Swift & AppKit | 5.9+ |
| 后端引擎 | Rust（cdylib） | 2021 edition |
| 数据库 | rusqlite (bundled SQLite) | 0.32 |
| 哈希 | BLAKE3 + xxHash64 | - |
| 并行 | rayon | 1.10 |
| macOS 原生 | NSVisualEffectView / QLThumbnailGenerator / FSEvents / Spotlight | - |
| macOS 标签 | xattr + plist + _kMDItemUserTags | - |

### 3.2 架构图

```
+----------------------------------------------------------+
| 窗口边框（亚克力 vibrancy）                               |
| +----------------+-----------------------+--------------+ |
| | 侧边栏（亚克力）| 操作区（实体#F5F5F5） | 操作区（实体） | |
| | - 个人收藏     | - 工具栏（双行）       | - 同左       | |
| | - 标签        | - 文件列表/分组        | - 同左       | |
| | - 底部按钮    | - 详情栏              | - 同左       | |
| | - 工具面板    | - 底部状态栏(进度)     | - 同左       | |
| +----------------+-----------------------+--------------+ |
| 设备浮层（实体背景，浮动左下角）                           |
+----------------------------------------------------------+
```

---

## 4. v0.6.7 修复清单

### 第一层：核心架构转变（F11-1~3）

| 编号 | 内容 | 涉及文件 | 说明 |
|------|------|---------|------|
| F11-1 | 操作区实体背景 | MainWindowController、FileListView、FileGridView | 从透明改为日间#F5F5F5/夜间#2D2D2D，侧边栏保留亚克力 |
| F11-2 | 子窗口全部实体背景 | Settings/Duplicate/Search/About/FileInfo/BatchRename/FFModalSheet/ProgressDialog（8文件） | 所有子窗口从透明改为实体，移除FFGlassView依赖 |
| F11-3 | 主题恢复三态+全局ErrorBoundary | ThemeManager、AppearanceSettingsView、AppDelegate | 恢复.system（v0.6.5错误移除）；NSSetUncaughtExceptionHandler异常捕获 |

### 第二层：主窗口重设计（F11-4~6）

| 编号 | 内容 | 涉及文件 | 说明 |
|------|------|---------|------|
| F11-4 | 路径栏完全仿访达 | BreadcrumbBar（完全重写） | 废弃NSScrollView（位置漂移根因），改固定裁剪容器 |
| F11-5 | 分组重新设计仿访达 | FileListView、FileGridView | 粘性header+计数徽章+缩进+修复Title重叠（双重绘制根因） |
| F11-6 | 详情栏占位图标+设备实体背景 | ExpandableDetailsBar | 空白folder占位，选中后替换 |

### 第三层：功能修复（F11-7~9）

| 编号 | 内容 | 涉及文件 | 说明 |
|------|------|---------|------|
| F11-7 | 卡顿修复 | FileListView、FileGridView、ThumbnailManager | NSWorkspace.icon缓存+磁盘缓存异步+缩略图完全异步 |
| F11-8 | 搜索修复+标签筛选 | PaneState、SidebarView | 子目录递归+allFiles修复空白+标签点击筛选当前面板 |
| F11-9 | 复制/移动底部进度栏 | MainWindowController、TaskProgressBar | 动态展开+文件名百分比+完成淡出 |

### 第四层：遗漏项补充（F11-10~11）

| 编号 | 内容 | 涉及文件 | 说明 |
|------|------|---------|------|
| F11-10 | 标签与macOS原生同步 | TagBridge | 读写_kMDItemUserTags，Finder双向可见 |
| F11-11 | 工具面板+大目录分页 | SidebarView、PaneState、FileListView | 工具面板动画展开+首批500异步追加 |

---

## 5. 关键架构决策（务必阅读，这些与旧文档不同）

| 决策 | 当前状态 | 历史变化 |
|------|---------|---------|
| **操作区背景** | 实体（#F5F5F5/#2D2D2D） | v0.6.4 透明 0.15/0.25 → v0.6.6 clear → **v0.6.7 实体** |
| **主题** | 三态（light/dark/system） | v0.6.5 移除.system → **v0.6.7 恢复三态** |
| **选中** | standard .regular（实体背景上蓝色可见） | v0.6.5 F7 0.6alpha错误 → v0.6.6 F10-2 改.clear → **v0.6.7 实体背景上清晰** |
| **收藏夹图标** | 彩色真实图标（NSWorkspace.icon） | v0.6.5 F4 错误改为蓝色模板 → v0.6.6 F10-4 改回 |
| **收藏夹折叠** | 不折叠（用户明确要求） | 与旧 HANDOVER.md 硬约束冲突，已废弃 |
| **标签列（第5列）** | 4列+内联药丸 | 已废弃第5列 |
| **标签同步** | 读写_kMDItemUserTags，Finder可见 | v0.6.7 新增 |
| **FFGlassView** | 仅侧边栏亚克力使用，子窗口已移除 | v0.6.7 移除 |
| **路径栏** | 完全仿访达重写（固定位置） | v0.6.7 重写，废弃NSScrollView |
| **ErrorBoundary** | 已实现 | v0.6.7 新增 |

---

## 6. 待办事项（下一阶段）

### 6.1 P1 问题（26 项，来自 v0.6.5 巡检报告）

建议优先级排序：

| 优先级 | 问题 | 位置 | 说明 |
|--------|------|------|------|
| 高 | **网格视图 appearance 同步** | FileGridView + MainWindowController | 主题监听仅调 list 未调 grid |
| 高 | **路径栏首段同级跳转缺失** | BreadcrumbBar | 根卷无法同级跳转 |
| 高 | **ProgressDialog 无调用方** | ProgressDialog | 死代码，需接线 |
| 中 | **详情栏材质对齐** | ExpandableDetailsBar | (F11-11已修，确认) |
| 中 | **网格视图缩略图校验对称** | FileGridView | (F10-9已修，确认) |
| 中 | **SidebarView 工具按钮反馈** | SidebarView | (F11-11已修，确认) |

详见 `docs/superpowers/specs/2026-07-27-v0.6.5-ui-audit-report.md`

### 6.2 P2 问题（26 项）

包括：细节美化、代码清理、性能微调等。详见巡检报告。

### 6.3 功能扩展待办

| 优先级 | 功能 | 说明 |
|--------|------|------|
| 中 | **Intel 通用二进制** | `ONLY_ACTIVE_ARCH=YES`，需改 Universal |
| 低 | AI 标签生成引擎 | Rust core 有规则版 generate_tags，非真正 AI |
| 低 | 全局撤销栈完善 | 当前 per-window UndoManager，可扩展 |

### 6.4 代码 Minor 问题（13 项）

记录在 `.superpowers/sdd/progress.md`，包括：
- 陈旧注释（MainWindowController.swift:233/444）
- 死代码（SidebarDataSourceBase.configureTagPill）
- API 兼容性守卫
- 等

---

## 7. 构建与发布

### 7.1 环境要求

- **macOS** 13.0+（Apple Silicon 或 Intel）
- **Xcode-beta**（当前使用），**必须设置 DEVELOPER_DIR**
- **Rust** 1.75+（通过 `rustup` 安装）

### 7.2 构建命令

```bash
# 必需：设置 Xcode-beta 路径
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

# 项目路径
cd /Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native

# Debug 构建
xcodebuild -project FlowFinderNative/FlowFinderNative.xcodeproj \
           -scheme FlowFinderNative \
           -configuration Debug build 2>&1 | grep -E "(error:|BUILD)"

# Release 构建
xcodebuild -project FlowFinderNative/FlowFinderNative.xcodeproj \
           -scheme FlowFinderNative \
           -configuration Release build 2>&1 | grep -E "(error:|BUILD)"
```

### 7.3 打包 DMG + ZIP

```bash
RELEASE_DIR="$HOME/Library/Developer/Xcode/DerivedData/FlowFinderNative-*/Build/Products/Release"
DIST_DIR="/Volumes/Iris-Data/Download/AI/文件管理系统/flowfinder-native/dist"

cp -R "$RELEASE_DIR/FlowFinderNative.app" "$DIST_DIR/"
cd "$DIST_DIR"
zip -r -y FlowFinderNative-v0.6.7-mac.zip FlowFinderNative.app

mkdir -p dmg-staging
cp -R FlowFinderNative.app dmg-staging/
ln -s /Applications dmg-staging/Applications
hdiutil create -volname "FlowFinderNative 0.6.7" \
  -srcfolder dmg-staging -ov -format UDZO \
  FlowFinderNative-v0.6.7-mac.dmg
rm -rf dmg-staging
```

### 7.4 GitHub Release

```bash
gh release create v0.6.7 \
  --repo waltxao/FlowFinder \
  --title "FlowFinder Native v0.6.7 (670)" \
  --notes-file docs/release-notes/release-notes-v0.6.7.md \
  --target main \
  dist/FlowFinderNative-v0.6.7-mac.dmg \
  dist/FlowFinderNative-v0.6.7-mac.zip
```

### 7.5 当前 Release

- **URL：** https://github.com/waltxao/FlowFinder/releases/tag/v0.6.7
- **资产：** DMG (3.6 MB) + ZIP (3.1 MB)
- /Applications 已安装 v0.6.7

### 7.6 GitHub Token 警告

旧 token 已暴露在对话历史中，**建议立即撤销并重新生成**。

---

## 8. macOS 27 SDK 注意事项

- `columnAutoresizingStyle`：用 `.lastColumnOnlyAutoresizingStyle`（非 `.lastColumnOnly`）
- `draw(withFrame:in:)` 替代旧版 `drawWithFrame:inView:`
- 部署目标 macOS 12.0，使用新 API 需加 `#available` 守卫
- `NSColor.secondarySystemFill` 需 macOS 14.0+

---

## 9. 关键文件索引

### 9.1 UI 核心文件（按重要性排序）

| 文件 | 行数 | 职责 |
|------|------|------|
| `UI/FileListView.swift` | ~2000 | 文件列表（列头、选中、分组、缩略图、搜索过滤） |
| `UI/MainWindowController.swift` | ~1500 | 主窗口（布局、设备浮层、底部进度栏、主题监听） |
| `UI/SidebarView.swift` | ~1755 | 侧边栏（收藏夹、标签、工具面板、主题/设置按钮） |
| `UI/FileGridView.swift` | ~1300 | 网格视图（选中、分组、缩略图复用） |
| `UI/PaneToolbar.swift` | ~355 | 工具栏（搜索、排序、分组、视图切换） |
| `UI/BreadcrumbBar.swift` | ~420 | 路径栏（v0.6.7 完全重写） |
| `UI/SettingsWindowController.swift` | ~580 | 设置窗口（分区布局） |
| `UI/ExpandableDetailsBar.swift` | ~530 | 详情栏（占位图标、选中显示） |

### 9.2 设计文档

| 文档 | 说明 |
|------|------|
| `docs/superpowers/specs/2026-07-29-v0.6.7-full-ui-redesign-design.md` | **v0.6.7 全应用 UI 重设计（最新）** |
| `docs/superpowers/specs/2026-07-28-v0.6.6-finder-clone-redesign-design.md` | v0.6.6 仿访达完整重设计 |
| `docs/superpowers/specs/2026-07-27-v0.6.5-ui-audit-report.md` | **v0.6.5 全量 UI 巡检报告（P1/P2 清单）** |
| `docs/MIGRATION_LOG.md` | **完整重构日志（建议先读）** |

### 9.3 设计稿 HTML

位于 `/Volumes/Iris-Data/Download/AI/文件管理系统/.trae/design-mockups/pages/`

---

## 10. 用户偏好与工作规则

### 10.1 用户偏好

| 偏好 | 当前实现 |
|------|---------|
| 沟通语言 | **简体中文**，不得包含繁体字 |
| 一次一问 | 问清一个问题再问下一个，直到 99% 信心 |
| 所有 UI 文案 | 简体中文 |
| 整体视觉 | **完全克隆访达** |
| 收藏夹 | "个人收藏"、不折叠、彩色真实图标 |
| 标签点击 | 筛选当前活动面板 |
| 设备栏 | 浮动左下角+实体背景 |
| 设置页 | 实体背景+分区布局 |
| 搜索 | 当前目录+子目录本地过滤 |
| 复制/移动反馈 | 底部状态栏进度条 |
| 操作区背景 | 日间#F5F5F5/夜间#2D2D2D |
| **图片输入** | **AI 不支持图片输入，用户截图无法查看，需依赖文字描述** |

### 10.2 用户工作规则（最高优先级）

1. **零容忍一次性任务**：可能重复的需求先手动处理样本确认，确认后固化为 SKILL.md
2. **MECE 原则**：每种工作类型有且只有一个 skill 负责
3. **最狠的失败判定**：第二次要求做同一件事即系统性失败
4. **六步闭环**：概念 → 原型 → 评估 → 编码 → 定时 → 监控

### 10.3 明确废弃的旧约束

| 旧约束（HANDOVER v0.6.4） | 状态 | 说明 |
|---------------------------|------|------|
| 侧边栏区段可折叠+持久化 | ❌ 废弃 | 用户明确要求不折叠 |
| 独立标签列（第5列） | ❌ 废弃 | 保持4列+内联药丸 |
| .system 跟随系统 | ✅ 恢复 | v0.6.5 错误移除，v0.6.7 恢复 |
| 全透明玻璃材质 | ❌ 废弃 | 改为亚克力侧边栏+实体内容区 |

---

## 11. 给下一个 AI 的启动指南

```
1. 先读本文件（HANDOVER.md），了解项目全貌和关键架构决策
2. 再读 docs/MIGRATION_LOG.md，了解版本历史
3. 设置 Xcode-beta：export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
4. 检查构建：xcodebuild ... -configuration Debug build
5. 等待用户反馈（注意：你看不到图片，需文字描述）
6. 如有新问题，先问一个澄清问题，一次只问一个
7. 按 brainstorming → writing-plans → subagent-driven-development 流程执行
8. 所有 UI 文案和代码注释使用简体中文
9. 工作完成后更新此交接文档
10. 注意：用户偏好优先于旧硬约束
```

---

**交接完成。** 请下一个 AI 接手后，先阅读本文件，理解 v0.6.7 的核心架构转变（亚克力+实体），然后等待用户反馈，根据反馈继续开发。
