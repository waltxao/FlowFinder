# FlowFinder 参考实现（已实测）

来源：会话 `8e8ea484-01b5-4565-8e7c-e1034f1d68a1`，2026-10-21 至 2026-10-22。
这是 `xcode-dated-build-number` 的已验证参考，不是通用模板；移植时替换项目路径并重新走侦察步骤。

## 最终规则

- `MARKETING_VERSION = 0.8.0`，保持纯 `x.y.z`。
- `CURRENT_PROJECT_VERSION = yymmddNN`，旧值 `8001` 会在首次运行时重置为当日 `01`。
- UI 显示 `FFBuildInfo.displayVersion`：`0.8.0-26102201 Beta`。
- 旧格式 `0.8.0 (8001) Beta` 已废弃。

## 文件地图

| 文件 | 作用 |
| --- | --- |
| `flowfinder-native/scripts/lib-version.sh` | 版本单一真源读取器；优先 `xcodebuild -showBuildSettings`，失败时回退 pbxproj |
| `flowfinder-native/scripts/bump-version.sh` | 计算并写入 `CURRENT_PROJECT_VERSION`，支持 `--dry-run` |
| `flowfinder-native/Makefile` | 暴露 `bump-version`；`build`/`release`/`beta` 各调用一次 |
| `flowfinder-native/scripts/package.sh`、`package-beta.sh` | 从 `lib-version.sh` 读取版本并传给 `xcodebuild` |
| `flowfinder-native/FlowFinder/FlowFinder/UI/FFCommon.swift` | `FFBuildInfo.displayVersion` 展示层 |
| `flowfinder-native/FlowFinder/FlowFinder/Resources/Info.plist` | 使用 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` |
| `flowfinder-native/FlowFinder/Tests/FlowFinderTests/InteractionRegressionTests.swift` | 展示格式断言 |

`Info.plist` 不在工程根目录；最初猜测 `FlowFinder/FlowFinder/Info.plist` 失败，实际路径是 `FlowFinder/FlowFinder/Resources/Info.plist`。

## 已验证的递增脚本

`scripts/bump-version.sh` 的核心逻辑（2026-10-22 版本）：

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-version.sh"

PBXPROJ="$FF_PROJECT_DIR/FlowFinder/FlowFinder.xcodeproj/project.pbxproj"
TODAY="$(date +%y%m%d)"

if [[ "$FF_BUILD" == "$TODAY"[0-9]* ]]; then
    NEXT_SEQ=$(( 10#${FF_BUILD#"$TODAY"} + 1 ))
else
    NEXT_SEQ=1
fi
NEXT_BUILD="$(printf '%s%02d' "$TODAY" "$NEXT_SEQ")"

if [[ "${1:-}" == "--dry-run" ]]; then
    echo "$FF_VERSION-$NEXT_BUILD"
    exit 0
fi

sed -i '' -E "s/^([[:space:]]*CURRENT_PROJECT_VERSION = )[^;]+;/\1${NEXT_BUILD};/" "$PBXPROJ"
echo "$FF_VERSION-$NEXT_BUILD"
```

特点与限制：

- 使用 macOS BSD `sed -i ''`。
- 用 `sed` 替换 pbxproj 中所有匹配行，天然同步 Debug/Release。
- 参考实现没有 99 上限保护，也没有对“同一天但后缀非两位数字”的严格校验；长期使用时增加保护。
- `grep` 兜底只取第一条构建号；多配置不一致时不会报警，因此侦察阶段必须人工核对。

## Makefile 接线

```make
## bump-version: 按 A.B.C-yymmddxx 规则递增内部构建号（CFBundleVersion）
bump-version:
	@bash $(SCRIPT_DIR)/bump-version.sh

## build: Debug 构建（Rust + Swift），构建号自动递增
build: rust
	@echo "$(GREEN)✓ 版本 $$(bash $(SCRIPT_DIR)/bump-version.sh)$(NC)"
	...

## release: Release 构建（可直接分发），构建号自动递增
release:
	@echo "$(GREEN)✓ 版本 $$(bash $(SCRIPT_DIR)/bump-version.sh)$(NC)"
	...

## demo: Debug 构建并复制到桌面（用户实测用）
demo: build
	...

## beta: 打测试版 DMG/ZIP 到 build-beta/，构建号自动递增
beta:
	@bash $(SCRIPT_DIR)/bump-version.sh >/dev/null
	@bash $(SCRIPT_DIR)/package-beta.sh
```

