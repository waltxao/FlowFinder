---
name: feature-branch-github-release
description: "从功能分支发布 GitHub Release 并验证发布结果：用 --target 锁定提交、核对或修正 tag SHA、检查 prerelease、资产、sha256 校验和与本地 HEAD，并在提交前还原被构建改写的预编译库。用于 gh release create 从非默认分支发版、tag 被指到 main、打包改写 .a/.dylib、或发布后需要复核时；版本号递增与戳记走 iteration-build-version-stamp。"
---

# Feature Branch GitHub Release

在功能分支上发版时，`gh release create` 默认把新 tag 打在仓库默认分支（通常是 `main`），而不是当前分支。本技能用显式 `--target` 固定提交，并在发布后逐项核对 tag、资产和校验和；同时拦截打包脚本对仓库内预编译库的意外改写。

## 核心规则

1. 永远带 `--target <40 位 SHA>` 创建 Release；不要依赖当前分支或默认分支。
2. `--target` 只影响**新建** tag；tag 已存在时它不会移动 tag。
3. tag 和 Release 是共享状态：创建、改指、覆盖资产、删除前都要用户确认。
4. 命令成功 ≠ 发布正确：每次创建后立即回读 tag SHA、资产与校验和。
5. 打包后再提交：先识别并还原构建改写的 tracked 文件（`.a`、`.dylib`、生成物）。
6. 文档只写最终产物与实测数字，并在创建 Release 前提交，避免 tag 落在文档提交之前。

## 参数

开始前记录并让用户确认：

| 参数 | 示例 | 说明 |
| --- | --- | --- |
| `REPO` | `owner/repo` | 用 `gh repo view` 取 |
| `BRANCH` | `feat/v0.9-overhaul` | 当前功能分支 |
| `TAG` | `v0.8.0-b1` | 远端 tag 名 |
| `VERSION` | `0.8.0-26102209` | 产物内版本戳 |
| `ASSETS` | dmg / zip / sha256 | 发布资产清单 |
| `PRERELEASE` | `true` | Beta 必须为 true |

tag 名与资产文件名不必相同，但版本前缀必须能对上；先看仓库既有 Release 命名再决定。版本号未定或需要递增时，先走 `iteration-build-version-stamp`。

## 工作流

### 1. 固定源提交

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
SRC_SHA=$(git rev-parse HEAD)
gh auth status
git status --porcelain
git ls-remote origin "refs/heads/$BRANCH"
```

- 远端分支头必须等于 `SRC_SHA`；不一致先推送（需确认）。
- 检查 tag 是否已存在：

```bash
git ls-remote --tags origin "refs/tags/$TAG"
```

有输出就停止：`--target` 不会移动已有 tag。改走 `gh release edit` / `gh release upload --clobber`，或经确认后删除重建。

### 2. 打包，立即识别构建改写

```bash
git status --porcelain > /tmp/release-pre-build.status
# 运行项目打包脚本，例如 make beta / scripts/package-beta.sh
git status --porcelain > /tmp/release-post-build.status
git diff --name-only
```

逐项判断新增改动：

- 版本文件、CHANGELOG、发布说明：预期的源码改动，提交。
- 预编译库（`*.a`、`*.dylib`）、DerivedData、生成资源：构建副产物，还原。
- 不确定时看该文件最近一次提交与 `git diff --stat`，不要整目录回滚。

```bash
git restore -- path/to/libfoo.a path/to/libfoo.dylib
git status --porcelain
```

只还原构建改写的具体路径；禁止 `git checkout .` / `git reset --hard`。若预编译库本来就该随本轮更新，则提交它并在报告中说明，不能悄悄留在工作区。

### 3. 核对产物再发布

```bash
APP=/path/to/Final.app
DIST=/path/to/dist
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"
( cd "$DIST" && shasum -a 256 App.dmg App.zip > App.sha256 )
( cd "$DIST" && shasum -a 256 -c App.sha256 )
```

- 资产名、版本戳、tag 三者要能对应。
- 若自检只在 `#if DEBUG` 下编译，Release 构建里没有自检日志属预期：记录「Release 自检 N/A」，用 Debug 构建的测试结果和最终产物的版本/签名作证据；不要把这种情况写成「自检失败」，也不要把 Debug 数字冒充 Release 自检。
- 带更新检查的应用，发布说明需包含完整版本戳；否则应用识别不到新版本。

### 4. 文档先提交，再取最终 SHA

发布状态、版本、测试数字写进台账/交接/CHANGELOG 后：

```bash
git add docs/ CHANGELOG.md
git commit -m "docs: 记录 $TAG 发布"
git push origin "$BRANCH"   # 需确认
SRC_SHA=$(git rev-parse HEAD)
git ls-remote origin "refs/heads/$BRANCH"
```

这样 tag 指向的提交包含发布文档。若先发 Release 再补文档，tag 会停在文档提交之前，只能经确认后将 tag 改指到新提交（见第 6 步）。

### 5. 创建 Release

```bash
DIST=/path/to/dist
gh release create "$TAG" \
  --target "$SRC_SHA" \
  --title "App $TAG" \
  --notes-file /tmp/release-notes.md \
  --prerelease \
  "$DIST/App.dmg" "$DIST/App.zip" "$DIST/App.sha256"
```

