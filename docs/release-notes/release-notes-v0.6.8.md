# FlowFinder Native v0.6.8 (680)

**发布日期：** 2026-07-31
**版本：** 0.6.8 (680)
**前置版本：** v0.6.7.1 (671)

---

## 概述

v0.6.8 是侧边栏交互与主题切换的稳定性修复版本，针对 v0.6.7 全应用 UI 重设计后用户反馈的侧边栏焦点框、收藏夹显示、标签同步、标签样式、日间/夜间模式切换等问题进行系统性修复。

## 修复清单

### 侧边栏

| 问题 | 根因 | 修复方案 |
|------|------|----------|
| 点击收藏夹文件夹时整个模块外出现蓝色焦点框 | NSOutlineView 获得键盘焦点时绘制 focus ring | 重写 `FFFNoDisclosureOutlineView.canBecomeKeyView` 返回 `false`，阻止获得键盘焦点，保留 `.sourceList` 选中高亮 |
| 收藏夹列表未完整显示（被滚动容器裁剪） | 外层 `NSScrollView` 的 ClipView 裁剪机制限制内容 | 移除外层滚动容器，收藏夹高度根据文件夹数量自适应，标签模块随之下移 |
| 新增标签未自动同步到侧边栏标签模块 | `FileListView`/`FileGridView` 发送的通知名（`FileListTagsChanged`）与 `TagsSidebarDataSource` 监听的通知名（`FileTagsDidChange`）不匹配 | 统一通知名称为 `FileTagsDidChange` |
| 标签样式不统一、未与收藏夹对齐 | 标签行使用透明背景而非药丸样式 | 统一为胶囊形状药丸 + 颜色圆点，背景为标签色浅底（0.12/0.22 透明度），左边缘与收藏夹图标对齐 |

### 主题

| 问题 | 根因 | 修复方案 |
|------|------|----------|
| 日间/夜间模式切换时显示不正确 | `FFDesign.isDark` 依赖 `NSApp.effectiveAppearance`（设置 `NSApp.appearance` 后延迟更新），导致 `FFGlassView.refreshAllInstances()` 读取旧值 | 改用 `ThemeManager.shared.resolvedIsDark`（基于已立即更新的 `currentMode`） |
| 夜间模式完全不可用 | `MainWindowController` 中窗口外观被强制设为 `nil`，覆盖 `ThemeManager` 设置 | 改为跟随 `NSApp.appearance` |

### 详情栏

| 问题 | 根因 | 修复方案 |
|------|------|----------|
| 详情栏展开按钮（chevron）无法点击 | `compactView` 和 `expandedView` 在视图层级中覆盖了按钮 | 重新排列视图层级，确保按钮在最上层可交互 |

### 右键菜单

| 问题 | 根因 | 修复方案 |
|------|------|----------|
| 列表视图右键菜单缺少「剪切」按钮 | `FileListView` 未添加剪切菜单项 | 补充剪切菜单项，与网格视图完全一致 |
| 「移动到废纸篓」未标为红色 | 菜单项未设置红色文字属性 | 添加红色文字样式，与访达行为一致 |

### 其他

| 问题 | 根因 | 修复方案 |
|------|------|----------|
| 全局撤销栈（Cmd+Z）无效 | `UndoManager` 未正确集成到窗口响应链 | 集成自定义 `UndoManager` 到窗口响应链 |
| 「显示简介」功能失效 | 通知链不完整，`FileInfoWindowController` 未收到通知 | 修复通知链确保窗口正确显示 |

## 技术变更

- `SidebarView.swift`：`FFFNoDisclosureOutlineView` 新增 `canBecomeKeyView` 重写；移除收藏夹 `NSScrollView` 容器；标签行药丸样式重写
- `DesignTokens.swift`：`isDark` 改用 `ThemeManager.shared.resolvedIsDark`
- `ThemeManager.swift`：`applyMode` 确保窗口和容器 appearance 正确设置
- `MainWindowController.swift`：窗口外观跟随 `NSApp.appearance`，移除强制 `nil`
- `FileListView.swift` / `FileGridView.swift`：通知名称统一为 `FileTagsDidChange`
- `ExpandableDetailsBar.swift`：视图层级重排确保展开按钮可交互

## 版本信息

- `CFBundleShortVersionString` = 0.6.8
- `CFBundleVersion` = 680
- Rust Core `flowfinder-core` = 0.6.8

## 下载

| 文件 | 说明 |
|------|------|
| `FlowFinderNative-v0.6.8-mac.dmg` | DMG 安装镜像 |
| `FlowFinderNative-v0.6.8-mac.zip` | ZIP 压缩包（含 .app） |

## 从 v0.6.7 升级

直接替换 `/Applications/FlowFinderNative.app` 即可，用户设置（外观模式、收藏夹、标签）通过 UserDefaults 和 SQLite 持久化，升级后保留。
