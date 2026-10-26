---
name: flowfinder-desktop-copy-deploy
description: "FlowFinder 桌面副本（~/Desktop/FlowFinder.app）安全部署 playbook：备份旧包 → 判断能否复用已验证的 Debug 产物（二进制晚于全部源码 + codesign 通过）→ rm -rf/cp -R 覆盖桌面副本（不重跑 make demo，避免构建号多递增一次）→ codesign --verify --deep → open 后用 PID 归属 + 窗口几何 + 侧栏版本标签实测确认 → 同步 HANDOVER / REQUIREMENTS-LEDGER / 交接文案 / CHANGELOG 的『当前态』表述并保留各轮历史表述。Use when asked to 覆盖/同步 桌面副本、make demo、部署 ~/Desktop/FlowFinder.app、用户实例版本与文档记录对不上、build number 漂移。Do not use for building/testing or UI auditing — those have their own skills."
when_to_use: "需要把 FlowFinder 构建产物覆盖到 ~/Desktop/FlowFinder.app 供用户实测，并同步文档当前态时。"
argument-hint: "[--dry-run|--apply] [expected-version]"
---

# FlowFinder 桌面副本安全部署

## 目标与边界

把已验证的产物安全落到用户每天在用的 `~/Desktop/FlowFinder.app`，并让文档记录的构建号与实际安装的包**逐字对得上**。

适用：

- 用户授权后，要把当前 Debug 产物覆盖到桌面副本供实机实测。
- 文档记录的构建号与桌面副本实机版本不一致，需要复核到底装的是哪个包。
- 部署后需要可归因的运行证据（PID、窗口几何、版本标签）再写文档。

不适用：

- 跑全量 XCTest / `FF_SELFTEST`：用 `flowfinder-xctest-batch-verification`。
- UI/UX 截图验收与缺陷审计：用 macOS UI 审计类 Skill。
- 打分发 DMG/ZIP：用 `make beta`（会递增构建号，属发版流程）。

## 安全红线

1. **覆盖桌面副本前必须取得用户明确授权。** 历史每轮文档都写「用户授权后覆盖」；未授权时只 `make build`，不动副本（HANDOVER 里有多个「未执行 make demo，桌面副本仍为 26102221」的合规轮次）。
2. 备份先于覆盖。旧包先落到 `/tmp/ff-desktop-backup/FlowFinder-<旧构建号>.app`，再 `rm -rf`。
3. 不跑 `make swift-test`（含 `pkill -f "MacOS/FlowFinder"`，会结束用户正在用的实例）。需要杀进程时只按**完整可执行路径**定位 PID。
4. 不 commit、不 push。部署只产出实机证据。
5. 「已启动」不等于「已验证」：必须拿到 PID + 路径归属、`codesign` 结果、版本标签实机值三项，才允许写文档当前态。
6. 只认当次实测数字。不复用上一轮 XCTest/自检数字，也不改写历史轮次里记录的旧数字。

## 关键判定：复用现成产物，还是重新出包

项目约定是「任何 UI 改动先用 `make demo` 出包」（`docs/HANDOVER.md` 收尾清单第 7 条）。但 `make demo` = `build` + 覆盖，而 `build` 每次都跑 `scripts/bump-version.sh` 递增 `CFBundleVersion`（规则 `A.B.C-yymmddxx`）：

- 若本轮已经为跑测试执行过 `make build`，再跑 `make demo` 会**多递增一次构建号**，产出一个内容与已验证包相同、但号对不上的新包 → 文档记录的构建号与桌面实机版本从此错开。这是 2026-10-22 实际踩到并改用复用路径的原因。
- 复用前提（两个都成立才可复用）：
  1. Debug 产物二进制 mtime **晚于全部源码**（`find -newer`，源码含 `*.swift`/`*.rs`/`project.pbxproj`/`*.plist`/`scripts/*.sh`）。
  2. `codesign --verify --deep` 通过（工程用 ad-hoc 签名 `CODE_SIGN_IDENTITY=-`）。
- 任一不成立 → 不要复用，回去 `make build` 出新号，再按新号重跑测试与文档。

产物路径（Makefile 变量，勿硬编码猜）：

| 变量 | 值 |
|---|---|
| `DERIVED` | `~/Library/Caches/FlowFinderBuild`（外置卷构建会挂死，故默认落内置盘） |
| `APP_DEBUG` | `$DERIVED/Products/Debug/FlowFinder.app` |
| `DESKTOP_APP` | `~/Desktop/FlowFinder.app` |

