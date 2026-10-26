---
name: xcode-swift-delivery-loop
description: "在既有 macOS Xcode/Swift/AppKit 项目按已批准规格做多切片改造时使用：登记新增 Swift 文件、先红后绿跑 XCTest、定位被 make 包装截断的失败、隔离 LaunchServices/侧栏图标导致的测试宿主挂死，并以 build、全量测试、应用内自检、产物冒烟和未验项交接收尾。"
---

# Xcode Swift 交付闭环

## 适用边界

用于已有计划、规格或明确验收标准之后的实现与交付，尤其是包含多个可独立验收切片的 macOS Swift/AppKit 改造。

用于：

- 按 SPEC/PLAN 连续实现多个任务。
- 新增或移动 Swift 文件后需要修正 Xcode 工程登记。
- `make swift-test` 只给出汇总，需要定位具体失败用例。
- XCTest 宿主被 LaunchServices、侧栏图标或环境状态卡住。
- 一轮收尾，需要构建、全量测试、应用内自检、产物冒烟和交接文档。

不用于：

- 需求脑暴、方案取舍或未拍板的 UI/UX 设计。
- 没有现有工程可读的全新项目。
- 仅需解释代码或做一次静态审查。

若设计或验收标准仍未确认，先使用 brainstorming、visual-requirement-confirmation 等设计流程；方案获批后再进入本流程。不要用“测试通过”替代设计确认。

默认不提交、不推送、不修改目标项目之外的文件，除非用户明确授权。

## 开工前检查

1. 读取项目约定和交接入口，例如 `AGENTS.md`、`HANDOVER.md`、SPEC、PLAN、需求台账、CHANGELOG。
2. 确认项目根目录、当前分支、`git status`、未提交改动和产物路径。
3. 从 Makefile、README、scheme 或 CI 配置中确认真实命令；不要凭记忆假设命令名。
4. 判断 Xcode 工程类型：
   - 传统 `PBXGroup`：新增文件通常需要手工登记。
   - `PBXFileSystemSynchronizedRootGroup`：文件系统同步组自动纳入，不要照搬手工登记。
   - XcodeGen、Tuist、SPM：修改项目清单，不手改生成产物。
5. 选定本切片可观察的行为和单一聚焦测试。若无法自动化，明确写出人工验证步骤和原因。
6. 若工程基线未知，先跑一次构建和测试，记录起始状态；不要把既有失败当成本次回归。

FlowFinder 的已验证命令、路径和测试宿主配置见
[references/flowfinder-delivery-profile.md](references/flowfinder-delivery-profile.md)。复用前重新核实路径和计数。

## 单切片闭环

按一个可独立验收的切片推进，不要混合无关修复。

### 1. 先写失败测试

- 为行为写聚焦 XCTest，优先纯函数或可注入依赖的结构。
- 运行单个测试类或方法，记录红灯证据。
- 若物理拖拽、系统权限或屏幕状态导致无法自动驱动，保留可断言的纯逻辑层，并把剩余人工步骤列入未验项。
- 无法先写测试时，说明原因并给出替代验证；不要静默跳过。

### 2. 实现最小改动

- 只改满足本切片验收所需的代码。
- 新增 Swift 源文件时检查目标归属：应用 target 与测试 target 要分别登记。
- 传统 pbxproj 通常需要四处一致：

  1. `PBXBuildFile`：建立 build file，引用 file reference。
  2. `PBXFileReference`：登记文件路径。
  3. `PBXGroup`：把 file reference 放进正确分组。
  4. `PBXSourcesBuildPhase`：把 build file 加入对应 target 的 Sources。

- 使用唯一 ID，不要复制已有 ID；不要把应用文件误加进测试 target。
- 修改完成后先 grep 文件名，确认四个位置都存在且目标正确，再构建验证。
- 对于同步组或项目生成器，按第 4 项开工检查的结论处理，不要机械套用四步。

### 3. 聚焦转绿，再跑全量

- 先跑聚焦测试，确认新增行为转绿。
- 再跑全量测试和构建，防止切片间回归。
- 若测试包装器只保留尾部摘要，直接运行底层 `xcodebuild`：

```bash
xcodebuild test \
  -project <Project>.xcodeproj \
  -scheme <TestScheme> \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  -only-testing:<TestTarget>/<TestClass> \
  2>&1 | grep -E "Test Case .*failed|XCTAssert|error:|TEST (SUCCEEDED|FAILED)" | tail -80
```

