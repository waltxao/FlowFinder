# FlowFinder Native 项目交接文档

> **交接日期：** 2026-10-17（v0.8.0 侧边栏 P1 完成，未发版）
> **当前版本：** 0.7.6 基线 + 未发版大改（详情栏重设计 + 原生体验四波次 + v0.8.0 侧边栏 P1）
> **仓库地址：** https://github.com/waltxao/FlowFinder
> **分支：** main
> **最新提交：** ea1494f（docs: 交接文档更新）；v0.8.0 P1 改动在工作区未提交
> **本地路径：** `/Volumes/Iris-Data/文件管理系统/flowfinder-native`
> **测试基线：** Rust 200 tests / Swift XCTest 115 tests 全绿（2026-10-17 复验）
>
> ⚠️ **路径变更（2026-10-17）**：项目已从 `/Volumes/Iris-Data/Download/AI/文件管理系统/` 迁移到
> `/Volumes/Iris-Data/文件管理系统/`。本文档中所有旧路径引用均已失效，以本节路径为准。

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
| **0.7.0** | **2026-08-02** | **设置重构 + 更多核心功能（见 CHANGELOG）** |
| **0.7.2** | **2026-08-07** | **设置页大修 + 液态玻璃重设计 + 撤销/重做闭环** |
| **0.7.4** | **2026-08-09** | **全量稳定性修复 + 真实 FSEventStream 文件监听** |
| **0.7.5** | **2026-08-14** | **安全加固 + FTS5 内容索引 + 测试/发布基建** |
| **0.7.6** | **2026-08-28** | **发布后修复轮：布局冲突清零 + 弹窗几何 + sheet 会话正规化（当前版）** |
| **0.8.0-WIP** | **2026-08-30** | **未发版大改：详情栏重设计（可调高/三模块/流动填充）+ 原生体验四波次（主线程根治/键盘优先/Finder互通/交互反馈/视觉材质密度）+ 收藏导航误杀修复** |
| **0.8.0-P1** | **2026-10-17** | **侧边栏收藏模块重设计 P1：滚动容器 + 单一 outline 分区模型（「个人收藏」group row）+ 删除两条定高约束链 + 拖拽重排 + 右键菜单五项 + 失效灰显保留 + 空态引导行；Swift 测试 98→115** |

