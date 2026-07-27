# FlowFinder Native v0.6.5 (650)

**发布日期：** 2026-07-27
**版本：** 0.6.5 (650)
**分支：** main

---

## 本次发布概述

v0.6.5 是一次仿访达 UI 重构版本，修复了 v0.6.4 用户反馈的 8 个界面问题，并通过全量 UI 巡检发现并修复了 8 个 P0 问题，共 16 项修复。

## 用户反馈的 8 个问题修复

### 1. 收藏夹全面仿访达（F4）
- 收藏夹图标改为蓝色模板 SF Symbols（桌面/文档/下载/应用程序/主目录各有对应图标）
- 选中样式改为 sourceList 半透明蓝高亮
- 移除 FFGlassView 玻璃卡片包裹，改为 NSVisualEffectView(.sidebar) 标准材质

### 2. 标签药丸裁切修复（F5）
- 药丸容器 leading 约束从软约束改为硬约束，紧贴文件名后 8pt
- 文件名超长时截断而不挤压药丸
- 药丸背景改为带标签颜色的浅色，提高对比度

### 3. 移除操作区圆角卡片（F2）
- 左右操作区移除 12pt 圆角卡片包裹，改为仿访达撑满布局
- 左右面板用 1px 发丝线分隔
- 背景透明，让 NSVisualEffectView 的 underWindowBackground 材质透出

### 4. 路径栏位置修正（F3）
- 重构双行工具栏布局
- BreadcrumbBar 嵌入 PaneToolbar Row1，紧贴刷新按钮
- 修复 Row2 被外部 36pt 约束压缩导致不可见的 bug

### 5. 搜索/视图/排序/分组按钮恢复可见（F3）
- 双行工具栏：Row1 = 导航按钮 + 刷新 + 路径栏；Row2 = 搜索 + 排序 + 分组 + 视图切换 + 工具按钮
- 修正高度约束冲突，Row2 恢复正常显示

### 6. 单击选中渲染修复（F7）
- mainContainer 改用 OpaqueContainerView 修复鼠标穿透
- tableView 背景改半透明（0.6 alpha）给选中色提供底色衬托
- tableViewSelectionDidChange 中显式 makeKey + makeFirstResponder
- viewDidLayout（layout() override）同步 appearance

### 7. 应用图标圆角（F6）
- 侧边栏顶部应用图标加 8pt 圆角矩形包裹
- 添加浅色背景层提升视觉层次

### 8. 缩略图加载链修复（F8）
- ThumbnailManager 增加请求/成功/失败日志
- FileListView 修复 cell 复用时旧请求覆盖新 cell 的竞态
- 回调校验改为完整路径（替代文件名），避免同名文件误覆盖
- 取消旧请求机制

## 全量 UI 巡检 P0 修复（F9-A~F）

### F9-A：FileGridView 综合修复
- 网格视图增加 Enter 内联重命名（与列表视图对称）
- 14 个右键菜单项补齐 SF Symbols 图标
- 「复制到/移动到另一面板」增加 panelSide + menuNeedsUpdate 动态方向箭头

### F9-B：详情栏字号统一
- 收起态名称字号统一为 13pt medium，消除 11pt/13pt 跳变

### F9-C：FileInfoWindow 接线为独立窗口
- 将"显示简介"从"展开 DetailsBar"改为弹出独立 Info 窗口（仿访达 Get Info）
- FileInfoWindowController 加入 Xcode target（此前从未编译），修复潜伏的 formatFileSize 编译错误
- 清理 ExpandDetailsBar 死代码通知

### F9-D：搜索面板 scopePopup 接线
- 范围切换（全部范围/当前位置/指定位置）实际生效
- "指定位置"用 NSOpenPanel 弹出目录选择器

### F9-E：关于窗口版本号动态读取
- 版本号从硬编码改为动态读取 Bundle.main.infoDictionary
- 与设置-关于分区保持一致

### F9-F：ProgressDialog 取消功能接线
- 取消按钮接线到 TaskSchedulerManager.cancelTask
- FFModalSheet 新增可选 secondaryAction 闭包，向后兼容现有子类

## 其他改进

- 应用版本号升级至 0.6.5 (650)
- 项目部署目标保持 macOS 12.0
- 完整设计文档、实施计划、巡检报告归档至 docs/superpowers/

## 已知遗留（下一轮处理）

- 26 项 P1 问题（如网格视图 appearance 同步、路径栏首段同级跳转、详情栏材质统一等）
- 26 项 P2 问题（细节优化）
- 13 项代码 Minor（如陈旧注释、防御性编程等）

详见 `docs/superpowers/specs/2026-07-27-v0.6.5-ui-audit-report.md`

## 下载

- FlowFinderNative-v0.6.5-mac.dmg (3.5 MB)
- FlowFinderNative-v0.6.5-mac.zip (3.0 MB)

## 系统要求

- macOS 13.0+（Apple Silicon 或 Intel）
- 建议 macOS 14.0+ 以获得完整视觉体验

## 安装

- DMG：打开后拖拽 FlowFinderNative 到 Applications 文件夹
- ZIP：解压后拖拽到 Applications 文件夹

---

**完整变更日志：** `docs/MIGRATION_LOG.md`
**设计文档：** `docs/superpowers/specs/2026-07-27-v0.6.5-finder-redesign-design.md`
**实施计划：** `docs/superpowers/plans/2026-07-27-v0.6.5-finder-redesign.md`
