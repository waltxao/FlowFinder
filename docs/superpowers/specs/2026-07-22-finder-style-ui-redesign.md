# FlowFinder UI 重设计 - 访达风格

**日期**: 2026-07-22
**状态**: 已批准
**方案**: 混合方案（方案C）— 新建2个可复用类 + 增量修改其余组件

## 需求总结

| # | 需求 | 细节 |
|---|------|------|
| 1 | 玻璃透明度 | 侧边栏保留液态玻璃效果；双栏内容区添加 99% 不透明遮罩 |
| 2 | DetailsBar | 改为可展开详情面板，显示选中文件的高清预览图标 + 元数据 |
| 3 | 原生图标 | 侧边栏、文件列表、DetailsBar、工具栏全部使用访达原生系统图标 |
| 4 | 单击交互 | 单击选中（蓝色高亮），双击打开 |
| 5 | 内容遮罩 | 双栏区域加 99% 不透明遮罩；侧边栏每个区域各自独立圆角遮罩 |
| 6 | 面包屑 | 左右两栏顶部各加路径面包屑导航（可点击跳转） |
| 7 | 窗口间距 | 距顶部 8-10pt 间距 |
| 8 | 设备栏 | 半透明圆角遮罩，动态高度，所有设备+进度条全部显示无需滚动 |
| 9 | 空间进度条 | 每个设备显示水平进度条（已用=彩色，剩余=灰色）+ 文字显示可用空间 |
| 10 | 药丸标签 | 所有标签用药丸圆角包裹文字，左侧彩色小点区分 |

## 整体架构

```
NSWindow (透明, appearance=nil, 距顶部8-10pt)
└── NSGlassEffectView (.clear style) — 液态玻璃底层
    └── contentView (mainContainer)
        ├── mainSplitView (水平分割)
        │   ├── SidebarView (侧边栏 — 保留玻璃穿透)
        │   │   ├── GlassSectionMaskView (收藏夹 — 圆角遮罩)
        │   │   │   └── 每个收藏: NSWorkspace真实位置图标 + 名称
        │   │   ├── GlassSectionMaskView (标签 — 圆角遮罩)
        │   │   │   └── 每个标签: 药丸背景 + 彩色小圆点 + 文字
        │   │   └── GlassSectionMaskView (存储设备 — 圆角遮罩 + 动态高度)
        │   │       └── 每个设备: 原生图标 + 名称 + 水平进度条 + 可用空间文字
        │   └── paneSplitView (双栏 — 99%不透明遮罩)
        │       ├── leftPaneContainer
        │       │   ├── BreadcrumbBar (路径面包屑 — 可点击跳转)
        │       │   ├── PaneToolbar (工具栏 — 原生药丸按钮)
        │       │   ├── FileListView (文件列表 — 原生图标 + 单击选中)
        │       │   └── ExpandableDetailsBar (可展开详情面板)
        │       └── rightPaneContainer (同上)
        └── TaskProgressBar
```

## 新增可复用组件

### 1. GlassSectionMaskView

- **继承**: NSView
- **功能**: 为侧边栏每个区域提供半透明圆角遮罩
- **属性**:
  - `cornerRadius: CGFloat` (默认 8pt)
  - `maskColor: NSColor` (默认半透明白色/黑色，根据明暗模式自适应)
- **实现**: 内部用 CALayer 实现圆角 + 半透明背景
- **用法**: 包裹侧边栏每个区域的内容视图

### 2. BreadcrumbBar

- **继承**: NSView
- **功能**: 显示路径面包屑导航，每段可点击跳转
- **显示**: `Macintosh HD > Users > waltxao > Desktop`
- **分隔符**: `chevron.right` SF Symbol
- **交互**: 点击路径段跳转到对应目录
- **背景**: 透明（继承玻璃效果），文字使用系统字体
- **位置**: PaneToolbar 上方，文件列表上方

### 3. ExpandableDetailsBar

- **继承**: NSView（替代现有 DetailsBar）
- **收起状态**: 单行 — 高清预览图标(32x32) + 文件名 + 大小
- **展开状态**: 完整面板 — 大尺寸预览图标(64x64) + 以下字段:
  - 文件名
  - 类型
  - 大小
  - 创建日期
  - 修改日期
  - 权限
  - 路径
  - 标签（药丸样式）
- **展开/收起**: 点击按钮切换，高度动画过渡
- **预览图标**: `NSWorkspace.shared.icon(forFile:)` + QuickLook 缩略图

## 现有组件修改

### SidebarView

- 三个区域各用 GlassSectionMaskView 包裹
- 收藏夹图标改用 `NSWorkspace.shared.icon(forFile:)`:
  - 桌面 → `NSImage(systemSymbolName: "desktop")` 或真实桌面图标
  - 文稿 → 文稿文件夹真实图标
  - 下载 → 下载文件夹真实图标
  - 应用程序 → 应用程序文件夹真实图标
- 标签改为药丸样式:
  - 圆角背景 (cornerRadius = height/2)
  - 左侧彩色小圆点 (8x8)
  - 文字居中
- 存储设备栏:
  - 动态高度: section标题 + 设备数 × (图标行 + 进度条行 + 文字行)
  - 每个设备增加:
    - 水平进度条 (已用=systemBlue, 剩余=systemGray)
    - 可用空间文字 (如 "234GB 可用")
  - 设备图标:
    - Macintosh HD → `internaldrive` SF Symbol
    - 用户主目录 → `house` SF Symbol
    - 外接硬盘 → `externaldrive` SF Symbol
    - 网络驱动器 → `externaldrive.connected.to.line` SF Symbol

### PaneToolbar

- 按钮确认 `bezelStyle = .accessoryBarAction` + `controlSize = .small`
- 面包屑从工具栏移至独立的 BreadcrumbBar 组件
- 工具栏仅保留: 导航按钮(后退/前进) + 搜索框 + 排序(名称/方向) + 视图切换(列表/图标)

### FileListView

- 确认 `NSWorkspace.shared.icon(forFile:)` (已完成)
- 单击选中修复:
  - `shouldSelectRow` 返回 true
  - `tableViewSelectionDidChange` 触发选中回调
  - 选中行使用 `systemBlue` 高亮背景
- 双击打开保持不变

### MainWindowController

- 窗口距顶部 8-10pt: 设置 `window.setFrameOrigin` 或在 windowDidBecomeKey 中调整
- 双栏内容区添加 99% 不透明 CALayer:
  - `let maskLayer = CALayer(); maskLayer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.99).cgColor`
  - 添加到 paneSplitView 的 layer
- ThemeManager 兼容: 确保 `window.appearance = nil` 不被覆盖 (已修复)

## 实现顺序

1. 窗口间距调整 (MainWindowController)
2. 双栏 99% 遮罩 (MainWindowController)
3. GlassSectionMaskView 新建 + 侧边栏三个区域包裹 (SidebarView)
4. BreadcrumbBar 新建 + 从 PaneToolbar 拆分
5. SidebarView 标签药丸样式
6. 存储设备栏进度条 + 动态高度
7. 原生图标全面替换 (侧边栏位置图标)
8. ExpandableDetailsBar 新建替换 DetailsBar
9. 单击选中修复
10. ThemeManager 兼容性修复

每步完成后构建验证，确保不破坏现有功能。