> 注：0.7.1 / 0.7.3 为内部版本号跳号，未发布 Release。
>
> **0.7.5 发布后修复轮（2026-08-28，未发版）**：AppKit 布局冲突清零（工具面板列宽/设备栏折叠/面包屑双高度/状态浮层按钮/标签区定高）；FFModalSheet 弹窗高度测量修复（按钮曾被裁出窗外）与 sheet 会话正规化（endSheet，修复查重删除后「浏览...」静默失效）；新增 3 个 AppKit 几何/会话回归测试（70→73）。改动在工作区未提交。

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
| **文件监听** | 真实 FSEventStream + 300ms 去抖 | v0.7.4 重写（原为占位轮询） |
| **FSEvents 状态机** | starting/active/failed/stopped（ff_fsevents_status） | v0.7.5 新增，启动失败可观察 |
| **内容索引** | 独立 SQLite FTS5（content_index.sqlite） | v0.7.5 新增，「内容包含」走索引查询，与目录缓存分离 |
| **path_guard** | 全写入口路径安全校验（复制/移动/删除/重命名/批量） | v0.7.5 补全 |
| **批量重命名校验** | 专用 safe_filename（拒绝 / \ .. 绝对路径 控制字符 空名） | v0.7.5 新增（路径穿越修复） |
| **批量/整理冲突** | 目标已存在默认拒绝，不再静默覆盖 | v0.7.5 变更 |
| **删除/撤销/重做** | 全部后台化（isDeleting/deleteFailedPaths 状态机） | v0.7.5 变更 |
| **Swift 测试** | 可执行 XCTest target（FlowFinderNativeTests shared scheme） | v0.7.5 新增，make swift-test 走 xcodebuild |
| **FFI ABI** | C ABI 锁定：布局断言 + 回调借用契约 + 符号三方对比 | v0.7.5 新增 |
| **发布签名** | fail-closed：codesign --verify 失败即中止打包 | v0.7.5 变更 |
| **FFModalSheet sheet 会话** | beginSheetModal 记录宿主，关闭统一走 parent.endSheet | 2026-08-28 变更：close() 会毒化后续 NSOpenPanel sheet（macOS 27） |
| **FFModalSheet 高度测量** | 两段式：先撑到已知尺寸布局再量 fittingSize；footer 贴底 defaultHigh 兜底 | 2026-08-28 变更：0 尺寸测量导致按钮裁出窗外 |
| **AppKit 瞬态可变约束** | 可变列宽/定高一律 defaultHigh，required 会瞬态无解刷冲突日志 | 2026-08-28 沉淀（工具面板/标签区） |
| **AppKit 隐藏视图** | 隐藏视图的约束仍参与求解；动态行列表用清空/重建而非隐藏 | 2026-08-28 沉淀（设备栏） |
| **编译缓存陷阱** | cargo/xcodebuild 会重放陈旧缓存诊断与旧测试数；采信前先 clean 强制重编译 | 2026-08-28 沉淀（202→200 tests、幽灵警告） |
| **打包架构** | ARCHS=arm64 + ONLY_ACTIVE_ARCH=YES | v0.7.5 固定（dylib 仅 arm64） |
| **目录列举队列** | 独立并发队列（directoryListQueue）+ 10s 超时兜底 | 2026-08-30 热修：共享 ffiQueue 曾被慢目录（iCloud）阻塞致全局死锁 |
| **FSEvents 线程 QoS** | USER_INITIATED（0x19，pthread_set_qos_class_self_np） | 2026-08-30：修复主线程同步握手优先级反转（正式版导航卡顿根因） |
| **侧边栏通知身份守卫** | isOwnSidebarNotification：发送者为 NSView 且所属窗口=本窗口（未挂窗退回视图树判定）；poster（outlineViewSelectionDidChange）必须以 outlineView 为 object | 2026-08-30：初版只认 SidebarView 实例误杀本窗口导航（数据源对象是实际发送者）；e3792db 视图树判定仍误杀——数据源（NSObject）cast NSView 必失败、设备浮层不在 sidebarView 子树；2026-09-02 根治：poster 改发 outlineView + 守卫补窗口身份判定（回归测试 SidebarNavigationPosterTests） |
| **快捷键系统** | ShortcutCenter 统一键位读取（UserDefaults，默认=旧行为）| 2026-08-30：硬编码键位全部改读设置 |
| **测试宿主** | XCTest 环境跳过宿主 UI 创建（启动环境变量判定） | 2026-08-30：宿主主窗口簿记块与测试裸释放竞态曾致运行器 SIGSEGV |
| **视觉令牌** | FFDesign.OperationArea / Typography / Glass.cornerRadiusPanel，全双值+刷新链 | 2026-08-30：三套硬编码灰归一、字体层级化、圆角收敛 16/10 |
| **列表密度/网格缩放** | FFListDensity 三档 + grid_icon_size（⌘滚轮/捏合，80-200 夹紧） | 2026-08-30 Wave4 |
| **Release 打包（当前环境）** | ⚠️ 失败：macOS 27 + Homebrew Rust 1.96.1 生成 mis-aligned LINKEDIT dylib，dlopen 拒绝（Debug 正常） | 2026-08-30 排查：非外置卷问题（内置卷复现），非部署目标问题；需换工具链或等修复 |

---

## 6. 待办事项（下一阶段）

### 6.1 发布遗留（v0.7.6 发版后状态，2026-08-28）

