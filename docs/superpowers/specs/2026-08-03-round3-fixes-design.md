# FlowFinder 三轮修复设计文档（7 项）

> 日期：2026-08-03
> 版本：v0.7.0 → v0.7.1（本轮修复后发版）
> 状态：已批准
> 范围：Swift & AppKit 侧

## 背景与流程反思

v0.7.1 二轮修复经用户实测，7 项"依旧有问题"。经**亲自精读代码**（非子代理）确认：多数问题是"代码逻辑正确但运行时未生效"，而非未实现。二轮子代理流程只验证了"构建通过+代码审查"，未验证运行时行为，是问题漏网主因。

**本轮执行方式变更：不再走子代理流程，由主控亲自实现、逐项构建+运行验证（临时 NSLog 诊断），确认生效后再交付用户实测。**

---

## 1. 收藏夹高亮未包裹内容（T1）

**根因（亲查）**：系统 `NSTableRowView` 的选中高亮画在"行"上，但 cell 内容（图标 leading=0、文字 trailing=-6）的布局与行的实际宽度/位置存在偏移，且 `intercellSpacing.height=2` 在行间留缝。恢复 `canBecomeKeyView=true` 后高亮为蓝色，但仍未与内容完全重合。

**方案**：放弃系统 row 高亮，改用自绘背景层：
- `selectionHighlightStyle = .none`，关闭系统绘制
- 自定义 `FFSidebarRowView`（NSTableRowView 子类）`drawSelection` 时用强调色绘制**精确覆盖 cell 内容区域**（图标左缘到文字右缘、整行高）的圆角矩形
- 行间缝隙由自绘层内部消除（选中行背景延伸到行框全高）

## 2. 搜索栏图标未贴右（T2）

**根因（亲查）**：`flexibleSpacer` hugging=1 吃掉全部富余宽度，搜索框（hugging 250）停在 120pt 下限，图标虽贴右但中间大片空白。

**方案**：
- 移除 `flexibleSpacer`
- 搜索框恢复 hugging=1（弹性吸收剩余宽度，窗口越宽越宽）
- 图标簇因默认 hugging 高于搜索框，自然贴最右

## 3. 玻璃四角灰方块 + 无亮线/阴影（T3）

**根因（亲查）**：`updateSublayerFrames` 中 tint/noise 层的 `cornerRadius`+`masksToBounds` 在 `layout()` 时设置，但**首次布局时 `bounds` 为空直接 return**，导致装饰层始终未裁剪；亮线用 `layer.borderWidth` 在 CALayer 上，部分场景被原生玻璃子视图遮挡不显示。

**方案**：
- 装饰层裁剪改为**创建时即设** cornerRadius（在 setupPanelGlass/setupComponentGlass 中创建 tint/noise 后立即设置 `cornerRadius = self.cornerRadius`），并在 `layout()` 中保持同步
- 亮线描边改为 `CAShapeLayer`（沿圆角矩形边缘画 1pt 描边路径），显式 `addSublayer` 到最上层，确保不被遮挡；主题刷新时更新颜色
- 阴影保持 CALayer shadowPath（已生效）

## 4. 工具面板点击打不开 + 无悬停反馈（T4）

**根因（亲查）**：`toolPanelView` 只有 leading/bottom/trailing 约束，**无高度约束**（devicePanel 有 `devicePanelHeightConstraint`），NSGridView 内容高度不足以撑起面板时整体塌缩，面板不可见/不可点。

**方案**：
- 给 `toolPanelView` 增加高度约束（与设备面板一致区域，高度按 2 行卡片计算，如 190pt；用 `>=` 允许内容撑高）
- `ToolPanelCardView` 确保 `wantsLayer = true` 已设置（悬停变色依赖 layer 背景）；`updateTrackingAreas` 加 `if onTap != nil` 守卫避免禁用卡片悬停

## 5. QuickLook 空格无反应（T5）

**根因（亲查）**：`FFQuickLookTableView.keyDown` 拦截空格，但 NSTableView 的键盘事件先经 `interpretKeyEvents`（文本输入处理），空格被其消耗，`keyDown` 可能不触发。

**方案**：
- 改用 `performKeyEquivalent(with:)`（在 interpretKeyEvents 之前由 NSWindow 分发）拦截空格
- 保留 `keyDown` 兜底
- 网格 `DraggingCollectionView` 同样改用 `performKeyEquivalent`
- 临时 NSLog 验证事件到达（运行验证）

## 6. 设置页看不清/布局乱（T6）

**根因（亲查）**：窗口 `isOpaque=true` + `windowBackgroundColor` 实体背景，但 `mainContainer.layer` 背景与窗口背景叠加对比不足；分区宽度依赖 `constrainStackInScroll` 的固定 `-48` 边距与内部控件固有宽度，多个无 intrinsic size 控件塌缩。

**方案**：
- 窗口与内容区统一实体背景（`windowBackgroundColor`），移除透明度叠加
- 统一分区宽度约束（stack 撑满 clipView 宽 - 统一边距）
- 排查并修复塌缩控件（SMBManagerPanel、AppearanceSettingsView 已修，复核其余）
- 逐分区点测 action 绑定

## 7. 详情栏专属信息单独两列不协调（T7）

**根因（亲查）**：`updateFileTypeSpecificInfo` 把图片分辨率/版本号等放入独立 `columnsStack`（左右两列），与主信息列（column1/column2）分离，视觉断裂。

**方案**：将专属信息行**合并到主信息 column1**（种类/大小/位置/日期之后追加），删除独立的 fileTypeInfoContainer 两列结构；`computedExpandedHeight` 相应简化（行数=主信息+专属信息）。

---

## 改动文件清单

| 文件 | 涉及项 |
|---|---|
| `UI/SidebarView.swift` | T1 收藏夹高亮自绘 |
| `UI/PaneToolbar.swift` | T2 搜索栏 |
| `UI/FFGlassView.swift` | T3 玻璃裁剪/亮线 |
| `UI/MainWindowController.swift` | T4 工具面板高度 |
| `UI/ToolOverlayView.swift` | T4 卡片 wantsLayer/悬停 |
| `UI/FileListView.swift` + `UI/FileGridView.swift` | T5 QuickLook 拦截 |
| `UI/SettingsWindowController.swift` + `UI/SettingsSectionView.swift` | T6 设置页 |
| `UI/ExpandableDetailsBar.swift` | T7 详情栏合并 |

## 验证方式（关键）

1. 每项实现后 Debug 构建 + 临时 NSLog 诊断（事件到达/布局尺寸），**亲自运行验证**
2. 全部完成后交付用户实测，反馈通过才发版 0.7.1
