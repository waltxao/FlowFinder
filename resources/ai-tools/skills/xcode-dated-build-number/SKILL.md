---
name: xcode-dated-build-number
description: "维护 Xcode 项目的内部构建号 A.B.C-yymmddxx：MARKETING_VERSION 保持纯 x.y.z，CFBundleVersion 使用 yymmddNN，同日递增、跨日或旧值重置为 01，并让 make build/release/beta 各递增一次、UI 用连字符显示。用于更新构建号、准备 Beta/Release、修复版本显示或校验 dry-run 时。"
---

# Xcode Dated Build Number

## 核心规则

- `MARKETING_VERSION` / `CFBundleShortVersionString` 只能是纯 `A.B.C`。不得写入日期、连字符、括号或 `Beta` 后缀。
- `CURRENT_PROJECT_VERSION` / `CFBundleVersion` 存 `yymmddNN`：`yymmdd` 为本地日期，`NN` 为当日两位序号。
- 同日已有有效值 `yymmddNN` → `NN + 1`；跨日、旧格式（如 `8001`）、空值 → `01`。
- 展示层由两个 Bundle 值拼成 `A.B.C-yymmddNN Beta`，例如 `0.8.0-26102201 Beta`。必须用连字符，不用括号。
- 历史格式 `0.8.0 (8001) Beta` 属于旧规则；迁移时同步修改 UI、测试和文档，不要保留两套格式。

## 工作流

### 1. 侦察版本链路

先定位唯一真源和所有消费方，不要假设路径：

```bash
PROJECT_ROOT=/path/to/project
rg -n "MARKETING_VERSION|CURRENT_PROJECT_VERSION" "$PROJECT_ROOT" --glob 'project.pbxproj'
rg -n "CFBundleShortVersionString|CFBundleVersion" "$PROJECT_ROOT" --glob 'Info.plist'
rg -n "displayVersion|CFBundleVersion|CFBundleShortVersionString" "$PROJECT_ROOT" --glob '*.{swift,m,mm}'
rg -n "bump|VERSION|BUILD" "$PROJECT_ROOT/Makefile" "$PROJECT_ROOT/scripts" 2>/dev/null
```

确认：

- `Info.plist` 可能在 `Resources/` 下，不在工程根目录。
- 工程是否用 `xcconfig` 继承版本；若在 `xcconfig`，改那里，不要只改 pbxproj。
- Debug/Release 等所有配置的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION` 是否一致。
- 哪些 Make 目标、打包脚本、UI 位置消费版本号。

### 2. 记录基线并保护工作区

1. 记录当前营销版本、构建号和本地日期：

   ```bash
   date +%y%m%d
   ```

2. 设置目标文件变量并查看是否有未提交改动：

   ```bash
   PBXPROJ="$PROJECT_ROOT/path/to/App.xcodeproj/project.pbxproj"
   INFO_PLIST="$PROJECT_ROOT/path/to/Resources/Info.plist"
   MAKEFILE="$PROJECT_ROOT/Makefile"
   git status --short -- "$PBXPROJ" "$INFO_PLIST" "$MAKEFILE"
   ```

3. 若 pbxproj 有与版本无关的脏改动，先备份该文件或改用临时副本。禁止用无差别的 `git checkout` 回滚。

4. 若多个配置的当前构建号不一致，停止并先解决差异；不要用一个值覆盖全部配置。

### 3. 计算并真 dry-run

计算规则：

```text
TODAY = date +%y%m%d
if current =~ ^TODAY[0-9]{2}$:
    next = current suffix + 1
else:
    next = 01
```

要求：

- dry-run 只打印，不写文件。
- 运行前后用 `shasum` 或 `git diff --exit-code -- "$PBXPROJ"` 证明文件未变。
- 预览必须同时显示旧值、新值和完整展示串。

若现有脚本的“dry-run”实际会写入，先修复为只读预演；不能修复时，把它当作实跑并在正式构建前回滚。

### 4. 接入构建命令

- 暴露独立的 `bump-version` 目标。
- `build`、`release`、`beta` 各调用一次递增；`demo`、`run` 若继承 `build`，不得再次递增。
- 不要同时执行 `make bump-version` 和 `make build/release/beta`，否则会消耗两个序号。
- 打包脚本从同一真源读取版本，并通过构建设置传入，例如：

  ```bash
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" xcodebuild ...
  ```

- 在脚本中硬编码版本号视为错误。

### 5. 修改显示层

- 从 Bundle 读取值再拼接，不硬编码：

  ```swift
  "\(marketingVersion)-\(buildNumber) \(channel)"
  ```

- 覆盖所有展示位置：侧栏/品牌区、关于页、单实例提示、诊断信息。
- 增加或更新断言，至少覆盖：

  ```swift
  XCTAssertEqual(displayVersion(marketing: "0.8.0", build: "26102101", channel: "Beta"),
                 "0.8.0-26102101 Beta")
  ```

- 先运行该测试确认旧格式会失败，再改显示实现；这能防止括号格式回潮。

### 6. 正式构建前清理验证消耗

任何“真实递增”验证都会消耗序号。正式构建前：

1. 只把构建号相关行恢复到基线，保留其他改动。
2. 用 `git diff -- "$PBXPROJ"` 确认差异只包含版本字段。
3. 重新读取当前构建号，确认已回到基线。
4. 无法确认差异性质时停止并询问，不要猜测回滚。

### 7. 构建并核验产物

```bash
XCODEPROJ="$PROJECT_ROOT/path/to/App.xcodeproj"
SCHEME=YourScheme
xcodebuild -project "$XCODEPROJ" -scheme "$SCHEME" \
  -configuration Release -showBuildSettings \
  | rg "MARKETING_VERSION|CURRENT_PROJECT_VERSION"
```

构建后读取产物 Info.plist：

```bash
APP="/path/to/Built.app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist"
```

期望：短版本为 `A.B.C`，构建号为 `yymmddNN`，UI 展示为 `A.B.C-yymmddNN Beta`。无法实际打开 UI 时，明确报告 UI 未验证，不要用单测替代真机结论。

## 边界与陷阱

- 序号到 `99` 时不要静默输出三位数；报错并要求人工决定扩展格式。
- 只把“今天日期 + 两位数字”视为可递增旧值；其余一律重置为 `01`。
- 日期统一用本地时区的 `date +%y%m%d`，团队约定时区后不要混用 UTC。
- 不自动递增 `MARKETING_VERSION`；本流程只维护内部构建号和展示格式。
- 新增构建步骤时检查是否重复递增：Make 依赖链、脚本内部调用、CI 命令都可能各加一次。
- 构建号变更后，旧产物、桌面副本、DMG/ZIP 中的版本可能仍是旧值；需要重新打包或覆盖，并分别核验。

## 验证清单

- [ ] `MARKETING_VERSION` 为纯 `A.B.C`，所有配置一致。
- [ ] `CURRENT_PROJECT_VERSION` 为 8 位 `yymmddNN`，所有配置一致。
- [ ] dry-run 未修改文件。
- [ ] `build`/`release`/`beta` 各只递增一次。
- [ ] 显示格式使用连字符，测试断言覆盖。
- [ ] 正式产物 Info.plist 与 UI 展示一致。
- [ ] 验证消耗的序号已回滚或已明确说明最终序号。
- [ ] `git diff` 只包含预期的版本字段与代码改动。

## 参考实现

FlowFinder 的已实测实现、命令输出与踩坑记录见 [references/flowfinder-reference.md](references/flowfinder-reference.md)。移植时先按上述工作流侦察，再参考其代码，不要直接复制项目专属路径。