| 优先级 | 事项 | 说明 |
|--------|------|------|
| 中 | **Developer ID 公证** | 0.7.6 产物仍为 ad-hoc 签名（首次打开需右键→打开）。配置 Secrets `APPLE_DEVELOPER_ID` + `NOTARY_API_KEY`/`NOTARY_KEY_ID`/`NOTARY_ISSUER` 后推送 tag 自动公证 |
| 高 | **Release 打包环境问题** | macOS 27 + Homebrew Rust 1.96.1：Release 构建的 proc-macro dylib（serde_derive 等）LINKEDIT mis-aligned，`dlopen` 拒绝（Debug 正常）。临时方案：用 `scripts/package-beta.sh` 出 Debug 测试版；根治待 rustup 换工具链或 Rust 修复 |
| 高 | **build-rust.sh 的 Xcode ld relink 失效** | 2026-09-13 复现：`ld -force_load libflowfinder_core.a` 报 `Undefined symbols for architecture arm64`，脚本回退到直接拷贝 rust-lld 产出的 dylib。Debug 链路仍能通过（.app 可启动），但 Release 的重链接兜底实际已失效，需补齐缺失的系统库/框架链接参数 |
| 高 | **Swift 测试跑不起来（环境）** | 2026-09-13：`make swift-test` 连续报 `The test runner hung before establishing connection`（宿主进程 sample 显示主线程空闲在 run loop，应用本身没死锁）。疑似 testmanagerd 状态污染。跑测试前务必先 `pkill -f "MacOS/FlowFinderNative"`（单实例策略会让宿主秒退）；若仍失败，重启 Xcode 或系统后再试 |
| 高 | **版本号元数据** | pbxproj MARKETING_VERSION=0.7.4、Info.plist 版本字段未随新功能更新；发版前统一升版 |
| 中 | **发版决策** | 60+ 提交未发版：需决策版本号（建议 0.8.0）、CHANGELOG、DMG/ZIP 资产、公证 |
| 已完成 | ~~v0.7.5 Release 资产过时~~ | 已发 v0.7.6（含发布后修复，DMG/ZIP/sha256 资产齐） |
| 已完成 | ~~工作区未提交改动~~ | 已随 v0.7.6 提交（ce8cd35 修复 + b434630 发版） |
| 已完成 | ~~clippy / import SwiftUI / /Applications 旧版本~~ | 49d6e74 / d0133bb / 本轮安装 0.7.6 |

### 6.2 功能扩展待办

| 优先级 | 功能 | 说明 |
|--------|------|------|
| 中 | Intel 通用二进制 | 需 Rust dylib 双架构 + 去 ONLY_ACTIVE_ARCH |
| 低 | 全局撤销栈完善 | 当前 per-window UndoManager，可扩展 |
| 低 | 内容索引 UI 进度 | FTS5 建索引为后台静默，可加状态指示 |
| 低 | NSToolbar 整合红绿灯 | 双窗格架构冲突（macOS 单窗口单工具栏），已做 overflow 分级保底；未来单列评估 |
| 低 | 真机手势确认 | 轻扫前进后退方向、捏合手感需日常使用确认（若轻扫方向相反为两处各 1 行翻转） |
| 低 | 双栏同步逐帧跟随 | 当前为拖拽结束快照式；如需逐帧跟随，通知 userInfo 携带内存值即可 |
| 低 | 子窗口正文字号令牌化 | Wave4 顺延项（SearchPanelController:414 残留 calibratedWhite） |
| 低 | 列举按路径合并 | 卡死线程无界累积为已接受取舍；可做按路径去重/有界工作线程 |

### 6.3 v0.8.0 侧边栏重设计剩余（P1 已完成，2026-10-17）

设计稿：`docs/superpowers/specs/2026-09-02-v0.8.0-sidebar-favorites-redesign-design.md`

