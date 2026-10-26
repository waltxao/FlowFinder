---
name: iteration-build-version-stamp
description: "为 macOS/Xcode 项目把每轮迭代构建落实为可验证的版本戳 A.B.C-yymmddxx：定位版本真源、先用 fixture 覆盖同日续号与跨日重置、接入 make build/release/beta 并让每个分发动作恰好递增一次且同一 Make 调用不重复递增、统一显示层、在最终 .app 上核验 CFBundleVersion 并同步台账与 CHANGELOG。用于版本机制落地、Makefile 接线、Beta/Release 版本收口、修复构建号不一致或验证递增时；只查规则定义可用 xcode-dated-build-number。"
---

# Iteration Build Version Stamp

把 `A.B.C-yymmddxx` 从一条命名约定变成每轮迭代都能重复执行、可审计的发布动作。重点不是再解释规则，而是避免三件事：验证消耗序号、Make 目标重复递增、文档写了中间版本。

## 与 xcode-dated-build-number 的分工

- `xcode-dated-build-number`：规则定义、侦察命令、FlowFinder 实测参考。
- 本技能：可移植脚本、fixture 预演、Makefile 接线、最终产物验收与文档收口。
- 两者同时命中时，按本技能的执行顺序推进；规则冲突时以项目当前裁定为准。不要维护两份递增脚本。

## 版本契约

| 字段 | 值 | 约束 |
| --- | --- | --- |
| `MARKETING_VERSION` / `CFBundleShortVersionString` | `A.B.C` | 纯数字点号；不加日期、连字符、括号或 `Beta` |
| `CURRENT_PROJECT_VERSION` / `CFBundleVersion` | `yymmddNN` | 本地日期 6 位 + 当日两位序号；共 8 位 |
| UI 展示 | `A.B.C-yymmddNN Beta` | `Beta` 只属于展示层；Release 可换通道名 |
| 真源 | `project.pbxproj` 或 `xcconfig` | 先定位，不假设；所有配置必须一致 |

## 开始前确认

1. 工程根目录与 `project.pbxproj` 绝对路径。
2. 哪个目标是最终分发产物：`build`、`release`、`beta`、`demo` 或其他。只对该目标收口。
3. 版本是否继承自 `xcconfig`；若是，改继承源，不要只改 pbxproj。
4. 需要同步的文档：需求台账、HANDOVER、CHANGELOG、SPEC/PLAN、设计规范。

## 工作流

### 1. 侦察真源与消费方

```bash
PROJECT_ROOT=/path/to/project
rg -n "MARKETING_VERSION|CURRENT_PROJECT_VERSION" "$PROJECT_ROOT" --glob 'project.pbxproj'
rg -n "MARKETING_VERSION|CURRENT_PROJECT_VERSION" "$PROJECT_ROOT" --glob '*.xcconfig'
rg -n "CFBundleShortVersionString|CFBundleVersion" "$PROJECT_ROOT" --glob 'Info.plist'
rg -n "displayVersion|CFBundleVersion|CFBundleShortVersionString" "$PROJECT_ROOT" --glob '*.{swift,m,mm}'
rg -n "bump|version|VERSION|BUILD" "$PROJECT_ROOT/Makefile" "$PROJECT_ROOT/scripts" 2>/dev/null
```

记录：

- pbxproj 中所有 `CURRENT_PROJECT_VERSION` 的行号与值；必须一致。
- `Info.plist` 是否使用 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`。
- 所有展示位置：侧栏/品牌区、关于页、单实例提示、诊断输出。
- 构建链中是否已有递增逻辑；有则先合并，不要叠加两套。

### 2. 固定基线

```bash
date +%y%m%d
PBXPROJ=/path/to/App.xcodeproj/project.pbxproj
git status --short -- "$PBXPROJ" Makefile scripts
```

- 记录当前 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION`、分支和最终产物目标。
- pbxproj 有未提交改动时先备份或使用副本；不要用无差别 `git checkout` 回滚。
- 多配置值不一致时停止，先查清哪一个是真源。

### 3. 用 fixture 预演，不碰真实工程

真实递增会消耗序号。先在临时副本上覆盖所有分支：

