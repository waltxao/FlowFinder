# SPEC · 0.8.0 Beta 顶栏与交互修复（2026-10-21）

> 状态：**已实现 / 已验证（2026-10-21）**；A1 像素与 hover 目测待用户确认
> 版本：**0.8.0 (8001) Beta**（用户裁定；不是 0.9.0）
> 分支：`feat/v0.9-overhaul`（分支名沿用，产品版本按本文档）
> 依据：`HANDOVER.md`、`REQUIREMENTS-LEDGER.md`、本轮 6 张可视化对比稿

## 1. 用户裁定

| ID | 决策 | 选择 |
|---|---|---|
| D-01 | 标签形态 | A1 焊死式：活动标签与卡片同色，9pt 内凹肩线，无下划线与整圈描边 |
| D-02 | 顶栏基线 | 30pt 标题带；活动 28 / 非活动 24；全部中心线 16pt；**不移动系统红绿灯** |
| D-03 | 顶栏图标 | 侧栏三个图标保留；24pt 命中 / 15–16pt 线性图标 / 4pt 间距 / hover 底色；× 与 + 统一 24pt 命中 |
| D-04 | 隐藏侧栏 | 首个标签左缘 112pt（标签条容器 78；给 9pt 肩线留空间），动画结束后重算，不得压在红绿灯/浮动开关上 |
| D-05 | 关闭按钮 | 点击系统红绿灯必须关闭窗口；窗口级拖拽监视器不得吞掉标准窗口按钮的 mouseDown |
| D-06 | 同目录拖放 | 完全无操作：不弹冲突/复制窗；文件拖回原目录、文件夹拖进自身或子目录均无效 |
| D-07 | 版本 | 0.8.0 (8001) Beta；侧栏显示版本，关于页显示构建时间与 bundle 路径 |
| D-08 | 两个版本 | 启动时检测同 Bundle ID 的其它进程并提示；删除全部 8 个旧副本（移到废纸篓） |
| D-09 | 测试构建 | `make swift-test` 使用 `/tmp` 下的 DerivedData，避免在用户目录再生成一个可启动副本 |

## 2. 视觉规格

### 2.1 顶栏几何

```
标题带 30pt（卡片顶边 = 30）
活动标签 28pt：top 2 / bottom 30（与卡片焊死）
非活动标签 24pt：top 4 / bottom 28（视觉上浮 2pt）
中心线：所有标签、×、+、侧栏图标、红绿灯均为 16pt（自窗口顶）
首标签左缘：卡片左缘 + 26pt（保留面板圆角与 9pt 肩线的间距）
隐藏侧栏：标签条左缘 = 112pt；首个标签自然再内缩 26pt
```

### 2.2 标签

- 活动标签：A1 内凹肩线（`FFTabSilhouette.tabFootprint`，seam 9 / corner 10），填充 = 面板卡片色；无 side border、无 underline。
- 非活动标签：透明底、secondary 文本、12pt regular；hover 才出现关闭 ×。
- 标签内容：12pt folder 模板图标 + 标题（active medium / inactive regular），标题截断尾部。
- 关闭 ×：视觉 10pt，命中 24pt，hover 20pt 圆形底色；active 常显，inactive hover 显示。
- 新建 +：13pt 线性图标，命中 24pt，6pt 圆角 hover 底色，中心与标签一致。

### 2.3 侧栏图标

- `panelLeftClose/Open`、`sun/moon/circleDot`、`columns2/square` 统一 24×24 命中，图标 15–16pt。
- hover 底色使用 labelColor 6–8% alpha，pressed 10%；不改变现有 target/action。
- 左侧开关仍紧跟红绿灯；主题/单双栏仍贴侧栏右缘，间距 4pt。

### 2.4 隐藏侧栏

- `setSidebarVisible` 动画完成后必须再次 `updateTabStripFrames()`。
- `splitViewDidResizeSubviews`/窗口尺寸变化也刷新标签条左缘。
- 修复前的问题：动画前按 wrapperLeading≈220 算出 offset 0，动画后不重算，标签条停在 x=0 压住红绿灯。

## 3. 行为修复

### 3.1 红绿灯关闭

在 `FFPaneDragController.handleDown` 最前检查 `event.locationInWindow` 是否落在
`window.standardWindowButton(.closeButton/.miniaturizeButton/.zoomButton)` 的窗口坐标内；
命中则原样返回 event，不设 mode、不 `performDrag`。根因是 fullSizeContentView 下
`contentView.hitTest` 会返回红绿灯背后的侧栏/标签条，区域解析成 `.window` / `.title`，
监视器把点击当成拖窗口并消费。

### 3.2 同目录拖放

新增纯函数 `FFFileDropPolicy.validSources(_:destination:)`：

- 源父目录 == 目标目录 → 丢弃；
- 源是文件夹且目标 == 源或位于源之下 → 丢弃；
- 全部被丢弃 → `validateDrop` 返回 `[]`，`acceptDrop` 返回 `false`，不进入 ConflictResolver；
- 混合批次只处理有效源。

列表与网格两套 drop 通道都接入。

## 4. 版本与副本

- `MARKETING_VERSION = 0.8.0`，`CURRENT_PROJECT_VERSION = 8001`（Debug/Release 两处）。
- 侧栏版本行：`0.8.0 (8001) Beta`；关于页增加构建时间、bundle 路径。
- 启动检测：同 Bundle ID 的其它运行进程 → NSAlert 列出路径/版本，按钮“继续打开 / 退出这个实例”。
- 删除 8 个旧副本：Applications ×2、DerivedData ×2、repo build/ 与 build_stale_0021、Download/测试 0.7.5 与 0.7.4；保留 Desktop 与缓存构建。
- 旧副本移入废纸篓，不 `rm`；Xcode 测试改为 `/tmp` DerivedData，避免再次污染。

## 5. 非目标

- 不移动系统红绿灯，不自绘红绿灯。
- 不改 Rust core / FFI。
- 不改标签拖拽的 60Hz 落点模型；只改标签外观与条内几何。
- 不重做侧栏信息架构；只改顶栏图标 hover/尺寸。
- 不提交、不推送（用户未要求）。

## 6. 验收

- `make build` BUILD SUCCEEDED。
- `make swift-test` **301 条 0 失败**（新增 19 条纯函数/几何测试）。
- `FF_SELFTEST=1` **153 项 0 失败**（决策表 71 / 区域 7 / 行为 4 / 焊接 35 / 侧栏避让 4 / 外壳 22 / 落点 10）。
- AX/物理点击实测：+ 能新建标签；红绿灯关闭能关窗（窗口数 1→0，进程存活）；隐藏侧栏后首标签左缘 112（容器 78）、>102；侧栏显示 `0.8.0 (8001) Beta`。
- 真机目测：30pt 标题带、A1 肩线、16pt 中心线、hover 态；本机屏幕录制权限未授予，截图待用户补充。
- 8 个旧副本已移入废纸篓；`mdfind` 只剩 Desktop（缓存构建在 Library/Caches，不被 Spotlight 索引）。
- 双开实测：第二个进程日志 `[INSTANCE] 检测到其它实例`，提示框返回 1000（继续打开）。
