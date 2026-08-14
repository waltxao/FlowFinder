# T11 — 可执行 Swift XCTest target 与 shared scheme（FlowFinder v0.7.5 Wave3）

状态：**完成**。`xcodebuild test -scheme FlowFinderNativeTests` 全绿（43 tests, 0 failures）。

## 结果概览

| 项 | 状态 |
|---|---|
| FlowFinderNativeTests XCTest target | ✅ 已创建，`com.apple.product-type.bundle.unit-test` |
| shared scheme | ✅ `FlowFinderNative.xcodeproj/xcshareddata/xcschemes/FlowFinderNativeTests.xcscheme`（不依赖 xcuserdata） |
| ContentIndexBridge.swift 加入 app target | ✅（T7 未改 pbxproj，本任务补齐） |
| T10 PaneStateDeleteFilterTests + T7 ContentIndexBridgeTests | ✅ 全部纳入测试 target |
| stale API 清理 | ✅ 零残留 |
| `xcodebuild test` 运行 | ✅ 43 tests 通过 |

## Target / Scheme 架构

- **新 target `FlowFinderNativeTests`**（productType `com.apple.product-type.bundle.unit-test`）：
  - Sources build phase：`FlowFinderNativeTests.swift`、`ContentIndexBridgeTests.swift`、`PaneStateDeleteFilterTests.swift`（`Tests/FlowFinderNativeTests/**` 全部）
  - Frameworks build phase：`XCTest.framework`（`System/Library/Frameworks/XCTest.framework`）
  - host app 依赖：`PBXTargetDependency` + `PBXContainerItemProxy` → `FlowFinderNative` app target
  - 构建配置（Debug/Release）：`TEST_HOST` / `BUNDLE_LOADER` = app 可执行文件，`GENERATE_INFOPLIST_FILE=YES`，
    `HEADER_SEARCH_PATHS` 指向 `rust-core/include`（解析 app 的 bridging header 依赖），
    `LD_RUNPATH_SEARCH_PATHS` 含 `@executable_path/../Frameworks`
- **shared scheme `FlowFinderNativeTests`**：BuildAction 构建 app + test bundle；TestAction 引用 test bundle；
  环境变量 `CFFIXED_USER_HOME=/tmp/flowfinder-test-home`（隔离测试宿主 App 的 HOME，见下）
- **修复既有 pbxproj 悬挂引用**：定义 Products group（`FF000062`）与 app 的 Frameworks build phase（`FF000054`）

## stale API 替换（FlowFinderNativeTests.swift）

| 旧（已删除） | 新（当前 API） |
|---|---|
| `FileEntryViewModel` / `errorMessage` / `navigateToHome()` | `PaneViewModel` / `error` / `navigate(to:)` |
| `CoreBridge.copyFileAsync` | `CoreBridge.parallelCopy`（rayon 批量复制，返回成功数） |
| `CoreBridge.deleteFileAsync` | `CoreBridge.parallelMove`（rayon 批量移动，源消失=原“异步删除”意图） |
| `CoreBridgeError.unknownError` | `CoreBridgeError.stringConversionFailed` |
| `FileEntry.mimeType` | `FileEntry.kindDescription` |
| `testLibraryCanBeLoaded` 路径 `../Frameworks`（错误） | `Contents/Frameworks`（@rpath 打包的真实位置） |

测试意图全部保留，无 skip、无删除。

## 关键工程修复（测试得以真正运行的两处根因）

1. **dylib 安装名（install name）**：`Libraries/libflowfinder_core.dylib` 的 install name 是 cargo 的绝对路径
   `rust-core/target/.../deps/libflowfinder_core.dylib`（build-rust.sh 的 relink 回退到原始 cargo dylib 时未修正）。
   导致 app 链接记录绝对路径，运行时 dyld 尝试从源码树（外置卷 `/Volumes/Iris-Data`）加载 → 测试 runner 挂起
   （`dyld4::getLoader … open` 阻塞）。修复：在 `Build Rust Core` shell script phase 末尾
   `install_name_tool -id @rpath/libflowfinder_core.dylib`。
2. **代码签名失效**：`install_name_tool` 会使 dylib 的既有签名失效 → 运行时 `SIGKILL (Code Signature Invalid / Invalid Page)`。
   修复：`Build Rust Core` 与 `Copy Dylib to Bundle` 两个 phase 在 `install_name_tool` 后 `codesign --force --sign -`。

3. **测试宿主 App 启动挂起（环境）**：App 的 `applicationDidFinishLaunching` → `MainWindowController.init`
   → `loadInitialDirectories` 同步扫描 `~/Desktop` / `~/Documents`。开发者真实 HOME 由 iCloud 管理
   （dataless 文件），`getattrlistbulk` 元数据读取在 XCTest harness（libRPAC 拦截）下阻塞 → "hung before
   establishing connection"。**不改产品逻辑**的解法：scheme 注入 `CFFIXED_USER_HOME=/tmp/flowfinder-test-home`
   隔离测试宿主 App 的 HOME（`make swift-test` 会自动创建该目录）。

## 实际验证命令与结果

```bash
# Xcode 27.0 (beta) 可用（/Applications/Xcode-beta.app）
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild test -project FlowFinderNative.xcodeproj \
    -scheme FlowFinderNativeTests -destination 'platform=macOS,arch=arm64' \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
# => ** TEST SUCCEEDED **  (43 tests, 0 failures)
#    ContentIndexBridgeTests: 8 passed
#    FlowFinderNativeTests:    28 passed
#    PaneStateDeleteFilterTests: 7 passed
```

- `xcodebuild -list`：Targets `FlowFinderNative` / `FlowFinderNativeTests`；Schemes `FlowFinderNativeTests`
- `xcrun swiftc -parse`：3 个测试文件全部 PARSE OK
- `plutil -lint` pbxproj OK；`xmllint` scheme OK

## 环境限制记录

- 当前 `xcode-select -p` = `/Library/Developer/CommandLineTools`（仅 CLT），**CLT 不含 `xcodebuild`**。
  完整 Xcode 位于 `/Applications/Xcode-beta.app`（Xcode 27.0 build 27A5218g）。
  因此必须在命令前 `DEVELOPER_DIR=/Applications/Xcode*.app/Contents/Developer`，Makefile 已自动定位。
- 若机器完全无 Xcode，`xcodebuild` 不可用，Swift XCTest 无法运行（环境限制）；Rust 测试不受影响。

## 证据文件

- `summary.md`（本文件）
- `test-output.log`：完整 `xcodebuild test` 输出（含 ** TEST SUCCEEDED **，43/43 通过）
- `target-discovery.log`：`xcodebuild -list`、pbxproj 结构 grep（target/XCTest.framework/membership/TEST_HOST/dependency）、stale API 零残留扫描、`swiftc -parse`
