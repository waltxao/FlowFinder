# T13 — 主流程 AppKit 无障碍与交互一致性

状态：完成（直接实施；后台任务因模型配额取消）
日期：2026-08-14

## 改动清单
- UI/PaneToolbar.swift：8 个图标按钮 setAccessibilityLabel（返回/前进/上级/刷新/列表/网格/文件夹选项/新建文件夹）
- UI/FFCommon.swift：新增 FileEntryAccessibility（label/sidebarLabel/searchResultLabel 纯函数）+ FFMotion.animationDuration（reduced-motion）
- UI/FileListView.swift：name 列 cell 设无障碍标签（名+类型+大小）
- UI/FileGridView.swift：FileGridCollectionViewItem.view 设无障碍标签
- UI/SidebarView.swift：收藏夹条目 label（名称+选中状态）
- UI/SearchPanelController.swift：结果行 label + 搜索字段 label
- UI/FFModalSheet.swift：隐藏标题栏 sheet 显式 setAccessibilityTitle + 关闭按钮 label
- reduced-motion：7 处 NSAnimationContext duration 走 FFMotion.animationDuration（ExpandableDetailsBar 1、MainWindowController 3、PaneToolbar 1、SettingsSectionView 2）

## 测试
- xcodebuild test：70 tests / 0 failures（T12 基线 65 + T13 新增 FileEntryAccessibilityTests 4 + FFMotionTests 1）

## 边界（记录在案）
- 动态字体：主流程文本已使用 systemFontSize/small 系统字号（FileListView cell、SidebarView 等）；网格 nameLabel 11pt 与药丸类小控件保留设计值。未做 AppleTextSize 变化监听重设字体（涉及布局风险），manual QA 验证 125%/200% 缩放主内容不裁剪
- 列表/网格键盘一致性：QuickLook 空格 firstResponder 守卫、Enter 重命名、Delete 删除在 T4/T9 已统一（Rust/FFI 侧），本任务验证 UI 侧行为一致

## Manual QA（记录）
- VoiceOver 走查：工具栏按钮、列表/网格条目、侧边栏条目、搜索结果、对话框标题均可朗读
- Tab 焦点顺序：工具栏→列表→侧边栏顺序确定；focus ring 系统默认可见
- reduced-motion：开启系统减弱动态效果后展开/收起/悬停动画即时完成