| 阶段 | 事项 | 状态 / 说明 |
|------|------|-------------|
| P1 | 收藏分区访达化（滚动容器 / 分区 outline / 拖拽重排 / 右键五项 / 失效灰显 / 空态行 / 删除定高约束） | ✅ 已完成（2026-10-17） |
| P2 | 标签区并入统一 outline：**行式**（色点+名称+计数徽章）或保留药丸 —— 设计决策点 **D3 待拍板** | 未开始 |
| P2 | 拖文件到标签行=打标签（复用 TagBridge）；hover「…」菜单（重命名/删除） | 未开始 |
| P3 | 设备区：**甲·保留浮动浮层仅换真实卷图标**（D4 推荐）或 **乙·并入「位置」分区**（含 ⏏ 弹出） | 未开始（D4 待拍板） |
| 决策 | D1 标准位置图标：A 维持 NSWorkspace / **B 专属彩色映射表（推荐）**；D2 拖文件到收藏项=仅添加收藏（已按推荐实现） | D1 未实施（P1 未纳入范围） |
| 遗留 | 拖出侧边栏移除收藏（访达语义）未实现——风险高于收益，验收清单未列入；如需可加「拖到窗口外松手」多重判定 | 待评估 |

---

## 7. 构建与发布

### 7.1 环境要求

- **macOS** 13.0+（Apple Silicon）
- **Xcode-beta**（当前使用），**必须设置 DEVELOPER_DIR**
- **Rust** 1.75+（通过 `rustup` 安装）

### 7.2 常用命令（Makefile）

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
cd /Volumes/Iris-Data/文件管理系统/flowfinder-native

make build        # Rust dylib + Debug app 构建
make run          # 构建并启动
make test         # rust-test + swift-test + integration-test
make rust-test    # cargo test（200 tests）
make swift-test   # xcodebuild test（115 tests）
make clean / setup / release / xcode / help
```

**⚠️ 2026-10-17 实测更正（重要）：** 工程**没有** `FlowFinderNative` 共享 scheme，只有
`FlowFinderNativeTests`。旧文档里的 `-scheme FlowFinderNative` 会直接报
`does not contain a scheme named "FlowFinderNative"`。Debug 构建必须走 `-target`：

```bash
xcodebuild -project FlowFinderNative/FlowFinderNative.xcodeproj \
           -target FlowFinderNative \
           -configuration Debug \
           SYMROOT=/tmp/ff-dd/Build/Products \
           OBJROOT=/tmp/ff-dd/Build/Intermediates \
           MARKETING_VERSION=0.8.0 CURRENT_PROJECT_VERSION=8002 \
           ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
           CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
# 产物：/tmp/ff-dd/Build/Products/Debug/FlowFinderNative.app
```

跑 Swift 测试前必须先 `pkill -f "MacOS/FlowFinderNative"`（单实例策略会让测试宿主秒退；
否则会看到 `test runner hung before establishing connection` 假故障）。

```bash
pkill -f "MacOS/FlowFinderNative" 2>/dev/null
xcodebuild test -project FlowFinderNative/FlowFinderNative.xcodeproj \
                -scheme FlowFinderNativeTests -destination 'platform=macOS' \
                CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

**新增 Swift 文件必须注册 `project.pbxproj` 四处**（PBXBuildFile / PBXFileReference /
Group children / Sources build phase），ID 用 24 位十六进制且先 grep 确认不冲突。

### 7.3 一键打包（推荐）

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/package.sh
```

测试版（Debug）打包 2026-09-13 新增，Release 通道不可用时用它出可测产物：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/package-beta.sh
# BETA_LABEL=beta.2 ...   # 迭代下一版
# INSTALL=1 ...           # 打包后直接装进 /Applications
```

产出目录 `build-beta/`（与 Release 的 `build/` 隔离）：
- `FlowFinder-0.8.0-beta.1.dmg` / `.zip` / `.sha256`

