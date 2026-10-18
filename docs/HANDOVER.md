# FlowFinder 交接文档（大改前基线）

> **整理日期：** 2026-10-18
> **当前版本：** 0.7.9（构建 7901），已发 `v0.7.9-b1` 预发布
> **最新 Release：** https://github.com/waltxao/FlowFinder/releases/tag/v0.7.9-b1（Latest 仍是 v0.7.6）
> **分支：** main
> **本地路径：** `/Volumes/Iris-Data/文件管理系统/flowfinder-native`
> **代码规模：** Swift 64 文件 / 32,964 行；Rust 24 文件 / 13,529 行
> **测试基线：** Rust 200 项全绿；Swift 144 个用例（最近一次全绿 137 项 + 7 项路径栏新增单测单独验证）

本文档是大改前的**唯一交接入口**。产品定义看 `PRODUCT.md`，视觉看 `DESIGN-SPEC.md`，
验收看 `ACCEPTANCE.md`，功能清单看 `REQUIREMENTS.md`。

---

## 1. 一句话现状

能日常使用的双面板文件管理器，UI 已按访达语义收敛过三轮；**代码结构没跟上功能**——
五个 1700–2500 行的巨型文件承担了主窗口、列表、侧栏、详情栏、网格的全部逻辑，
这是大改最该动的地方。

---

## 2. 产品定位

| 项 | 结论 |
|---|---|
| 是什么 | macOS 原生双面板文件管理器（Swift/AppKit UI + Rust core，FFI C ABI） |
| 平台 | **仅 macOS 桌面**，不做移动端、不做 Intel 通用包（当前 arm64-only） |
| 不做什么 | 不做网盘、不做同步、不做插件系统、不做多标签页之外的窗口管理 |
| 目标用户 | 需要双栏对照搬运文件的本地重度用户 |
| 当前状态 | 0.7.9-b1，预发布；正式版（1.0）未排期 |

---

## 3. 代码地图

### 3.1 顶层结构

```
flowfinder-native/
├── FlowFinderNative/                 # Xcode 工程
│   ├── FlowFinderNative/             # 应用源码（64 文件 / 32,964 行）
│   │   ├── App/                      # 入口、AppDelegate（2 文件）
│   │   ├── Bridge/                   # Swift↔Rust 桥接（11 文件，CoreBridge 为主）
│   │   ├── Model/                    # FileEntry / PaneState 等（6 文件）
│   │   ├── UI/                       # 全部界面（45 文件 / 27,030 行）
│   │   ├── Libraries/                # build-rust.sh 产物（.a/.dylib，不入库）
│   │   └── Resources/                # Info.plist、图标
│   ├── Tests/FlowFinderNativeTests/  # XCTest（1 个大文件 + 少量分文件）
│   └── FlowFinderNative.xcodeproj
├── rust-core/                        # Rust core（24 文件 / 13,529 行）
│   ├── src/ffi/mod.rs                # FFI 入口（3,124 行）
│   ├── src/ffi/tests.rs              # FFI 集成测试（1,768 行）
│   ├── src/core/                     # 18 个功能模块
│   ├── include/ff_ffi.h              # C ABI 头文件
│   └── target/                       # cargo 缓存（1.4G，不入库）
├── docs/                             # 五件套 + 官网（index.html/images）
├── scripts/                          # build-rust.sh / package-beta.sh / 集成测试
├── build/Products/                   # Debug 产物（make build 输出，不入库）
└── Makefile
```

### 3.2 需要重点认识的巨型文件

| 文件 | 行数 | 实际职责（远超文件名） |
|---|---|---|
| `UI/FileListView.swift` | 2,450 | 列表 + 列头 + 分组 + 行视图 + 缩略图 + 键盘 + 拖拽 + 右键 |
| `UI/MainWindowController.swift` | 2,342 | 窗口骨架 + 双面板装配 + 设备浮层 + 进度栏 + 通知 + 焦点 |
| `UI/SidebarView.swift` | 2,321 | 收藏 outline + 标签 + 设备 + 工具面板 + 右键菜单 |
| `UI/ExpandableDetailsBar.swift` | 2,243 | 详情栏全部形态（收起/展开/多选/空态/标签药丸） |
| `UI/FileGridView.swift` | 1,798 | 网格 + 分组 + 选中 + 拖拽 |
| `UI/SettingsWindowController.swift` | 1,415 | 设置全部页 |
| `rust-core/src/ffi/mod.rs` | 3,124 | 全量 C ABI（函数多而薄，但单文件过大） |

---

## 4. 架构与数据流

