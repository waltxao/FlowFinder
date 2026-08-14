# package.sh 基线 — 签名校验与产物状态 (task-1, Wave1 T1)

状态结论: **`package.sh` 中 codesign 校验失败仅 log_warn, 不阻断打包流程**;
`dist/` 现有产物均为 v0.7.3 (与脚本声明的 VERSION 0.7.4 不一致)。
采集日期 2026-08-13。

## 1. codesign 校验失败的容错行为 (源码证据)

`scripts/package.sh:225-240` ([3/4] 代码签名):

```bash
if [ -n "$DEVELOPER_ID" ]; then
    codesign --sign "$DEVELOPER_ID" --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS_PATH" "$APP_PATH"
else
    codesign --sign - --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS_PATH" "$APP_PATH"
fi

log_info "验证签名..."
if codesign --verify --verbose=2 "$APP_PATH" 2>&1 | tail -5; then
    log_success "签名验证通过"
else
    log_warn "签名验证返回非零状态（可能仍可本地运行）"
fi
```

关键点:

- 脚本头部 `set -euo pipefail` (第 2 行), 但 **`if` 条件中的命令不受 errexit 约束** —
  校验失败走 `else` 分支, 仅打印 `[WARN]`, 随后无条件进入 [4/4] 创建 DMG。
- 校验失败没有 `die`, 没有提前退出; 打包继续。
- `codesign --sign` 本身的失败(而非 `--verify`)则会因 `set -e` 中止 — 基线问题只在校验环节。

行为验证 (镜像脚本的 if+pipefail 结构):

```bash
$ set -euo pipefail; if codesign --verify /nonexistent/path 2>&1 | tail -1; then echo "BRANCH: success"; else echo "BRANCH: warn-only, script continues"; fi; echo "AFTER_IF: still running (set -e did not abort)"
/nonexistent/path: No such file or directory
BRANCH: warn-only, script continues
AFTER_IF: still running (set -e did not abort)
```

## 2. 当前产物状态 (dist/)

```bash
$ ls -la dist/
total 13184
drwxr-xr-x@  6 waltxao  staff      192 Aug  7 21:09 .
-rw-r--r--@  1 waltxao  staff     6148 Aug  7 21:09 .DS_Store
-rw-r--r--@  1 waltxao  staff  3374943 Aug  7 21:09 FlowFinder-0.7.3.dmg
-rw-r--r--@  1 waltxao  staff  3364631 Aug  7 21:09 FlowFinder-0.7.3.zip
drwxr-xr-x@  3 waltxao  staff       96 Aug  7 21:09 FlowFinderNative.app
```

- dist/ 最新产物日期 2026-08-07, 版本 **0.7.3**;
- package.sh 声明的版本为 **0.7.4 (BUILD_NUMBER 740)** (`VERSION="0.7.4"` / `BUILD_NUMBER="740"`,
  第 29-30 行, 由 xcodebuild `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` 注入, 第 182-183 行)
  — 即 dist/ 尚未包含 0.7.4 的发布包。

## 3. 现有 .app 签名状态

```bash
$ codesign --verify --verbose=2 dist/FlowFinderNative.app 2>&1 | tail -3
/Volumes/.../dist/FlowFinderNative.app: valid on disk
/Volumes/.../dist/FlowFinderNative.app: satisfies its Designated Requirement
$ echo $?
0

$ codesign -dv dist/FlowFinderNative.app 2>&1 | head -6
Executable=/Volumes/.../dist/FlowFinderNative.app/Contents/MacOS/FlowFinderNative
Identifier=com.flowfinder.native
Format=app bundle with Mach-O thin (arm64)
CodeDirectory v=20500 size=6582 flags=0x10002(adhoc,runtime) hashes=195+7 location=embedded
Signature=adhoc
Info.plist entries=23
```

- 现有 dist .app 为 ad-hoc (adhoc,runtime) 签名, 当前校验通过;
- 注意: 本机仅有 CommandLineTools (无完整 Xcode), `swift test`/xcodebuild 构建阶段会因
  actool 报错 (见 baseline-swift-matrix.md), 因此未实际运行完整 `package.sh`
  (其第一步会 `rm -rf build/` 并执行 xcodebuild Release 构建, 在构建阶段即失败)。

## 4. 基线事实清单

| 项目 | 状态 |
|---|---|
| codesign --verify 失败 | 仅 `[WARN]` 提示, 打包继续 (第 236-240 行) |
| codesign --sign 失败 | `set -e` 中止脚本 (硬失败) |
| dist/ 产物版本 | 0.7.3 (dmg 3.37MB / zip 3.36MB / app), 日期 2026-08-07 |
| package.sh 声明版本 | 0.7.4 (740) |
| 本机打包前提 | 缺完整 Xcode, xcodebuild/actool 构建失败 |

修复方向 (供后续 wave 参考): 将校验失败升级为 `die` (阻断不签名产物发布),
或区分 "ad-hoc 未公证" 与 "签名损坏" 两种情形分别处理; 重新打包 0.7.4 产物。