注意：这些目标内部已经递增，不要再额外执行 `make bump-version`。`demo` 继承 `build`，只递增一次。

## 展示层

`UI/FFCommon.swift:1364-1384`：

```swift
enum FFBuildInfo {
    static let channel = "Beta"

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static func displayVersion(marketing: String, build: String, channel: String) -> String {
        "\(marketing)-\(build) \(channel)"
    }

    static var displayVersion: String {
        displayVersion(marketing: marketingVersion, build: buildNumber, channel: channel)
    }
}
```

对应测试 `InteractionRegressionTests.swift:539-542`：

```swift
func testDisplayVersionFollowsDateStampedRule() {
    XCTAssertEqual(FFBuildInfo.displayVersion(marketing: "0.8.0", build: "26102101", channel: "Beta"),
                   "0.8.0-26102101 Beta")
}
```

## 实测时间线

1. 旧 pbxproj：`CURRENT_PROJECT_VERSION = 8001`（Debug/Release 两处），`MARKETING_VERSION = 0.8.0`。
2. dry-run 旧值：输出 `0.8.0-26102101`。
3. 真实递增：写入 `26102101`；同日 dry-run 输出 `0.8.0-26102102`。
4. 为验证同日递增执行真实递增到 `26102102`，随后回滚 pbxproj 到 `8001`，避免验证消耗正式序号。
5. 2026-10-22 正式 `make build`：输出 `✓ 版本 0.8.0-26102201`，跨日重置为 `01`。
6. `make demo`：递增为 `0.8.0-26102202`，覆盖桌面副本并启动。
7. 产物核验：

   ```text
   "CFBundleShortVersionString" => "0.8.0"
   "CFBundleVersion" => "26102202"
   FlowFinder.app: valid on disk
   FlowFinder.app: satisfies its Designated Requirement
   ```

8. 最终产物自检 163 项 0 失败、20 轮布局压力 0 失败；UI/AX 读到 `0.8.0-26102201 Beta`，桌面副本为 `0.8.0-26102202 Beta`。

## 踩坑与修复

### 括号格式导致红测

旧实现返回 `0.8.0 (26102101) Beta`，而新测试期望 `0.8.0-26102101 Beta`：

```text
XCTAssertEqual failed: ("0.8.0 (26102101) Beta") is not equal to ("0.8.0-26102101 Beta")
```

把 `displayVersion` 改为连字符拼接后测试通过。迁移时先写这条失败测试，再改实现。

### 验证实跑消耗序号

真实递增验证会把 `01` 推到 `02`。本次在正式构建前把 pbxproj 回滚到 `8001`；如果不回滚且当天继续正式构建，会从 `02` 开始。回滚时必须限定 pbxproj 且确认 diff 只含版本行。本次正式构建发生在次日，即使不回滚也会按跨日规则重置为 `01`，但不应依赖这一点来掩盖验证消耗。

### 文档残留旧格式

仓库中多处文档仍写 `0.8.0 (8001) Beta`，包括设计规范、产品文档、交接文档和测试注释。版本规则变更后要同步搜索并更新，否则后续代理会照旧格式实现。

## 移植检查

- 把 `FF_PROJECT_DIR`、`FF_XCODEPROJ`、`PBXPROJ` 换成目标工程路径。
- 若版本值在 `xcconfig` 中，改读取与写入位置，不要只改 pbxproj。
- 保留 `--dry-run` 的真正只读语义，并在运行前后校验文件未变。
- 增加 `NN == 99` 的失败保护，避免生成 9 位构建号。
- 增加“当前值必须匹配 `^TODAY[0-9]{2}$`”的严格判断。
- 增加多配置一致性检查：所有 `CURRENT_PROJECT_VERSION` 必须相同。
