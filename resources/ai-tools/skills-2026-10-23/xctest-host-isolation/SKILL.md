---
name: xctest-host-isolation
description: "Run a full macOS XCTest baseline when the repo lives on an external volume or the test host conflicts with a running desktop app: mirror to internal disk, isolate the test-host bundle ID, batch test classes with per-batch timeouts, and aggregate exact results. Use for xcodebuild test hangs, NSFileManager open on /Volumes, single-instance modal risk, or tests that pass individually but hang in a full run. 触发词：全量测试挂起、外置卷、测试宿主、单实例、分批测试。"
---

# XCTest Host Isolation

## 适用边界

用于以下情况：

- `xcodebuild test` 全量运行挂起，源码位于 `/Volumes/...` 等外置卷。
- 单个测试类能通过，但全量运行在某个异步套件处挂起。
- 测试宿主与正在运行的桌面 App 使用同一 Bundle ID，存在单实例/LaunchServices 干扰。
- 需要在不修改原工程、不操作桌面实例的前提下，取得可复核的全量测试证据。

不用于：

- 普通单类/单方法测试，或按 SPEC 做 TDD 切片：用 `xcode-swift-delivery-loop`。
- UserDefaults / 测试 HOME 污染：用 `macos-xctest-isolation`。
- AppKit 拖拽、命中、窗口交互回归：用 `appkit-interaction-regression-testing`。
- 单跑即可复现的产品缺陷：用 `superpowers:systematic-debugging`。

## 安全红线

1. 不结束用户正在使用的桌面 App。只清理 derivedData 下测试宿主的完整可执行路径，按 PID 核对。
2. 不修改原工程。`rsync` 只写入镜像；`project.pbxproj` 的 Bundle ID 只在镜像中改。
3. 不使用 `rsync --delete`，不覆盖镜像中已改的 `project.pbxproj`。
4. 不 commit、不 push。本 Skill 只产出测试证据。
5. 归档日志后再删除镜像；删除前核对路径必须在 `/tmp` 或专用临时目录。

## 核心判断

| 现象 | 判断 | 动作 |
|---|---|---|
| 全量卡住，`sample` 显示 `NSFileManager.contentsOfDirectoryAtURL` → `open`，路径在 `/Volumes` | 外置卷/FileProvider I/O | 镜像到内置盘 |
| 镜像后全量仍在约 200 条后挂起，单类可过 | 跨测试类异步污染 | 按测试类分批 |
| 测试宿主与桌面实例同 Bundle ID，出现单实例提示 | LaunchServices/实例守卫干扰 | 镜像内改宿主 Bundle ID；但这通常不是异步挂起主因 |
| 批次 `status=65`，只跑了少量测试且 `failures=0` | 构建/启动失败 | 标 `COVERAGE incomplete`，查编译错误，不能计入覆盖 |
| 15s `PaneFileOperationChanged` 超时，随后 `isDeleting` 断言失败 | 废纸篓/TCC/测试宿主环境 | 单跑复测，归类环境失败 |
| 30s `BLOCKPREDICATE` 超时 | UI/异步 flaky | 单跑复测，不直接当回归 |

## 流程

### 0. 记录现场

先记录，不要先杀进程：

```bash
APP_PATH="/Applications/Example.app"
pgrep -fl -- "$APP_PATH/Contents/MacOS/"
```

若测试宿主已挂起，先采样主线程：

```bash
TEST_HOST_PID="<derivedData 下测试宿主 PID>"
sample "$TEST_HOST_PID" 2 -file /tmp/xctest-hung-sample.txt
sed -n '1,140p' /tmp/xctest-hung-sample.txt
```

同时记录：

- `SOURCE`：源码根目录
- `PROJECT`：`.xcodeproj` 路径
- `SCHEME`：测试 scheme
- `TESTS_ROOT`：包含 `XCTestCase` 的测试目录
- `MODULE`：测试模块名
- `DERIVED`：内置盘 derivedData
- `MIRROR`：内置盘镜像目录
- `HOST_PATH`：`$DERIVED/Build/Products/Debug/<App>.app/Contents/MacOS/<App>`（测试宿主完整路径）
- 桌面实例的 PID、路径；不要对它执行 kill。

### 1. 镜像到内置盘

```bash
SOURCE="/Volumes/Example/Project"
MIRROR="/tmp/xctest-mirror"
rsync -a \
  --exclude='.git' \
  --exclude='build-beta' \
  --exclude='resources' \
  --exclude='rust-core/target' \
  --exclude='.DS_Store' \
  --exclude='*.xcresult' \
  "$SOURCE/" "$MIRROR/"
test -f "$MIRROR/FlowFinder/FlowFinder.xcodeproj/project.pbxproj"
```

