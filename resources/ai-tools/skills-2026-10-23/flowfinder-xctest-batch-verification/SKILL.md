---
name: flowfinder-xctest-batch-verification
description: "FlowFinder macOS XCTest 取证：全量串跑挂起、工程位于外置卷、测试宿主同 Bundle ID 或单实例提示时，使用 /tmp 内置盘镜像、镜像内独立 Bundle ID、按测试类分批与严格汇总；同样覆盖单类/单方法聚焦跑与 TDD 红绿取证（复用镜像 + 增量同步 + 镜像内临时回改，源工程零改动），并给出测试宿主 NSWindow/XCTMemoryChecker 崩溃签名与过期契约断言的分类口径，再以隔离环境启动 FF_SELFTEST。Use when asked to run FlowFinder full or focused tests, xcodebuild test hangs, the test host shows a single-instance prompt, testHardcodedTokenBudget stalls on /Volumes, a single test class needs red/green proof, the test host crashes, or the self-test window does not appear. 触发词：全量测试、聚焦跑、单类红绿、XCTest 挂起、外置卷、测试宿主、单实例、分批、428/434/435、崩溃取证、过期契约、FF_SELFTEST。"
---

# FlowFinder XCTest 镜像化验证：分批全量 + 聚焦红绿

## 目标与边界

用于在不修改源工程、不关闭用户桌面实例的前提下，取得可复核的 FlowFinder XCTest 证据——既包括分批全量覆盖，也包括单类、单方法的聚焦跑与红绿取证。

适用：

- `xcodebuild test` 全量串跑挂起，单类可以通过。
- 工程位于 `/Volumes/...` 外置卷，`testHardcodedTokenBudget` 卡在目录 `open`。
- 测试宿主与桌面副本同 Bundle ID，出现单实例提示或 LaunchServices 干扰。
- 单个测试类或单个方法的 TDD 红绿：在已隔离的镜像内跑聚焦测试（见「聚焦跑与红绿取证」），前提是源工程零改动。
- 需要同时验证 XCTest 与 `FF_SELFTEST=1` 应用内自检。

不适用：

- UI/UX 截图验收：使用对应的 macOS UI 审计 Skill。
- 可稳定复现的产品缺陷定位：先走系统化调试，再回到本流程做全量回归。

## 安全红线

1. 只读源工程。镜像写入 `/tmp`，不在源工程或桌面副本上改 `project.pbxproj`、Bundle ID 或测试配置。
2. 不运行 `make swift-test`。该目标包含 `pkill -f "MacOS/FlowFinder"`，会结束用户正在使用的桌面实例。
3. 只结束 derivedData 中完整路径匹配的测试宿主；禁止按进程名批量 `pkill`。
4. 不 commit、不 push。本 Skill 只产出测试证据。
5. 不用 `rsync --delete`。整树同步必然带回源工程的裸 App Bundle ID、覆盖镜像里的隔离结果，所以同步后立刻重新 `sed` 隔离并断言（`sync_mirror.sh` 已把这两步绑在一起）；只同步源码/测试目录则不动 `project.pbxproj`，隔离自然保留。
6. 先验证，后修复。定向测试通过、部分批次通过、进程已启动都不等于全量通过。
7. 有跳过、挂起、构建失败或未执行自检时，报告必须标为覆盖不完整或 Blocked。
8. 一份镜像同时只有一个持有者。动手前查 `pgrep -fl "ff-fix-mirror|flowfinder-xctest"` 并确认没有别的会话正在用同一镜像或 `/tmp/flowfinder-xctest-derived`；否则两次运行的构建产物和 xcresult 会互相覆盖，证据无法归因。
9. 聚焦取证只改镜像：源工程保持零改动，任何「临时回改出红」都必须在镜像内完成并当场还原。

## 已核实的失败模型

