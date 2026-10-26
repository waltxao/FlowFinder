# FlowFinder AI 资源清单（MCP / Skill / 插件）

> 整理日期：2026-10-22（第二十二轮 R-29 收尾时按用户要求入库）；**2026-10-23 增补**（R4 全量修复收尾时新增 `skills-2026-10-23/` 快照，见 §一·b 与 §三·b）；**2026-10-25 更新**（`flowfinder-docs-sync` 增加提交/推送/README 收口与真机 AX 坑；`flowfinder-xctest-batch-verification` 增加单测/修饰符/双栏搜索补充；证据目录 `docs/images/audit-2026-10-25-sidebar-search/` 含个人文件名，仅本地留存、未随仓库上传）。
> 本目录 `resources/ai-tools/` 是本项目开发协作所用 AI 资源的**项目内快照**，便于交接与追溯。
> 运行时的权威来源仍是本机目录（见下表），此处为副本；更新副本时请整目录重新拷贝。

## 一、目录结构

```
resources/ai-tools/
├── MCP-AND-SKILLS.md        # 本清单
├── skills/                  # 2026-10-22 快照（15 个，源自 ~/.qoder-cn/skills/，历史轮次工作流）
├── skills-2026-10-23/       # 2026-10-23 增补快照（19 个，源自 ~/.qoder/skills/，R4 审计/修复/验证工具链）
└── plugins/
    └── grillme-matt/0.1.0   # 拷问式开发工作流插件（源自 Qoder 插件缓存）
```

### 一·b、`skills-2026-10-23/`（19 个，484 KB）

来源：`~/.qoder/skills/`（2026-10-22 前后为 FlowFinder 新写的运行时 Skill）。分三组：

**FlowFinder 专属（2 个）**

| Skill | 用途 / 本项目实测 |
|---|---|
| flowfinder-xctest-batch-verification | 全量 XCTest 分批串跑的隔离方案（/tmp 内置盘镜像 + 独立 Bundle ID + 按类分批 + 假绿识别）；R4 收口的 17 批 516 条即用它跑出 |
| flowfinder-desktop-copy-deploy | 桌面副本安全部署门禁（新鲜度/签名/备份/--apply + 实机取证脚本）；2026-10-23 部署 0.8.0-26102301 即用它完成 |

**macOS AppKit / CUA 审计与验证链（14 个）**

| Skill | 用途 |
|---|---|
| cua-macos-ui-audit | Computer Use 隔离副本全量 UI 审计（R4 审计的方法骨架） |
| macos-cua-isolated-ui-audit | 同上的轻量入口：锁屏/恢复/权限门/PID 归因 |
| appkit-stale-frame-layout-debug | 陈旧 frame 布局 bug 的系统化调试法（R-35 根因所属类别） |
| appkit-interaction-regression-testing | 交互回归（拖拽/手势/命中）实机取证 |
| appkit-drag-performance | 拖拽性能剖析 |
| appkit-ui-polish-implementation | UI 打磨改动的实现纪律 |
| appkit-visual-effect-verification | 玻璃/材质效果的视觉验证 |
| macos-appkit-ui-verification / macos-native-ui-verification | AppKit 真机验证的两级流程 |
| macos-cua-session-recovery / macos-cua-lock-and-launch-recovery / macos-computer-use-lock-recovery | CUA 会话卡死/锁屏/启动失败的恢复 |
| xctest-host-isolation / macos-xctest-isolation | 测试宿主隔离（Bundle ID 冲突、单实例提示） |
| xcode-swift-delivery-loop | Swift 交付闭环（构建→测试→落包） |

**流程类（3 个）**

| Skill | 用途 |
|---|---|
| visual-requirement-confirmation | 可视化逐项确认（一次一问）——UI 方案对比稿的既定协议 |
| third-party-audit-triage | 外部审计/他人报告的三方校验（Confirmed/环境产物分类口径） |
| （其余同组 superpowers 见 `skills/superpowers`） | 本轮 R4 修复全程走 TDD（先红后绿），R4-32 回归测试即按此写出 |


### 一·c、2026-10-25 更新（2 个 FlowFinder 专属 Skill）

| Skill | 本次更新 |
|---|---|
| flowfinder-docs-sync | 增加「提交、推送与 README」段：fetch/差异审阅/显式路径 add/分组提交/大文件与密钥检查/推送后回写哈希/README 徽章与 Release 资产核对/技能副本同步；增加「真机验证补充」：CGEvent 修饰符复位、双栏搜索语义、临时收藏右键清理、详情栏残留已知问题 |
| flowfinder-xctest-batch-verification | 增加 2026-10-25 补充：单测不等于全量基线、Command 修饰符残留复位、真机会话禁用 `make swift-test`、双栏搜索先设范围再输入 |

