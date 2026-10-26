# FlowFinder Delivery Profile

本文件记录 FlowFinder 在 2026-10-21 已核实的交付命令、工程结构和测试环境。它是项目档案，不是通用规则；每次复用前重新读取 Makefile、scheme 和工程状态，确认命令、路径和数量仍然有效。

## 工程位置

| 项 | 值 |
|---|---|
| 项目根目录 | `/Volumes/Iris-Data/文件管理系统/flowfinder-native` |
| Xcode 工程 | `FlowFinder/FlowFinder.xcodeproj` |
| Xcode scheme | `FlowFinderTests` |
| 应用 target | `FlowFinder` |
| 测试 target | `FlowFinderTests` |
| 参考分支 | `feat/v0.9-overhaul`（会变化，先自行确认） |
| 桌面产物 | `/Users/waltxao/Desktop/FlowFinder.app` |

## 已验证命令

```bash
cd "/Volumes/Iris-Data/文件管理系统/flowfinder-native"

# 构建
make build

# 全量 Swift XCTest；内部使用 xcodebuild，不是 swift test
make swift-test
```

`make swift-test` 的 Makefile 规则会把 xcodebuild 输出过滤为
`error:`、`Executed ... tests`、`TEST SUCCEEDED/FAILED`，再 `tail -8`。失败时具体用例名可能被截断。

需要失败详情时直接运行：

```bash
cd "/Volumes/Iris-Data/文件管理系统/flowfinder-native"

xcodebuild test \
  -project FlowFinder/FlowFinder.xcodeproj \
  -scheme FlowFinderTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  2>&1 | grep -E "Test Case .*failed|XCTAssert|error:.*Tests|TEST FAILED" | head -60
```

本机曾使用 `DEVELOPMENT_DIR=/Applications/Xcode-beta.app/Contents/Developer` 指定工具链；
换机或 Xcode 更新后先检查 `xcode-select -p`，不要把该路径当成固定事实。

运行单个测试类：

```bash
xcodebuild test \
  -project FlowFinder/FlowFinder.xcodeproj \
  -scheme FlowFinderTests \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  -only-testing:FlowFinderTests/<TestClass>
```

## pbxproj 登记

FlowFinder 当前使用传统 `PBXGroup`。新增 Swift 文件时检查四处：

1. `PBXBuildFile`：`<ID> /* File.swift in Sources */ = {isa = PBXBuildFile; fileRef = <FileRefID>; };`
2. `PBXFileReference`：`<FileRefID> /* File.swift */ = {isa = PBXFileReference; ... path = File.swift; ...};`
3. `PBXGroup`：把 `<FileRefID>` 放进应用或测试分组。
4. `PBXSourcesBuildPhase`：把 `<ID>` 放进正确 target 的 Sources 列表。

应用源文件和测试源文件的 target 不同：

- 生产代码加入 `FlowFinder` 的 Sources。
- 测试文件加入 `FlowFinderTests` 的 Sources。
- 分配新的唯一 ID；不要复制已有 ID，也不要把测试文件加入应用 target。

若工程切换为 `PBXFileSystemSynchronizedRootGroup`、XcodeGen、Tuist 或 SPM，先按新结构处理，不要继续手工登记。

## 测试宿主隔离

FlowFinder 的 `FlowFinderTests.xcscheme` 曾出现以下配置：

- `LaunchAction` 的 `CFFIXED_USER_HOME=/tmp/flowfinder-test-home`。
- TestAction 的 `shouldUseLaunchSchemeArgsEnv="YES"`，因此测试宿主沿用 LaunchAction 环境。
- TestAction 增加 `FF_SKIP_SIDEBAR_ICONS=1`。

测试 home 至少需要：

```text
/tmp/flowfinder-test-home/Desktop
/tmp/flowfinder-test-home/Documents
```

用途：XCTest 创建完整窗口并触发布局时，侧栏收藏夹图标会走
`NSWorkspace.iconForFile` → LaunchServices → `__getattrlist`。如果收藏路径指向慢卷或网络路径，主线程可能长时间卡住，表现为某个测试 30 秒以上不结束。

`FF_SKIP_SIDEBAR_ICONS=1` 只跳过测试中的真实图标查询，是测试隔离开关：

- 不要用于发布或日常运行。
- 不要把它说成生产性能修复。
- 测试结束后仍应确认真实应用启动与侧栏显示。

排查时用 `sample <pid>` 或等价工具确认主线程是否卡在 `NSWorkspace`/LaunchServices；同时清理残留的 `MacOS/FlowFinder` 和测试宿主进程。

## 应用内自检

自检走可执行文件本身，不依赖 XCTest：

```bash
FF_SKIP_PERMISSION_GATE=1 FF_SELFTEST=1 \
  "$HOME/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app/Contents/MacOS/FlowFinder"
```

`FF_SKIP_PERMISSION_GATE=1` 仅用于本地自动化，不要用于发布验收。2026-10-21 的基线是自检 **135 项 0 失败**；数量会变化，引用前重新跑。

## 产物与桌面副本

构建产物：

```text
/Users/waltxao/Library/Caches/FlowFinderBuild/Products/Debug/FlowFinder.app
```

桌面副本：

```text
/Users/waltxao/Desktop/FlowFinder.app
```

更新桌面副本后核对：

```bash
shasum -a 256 /Users/waltxao/Desktop/FlowFinder.app/Contents/MacOS/FlowFinder
```

同时确认可执行文件启动后显示的版本号与工程版本一致。2026-10-21 的会话中版本为 `0.7.9`，但版本号不是长期常量。

## 已验证基线（2026-10-21）

- `make build`：`BUILD SUCCEEDED`。
- 全量 XCTest：**279 条 0 失败**。
- `FF_SELFTEST=1`：**135 项 0 失败**。
- 桌面副本已更新，并核对过可执行文件 hash。
- 关闭窗口、深色模式等辅助修复已通过自动测试和真机走查。
- 所有改动留在工作区，未提交、未推送。

这些数字是历史证据，不是当前状态的保证。复用技能时重新运行命令，重新记录日期和数量。

## 仍需人工验收的项目

以下项目在 2026-10-21 的最终交付中仍未完成或仍依赖人工判断：

- 高对比模式下逐屏截图检查。
- VoiceOver 完整走查。
- 1060×700 全屏截图。
- 跨窗口拖拽的真实手感、浮层跟随和窗口拖动跟手性。
- 精确性能采样：选中 <50ms、500 项 <300ms、滚动 60fps、主线程 >100ms 等指标。

物理拖拽曾因合成事件坐标原点、TCC 弹窗和窗口遮挡而无法可靠自动化；需要在桌面副本上由人手动执行：

```text
拖标签出窗成新窗 → 拖回操作区变双栏（新面板在落点侧）
→ 卡片留白调宽（窗口不动）
```

视觉走查曾因屏幕锁定/全黑而无法进行。发生这种情况时，应在 SPEC、需求台账和 HANDOVER 中写“未验”及原因，并给出上述人工步骤；不要用自动测试或构建成功代替视觉验收。