| 现象 | 判定 | 动作 |
|---|---|---|
| 全量卡在 `NSFileManager.contentsOfDirectoryAtURL` → `open`，路径在 `/Volumes` | 外置卷 I/O | 镜像到 `/tmp` 后复测 |
| 测试宿主与桌面 App 同 Bundle ID，出现单实例提示或模态框 | LaunchServices 实例守卫 | 只在镜像内给 App target 换独立 Bundle ID |
| 改独立 Bundle ID 后全量仍在约 200 条后挂起，单类可过 | 跨测试类异步污染 | 按测试类分批，串行执行 |
| 批次 `status=65`、只跑少量测试、没有完整汇总 | 构建或启动失败 | 标 `COVERAGE incomplete`，查 `error:`，不能计入通过 |
| `DuplicateScanBrowseRegressionTests` 串跑超时、单跑通过 | 既有跨套件环境问题 | 单跑复测并记录，不直接记产品回归 |
| `PaneStateDeleteFilterTests/testDeleteIsNonBlocking` 等不到删除通知 | 测试宿主废纸篓/TCC 环境 | 单跑复测；仍失败则标 `ENV/FLAKY` |
| 聚焦跑 `exit=65` 但日志里没有任何 `Executed N tests` 行，且有 `Testing cancelled because the build failed` | 编译失败，不是测试失败 | 标 `BUILD-OR-SETUP-FAILURE`，`grep -n ' error:'` 取前若干条；不计入通过，也不写成产品回归 |
| 批次没有汇总行、宿主进程消失，`~/Library/Logs/DiagnosticReports/FlowFinder-*.ips` 里主线程栈为 `objc_release` → `objc_autoreleasePoolPop` → `-[XCTMemoryChecker _assertInvalidObjectsDeallocatedAfterScope:]`，`exception.type=EXC_BAD_ACCESS` | 测试里创建真实 `NSWindow` 触发 XCTest 内存校验，把测试宿主直接挂掉 | 标 `ENV/HARNESS`，不得记产品失败；改用裸容器承载视图（`let container = NSView(frame:)` + `container.layoutSubtreeIfNeeded()`），只有被测对象自己开窗口时才用 `NSWindow` |
| 单条断言失败，且断言的正是被新规格推翻的旧口径（例：`XCTAssertTrue(scrollView.hasVerticalScroller)` 对上「信息区不得靠内部滚动条兜底」） | 过期契约断言：测试口径落后于规格，不是产品回归 | 先核对该行为的最新批准口径；确认是新口径就改断言并同步更名测试，只复跑受影响批次，总数按本次实测重报；不得为凑旧总数而回退产品实现 |
| 自检进程存在但没有窗口、没有 `/tmp/ff-debug.log` 完成行 | 启动或环境阻塞 | 检查 Bundle 身份和权限门；记为 Blocked |

工程口径每次都要重新测量，不得沿用历史数字：2026-10-22 记录为 76 类 / 434 条，2026-10-23 重新测量为 79 个 `XCTestCase` 类、458 处 `func test…` 声明，上一轮审计的 `Executed` 汇总口径为 435 条 / 16 批。声明数、类内计数和 xcodebuild 实际 `Executed` 数三者不等价，报告只写本次实测值。

```bash
TESTS_ROOT="$SOURCE/FlowFinder/Tests/FlowFinderTests"
grep -RhE '(^|[[:space:]])(final[[:space:]]+)?class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*XCTestCase' \
  "$TESTS_ROOT" | sed -E 's/.*class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/' | sort -u | wc -l
grep -RhE '^[[:space:]]*(final[[:space:]]+)?func[[:space:]]+test[A-Za-z0-9_]*\(' "$TESTS_ROOT" | wc -l
```

## 流程

### 0. 记录现场

```bash
SOURCE="/Volumes/Iris-Data/文件管理系统/flowfinder-native"
MIRROR="/tmp/flowfinder-xctest-mirror-$(date +%Y%m%d%H%M%S)"
DERIVED="/tmp/flowfinder-xctest-derived"
LOG_DIR="/tmp/flowfinder-xctest-batches"
TEST_HOME="/tmp/flowfinder-test-home"

git -C "$SOURCE" rev-parse --short HEAD
git -C "$SOURCE" status --short | wc -l
pgrep -fl "FlowFinder.app/Contents/MacOS/FlowFinder" || true
pgrep -fl "${MIRROR##*/}|flowfinder-xctest-derived" || true
ls -d /tmp/flowfinder-xctest-mirror-* /tmp/ff-fix-mirror 2>/dev/null || true
```

记录桌面实例 PID 和路径，不要结束它。记录源工程 HEAD、未提交文件数、scheme 和测试数量。最后两条确认没有另一个会话正持有同一镜像或 derivedData（安全红线 8）；若有，先与用户确认归属，不要共用。

### 1. 镜像到内置盘