- `--target` 用完整 SHA，不用分支名。
- Beta 加 `--prerelease`；稳定版不要加。
- 资产路径逐个列出，避免 glob 把无关文件带上。
- 创建成功后 tag 只存在于远端；本地 `git rev-parse "$TAG"` 可能报 `unknown revision`，这是未 fetch，不是 tag 没建。

### 6. 立即核对并修正 tag 指向

```bash
gh api "repos/$REPO/commits/$TAG" --jq .sha
git ls-remote origin "refs/tags/$TAG" "refs/tags/$TAG^{}"
```

两者都必须解析到 `SRC_SHA`。annotated tag 的 `^{}` 才是 commit；轻量 tag 只有第一行。

若指向 `main`（常见根因：漏了 `--target`），经用户确认后改指：

```bash
gh api --method PATCH "repos/$REPO/git/refs/tags/$TAG" \
  -f sha="$SRC_SHA" -F force=true
git fetch --tags --force
```

改完重跑本节校验。`gh release view` 里的 `targetCommitish` 是创建时记录，PATCH tag 后可能仍显示 `main`；以 tag 实际指向的 commit 为准。tag 保护规则拒绝更新时停止并报告，不要删除 Release 绕过。

### 7. 核对 Release 元数据与资产

```bash
gh release view "$TAG" \
  --json tagName,isDraft,isPrerelease,targetCommitish,assets \
  --jq '{tag:.tagName,draft:.isDraft,prerelease:.isPrerelease,target:.targetCommitish,
         assets:[.assets[]|{name,size}]}'
```

逐项确认：

- `isPrerelease` 与发布通道一致，稳定版不得误标 prerelease。
- `isDraft=false`。
- 资产数量、文件名、大小与本地产物一致，大小不为 0。

下载已上传副本并校验，防止上传损坏：

```bash
rm -rf /tmp/release-check && mkdir -p /tmp/release-check
gh release download "$TAG" --dir /tmp/release-check
cd /tmp/release-check && shasum -a 256 -c ./*.sha256
```

macOS 默认没有 `sha256sum`，用 `shasum -a 256 -c`。校验文件的条目必须只写文件名，不能带本地路径前缀。

不通过时：先重下确认不是传输问题；仍不一致则重新生成校验和并 `gh release upload "$TAG" <file> --clobber`（需确认），不要用下载到的坏文件反推校验和。

### 8. 收口报告

报告必须包含实测输出，而不是「已发布」四个字：

- Release URL、tag、`gh api .../commits/$TAG` 的 SHA、本地 `HEAD`。
- prerelease/draft 状态、资产名与字节数。
- `shasum` 校验结果。
- 工作区是否干净；被还原的构建改写文件。
- 文档提交 SHA；分支是否已推送。

## 失败模式

| 现象 | 根因 | 正确处理 |
| --- | --- | --- |
| tag 指向 `main` | `gh release create` 未带 `--target` | PATCH tag ref 后重新校验 |
| `git rev-parse TAG` 报 unknown revision | tag 只在远端，本地未 fetch | `git fetch --tags --force` |
| 加了 `--target` 但 tag 没动 | tag 已存在，`--target` 被忽略 | 先查 `ls-remote`；改走 edit/PATCH |
| `targetCommitish` 仍是 `main` | 它是创建时元数据 | 校验 tag 指向的 commit，不看该字段 |
| 校验和不匹配 | 上传损坏、文件名/路径不一致、产物被重建 | 重下核对；必要时重新上传并确认 |
| 发布后工作区有 `M *.a` / `M *.dylib` | 打包脚本重写了预编译库 | 提交前按路径还原 |
| Release 自检「失败」 | 自检被 `#if DEBUG` 编译掉 | 记录 N/A；用 Debug 测试 + 产物版本/签名 |
| 资产数量不对 | glob 或遗漏校验和文件 | 显式列出每个资产并回读 assets |

## 确认门

执行前逐项获得用户确认：

- 推送分支、创建/编辑 Release、覆盖资产、修改或删除 tag。
- 任何 `--force`、`--clobber`、删除远端 tag/Release。
- 预编译库是提交还是还原。

只读核对（`gh release view`、`git ls-remote`、下载校验）不需要确认。

## 验证清单

- [ ] `SRC_SHA` 是预期的功能分支提交，且远端分支头一致。
- [ ] 创建前 `refs/tags/$TAG` 为空（新建）或已确认更新策略。
- [ ] `gh release create` 显式带 `--target "$SRC_SHA"`。
- [ ] `gh api repos/$REPO/commits/$TAG` 与 `git ls-remote` 均等于 `SRC_SHA`。
- [ ] `isPrerelease`、`isDraft` 正确。
- [ ] 资产数量、名称、大小与本地一致。
- [ ] 下载后的 `shasum -a 256 -c` 全部 OK。
- [ ] 工作区干净，预编译库未被误提交。
- [ ] 台账/交接/CHANGELOG 只写最终版本与实测数字。
- [ ] 报告含 URL、tag SHA、资产、校验和、HEAD。

## 相关技能

- `iteration-build-version-stamp`：版本戳与构建号递增；本技能不重复实现。
- `flowfinder-docs-sync`：FlowFinder 仓库的台账/交接同步规则；其他项目按各自约定执行。