- 全量失败时去掉 `-only-testing`，或用 `.xcresult` 读取失败用例。
- 不要为了看见失败而永久削弱 Makefile；除非把“保留失败详情”作为正式的测试基础设施改进。

## 失败分诊

| 症状 | 先查 | 动作 |
|---|---|---|
| 新文件存在但报 `cannot find ... in scope` | pbxproj 四处登记、target membership | 修正登记后重建；不要靠复制代码绕过 |
| `TEST FAILED` 只显示数量，没有用例名 | make 包装的 `tail`/`grep` | 直接跑 xcodebuild 并过滤失败用例 |
| 宿主长时间卡住，sample 落在 `NSWorkspace.iconForFile` / LaunchServices | 是否在真实 home 中同步查图标 | 使用隔离测试 home 和测试专用跳过图标开关；确认是隔离而非生产修复 |
| 改用安全默认后旧测试失败 | 旧测试是否假定“已预选/已勾选” | 在测试中显式构造新状态，并补用户可见的显式操作；不要回退安全默认 |
| 异步测试超时 | 等待条件是否可观察、是否依赖真实系统服务 | 改为等待明确状态；不要只增大超时 |
| 视觉或性能无法验证 | 屏幕是否锁定/全黑、权限是否缺失、合成事件是否可靠 | 记录“未验”及人工步骤；不要用单测宣称视觉或性能通过 |

### XCTest 宿主隔离

当 sample 或堆栈显示测试卡在侧栏图标、LaunchServices、`getattrlist` 等系统查询：

- 用测试专用 home 隔离真实用户目录，例如在 TestAction 设置 `CFFIXED_USER_HOME=/tmp/<project>-test-home`。
- 在测试环境跳过会触发系统查询的装饰性工作。FlowFinder 使用 `FF_SKIP_SIDEBAR_ICONS=1`，仅放在 TestAction。
- 确认测试 home 所需目录存在。
- 结束残留的应用和测试宿主进程后重跑。
- 把该开关记录为“测试隔离”，不要带入发布环境，也不要据此宣称生产性能已修复。

## 交付闸门

按顺序执行项目中的等价命令：

- [ ] 构建成功。
- [ ] 聚焦测试通过。
- [ ] 全量 XCTest 通过，记录准确数量和日期。
- [ ] 应用内自检通过，记录断言数量。
- [ ] 产物已部署到约定位置，记录路径和可执行文件 hash。
- [ ] 启动产物做一次冒烟，确认版本和核心入口可用。
- [ ] 有 UI/交互变更时完成截图或人工路径；无法完成时明确标记“未验”。
- [ ] 更新 SPEC 状态、需求台账、HANDOVER、CHANGELOG 中受影响的部分。
- [ ] 最终报告包含改动、命令证据、数量、产物和未验项。

不要用以下内容替代最终闸门：

- 只有 `BUILD SUCCEEDED`。
- 只有聚焦测试通过。
- 只有旧的测试数量，没有本次日期。
- 只有应用内自检，没有全量 XCTest。
- 只有自动测试，没有视觉走查却声称视觉完成。

## 诚实交接

最终报告至少包含：

```text
完成：<本切片/本轮行为>
证据：<构建、XCTest 数量、自检数量、产物路径/hash>
未验：<视觉、性能、人工手感、权限项；附具体复核步骤>
边界：<未提交、未推送；仍存在的技术债>
```

- “已验证”和“未验证”分开写。
- 屏幕锁定、系统权限、合成事件不可靠等阻塞原因要具体写出，不能只写“未完成”。
- 测试专用环境变量和跳过开关必须记录。
- 测试数量、文件数量和时间会过期；下一次复用前重新测量。
- 除非用户明确要求，不创建提交、不推送、不合并分支。

## 反模式

- 构建成功就宣布功能完成。
- 为了让测试变绿而删除断言、放宽安全默认或伪造用户选择。
- 手工编辑 pbxproj 时复制 ID，或把文件加进错误 target。
- 把测试专用跳过开关带进发布路径。
- 用单元测试结果宣称视觉、性能或真实拖拽手感已验收。
- 在同一个切片里顺手重构无关代码。
- 把“未验”藏在总结之外，或只写在对话里而不更新项目文档。

## Resources

- [FlowFinder delivery profile](references/flowfinder-delivery-profile.md)：2026-10-21 已核实的命令、路径、测试宿主配置和未验项。仅作项目档案使用，复用前重新核实。