```bash
mkdir -p "$MIRROR"
rsync -a \
  --exclude='.git' \
  --exclude='build-beta' \
  --exclude='rust-core/target' \
  --exclude='.DS_Store' \
  --exclude='*.xcresult' \
  "$SOURCE/" "$MIRROR/"

test -f "$MIRROR/FlowFinder/FlowFinder.xcodeproj/project.pbxproj"
test -d "$MIRROR/FlowFinder/Tests/FlowFinderTests"
```

不要加 `--delete`。镜像要包含未提交的源码、测试和 `FlowFinder/Libraries` 下的库；否则测到的不是当前工作区。

步骤 1 和 2 可以一次用脚本做完（建镜像或复用已有镜像、同步、重新隔离并断言）：

```bash
bash /Users/waltxao/.qoder/skills/flowfinder-xctest-batch-verification/scripts/sync_mirror.sh \
  --mirror "$MIRROR" --dry-run
bash /Users/waltxao/.qoder/skills/flowfinder-xctest-batch-verification/scripts/sync_mirror.sh \
  --mirror "$MIRROR"
```

### 2. 只在镜像内隔离测试宿主

```bash
PROJECT_FILE="$MIRROR/FlowFinder/FlowFinder.xcodeproj/project.pbxproj"
cp "$PROJECT_FILE" "$PROJECT_FILE.bak-before-isolation"
sed -i '' \
  's/PRODUCT_BUNDLE_IDENTIFIER = com\.flowfinder\.native;/PRODUCT_BUNDLE_IDENTIFIER = com.flowfinder.native.fulltest;/g' \
  "$PROJECT_FILE"

! grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.flowfinder.native;' "$PROJECT_FILE"
grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.flowfinder.native.tests;' "$PROJECT_FILE"
grep -c 'PRODUCT_BUNDLE_IDENTIFIER = com.flowfinder.native.fulltest;' "$PROJECT_FILE"
```

App target 原 ID 是 `com.flowfinder.native`，测试 bundle 原 ID 是 `com.flowfinder.native.tests`。只替换 App target 的两个配置，保留测试 bundle 的 `.tests` ID。

清理旧的测试宿主产物，强制重新构建：

```bash
rm -rf "$DERIVED/Build/Products/Debug/FlowFinder.app"
```

复用同一镜像再同步有两种做法，二选一，别混用后忘记断言：

只同步源码和测试（不碰 `project.pbxproj`，隔离状态自然保留）：

```bash
rsync -a "$SOURCE/FlowFinder/FlowFinder/" "$MIRROR/FlowFinder/FlowFinder/"
rsync -a "$SOURCE/FlowFinder/Tests/" "$MIRROR/FlowFinder/Tests/"
```

整树同步（源码里新增了文件、改了版本号或 target 配置时，必须让 `project.pbxproj` 也进镜像）：同步会带来源工程的裸 Bundle ID，所以紧接着重跑上面的 `sed` 隔离，再执行 `sync_mirror.sh --check-only` 或手工断言裸 ID 已消失、`.tests` ID 仍在。

### 3. 分批执行

```bash
mkdir -p "$TEST_HOME/Desktop" "$TEST_HOME/Documents" "$LOG_DIR"
```

`$TEST_HOME` 不是可选清理项：`FlowFinderTests.xcscheme` 的 TestAction 把 `CFFIXED_USER_HOME=/tmp/flowfinder-test-home`（连同 `FF_SKIP_SIDEBAR_ICONS=1`、`FF_TESTING=1`）注入测试宿主，用来避免宿主扫描真实的 `~/Desktop`/`~/Documents`（iCloud 元数据读取会把 XCTest 挂住）。`/tmp` 重启即清空，目录缺失时宿主会退回真实 HOME，因此每次跑之前都要重建。走 `-scheme FlowFinderTests` 时这些变量由 scheme 提供；若绕过 scheme（`-target`、手工启动产物）则必须在命令里显式补上 `CFFIXED_USER_HOME` 与 `HOME`。

```bash
bash /Users/waltxao/.qoder/skills/flowfinder-xctest-batch-verification/scripts/run_batched_xctest.sh \
  --mirror "$MIRROR" \
  --batch-size 5 \
  --timeout 150 \
  --log-dir "$LOG_DIR" \
  --dry-run
```

确认类数、批数和命令后去掉 `--dry-run`。脚本固定使用：

- project：`FlowFinder/FlowFinder.xcodeproj`
- scheme：`FlowFinderTests`
- tests root：`FlowFinder/Tests/FlowFinderTests`
- module：`FlowFinderTests`
- derivedData：`/tmp/flowfinder-xctest-derived`