| fixture | 初始值 | 期望 |
| --- | --- | --- |
| 同日续号 | `<today>01` | `<today>02` |
| 跨日 | `<yesterday>03` | `<today>01` |
| 旧格式 | `8001` | `<today>01` |
| 空值 | 空 | `<today>01` |
| 配置不一致 | 两处不同 | 退出 1，不写 |
| 序号上限 | `<today>99` | 退出 1，不写 |
| 非字面量 | `$(FF_BUILD)` | 退出 1，不写 |

运行随附自检一次即可覆盖：

```bash
bash scripts/selftest.sh
```

自检只操作 `mktemp -d` 下的 fixture，不读取也不修改真实工程。

### 4. 对真实文件做只读 dry-run

```bash
BEFORE=$(shasum "$PBXPROJ" | awk '{print $1}')
bash scripts/bump-version.sh --pbxproj "$PBXPROJ" --dry-run
AFTER=$(shasum "$PBXPROJ" | awk '{print $1}')
[[ "$BEFORE" == "$AFTER" ]] || { echo "dry-run 写入了文件"; exit 1; }
```

输出应包含 `OLD_BUILD`、`NEW_BUILD`、`BRANCH`、`COUNT`、`LINES`。`BRANCH` 必须是 `increment`、`reset` 或 `reset-empty`，且与第 3 步的预期一致。

### 5. 接线 Makefile

推荐用统一 `stamp` 前置目标，让一次 Make 调用只递增一次：

```make
PBXPROJ := $(CURDIR)/App/App.xcodeproj/project.pbxproj
BUMP := bash scripts/bump-version.sh --pbxproj "$(PBXPROJ)"

.PHONY: stamp bump-version build release beta demo

stamp:
	@BUILD=$$($(BUMP) --quiet); echo "✓ 构建号 $$BUILD"

bump-version:
	@$(BUMP)

build: stamp
	@xcodebuild ...

release: stamp
	@xcodebuild ...

beta: stamp
	@bash scripts/package-beta.sh

demo: build
```

规则：

- `stamp` 只执行一次；`make build release` 也只递增一次。
- 一次 Make 调用只取一个号；要产出两个需要独立版本号的分发包时，拆成两次调用。
- `demo`、`run` 继承 `build` 时不得再调用递增脚本。
- 不要把 `make bump-version` 与 `make build/release/beta` 叠加执行，那会消耗两个序号。
- 不要把递增脚本放进 `$(shell ...)`：那会在 `make help` 等无关目标时也执行。
- 构建脚本从 pbxproj 读取版本，不要依赖 `stamp` 配方里的局部 shell 变量。
- 构建失败也会消耗序号；接受它，不要为了让第一个产物是 `01` 手工回退。

### 6. 统一显示层

```swift
enum BuildInfo {
    static var marketingVersion: String { /* CFBundleShortVersionString */ }
    static var buildNumber: String { /* CFBundleVersion */ }
    static func displayVersion(marketing: String, build: String, channel: String) -> String {
        channel.isEmpty ? "\(marketing)-\(build)" : "\(marketing)-\(build) \(channel)"
    }
    static var displayVersion: String {
        displayVersion(marketing: marketingVersion, build: buildNumber, channel: "Beta")
    }
}
```

- 先写断言新格式的失败测试，确认旧实现会红；再改实现。
- 覆盖所有展示面：品牌区/侧栏、关于页、单实例提示、诊断信息。
- 不在展示位置手拼字符串，不把 `Beta` 写进 Bundle 字段。

### 7. 递增并构建最终产物

让最终产物目标自己完成递增，不要先手工跑脚本再跑一个也会递增的目标：

```bash
make release   # 或真正产生产物的那个目标（已依赖 stamp）
```

- 从 Make 输出记录 `OLD_BUILD → NEW_BUILD`，或构建后从产物读取。
- 不要在同一轮先 `make build` 再 `make demo`，除非两者都要交付；那会得到两个不同构建号。
- 没有 Makefile 接线的工程，才手工执行一次 `bump-version.sh`，随后使用不重复递增的构建命令。
- 递增后立即确定最终构建号，后续文档只使用它。

### 8. 在最终产物上验收

```bash
APP=/path/to/Final.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"
```

- 短版本必须是纯 `A.B.C`，构建号必须是 `yymmddNN`，且与 Make 输出或脚本输出一致。
- 在**这个** `.app` 上跑自检/冒烟，不用中间构建代替。
- 打开 UI 核对版本行、关于页、单实例提示三处；无法操作 UI 时明确标注未验证。
- 产物是 DMG/ZIP 时，解包后重复上述校验；不要只验 build 目录。