- 排除项按项目调整；不要排除测试目标实际需要的资源。
- 不使用 `--delete`。
- 镜像后测试源码的 `#filePath` 指向镜像，失败堆栈会显示 `/tmp/...`，这是预期行为；报告时注明结果来自镜像。

也可使用：

```bash
scripts/prepare_mirror.sh \
  --source "$SOURCE" \
  --mirror "$MIRROR" \
  --project-rel "FlowFinder/FlowFinder.xcodeproj/project.pbxproj" \
  --app-bundle-id "com.example.app" \
  --isolated-bundle-id "com.example.app.fulltest" \
  --dry-run
```

去掉 `--dry-run` 才会写入。

### 2. 隔离测试宿主 Bundle ID（仅镜像）

只改 app target 的 ID，保留 test bundle 的 `.tests` ID：

```bash
PROJECT_FILE="$MIRROR/FlowFinder/FlowFinder.xcodeproj/project.pbxproj"
cp "$PROJECT_FILE" "$PROJECT_FILE.bak-before-isolation"
sed -i '' \
  's/PRODUCT_BUNDLE_IDENTIFIER = com.example.app;/PRODUCT_BUNDLE_IDENTIFIER = com.example.app.fulltest;/g' \
  "$PROJECT_FILE"
grep -n 'PRODUCT_BUNDLE_IDENTIFIER' "$PROJECT_FILE"
```

- 清理 derivedData 中旧的测试宿主，强制重新构建：
  ```bash
  rm -rf "$DERIVED/Build/Products/Debug/Example.app"
  ```
- 只删除 derivedData 下的产物，不删除源码或镜像。
- 若 App 用 Bundle ID 派生数据目录，先隔离测试 HOME，参考 `macos-xctest-isolation`。
- 这一步是为了排除 LaunchServices/单实例守卫干扰，不要把它当作异步挂起的唯一修复。
- `prepare_mirror.sh` 只用于首次镜像；若镜像里已含隔离后的 Bundle ID，它会拒绝覆盖。后续增量同步不要重跑它。

后续修改代码后，只增量同步源码和测试，保留已改的 `project.pbxproj`：

```bash
rsync -a "$SOURCE/FlowFinder/FlowFinder/" "$MIRROR/FlowFinder/FlowFinder/"
rsync -a "$SOURCE/FlowFinder/Tests/" "$MIRROR/FlowFinder/Tests/"
```

### 3. 按测试类分批运行

先列出类，确认数量：

```bash
grep -RhE '(^|[[:space:]])(final[[:space:]]+)?class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*XCTestCase' \
  "$TESTS_ROOT" \
  | sed -E 's/.*class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
  | sort -u | tee /tmp/xctest-classes.txt
wc -l /tmp/xctest-classes.txt
```

用脚本跑：

```bash
scripts/run_xctest_batches.sh \
  --project "$MIRROR/FlowFinder/FlowFinder.xcodeproj" \
  --scheme "FlowFinderTests" \
  --tests-root "$MIRROR/FlowFinder/Tests/FlowFinderTests" \
  --module "FlowFinderTests" \
  --workdir "$MIRROR" \
  --derived-data "/tmp/ff-xctest-internal" \
  --host-path "/tmp/ff-xctest-internal/Build/Products/Debug/FlowFinder.app/Contents/MacOS/FlowFinder" \
  --batch-size 5 \
  --timeout 150 \
  --log-dir "/tmp/ff-xctest-batches"
```

手动执行一批的等价命令：

```bash
timeout 150 xcodebuild test \
  -project "$MIRROR/FlowFinder/FlowFinder.xcodeproj" \
  -scheme "FlowFinderTests" \
  -destination 'platform=macOS' \
  -derivedDataPath "/tmp/ff-xctest-internal" \
  -only-testing:FlowFinderTests/ClassA \
  -only-testing:FlowFinderTests/ClassB \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  > "/tmp/ff-xctest-batches/batch-01.log" 2>&1
```

- 默认 5 类/批，是启动成本与跨类污染的折中。批次挂起时先减半，定位到具体类。
- 每批后按 `HOST_PATH` 清理残留测试宿主；不要按进程名 `pkill`。
- 不要在首批就跳过“已知 flaky”；先跑全量，拿到完整证据。若必须跳过，在报告中逐项列出。
- macOS 可能没有 `timeout`；脚本会检测 `timeout`/`gtimeout`。缺失时先安装 coreutils，或改用脚本内置的超时替代方案。

### 4. 判定结果

从每批日志末尾读取：