## 二、MCP 服务（Qoder 会话内使用，无法以文件形式入库，仅登记）

| MCP | 在本项目中的用途 |
|---|---|
| node-repl（Computer Use） | 真机 UI 验证主力：AX 状态 diff、元素点击、按键（⌘Z 等）、截图；J3-10 双入口/执行/撤销走查即用它完成。**R4 轮实测补充**：本机被用户自有窗口完全遮挡时，CUA 置顶不可行，可靠取证只剩 `screencapture -x -o -l<windowID>`（窗口自身 surface）+ AX frame + 进程内 `cacheDisplay` 位图 |
| record-and-replay | 录制复现流程（侧栏/单双栏空白问题取证），事件流转 Skill |
| browser-use / chrome-devtools | 官网页面与外部调研的浏览器操作 |
| context7 | 第三方库文档查询（Swift/AppKit/Rust 相关） |
| builtin（会话管理） | 跨会话交接与子任务 |

## 三、Skill 快照（`skills/`，15 个，2026-10-22 历史快照）

| Skill | 用途 / 触发场景 |
|---|---|
| superpowers | 方法论框架：brainstorming → writing-plans → TDD → 子代理开发 → code review；每轮整改的流程骨架 |
| grillme-matt（见 plugins/） | 拷问式需求对齐、领域建模、to-spec/to-tickets/implement/TDD/code-review；一次一问协议来源 |
| macos-isolated-app-ui-verification | 独立 Bundle ID 临时副本真机验证（PID 定位、AX 几何 + screencapture -R、偏好恢复）；每轮真机验收的标准流程 |
| macos-app-ui-verification | 通用窗口截图与坐标纪律（与上一 skill 分工） |
| macos-appkit-ui-testing | AppKit 布局回归 XCTest 编排 + 实机验收（20 轮压测等） |
| appkit-layout-tdd | AppKit 布局 TDD 的本地约定 |
| visual-confirmation-tdd-loop | 可视化对比稿 → 一次一问 → SPEC/PLAN → 失败测试先行 → 真机取证 → 文档同轮同步的闭环（顶栏整改等轮次的实际流程） |
| visual-confirmation-loop | 上一 skill 的前身，仅存档对照 |
| flowfinder-docs-sync | 本项目专属：改代码必须同轮更新 REQUIREMENTS-LEDGER.md 与 HANDOVER.md |
| requirement-docs-code-audit | 需求文档与代码一致性审计（R-23 文档原位重写用过） |
| settings-wiring-audit | 设置接线审计（别只 grep 常量名，裸键/调用方/FFI/测试一起核） |
| xcode-dated-build-number | 版本号 `A.B.C-yymmddxx` 自动递增规则 |
| feature-branch-github-release | 功能分支 + GitHub Release（v0.8.0-b1 发布流程） |
| iteration-build-version-stamp | 迭代构建号烙印 |
| native-icon-library-migration | SF Symbols + Phosphor 图标库迁移（R19 Phase 1 用过） |
| web-access | 联网调研（图标库选型、外部资料） |

## 四、插件（`plugins/`）

| 插件 | 版本 | 说明 |
|---|---|---|
| grillme-matt | 0.1.0 | 完整拷贝（grill-with-docs / domain-modeling / to-spec / to-tickets / implement / tdd / code-review / dev-router）。`tdd` 与 `implement` 在 J3-10 等轮次实际驱动红绿循环 |
| superpowers | 6.3.0 | 以用户级 Skill 形式快照于 `skills/superpowers`（插件缓存 772K 未整拷，SKILL.md 与 references 均在） |

## 五、快照与运行时来源对照

| 资源 | 项目内路径 | 运行时来源 |
|---|---|---|
| 15 个 Skill（2026-10-22） | `resources/ai-tools/skills/<name>/` | `~/.qoder-cn/skills/<name>/` |
| 19 个 Skill（2026-10-23） | `resources/ai-tools/skills-2026-10-23/<name>/` | `~/.qoder/skills/<name>/` |
| grillme-matt | `resources/ai-tools/plugins/grillme-matt/0.1.0/` | `~/.qoder-cn/plugins/cache/qoder-marketplace/grillme-matt/0.1.0/` |
| superpowers 插件完整缓存 | 未整拷（skills/superpowers 已含核心） | `~/.qoder/plugins/cache/qoder-marketplace/superpowers/6.3.0/` |

> 副本日期：2026-10-22 / 2026-10-23。Skill 会随插件更新演进，以运行时版本为准；本快照用于交接时理解「当时的工作流是什么」。
> 交接提示：接手 Agent 若在本机运行，直接用运行时 Skill（名字见两份快照目录）；若在别的机器，把 `skills-2026-10-23/` 对应目录拷回自己的用户级 Skill 目录即可恢复同一套工具链（脚本相对路径以各 SKILL.md 的 base directory 为准）。