### 9. 文档收口

只写最终产物版本，避免二次修正：

```bash
rg -n '0\.[0-9]+\.[0-9]+ \([0-9]+\)|[0-9]{6}[0-9]{2}' docs CHANGELOG* *.md 2>/dev/null
```

- 台账/HANDOVER 记录最终 `A.B.C-yymmddNN`、产物路径、`CFBundleVersion`、签名结果、自检数字。
- CHANGELOG 只写最终版本；不保留测试递增产生的中间号。
- 同步 SPEC/PLAN/设计规范中的旧格式示例，防止后续代理照旧实现。

## 脚本

`scripts/bump-version.sh`：

```bash
bash scripts/bump-version.sh --pbxproj <path> --dry-run
bash scripts/bump-version.sh --pbxproj <path> --quiet
bash scripts/bump-version.sh --pbxproj <path> --date 261022 --dry-run  # fixture
```

- 只接受 pbxproj 形态的 `CURRENT_PROJECT_VERSION = ...;`；不处理 xcconfig、不构建、不操作 git。
- 所有配置值必须一致；不一致直接失败，不覆盖。
- 非空非数字值（如 `$(FF_BUILD)`）直接失败，避免覆盖变量引用。
- 同日且末两位为数字才递增；其余重置为 `01`。
- 序号超过 `99` 失败，不生成 9 位构建号。
- `--dry-run` 保证零写入；`--quiet` 只输出新构建号，供 Make 捕获。
- 写入后读回校验，并确认 `MARKETING_VERSION` 未被改动；失败时自动恢复原文件。

`scripts/selftest.sh` 用临时 fixture 覆盖续号、跨日、旧值、空值、不一致、99 上限、非字面量、非法日期与未知参数。

## 反模式

| 反模式 | 后果 | 正确做法 |
| --- | --- | --- |
| 在真实 pbxproj 上反复试递增 | 序号被消耗，正式产物从 02 开始 | 先在 fixture 上预演 |
| 手工把 pbxproj 改回旧值 | 与已构建产物、文档不一致 | 接受消耗；必须回退时只改版本行并验证 diff |
| `make build` 后又 `make demo` | 两个构建号，文档只能二选一 | 先确定最终产物，只对它递增 |
| 每个目标都调用一次脚本 | 依赖链重复递增 | 用统一 `stamp` 前置目标 |
| 只改 Debug 或只改 Release | 两个配置版本不一致 | 脚本要求全部一致并全部改写 |
| 把 `Beta` 拼进 `CFBundleVersion` | Bundle 字段不规范 | 只在展示层拼通道名 |
| 在 build 目录验收 | 发布的是另一个产物 | 在最终 `.app`/DMG 上验收 |
| 文档先写中间号 | 需要二次修正 | 等最终产物出来再收口 |

## 验证清单

- [ ] 真源已定位；pbxproj/xcconfig 中所有配置值一致。
- [ ] `MARKETING_VERSION` 为纯 `A.B.C`。
- [ ] fixture 自检通过；真实 dry-run 前后文件 hash 不变。
- [ ] Make 目标每个最终产物只递增一次；`demo`/`run` 不重复递增。
- [ ] 显示层有失败测试保护的连字符格式，三处 UI 全部覆盖。
- [ ] 最终 `.app` 的 `CFBundleShortVersionString` / `CFBundleVersion` 与预期一致。
- [ ] 最终 `.app` 签名校验通过，自检/冒烟在该产物上通过。
- [ ] 台账、HANDOVER、CHANGELOG 只写最终版本；旧括号格式已清除。
- [ ] 没有手工回退序号，或回退 diff 只包含版本行且已重新验证。

## 边界

- 本技能不自动修改 `MARKETING_VERSION`；营销版本由发布负责人决定。
- 本技能不处理 App Store Connect 的 build number 冲突；那只影响上传，不改变本地规则。
- 本技能假设本地时区的 `date`；团队跨时区时先约定统一时区，不要混用 UTC。
- 若版本来自 xcconfig，先改读取/写入位置，再复用本流程；不要强行套 pbxproj 脚本。