产出（`build/` 目录）：
- `FlowFinder-0.7.5.dmg` — DMG 安装镜像
- `FlowFinder-0.7.5.zip` — ZIP 压缩包
- `FlowFinder-0.7.5.sha256` — SHA256 校验

脚本内建：Release 编译（arm64）→ bundle 校验 → 签名（fail-closed 验证）→ DMG+ZIP → checksum → 公证（凭据存在时）。**注意：-target 模式不支持 -derivedDataPath，脚本已按 selector 类型分支处理。**

### 7.4 GitHub Release

CI 已就绪：`.github/workflows/release.yml`（tag `v*` 触发，打包+公证+发布，需 Secrets）；本地可用：

```bash
gh release create v0.7.5 \
  build/FlowFinder-0.7.5.dmg build/FlowFinder-0.7.5.zip build/FlowFinder-0.7.5.sha256 \
  --title "v0.7.5" --notes-file docs/release-notes/release-notes-v0.7.5.md
```

### 7.5 当前 Release

- **URL：** https://github.com/waltxao/FlowFinder/releases/tag/v0.7.6
- **资产：** FlowFinder-0.7.6 DMG + ZIP + sha256（含发布后修复，shasum -c 校验通过）
- **签名：** ad-hoc（Hardened Runtime），公证待凭据
- **本地安装：** /Applications/FlowFinderNative.app = v0.7.6（与 Release 一致）
- **历史：** v0.7.5 资产保留于旧 Release（不含发布后修复，勿用于排障）
- **CI：** `.github/workflows/ci.yml`（PR：Rust fmt/build/test + Swift XCTest）；`.github/workflows/release.yml`（tag：打包+公证+发布）

---

## 8. macOS 27 SDK 注意事项

- `columnAutoresizingStyle`：用 `.lastColumnOnlyAutoresizingStyle`（非 `.lastColumnOnly`）
- `draw(withFrame:in:)` 替代旧版 `drawWithFrame:inView:`
- 部署目标 macOS 12.0，使用新 API 需加 `#available` 守卫
- `NSColor.secondarySystemFill` 需 macOS 14.0+

---

## 9. 关键文件索引

### 9.1 关键文件（v0.7.5 行数）

**Swift UI：**

| 文件 | 行数 | 职责 |
|------|------|------|
| `UI/FileListView.swift` | ~2117 | 文件列表（列头、选中、分组、缩略图、搜索过滤） |
| `UI/MainWindowController.swift` | ~1873 | 主窗口（布局、设备浮层、底部进度栏、主题监听） |
| `UI/MainWindowController+MenuActions.swift` | ~814 | 菜单操作扩展（v0.7.5 拆分） |
| `UI/SidebarView.swift` | ~2194 | 侧边栏（滚动容器、收藏分区 outline、标签、工具面板、主题/设置按钮、收藏右键菜单） |
| `UI/SidebarFavoritesStore.swift` | ~209 | v0.8.0 P1 新增：收藏数据层（顺序重排纯函数 / 失效状态机 / UserDefaults 持久化），可独立单测 |
| `UI/ExpandableDetailsBar.swift` | ~1733 | 详情栏（占位图标、选中显示） |
| `UI/FileGridView.swift` | ~1300 | 网格视图（选中、分组、缩略图复用） |
| `UI/PaneToolbar.swift` | ~355 | 工具栏（搜索、排序、分组、视图切换） |
| `UI/BreadcrumbBar.swift` | ~420 | 路径栏（v0.6.7 完全重写） |
| `UI/SettingsWindowController.swift` | ~580 | 设置窗口（分区布局） |
| `UI/FFModalSheet.swift` | ~383 | 模态弹窗基类（sheet 会话/高度测量两处平台陷阱，见关键决策） |
| `UI/FFCommon.swift` | - | FFPaneStateOverlayView：主流程状态视图（加载/空/错误/删除进度，v0.7.5 新增） |

**Rust Core：**