批数按本次实测类数除以 `--batch-size` 向上取整（76 类是 16 批 × 5，79 类是 16 批）。每批串行，超时后只清理该测试宿主。

### 4. 判定批次

每批以三项共同判定：

1. xcodebuild 退出码。
2. 最终 `Executed N tests, with M failures` 汇总行。
3. `** TEST SUCCEEDED **` 或 `** TEST FAILED **` 标记。

规则：

- 无汇总行：`TIMEOUT/NO-SUMMARY`，覆盖不完整。
- 有失败用例：`TEST-FAILURES`。`failures` 是断言失败数，不是失败测试数，报告要分开写。
- `status != 0` 且没有失败用例：`BUILD-OR-SETUP-FAILURE`，查编译或启动错误。
- `status = 0` 但测试数为 0 或没有成功标记：`INCOMPLETE`。
- 只有全部批次都有完整汇总且无失败，才能说“分批全量通过”。

### 5. 已知环境用例单跑

先跑全量。若 `DuplicateScanBrowseRegressionTests` 让批次挂起，单跑该类：

```bash
timeout 300 xcodebuild test \
  -project "$MIRROR/FlowFinder/FlowFinder.xcodeproj" \
  -scheme FlowFinderTests \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -only-testing:FlowFinderTests/DuplicateScanBrowseRegressionTests \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

单跑通过则记为 `ENV/ORDER-DEPENDENT`，不要写成产品失败；单跑仍失败则收集断言和耗时。

`testDeleteIsNonBlocking` 也单独复测。若仍是废纸篓/TCC 超时，记为 `ENV/FLAKY`，不冒充通过。

需要得到排除已知环境项后的干净覆盖时：

```bash
bash /Users/waltxao/.qoder/skills/flowfinder-xctest-batch-verification/scripts/run_batched_xctest.sh \
  --mirror "$MIRROR" \
  --batch-size 5 \
  --timeout 150 \
  --log-dir "$LOG_DIR/clean" \
  --skip DuplicateScanBrowseRegressionTests \
  --skip PaneStateDeleteFilterTests/testDeleteIsNonBlocking
```

这次结果必须报告为 `COVERAGE: complete-with-skips`，不能说成 434 条全量通过。

### 6. 应用内自检

自检走 Debug 可执行文件，不依赖 XCTest。使用镜像构建出的 App：

```bash
SELFTEST_APP="$DERIVED/Build/Products/Debug/FlowFinder.app"
SELFTEST_BIN="$SELFTEST_APP/Contents/MacOS/FlowFinder"
SELFTEST_LOG="/tmp/ff-debug.log"

rm -f "$SELFTEST_LOG"
env -u __CFBundleIdentifier \
  FF_SKIP_PERMISSION_GATE=1 \
  FF_SELFTEST=1 \
  "$SELFTEST_BIN" > /tmp/ff-selftest.stdout 2>&1 &
SELFTEST_PID=$!
```

等待最后一条汇总，而不是固定 sleep：

```bash
for _ in $(seq 1 60); do
  grep -q '\[LAYOUT\] 布局压力自检 20轮' "$SELFTEST_LOG" 2>/dev/null && break
  kill -0 "$SELFTEST_PID" 2>/dev/null || break
  sleep 1
done

