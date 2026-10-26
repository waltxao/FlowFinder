---
name: "superpowers"
version: "1.0.0"
display_name: "Superpowers 工程方法论"
display_name_en: "Superpowers Engineering Methodology"
description: "Agent 软件工程方法论框架：开始写码前先头脑风暴出规格，写可执行实施计划，强制红绿 TDD，子代理驱动开发，系统化调试与代码评审，收尾合并。当用户要做功能开发、重构、修复 bug、写实施计划、做代码评审，或提到「用 superpowers / 先想清楚再写 / 红绿测试 / 子代理开发」时触发。"
description_zh: "Agent 软件工程方法论框架：开始写码前先头脑风暴出规格，写可执行实施计划，强制红绿 TDD，子代理驱动开发，系统化调试与代码评审，收尾合并。当用户要做功能开发、重构、修复 bug、写实施计划、做代码评审，或提到「用 superpowers / 先想清楚再写 / 红绿测试 / 子代理开发」时触发。"
description_en: "An agentic software-development methodology framework. Before writing code, brainstorm a spec, write an executable implementation plan, enforce red-green TDD, drive development with subagents, debug systematically, run code review, and finish the branch. Trigger when the user asks to build a feature, refactor, fix a bug, write an implementation plan, or do code review, or mentions 'superpowers / think before coding / red-green tests / subagent development'."
---

# Superpowers 工程方法论（原创重制版）

> 本技能基于 obra/superpowers 公开的方法论重制，为 WorkBuddy 适配的**自包含工程流程框架**。它不搬运任何源码，只固化「先想清楚、再写计划、强制测试、系统收尾」的工作纪律。

## 核心理念

1. **测试驱动（TDD）** —— 永远先写测试。
2. **系统化优先于临场发挥** —— 用流程取代猜。
3. **降低复杂度是首要目标** —— 简单优于聪明。
4. **证据优于声称** —— 宣布完成前先验证。

## 触发后做什么

用户一旦提出「做功能 / 修 bug / 重构 / 写计划 / 评审」类需求，**不要直接写代码**。按下面的基础工作流依次推进，每一步的详细规则见 `references/`。

### 基础工作流（7 步）

1. **头脑风暴（brainstorming）** —— 写码前激活。通过提问把粗糙想法打磨成规格：探索替代方案，分块呈现设计让用户确认，落地为设计文档。详见 `references/01-workflow.md`。
2. **开隔离工作区（git worktree）** —— 设计确认后激活。新建分支 / worktree，跑通项目初始化，确认测试基线干净。
3. **写实施计划（writing-plans）** —— 有规格后激活。把工作拆成「2-5 分钟一个」的小任务，每个任务含精确文件路径、完整代码、验证步骤。格式见 `references/02-writing-plans.md`。
4. **子代理驱动开发 / 执行计划** —— 有计划后激活。每个任务派一个全新子代理，做两段式评审（先查规格符合度，再查代码质量）；或分批执行并设人工检查点。见 `references/05-code-review.md`。
5. **测试驱动开发（TDD）** —— 实现中激活。强制 RED-GREEN-REFACTOR：先写会失败的测试→看它红→写最少代码→看它绿→提交。测试前写的代码一律删除。见 `references/03-tdd.md`。
6. **请求代码评审（code-review）** —— 任务之间激活。对照计划审查，按严重度报告问题，Critical 级阻断推进。
7. **收尾开发分支（finish）** —— 任务完成后激活。验证测试通过，给出合并 / 开 PR / 保留 / 丢弃选项，清理 worktree。

### 配套能力

- **系统化调试（systematic-debugging）**：4 阶段根因法（根因追踪、纵深防御、条件等待）。见 `references/04-systematic-debugging.md`。
- **完成前验证（verification-before-completion）**：确认真的修好了，而不是「看起来修了」。
- **并行派单（dispatching-parallel-agents）**：并发子代理工作流。
- **接收评审（receiving-code-review）**：面对反馈如何回应。
- **写技能（writing-skills）**：按最佳实践新建技能（含测试方法论）。

## 使用纪律

- **任何任务前先检查相关技能** —— 这些是强制工作流，不是建议。
- **规格未确认，不动手**；计划没写清，不派活。
- **TDD 不可跳过**：没有失败的测试，就不算实现。
- **复杂度冒头就砍**：能用 100 行就别用 1000 行。

## 与现有技能的关系

本方法论是「怎么做软件工程」的元框架，可与具体领域技能（如 `baijiahao-emotion-pipeline` 的内容生产流水线）并列使用——它管「工程纪律」，领域技能管「业务规则」。
