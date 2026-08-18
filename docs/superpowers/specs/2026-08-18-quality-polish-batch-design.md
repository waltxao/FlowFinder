# v0.7.5+ 质量打磨批量设计（瑕疵三件套 + clippy 清零 + 入口点清理）

日期：2026-08-18
状态：已确认方向（用户选定"质量打磨批量"），设计定稿
范围：无新功能，纯质量内功；大文件拆分（FileListView 等）明确排除在本轮外

## 背景

v0.7.5 已发布（2026-08-14）并通过最终验证（2026-08-17 APPROVE）。验证记录了三项遗留：
公证未完成（无凭据，不在本轮范围）、clippy 127 warnings、FlowFinderApp.swift 遗留 import SwiftUI。

本轮复核发现实际情况比验证记录更严重：

1. **clippy 实测编译失败**：`cargo clippy --all-targets` 报 56 个 error + 91 个 warning
   （54 个 `not_unsafe_ptr_arg_deref` 被提级为 error，疑因工具链升级），CI 门禁形同虚设。
2. **import SwiftUI 并非"无实际使用"**：`App/FlowFinderApp.swift` 的 `@main struct FlowFinderApp: App`
   + `Settings { EmptyView() }` 入口壳本身就是 SwiftUI API。v0.7.5 验证记录此结论有误。
3. **v0.7.3 遗留三处瑕疵仍在**（交接文档明确记录，一直未清）。

## 目标

1. `cargo clippy --all-targets --all-features -- -D warnings` 完全通过（0 error 0 warning）。
2. 删除 v0.7.3 遗留三处瑕疵。
3. 应用入口改为纯 AppKit，移除 SwiftUI 依赖声明。
4. 全量回归通过：cargo test（202+）、make swift-test（70+）、Debug 构建部署桌面。

## 范围与方案

### 项目 1：clippy 56 error + 91 warning 清零

**error 部分（54 个 `not_unsafe_ptr_arg_deref`，全在 ffi/）**

方案 A（采用）：`ffi/mod.rs` 模块级 `#![allow(clippy::not_unsafe_ptr_arg_deref)]` + 注释说明理由。
理由：FFI 函数从 C ABI 调用，调用方（Swift）无法表达 Rust 的 unsafe 语义；C 边界函数
解引用裸指针是 FFI 固有模式，该 lint 对 FFI 模块属于已知误报场景。模块级收口优于
逐函数 allow（54 处噪音）。
方案 B（否决）：54 个函数全部改 `unsafe fn` + `# Safety` 文档。语义更严格，但所有
Rust 测试调用处要加 unsafe 块，改动面大且收益低（这些函数不会被 Rust 侧安全代码直接调用）。

**warning 部分（91 个，逐类机械修复，不逐条列举）**

| 类别 | 数量 | 修法 |
|---|---|---|
| `io::Error::new(ErrorKind::Other, ..)` -> `io::Error::other` | 17 | 机械替换 |
| 测试代码裸指针同类型 cast 多余 | ~15 | 删除多余 cast |
| 引用立即解引用（needless borrow） | ~10 | 删除多余 `&`/`*` |
| let 绑定 unit 值 | 9 | 改直接调用（如 `let _ = lock.unlock()` -> `lock.unlock()`） |
| `to_string` 多余 | 5 | 删除 |
| `map_or` 简化 / 冗余闭包 / `is_err()` | ~6 | 按建议改写 |
| `from_str` 命名混淆 | 2 | 重命名为非 trait 冲突名 |
| `Default` 实现建议（VolumeManager/TaskScheduler） | 2 | 补 `impl Default` |
| 其他单发 | 余量 | 逐条修复 |

原则：只做 lint 建议的等价改写，不做任何行为变更；有疑义的单独评估而不是盲改。

### 项目 2：v0.7.3 遗留三处瑕疵