```
AppDelegate → MainWindowController
                ├─ SidebarView（收藏/标签/设备）
                ├─ PaneContainer ×2
                │    ├─ PaneToolbar（导航 + 面包屑 + 搜索/排序/分组/视图）
                │    ├─ FileListView / FileGridView
                │    └─ ExpandableDetailsBar（浮层覆盖）
                └─ TaskProgressBar
                        │
                 PaneViewModel（每面板一个，Combine $state）
                        │
                   CoreBridge（Swift）
                        │  C ABI
                 rust-core::ffi/mod.rs
                        │
     bulk_read / fsevents / sqlite_cache / content_index(FTS5) / tags / …
```

关键事实：

- **状态单一来源是 `PaneState`**（`PaneViewModel.$state` 驱动 UI）。但「活动面板」
  另有 `activePane` + 第一响应者两个真值源，历史上多次出现菜单操作打到另一面板的 bug。
- **目录列举**走独立并发队列 + 10s 超时；共享队列曾被慢目录（iCloud）阻塞成死锁。
- **文件变更**走真实 FSEventStream + 300ms 去抖，300ms 后通知刷新。
- **选中态颜色**三处统一读 `FFAccent`（默认 `#0a84ff`，设置可改），失焦统一
  `unemphasizedSelectedContentBackgroundColor`。
- **设置**存 UserDefaults（Rust 侧 `~/Library/Preferences/com.flowfinder.native.json`，
  Swift 侧 `.plist`），两边都有，改动时注意双写。
- **封面式设计令牌**只有 `FFDesign.Text`（9 档字号）与少量背景/圆角常量；
  字号仍有 126 处硬编码（见 §8）。

---

## 5. 设计基线（大改也不能丢的东西）

`DESIGN-SPEC.md` §1 把视觉分成两类，**这是终止「像不像访达」扯皮的根本规则**：

| 类别 | 范围 | 要求 |
|---|---|---|
| 对标访达 | 材质、选中态、字号、行高、侧栏结构、列头、分组、面包屑、详情栏内容项 | 必须一致，可测量 |
| 产品自主 | 双行工具栏 72pt、双操作区、详情栏浮层高度、设备浮层、标签行式 | 按规格执行，**不得以「不像访达」为由返工** |

其他硬约束：

- 侧栏宽度默认 220（可拖 160–280，记忆）；窗口最小 1060×700（侧栏 160 + 两区各 450）。
- 操作区超椭圆圆角 16pt；详情栏玻璃浮层；设备浮层是唯一实体卡片。
- 活动面板 = 整块 1.5pt 强调色内描边（W-08），点击面板任一控件即切换。
- 列表选中框左右内缩 4pt + 5pt 圆角（C-04）。

---

## 6. 构建 / 测试 / 发布

