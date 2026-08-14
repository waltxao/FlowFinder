# Swift XCTest Baseline Matrix — FlowFinder v0.7.4 (task-1, Wave1 T1)

状态结论: **Swift XCTest 当前完全不可执行** — 不存在可运行的测试目标。以下为验证命令与原始输出(2026-08-13 采集)。

环境: macOS (darwin), Xcode 未安装, 仅 Command Line Tools
(`xcode-select -p` = `/Library/Developer/CommandLineTools`)

---

## 1. 测试文件存在, 但引用不存在的符号 `FileEntryViewModel`

测试文件:

```
FlowFinderNative/Tests/FlowFinderNativeTests/FlowFinderNativeTests.swift
```

验证 1 — `FileEntryViewModel` 在 Swift 源码中的引用位置:

```bash
$ grep -rln "FileEntryViewModel" FlowFinderNative/ --include="*.swift"
FlowFinderNative/Tests/FlowFinderNativeTests/FlowFinderNativeTests.swift
```

验证 2 — 不存在 `FileEntryViewModel` 的定义/源文件:

```bash
$ find FlowFinderNative -name "FileEntryViewModel*"
# (空 — 无任何输出)

$ ls FlowFinderNative/FlowFinderNative/Model/
FileEntry.swift   PaneState.swift   SidebarItem.swift   Tag.swift   TaskInfo.swift   VolumeInfo.swift
```

结论: `FileEntryViewModel` 只出现在测试文件(和 docs/、.omo/plans/ 的迁移文档)中,
`Model/` 目录下只有 `FileEntry.swift`, 无 `FileEntryViewModel.swift`。
即使存在测试 target, `@testable import FlowFinderNative` + `FileEntryViewModel` 也无法编译。

验证 3 — pbxproj 中无任何测试 target 痕迹:

```bash
$ grep -c "FileEntryViewModel" FlowFinderNative.xcodeproj/project.pbxproj
0

$ grep -nE "Tests|XCTest|testBundle" FlowFinderNative.xcodeproj/project.pbxproj
# (空 — 无任何输出: 无 FlowFinderNativeTests target, 无 XCTest 链接)
```

## 2. Package.swift 无 testTarget

```bash
$ grep -c "testTarget" FlowFinderNative/Package.swift
0
```

`Package.swift` 只声明了一个 `.executableTarget(name: "FlowFinderNative", path: "FlowFinderNative", ...)`,
`Tests/` 目录未被任何 target 引用, `swift test` 无从运行测试。

## 3. `swift test` 实际运行输出 (FlowFinderNative/ 下)

```bash
$ swift test > /var/folders/.../swift-test-full.log 2>&1; echo "EXIT=$?"
EXIT=1
```

日志关键行 (完整日志见 task-1 采集, 此处摘录):

```
warning: 'flowfindernative': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /Volumes/.../FlowFinderNative/FlowFinderNative.entitlements
Building for debugging...
[Planning deferred tasks]
error: Failed to decode version info for '/usr/bin/actool': The data couldn't be read because it isn't in the correct format. (stdout: '', stderr: 'xcode-select: error: tool 'actool' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
')
... (actool 错误重复 8 次) ...
error: Build failed
error: fatalError
```

失败原因: (a) 构建阶段 actool 需要完整 Xcode, 当前只有 CommandLineTools;
(b) 即使工具链可用, Package.swift 无 testTarget, 测试文件不在编译单元内。

## 4. `make swift-test` 实际运行输出 (项目根)

```bash
$ make swift-test > /var/folders/.../make-swift-test.log 2>&1; echo "EXIT=$?"
EXIT=2
```

日志尾部:

```
error: Build failed
error: fatalError
make: *** [swift-test] Error 1
```

Makefile 中 swift-test 的定义 (Makefile:53-56):

```make
## swift-test: Run Swift unit tests
swift-test:
	@echo "$(BLUE)Running Swift tests...$(NC)"
	@cd $(SWIFT_DIR) && swift test
```

即 `make test` (Makefile:45, rust-test + swift-test + integration-test) 会在
swift-test 一步失败 — Swift 侧当前没有任何通过路径。

## 汇总矩阵

| 检查项 | 命令 | 结果 |
|---|---|---|
| 测试源文件 | `ls FlowFinderNative/Tests/FlowFinderNativeTests/` | 存在 1 个文件 (FlowFinderNativeTests.swift) |
| FileEntryViewModel 定义 | `find FlowFinderNative -name "FileEntryViewModel*"` | 不存在 (仅测试/文档中引用) |
| pbxproj 测试 target | `grep -nE "Tests|XCTest" project.pbxproj` | 无 (0 行) |
| Package.swift testTarget | `grep -c "testTarget" Package.swift` | 0 |
| `swift test` | 退出码 | 1 (Build failed — actool 需要完整 Xcode) |
| `make swift-test` | 退出码 | 2 (make Error 1) |
| `make test` | 推断 | 失败于 swift-test 步骤 |

修复方向(供后续 wave 使用, 不在本任务范围): 修复 FileEntryViewModel 缺失引用、
为 Package.swift 增加 testTarget 或为 pbxproj 增加 FlowFinderNativeTests target、
安装完整 Xcode 使 actool 可用。