1. **删除死代码 `addTagMenu`**（`UI/FFPaneActionsController.swift:192`）：
   全项目无 selector 引用（重构后遗留）。删除整个方法。删除前再全局搜索确认一次。
2. **更新过时注释**（`UI/FFCommon.swift:139-140`）：
   FFPaneMenuBuilder 注释称"两个视图都实现了同名 @objc 方法，target 传入实际视图"，
   实际 target 是 actionsController。改为如实描述。
3. **FileListView.keyDown 统一委托**（`UI/FileListView.swift:1922`）：
   现状 Space/Enter 内联处理且用旧的 `modifiers.isEmpty` 判断（Enter 自带 .numericPad
   会导致漏判，虽有 FFQuickLookTableView 子类兜底）；FileGridView 已统一走
   `actionsController.handlePaneKey(event.keyCode)`。将 FileListView.keyDown 的
   Space/Enter/Del 分支改为与 GridView 相同的委托模式：
   `if !hasRealModifier && [49,36,76,51].contains(keyCode) { if actionsController.handlePaneKey(...) { return } }`，
   保留 Cmd+Down/Cmd+O/Cmd+Up 分支不变。

### 项目 3：应用入口纯 AppKit 化

现状：`App/FlowFinderApp.swift` 用 SwiftUI `@main` 壳 + `@NSApplicationDelegateAdaptor(AppDelegate.self)`。
方案：改为 `main.swift`（`NSApplication.shared` + `NSApplicationDelegate` + `NSApp.run()`），
删除 SwiftUI import 与 `App/FlowFinderApp.swift`。
权衡：保留现状亦可运行，但既然入口壳是 SwiftUI 的唯一使用点，去掉后项目不再链接
SwiftUI 运行时依赖，也消除"验证记录与事实不符"的混乱。改动仅入口文件 + pbxproj 注册，
AppDelegate 逻辑不动。
风险：@NSApplicationDelegateAdaptor 与手动 setDelegate 的差异在于 SwiftUI 会先设置自己的
delegate 再转发——本项目 AppDelegate 管理 NSWindow 生命周期，手动 `NSApp.delegate` 模式是
AppKit 标准做法，行为等价。需实测启动、菜单、设置窗口（Settings scene 曾是 SwiftUI 提供，
但项目实际设置窗口是 SettingsWindowController 独立 NSWindow，与 scene 无关——删除前确认
`Settings { EmptyView() }` 没有被用作真正的偏好设置入口）。

### 明确排除

- 大文件拆分（FileListView 2117 / MainWindowController 1873 / SidebarView 1763 / ExpandableDetailsBar 1733）
- 公证/签名（需用户 Apple 开发者凭据）
- Intel 通用二进制、LLM 标签、多语言、自动更新
- 任何 UI 行为变更

## 验证策略

1. `cargo clippy --all-targets --all-features -- -D warnings` 零输出通过。
2. `cargo test --all-features`：202+ 全过。
3. `make swift-test`（xcodebuild test）：70+ 全过。
4. Debug 构建并按用户约定复制到桌面：
   `cp -R /tmp/ff-dd/Build/Products/Debug/FlowFinderNative.app ~/Desktop/FlowFinderNative.app`
5. 手工冒烟（用户执行）：启动、双面板浏览、空格 QuickLook、Enter 重命名、Del 删除、
   Cmd+Down 打开、Cmd+Up 上级、设置窗口、右键菜单标签子菜单。

## 风险与回滚

- clippy 机械修复可能引入行为差异 -> 每类修复后跑 cargo test；可疑项不盲改。
- keyDown 统一委托可能改变键盘行为 -> FFQuickLookTableView 子类兜底链路保留，XCTest
  覆盖键盘用例；用户实测四键（空格/Enter/Del/Cmd+Down）。
- 入口点改写风险最高 -> 放最后单独提交，出问题可单独 revert 不影响前两项。
- 全程分三个独立 commit（瑕疵三件套 / clippy 清零 / 入口点），任意一项可独立回滚。