## 部署步骤

脚本默认 dry-run，只打印判定结果与计划；取得授权后加 `--apply` 才写入。

```bash
# 1) 只读检查：新鲜度 + 源产物签名 + 将备份到何处
scripts/deploy_debug_to_desktop.sh

# 2) 用户授权后执行（备份 → rm -rf → cp -R → 校验副本签名）
scripts/deploy_debug_to_desktop.sh --apply
```

脚本门禁退出码：`0` 可复用/已部署；`1` 被挡住（产物早于源码、签名不过、源产物缺失）——禁止绕过，回到 `make build` 出新号再走测试。`--apply` 成功也不等于部署完成，仍需下面的实机确认。

```bash
# 3) 打开并取证（needle = 期望的版本标签，如 0.8.0-26102235）
open ~/Desktop/FlowFinder.app
scripts/verify_desktop_instance.sh 0.8.0-26102235
```

退出码 `2` = 证据不完整（副本未运行、AX 不可用或版本标签未在 AX 静态文本中命中），按脚本提示补 `open` 或用 `screencapture` 截侧栏区域肉眼核对后重跑。ad-hoc 签名的包首次打开需右键 → 打开。

## 部署后必须取得的证据

写进文档的每一项都当轮实测：

1. **归属**：`pgrep -f` 按完整可执行路径得到的 PID，且路径就是 `~/Desktop/...`（副本与用户实例可能同 Bundle ID 共存，勿只按进程名）。
2. **签名**：桌面副本上 `codesign --verify --deep` 的结果。
3. **版本**：`CFBundleVersion` 与侧栏版本标签实机字符串（形如 `0.8.0-26102235 Beta`），以及主窗口标题/位置/尺寸。

坑（已实测）：`tell application "System Events" to first application process whose unix id is <pid>` 在本机会返回**另一个** PID 的进程，按它取到的窗口是用户实例的。脚本改用 `AXUIElementCreateApplication(pid)` 按 PID 直连；任何窗口几何证据都必须带 PID 归属断言才可写入文档。

## 文档当前态同步

同一轮完成，否则视为任务未完成（`docs/HANDOVER.md` 顶部同步纪律）。区分两类表述：

| 文件 | 改「当前态」 | 必须保留的「历史」 |
|---|---|---|
| `docs/HANDOVER.md` | 头部「当前版本」「验证基线」；桌面副本条目（构建号 + PID + 窗口 + 版本标签） | §1.5–§1.10 各轮当时的 XCTest/自检数字（190/258/335/164 等） |
| `docs/REQUIREMENTS-LEDGER.md` | 概览表「桌面副本 / 最新构建 / 基线」行；新增一条「桌面副本同步」变更记录（含日期、授权、备份路径、校验、PID） | 每条历史变更记录原文 |
| `CHANGELOG.md` | 「未发版」段的分发说明 | 已发布版本段不动 |
| `docs/交接文案-*.md` | 首段版本与桌面副本状态 | 旧文案文件不追溯改写 |

写法要点：明确记为「复用 `make build` 产物、未重跑 `make demo`」并给出原因（避免多递增一次构建号），旧包备份位置，以及校验通过的命令——这样下一轮接手者能解释为什么没走 `make demo`。

## 已核实失败模型

| 现象 | 判定 | 动作 |
|---|---|---|
| `make demo` 后实机版本比文档记录大一号 | `build` 钩子又 bump 了一次 | 复用已验证产物手动等价覆盖，文档记实机号 |
| 外置卷仓库 `xcodebuild` 停在 `Building Swift (Debug)...` 数分钟无输出 | llbuild 在 `/Volumes` 挂死（Makefile 注释实测） | 镜像到内置盘 `/tmp` 构建，见 `flowfinder-xctest-batch-verification` |
| 覆盖后窗口尺寸与预期不符 | 取到的是另一实例的窗口 | 用 PID 直连 AX 或截图断言，不信 System Events 的 `whose unix id` |
| 侧栏版本标签读不到 | 侧栏标签可能被窄宽截断或非 AXStaticText | 按主窗口几何 `screencapture` 侧栏区域肉眼核对 |

## Resources

- `scripts/deploy_debug_to_desktop.sh` — 门禁（新鲜度、签名）+ 备份 + 覆盖 + 副本签名校验；默认 dry-run。
- `scripts/verify_desktop_instance.sh` — 桌面副本 bundle 版本、`codesign`、按可执行路径的 PID 归属、AX 窗口几何与版本标签检索。
