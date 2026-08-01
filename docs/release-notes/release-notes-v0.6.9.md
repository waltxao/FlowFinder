# FlowFinder v0.6.9 发布说明

> **版本：** v0.6.9 (690)
> **日期：** 2026-08-01
> **前置版本：** v0.6.8 (680)

---

## 概述

v0.6.9 是一次 UI 细节精细化修复版本，针对 v0.6.8 后用户反馈的 6 个核心问题进行修复，涵盖 QuickLook 预览、超椭圆圆角、操作区视觉、详情栏浮动、文件名双行布局、文件夹配置菜单和工具选择覆盖页。

---

## 问题修复清单

| # | 模块 | 问题 | 根因 | 修复方案 |
|---|------|------|------|----------|
| 1 | QuickLook | 按空格键 QuickLook 完全无反应 | `QuickLookPreviewPanel` 为 NSObject 子类，未进入 responder chain，QLPreviewPanel 找不到 controller | 基类改为 NSResponder，实现 QLPreviewPanelController informal protocol，通过 responder chain 插入/移除 |
| 2 | 侧边栏 | 「我的收藏」标题与文件夹列表间距过大（12pt），与标签区（4pt）不一致；文件夹图标有缩进 | constraint constant 为 12；NSOutlineView 内部 cell 默认偏移 | 间距改为 4pt；`indentationPerLevel = 0` + `intercellSpacing = zero` |
| 3 | 操作区 | 白色背景未覆盖顶部工具栏；圆角为标准圆角非超椭圆；无边框；有分割线；拖动时显示蓝色边框 | 背景未覆盖工具栏区域；使用 `cornerRadius`；`dividerThickness` 默认值；拖动时添加 border | SquircleView 16pt 圆角；1px 边框；`dividerThickness = 0`；CAGradientLayer 渐变亮线 |
| 4 | 详情栏 | 详情栏在容器内部底部，文件列表因展开而缩短 | listView.bottomAnchor 锚定 detailsBar.topAnchor | 详情栏改为浮层，listView.bottomAnchor 锚定 container.bottomAnchor，增加阴影+12pt 圆角 |
| 5 | 文件名 | 文件名单行，标签在右侧；网格视图不显示标签 | cell 布局为单行 | 双行布局（上文件名、下标签药丸），动态行高（48pt/26pt） |
| 6 | 工具菜单 | 搜索栏后方工具菜单为查重/AI 工具菜单，需改为文件夹显示配置菜单 | 菜单内容不匹配需求 | 新菜单含 4 项显示开关 + 新建文件夹；工具功能移至 ToolOverlayView 覆盖页 |

---

## 新增文件

| 文件 | 用途 |
|------|------|
| `UI/SquircleView.swift` | 超椭圆圆角工具类，通过 CGPath 绘制 superellipse 路径 |
| `UI/ToolOverlayView.swift` | 工具选择覆盖页，大方块网格布局 |

---

## 修改文件

| 文件 | 变更内容 |
|------|----------|
| `UI/QuickLookPreviewView.swift` | 基类改为 NSResponder，实现 QLPreviewPanelController 协议，responder chain 管理 |
| `UI/MainWindowController.swift` | SquircleView 容器、边框、分割线移除、渐变亮线、详情栏浮层、ToolOverlayView 集成、通知观察者、Esc 关闭 |
| `UI/PaneToolbar.swift` | 工具菜单改为文件夹配置菜单，4 项显示开关 + 新建文件夹 |
| `UI/ExpandableDetailsBar.swift` | 圆角从 8pt 改为 12pt |
| `UI/FileListView.swift` | 双行布局、showFileTags/showFileExtensions 显示控制、动态行高 |
| `UI/FileGridView.swift` | 标签药丸显示、showFileTags/showFileExtensions 显示控制 |
| `UI/SidebarView.swift` | 收藏夹间距从 12pt 改为 4pt |
| `UI/FFCommon.swift` | 新增 UserDefaults keys 和 Notification names |
| `Model/PaneState.swift` | 新增 applyDisplayFilter 过滤隐藏文件和系统文件 |
| `FlowFinderNative.xcodeproj/project.pbxproj` | 添加 ToolOverlayView.swift 到项目，版本号更新到 0.6.9 (690) |

---

## 测试要点

1. **QuickLook**：选中文件按空格键弹出预览，方向键切换，Esc 关闭，再次空格切换
2. **文件夹配置菜单**：点击 `slider.horizontal.3` 按钮，切换 4 项显示开关，验证文件列表实时更新
3. **工具覆盖页**：点击侧边栏工具按钮，操作区显示工具选择页，点击查重/批量重命名正常触发，Esc/关闭按钮关闭
4. **超椭圆圆角**：观察操作区容器圆角为平滑的超椭圆曲线
5. **详情栏浮层**：选中文件后详情栏浮在文件列表上方，文件列表高度不变
6. **双行布局**：有标签的文件显示双行（文件名 + 标签药丸），无标签单行
7. **拖动亮线**：拖动操作区分隔条时仅显示渐变亮线，无蓝色边框