| 文件 | 行数 | 职责 |
|------|------|------|
| `core/content_index.rs` | ~1731 | 独立 SQLite FTS5 内容索引（v0.7.5 新增） |
| `core/safe_filename.rs` | ~107 | 文件名安全校验（路径穿越防线，v0.7.5 新增） |
| `ffi/mod.rs` | ~3121 | FFI 入口（tests 已拆出） |
| `ffi/tests.rs` | - | FFI 集成测试（69 个 #[test]，v0.7.5 拆分） |

**Swift 测试：** `FlowFinderNative/Tests/FlowFinderNativeTests/`（**115 tests**；覆盖：PaneState 删除/过滤/流程、详情栏流动填充与布局回归、键盘焦点与重复行回归、查重/搜索/无障碍、侧边栏导航通知发送者契约、**收藏数据层（顺序/失效/持久化，v0.8.0 P1 新增 17 项）** 等）

### 9.2 设计文档

| 文档 | 说明 |
|------|------|
| `docs/superpowers/specs/2026-09-02-v0.8.0-sidebar-favorites-redesign-design.md` | **v0.8.0 侧边栏收藏重设计（P1 已实施；D1/D3/D4 待拍板）** |
| `docs/superpowers/specs/2026-07-29-v0.6.7-full-ui-redesign-design.md` | v0.6.7 全应用 UI 重设计 |
| `docs/superpowers/specs/2026-07-28-v0.6.6-finder-clone-redesign-design.md` | v0.6.6 仿访达完整重设计 |
| `docs/superpowers/specs/2026-07-27-v0.6.5-ui-audit-report.md` | **v0.6.5 全量 UI 巡检报告（P1/P2 清单）** |
| `docs/MIGRATION_LOG.md` | **完整重构日志（建议先读）** |

### 9.3 设计稿 HTML

位于 `/Volumes/Iris-Data/文件管理系统/.trae/design-mockups/pages/`（旧路径 `Download/AI/` 已失效）

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
2. 再读 CHANGELOG.md（v0.7.2 起 / v0.8.0 段）与 docs/MIGRATION_LOG.md，了解版本历史
3. 项目根目录：/Volumes/Iris-Data/文件管理系统/flowfinder-native（旧 Download/AI 路径已迁移）
4. 设置 Xcode-beta：export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
5. 验证基线：cargo test（Rust 200 passed）+ xcodebuild test -scheme FlowFinderNativeTests（Swift 115 passed）
   跑 Swift 测试前先 pkill -f "MacOS/FlowFinderNative"（单实例策略会让宿主秒退）
6. Debug 构建用 -target（工程无 FlowFinderNative 共享 scheme），命令见 §7.2
   【用户约定】构建完必须复制到桌面供用户测试：
   cp -R /tmp/ff-dd/Build/Products/Debug/FlowFinderNative.app ~/Desktop/FlowFinderNative.app
7. 发布：Release 通道在当前环境（macOS 27 + Homebrew Rust 1.96.1）不可用，
   用 bash scripts/package-beta.sh 出测试版（build-beta/）
8. 等待用户反馈（注意：你看不到图片，需文字描述）
9. 如有新问题，先问一个澄清问题，一次只问一个
10. 所有 UI 文案和代码注释使用简体中文
11. 工作完成后更新此交接文档 + CHANGELOG
12. 注意：用户偏好优先于旧硬约束
13. 勿对 pbxproj 执行 git checkout（T11 test target 重建后多次修复；正确改法是编辑 pbxproj 而非回滚）
14. 新增 Swift 文件必须注册 pbxproj 四处，否则静默不参与编译（测试文件同理）
```

---

**交接完成。** 请下一个 AI 接手后，先阅读本文件，理解核心架构（亚克力侧边栏+实体内容区、Rust FFI C ABI、FTS5 内容索引、侧边栏分区 outline），然后验证测试基线（Rust 200 + Swift 115），等待用户反馈继续开发。