### 6.1 环境

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
# 当前机器：macOS 27.2 beta (26B5112a) + Xcode-beta + Homebrew Rust
```

### 6.2 常用命令

| 命令 | 作用 |
|---|---|
| `make build` | Rust core + Debug app（产物 `build/Products/Debug/`） |
| `make demo` | build 后复制到 `~/Desktop/FlowFinderNative.app`（**用户实测必做**） |
| `make rust-test` | cargo test（200 项） |
| `make swift-test` | xcodebuild test（144 个用例） |
| `make beta` | `scripts/package-beta.sh` 出 DMG/ZIP 到 `build-beta/` |
| `make version` | 打印版本（真源：Xcode 工程） |

### 6.3 三个必须知道的环境事实

1. **工程没有 `FlowFinderNative` 共享 scheme**，只有 `FlowFinderNativeTests`。
   Debug 构建走 `-target`（不支持 `-derivedDataPath`，用 `SYMROOT`/`OBJROOT` 绝对路径）。
2. **跑 Swift 测试前先 `pkill -f "MacOS/FlowFinderNative"`**。单实例策略会让测试宿主秒退，
   表现为 `test runner hung before establishing connection` 假故障。
3. **当前该故障是真故障**（2026-10-18）：机器凌晨重启进 macOS 27.2 beta 后，
   即使杀掉实例、清 DerivedData，测试宿主仍 100% 连不上；sample 宿主显示主线程
   正常空闲在 run loop，应用本身没死锁。判断为系统更新与 Xcode-beta 的兼容问题，
   与代码无关（前一日同套件全绿）。**大改前优先恢复测试通道**，见 §9。

### 6.4 版本号与发布

- 版本唯一真源：`project.pbxproj` 的 `MARKETING_VERSION`（当前 0.7.9）与
  `CURRENT_PROJECT_VERSION`（7901）。发版时四处同步：pbxproj、`rust-core/Cargo.toml`、
  `README.md` 徽标、`CHANGELOG.md`。
- 发布用 `make beta` → `gh release create vX.Y.Z ...`（当前走预发布）。
- **Release 通道在本机不可用**：Homebrew rustc 1.96.1 + macOS 27 生成 mis-aligned
  LINKEDIT dylib，`dlopen` 拒绝；测试版打包走 `package-beta.sh`（Debug 构建 + ad-hoc 签名）。
  `lto = "thin"` 可用，fat LTO 必炸。
- 产物 ad-hoc 签名，首次打开需右键 → 打开；Developer ID 公证未接（缺凭据 Secrets）。
- **官网下载直链写死了 tag**（`docs/index.html`），下次发版必须同步改，否则按钮指向旧包。

---

## 7. 工程约定与平台坑（都是踩过的）

### 7.1 Xcode / 工程

- 新增 Swift 文件必须在 `project.pbxproj` **注册四处**（PBXBuildFile / PBXFileReference /
  Group children / Sources phase），否则静默不参与编译。**注册前先 grep 候选 ID**——
  复用已占用 ID 会让 Xcode 解析到旧 fileRef，新文件静默丢失（表现为「cannot find X in scope」）。
- 勿对 `project.pbxproj` 执行 `git checkout`，正确改法是编辑而不是回滚。
- 委托创建的 `NSTableRowView` 其 `selectionHighlightStyle` 默认 `.none`；此时
  NSTableView 用系统强调色自绘，行视图的 `drawSelection` 覆写不会生效。要自绘必须显式设 `.regular`。

### 7.2 AppKit 布局

- 瞬态可变约束（列宽、定高）一律 `defaultHigh`，`required` 会瞬态无解、刷冲突日志。
- 隐藏视图的约束**仍参与求解**；动态行列表用清空/重建，不要靠 `isHidden`。
- `FFModalSheet` 两个坑：关闭必须走 `parent.endSheet`（`close()` 会毒化后续
  `NSOpenPanel` sheet）；高度测量要两段式（先撑到已知尺寸再量 `fittingSize`）。

### 7.3 Rust / FFI

- `build-rust.sh` 的重链接必须带 `-framework CoreServices`，否则 FSEventStream 符号未定义、
  静默回退到直接拷贝 dylib。
- 目录列举、FSEvents 必须各自独立队列/线程，QoS 用 USER_INITIATED，避免主线程优先级反转。
- FFI 结构体布局有断言测试，改字段顺序会直接编译失败——这是有意的。

### 7.4 其他

- 错误文案一律经 `FFErrorText.humanize` 转中文 + 给下一步；errno 必须精确解析，
  不能用 `contains`（`os error 28` 含子串 `os error 2`）。
- 侧栏通知必须带窗口身份守卫（`isOwnSidebarNotification`），多窗口下否则会误杀/误触。
- 调试日志用 `NSLog`（`print` 在 stdout 重定向时全缓冲）。
- 编译缓存会重放陈旧诊断与旧测试数，采信前先 clean 强制重编译。

---

## 8. 已知债务（大改清单的输入）

| 类型 | 项 | 位置 / 说明 |
|---|---|---|
| 结构 | **五个巨型文件** | 见 §3.2；列表 2450 行、主窗口 2342、侧栏 2321、详情栏 2243、网格 1798 |
| 结构 | Controller 同时管布局/数据/通知/焦点 | `MainWindowController` 有 100+ 方法，改动牵一发动全身 |
| 一致性 | 126 处硬编码字号未令牌化 | `FFDesign.Text` 之外散落全文；批量替换会动行高，须单独一轮 |
| 正确性 | 「活动面板」双真值源 | `activePane` + firstResponder，已有多次分派错误历史 |
| 功能 | P-05 卷操作无 UI | `ff_volume_*` 零调用（推出/挂载/健康状态） |
| 功能 | P-08 AI 整理卡未接线 | 设计稿有，UI 是禁用占位 |
| 功能 | X-05 标签缺重命名 | 新建/改色已有 |
| 功能 | X-08 连接服务器两个无效控件 | 记住密码 / 自动连接 |
| 测试 | **Swift 测试宿主连不上（当前阻塞）** | 见 §6.3；大改前必须先解决，否则没有回归护栏 |
| 测试 | 逻辑单测覆盖集中在少数纯函数 | `FFBreadcrumbSegments` / `FFStartupPath` / `FFErrorText` / `SidebarFavoritesStore` 是正例，可作模板 |
| 发布 | 公证未接、Release 工具链坏 | 只能出 ad-hoc 预发布包 |
| 发布 | 官网下载直链写死 tag | 每次发版手改 `docs/index.html` |
| 验收 | J3 全键盘旅程未验收 | ⌘F → 输入 → ↑↓ → Enter 全链路 |

---

## 9. 大改建议（按投入产出排序）

1. **先恢复测试通道**（阻塞项）。排查顺序：换 Xcode 正式版 / 重装 Xcode-beta /
   用 `xcodebuild test-without-building` 验证 / 新建一个空测试 target 验证宿主握手。
   没有测试护栏就动结构，等于裸奔。
2. **抽纯函数补测试**。已有四个先例；大改前把 `PaneState` 的排序/分组/过滤、
   路径拼接、标签排序等逻辑从 View 里剥出来，先写测试再动 UI。
3. **拆巨型文件**。建议顺序：`MainWindowController`（拆成 Window/PaneAssembly/
   DevicePanel/ProgressBar 四个 extension 文件）→ `FileListView`（列表数据源/行视图/
   键盘拖拽三块）→ `SidebarView` → `ExpandableDetailsBar`。每次只拆一个文件、
   拆完立刻 `make demo` 人工过一遍三条主旅程。
4. **收敛真值源**。把 `activePane` 与 firstResponder 合并成单一「焦点面板」概念，
   菜单/键盘/描边都从它派生。
5. **字号令牌收尾**（126 处）。这一项会动行高与视觉，必须单独一轮、逐屏截图比对。
6. 最后再动 `ffi/mod.rs`（3124 行）——它薄而多，拆分收益低于风险。

大改的验收口径建议直接沿用 `docs/ACCEPTANCE.md` 的三条旅程 + J3 键盘旅程，
不要新造一套。

---

## 10. 本次整理记录（2026-10-18）

### 10.1 删除（101 个已跟踪文件 + 约 530MB 未跟踪产物）

| 类别 | 内容 | 理由 |
|---|---|---|
| 历史规划稿 | `.omo/`（46）、`docs/superpowers/`（43） | v0.7.4/各轮重设计的 agent 产物，已被五件套取代 |
| 迁移文档 | `MIGRATION_LOG.md`、`MIGRATION_PLAN.md` | Tauri→原生迁移已完结 |
| 旧说明 | `VERIFICATION.md`、`DEVELOPMENT.md`、`SUBPROJECT_TEMPLATE.md` | 与 README、本文件重复 |
| 旧发版说明 | `docs/release-notes/`（5 份 0.6.x） | CHANGELOG + GitHub Releases 已覆盖 |
| 旧设计史 | `修改历史-2026-08-30-原生体验重设计.md` | 已被 DESIGN-SPEC 变更记录取代 |
| 调试/备份 | `docs/ff-debug-20260806.log`、`REQUIREMENTS.md.bak_20261017` | 垃圾与备份 |
| 误入库二进制 | `rust-core/libflowfinder_core_relinked.dylib`（2.9M） | 7/29 构建产物，全仓零引用 |
| 构建缓存 | `FlowFinderNative/.build/`（124M）、`build/Intermediates`（249M）、`build-beta/DerivedData`（142M）、`build-beta/*.dmg/.zip`（7.2M） | 可再生；发布包已在 GitHub Release |
| 其他 | `.superpowers/`（3.2M）、5 个 `.DS_Store`、`CONTINUE_DEV_PROMPT.md` | agent 工作目录与垃圾 |

仓库体积 2.3G → 1.8G（剩余主要是 `rust-core/target` 1.4G，刻意保留以省重编时间）。

### 10.2 保留

五件套 + 本文件、`docs/index.html` + `docs/images/`（官网）、`build/Products`（桌面副本来源）、
`rust-core/target`、`Libraries/`（当前构建产物）、`.trae`/`.vscode`（工具配置）。

### 10.3 找回方式

被删的历史文档都在 Git 历史里，例如：

```bash
git log --oneline -- docs/MIGRATION_LOG.md        # 找删除前的提交
git show <commit>:docs/MIGRATION_LOG.md > /tmp/x.md
```

`.gitignore` 已补：`.omo/`、`rust-core/*relinked*.dylib`、`docs/*.log`。

---

## 11. 接手清单

```
1. 读本文件 → PRODUCT.md → DESIGN-SPEC.md §1（两类基准）→ ACCEPTANCE.md 三条旅程
2. 验证构建：export DEVELOPER_DIR=... && make build && make demo
3. 验证 Rust：make rust-test（应 200 passed）
4. 验证 Swift：pkill -f "MacOS/FlowFinderNative" && make swift-test
   若报 test runner hung，先按 §9.1 排查，不要怀疑业务代码
5. 跑一遍主旅程：双栏导航 / 跨栏复制 / 标签筛选 / 搜索 / Quick Look
6. 大改前先做 §9.2：抽纯函数 + 补测试，再动结构
7. 任何 UI 改动先用 make demo 出包，让用户在桌面副本上实测
8. 改完更新 CHANGELOG「未发版」段 + 本文件的债务表
9. 发版时四处同步版本号，并改官网下载直链
10. 有疑问一次只问一个问题
```

---

**交接完成。** 当前代码可构建、可运行、可出包；测试通道待恢复。结构债务集中在
五个巨型文件与双真值源，大改请从「补护栏 → 拆文件 → 收敛状态」的顺序推进。