```bash
grep -E "Executed [0-9]+ tests, with [0-9]+ failures?" /tmp/ff-xctest-batches/batch-01.log | tail -1
grep -oE "Test Case '-\[[^]]+\]' failed" /tmp/ff-xctest-batches/batch-01.log | sort -u
```

判定规则：

- **无 `Executed` 行**：`HUNG/NO-SUMMARY`。记录批次和类，清理宿主，缩小批次重跑；不要把它计入覆盖。
- **`status != 0` 且 `failures == 0`，或测试数明显少于批内类数**：`BUILD-OR-SETUP-FAILURE`。查看 `error:` 和编译输出，标 `COVERAGE incomplete`。
- **有 `Test Case ... failed`**：`TEST-FAILURES`。收集唯一失败用例，逐条单跑。
- **`failures=N` 是断言失败数，不是失败测试数**。报告必须同时给出 `failed_tests` 与 `failure_assertions`。
- 单跑仍失败且涉及废纸篓、TCC、目录异步、UI 时间片：标 `ENV/FLAKY`，写清断言和耗时；不要直接修成产品回归。
- 单跑通过、批次失败：标 `ORDER-DEPENDENT/FLAKY`；记录前后批次，不把它算作产品失败。

### 5. 报告与清理

报告模板：

```text
source_root:
mirror:
mirror_synced_at:
project / scheme:
classes: 75  batches: 15  batch_size: 5
full_run: tests=426 failed_tests=1 failure_assertions=2 hung_batches=0 skipped=none
clean_run: tests=428 failed_tests=0 failure_assertions=0 hung_batches=0
skipped: DuplicateScanBrowseRegressionTests, PaneStateDeleteFilterTests/testDeleteIsNonBlocking
status: clean_run is NOT a complete full suite because of skipped targets
env_failures:
order_dependent:
unverified:
logs:
```

- 如果跳过了任何类/方法，必须写明 `skipped`，并说明它是否影响“完整全量”的结论。
- 只有 `COVERAGE complete` 且无失败，才能说“全量通过”；否则写“覆盖不完整”或“有环境失败”。
- 脚本在存在 `--skip` 时输出 `COVERAGE: complete-with-skips` 并以退出码 2 结束；这表示批次完整但全量覆盖不完整，不是“全量通过”。
- 先归档日志，再清理：

```bash
case "$MIRROR" in
  /tmp/*) rm -rf "$MIRROR" ;;
  *) echo "拒绝删除非 /tmp 镜像: $MIRROR" >&2 ;;
esac
```

- 不删除桌面实例、不删除用户数据、不清理用户 `~/Library`。

## 已验证案例（2026-10-22）

FlowFinder 原生 macOS App：

- 75 个测试类，15 批 × 5 类；全量 **426 tests / 2 failure assertions / 0 hung batches**。
- 唯一失败为 `PaneStateDeleteFilterTests.testDeleteIsNonBlocking`：15 秒等不到 `PaneFileOperationChanged`，`isDeleting` 断言失败；单跑仍失败 19.329 秒，归为废纸篓/测试宿主环境。
- 改测试宿主 Bundle ID 后全量仍在约 218/426 处挂起，证明它不是该异步挂起的主因；分批后才通过。
- 一次 **394 tests / 4 failures** 的批次中，`status=65` 且只跑了 4 条，属于构建/启动失败，不能当全量覆盖。
- 后续 clean run **428 tests / 0 failures**，但显式跳过了 `DuplicateScanBrowseRegressionTests` 与 `testDeleteIsNonBlocking`；该口径不等于完整全量。
- 类数会随代码增长；编写本 Skill 时对当前树 dry-run 已得到 **76 个类 / 16 批**。每次执行前以当次类清单为准，不要照抄 75/15。

## 脚本

- `scripts/prepare_mirror.sh`：镜像 + 仅镜像内的 Bundle ID 隔离；支持 `--dry-run`。
- `scripts/run_xctest_batches.sh`：类清单、分批、超时、宿主清理、汇总与覆盖判定；支持 `--dry-run`。
- 两个脚本都只接受绝对路径；先 `--dry-run` 检查命令，再实际执行。

## 与现有 Skill 的边界

- FlowFinder 项目特定的全量 XCTest + `FF_SELFTEST` 自检：`flowfinder-xctest-batch-verification`；本 Skill 只保留可复用的宿主隔离/分批方法。
- 实现切片、TDD 红绿、工程文件登记：`xcode-swift-delivery-loop`。
- UserDefaults / 测试 HOME 隔离：`macos-xctest-isolation`。
- AppKit 拖拽、命中、窗口交互：`appkit-interaction-regression-testing`。
- 单测可复现的产品缺陷：`superpowers:systematic-debugging`。