grep -c 'FAIL' "$SELFTEST_LOG" || true
grep -E '\[(SELFTEST|POLICY|REGION|BEHAVIOR|WELD|AVOID|WIDTH|SHELL|LAYOUT)\]' "$SELFTEST_LOG" | tail -20
```

- 完成条件是最后一条 `[LAYOUT] 布局压力自检 20轮 失败0`，且日志没有 `FAIL`。
- 2026-10-22 的已验证自检基线是 163 项 + 20 轮布局压力；数量会变化，以本次日志为准。
- 26102226/27 曾出现自检宿主窗口未创建，属于环境阻塞，不得记通过。
- 若直接启动无窗口，可尝试 LaunchServices：

```bash
open -n --env FF_SKIP_PERMISSION_GATE=1 --env FF_SELFTEST=1 "$SELFTEST_APP"
```

仍无窗口或日志时，标记 `SELF-TEST: Blocked`，并记录进程、窗口和权限门证据。结束后只按精确二进制路径结束本次启动的 PID。

`FF_SKIP_PERMISSION_GATE=1` 只跳过 FlowFinder 自己的权限门，不绕过系统 TCC。`env -u __CFBundleIdentifier` 用来去掉 Qoder shell 透传的 `com.qoder.app` 身份，避免自检进程解析成错误 Bundle。

### 7. 汇报与清理

先归档日志，再清理镜像：

```bash
case "$MIRROR" in
  /tmp/*|/private/tmp/*) rm -rf "$MIRROR" ;;
  *) echo "拒绝删除非 /tmp 镜像: $MIRROR" >&2 ;;
esac
```

不要删除桌面实例、用户数据或源工程。清理后核对桌面实例仍在运行，并确认源工程没有新增修改。

如果同一会话后面还要做聚焦红绿或回归复跑，先保留镜像和 derivedData，只在交付证据归档后才删。

## 聚焦跑（单类/单方法）与红绿取证

全量分批之外，改动过程中的每一步还需要「一条测试先红、改完变绿」的取证。同样在镜像里做，源工程保持零改动。

### 复用镜像，只做增量同步

```bash
MIRROR="/tmp/ff-fix-mirror"     # 固定名，跨轮次复用；首轮不存在时由脚本创建
bash /Users/waltxao/.qoder/skills/flowfinder-xctest-batch-verification/scripts/sync_mirror.sh \
  --mirror "$MIRROR"
bash /Users/waltxao/.qoder/skills/flowfinder-xctest-batch-verification/scripts/sync_mirror.sh \
  --mirror "$MIRROR" --check-only
```

聚焦跑比重批跑快得多，但每次改完源码或测试都要重新同步，否则测的是上一轮的镜像内容。

### 聚焦命令

```bash
mkdir -p /tmp/flowfinder-test-home/Desktop /tmp/flowfinder-test-home/Documents
FIX="/tmp/ff-fix-mirror/FlowFinder/Tests/FlowFinderTests"

timeout 300 xcodebuild test \
  -project "$MIRROR/FlowFinder/FlowFinder.xcodeproj" \
  -scheme FlowFinderTests \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -only-testing:FlowFinderTests/FFLocalizationTests \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO > /tmp/ff-focus.log 2>&1
echo "exit=$?"
grep -E 'Executed [0-9]+ tests, with [0-9]+ failures?' /tmp/ff-focus.log | tail -1
grep -E "^.*error: -\[" /tmp/ff-focus.log | head -20
```

- 单方法用 `-only-testing:FlowFinderTests/<Class>/<testMethod>`。
- 走 `-scheme`，`CFFIXED_USER_HOME` 等测试宿主环境由 scheme 提供；`/tmp` 重启后 test-home 目录要先重建。
- `exit=65` 有两种含义：日志里有 `Executed N tests, with M failures` 是真失败；没有 `Executed` 行而有 `Testing cancelled because the build failed` 是编译失败，先修编译再谈红绿。

### 红绿取证

先确认红。如果失败是本轮新写的测试自然产生的，直接跑、留档即可。

若产品代码已经改好、需要证明「测试确实能抓到这个缺陷」，用镜像内临时回改（待复验口径：以下做法来自本次运行时扩展，尚未在后续会话中独立复现，第一次执行时逐条核对退出码和实测串再固化）：

```bash
TARGET=FFLocalizationTests
focus() {
  timeout 300 xcodebuild test \
    -project "$MIRROR/FlowFinder/FlowFinder.xcodeproj" \
    -scheme FlowFinderTests \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    -only-testing:FlowFinderTests/$TARGET \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO > "$1" 2>&1
  local status=$?
  echo "$(basename "$1") exit=$status"
  grep -E 'Executed [0-9]+ tests, with [0-9]+ failures?' "$1" | tail -1
}

PROD="$MIRROR/FlowFinder/FlowFinder/FileInfoWindowController.swift"
cp "$PROD" /tmp/ff-fixed-copy.swift      # 先存住修复版本
# 只改镜像：把修复点写回改造前的旧实现（编辑范围越小越好，改动记录在案）
focus /tmp/ff-red.log                   # 期望 exit=65 + 明确的断言失败列表
cp /tmp/ff-fixed-copy.swift "$PROD"      # 还原修复
diff -q /tmp/ff-fixed-copy.swift "$PROD" && echo "mirror restored"
focus /tmp/ff-green.log                 # 期望 exit=0 + 0 failures
```

红绿都成立后必须验三件事：

1. 红阶段的失败断言与预期缺陷一一对应，实测串可核对（例：`("861 bytes") is not equal to ("861 字节")`、`实测 Zero bytes`、`实测 ["en"]`），不是编译错误或环境问题冒充红。
2. 绿阶段 `Executed N tests, with 0 failures` 且 `** TEST SUCCEEDED **`，N 与本次实测口径一致。
3. 源工程零改动：`git -C "$SOURCE" status --short | wc -l` 与步骤 0 记录的条数一致，且临时回改只存在于镜像（`diff -q /tmp/ff-fixed-copy.swift "$PROD"` 通过）。

失败一条就补一条，不要在红还没成立时先改产品代码；也不要为了凑绿而放宽断言。

## 2026-10-25 补充

- **单测 ≠ 全量基线**：只跑单个回归时，报告必须写「single passed, full suite not rerun」，不得把单测数字并入 XCTest 总数；台账/交接的全量基线保持上一次全套实测值。
- **修饰符残留**：用 `CGEvent` 发 ⌘A/⌘ 组合后，若 keyUp 丢失会残留 Command，后续键入变成快捷键（曾误开任务中心）。收尾发 keyUp 55/54，并用 AX 读回 `AXTextField` 值确认输入真的发生。
- **不要跑 `make swift-test`**：在真机验证会话里它会先结束正在运行的 FlowFinder；改用镜像 + `xcodebuild build-for-testing` / `test-without-building -only-testing` 做聚焦验证。
- **双栏搜索**：验证「双栏」范围时，两侧输入同步且各自过滤；「本栏」时两栏解耦。先设范围再输入，并用 AX 行数取证。

## 报告模板

```text
source_root:
source_head:
source_dirty_files_before / after:
desktop_instance:
mirror_holder_session:
mirror:
app_bundle_id / test_bundle_id:
test_home_present:
classes=本次实测  batches=本次实算  batch_size: 5
full_run: tests=... passed=... failed_tests=... failure_assertions=... hung=... build_failures=...
known_env: DuplicateScanBrowseRegressionTests / PaneStateDeleteFilterTests.testDeleteIsNonBlocking
clean_run: tests=... failed_tests=... skipped=...
focused_runs: Class(/method) red=exit/tests/failures -> green=exit/tests/failures  mirror_revert_restored=yes/no
failures_classified: product / env-harness / stale-contract（每条注明判定依据；stale-contract 要写改断言+更名+只复跑哪一批）
crash_reports: ~/Library/Logs/DiagnosticReports/FlowFinder-*.ips 命中/未命中（命中写 exception.type 与 faultingThread 关键帧）
self_test: items=本次实测 layout_rounds=20 failures=... / Blocked
coverage: complete / complete-with-skips / incomplete
unverified:
logs:
```

## 完成前检查

- [ ] 目标测试来自 `/tmp` 镜像，不是外置卷源工程。
- [ ] 该镜像与 derivedData 只由本会话持有，未被另一个运行中的会话共用。
- [ ] 源工程和桌面实例均未修改或终止。
- [ ] 镜像内 App Bundle ID 已隔离，测试 bundle 的 `.tests` ID 未变。
- [ ] `/tmp/flowfinder-test-home/Desktop` 与 `Documents` 已重建，测试宿主未退回真实 HOME。
- [ ] 每个批次都有退出码、汇总行和日志。
- [ ] 聚焦跑的每一次红/绿都留了日志，红阶段的失败断言与缺陷可对应；若做了镜像内临时回改，副本已还原并 `diff -q` 通过。
- [ ] 失败用例已单跑复核，环境问题与产品失败分开；`exit=65` 已区分编译失败与断言失败。
- [ ] 批次无汇总行且宿主消失时，已查 `~/Library/Logs/DiagnosticReports/*.ips` 定性崩溃，而不是直接记产品回归。
- [ ] 判定为过期契约断言的，已核对最新批准规格口径，只复跑受影响批次，总数按实测重报。
- [ ] 自检出现完成行且无 `FAIL`；否则明确写 Blocked。
- [ ] 报告写明 tests 总数、失败断言数、失败测试数、跳过项和覆盖结论，数字全部来自本次实测。
- [ ] 未 commit、未 push。

## Resources

- `scripts/sync_mirror.sh`：建镜像或复用镜像、增量同步、重新隔离 App Bundle ID 并断言，同时补齐 `/tmp/flowfinder-test-home`；`--dry-run` 只看命令，`--check-only` 只验隔离。
- `scripts/run_batched_xctest.sh`：按测试类分批串行执行，逐批给出退出码、`Executed` 汇总、失败断言数与 `COVERAGE` 结论。
