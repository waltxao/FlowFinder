# Grill Me — 拷问式开发工作流

一个本地 Qoder 插件，把 8 个开发者工作流 skill 打包成一条从"需求对齐"到"代码审查"的构建链。

## 包含的 Skills

| Skill | 作用 | 触发场景 |
|---|---|---|
| `dev-router` | 工作流路由器，判断你处于哪个阶段并分发到正确 skill | 不确定下一步该干嘛、"帮我选流程" |
| `grill-with-docs` | 对方案逐条拷问式对齐，同步沉淀术语与决策 | "拷问""对齐需求""帮我审方案" |
| `domain-modeling` | 主动构建/打磨领域模型，维护 CONTEXT.md 与 ADR | 敲定领域术语、记录架构决策 |
| `to-spec` | 把已达成共识综合为规格说明书 | "写 spec""整理成文档" |
| `to-tickets` | 把规格拆为示踪弹式垂直切片任务 | "拆任务""分 ticket" |
| `implement` | 按 spec/任务集驱动 TDD 构建、检查、审查、提交 | "开始实现""按 spec 开发" |
| `tdd` | 红-绿-重构循环，一次一个行为 | "tdd""先写测试" |
| `code-review` | 标准轴 + 规格轴双轴独立审查 | "code review""帮我看看代码" |

## 支持文件

- `skills/domain-modeling/ADR-FORMAT.md`、`CONTEXT-FORMAT.md`
- `skills/grill-with-docs/ADR-FORMAT.md`

均通过 SKILL.md 内的相对链接（`./ADR-FORMAT.md` 等）引用，目录整体打包后链接保持有效。

## 不含组件

- Commands：无
- Connector / MCP：无（纯本地 skill 插件）

## 来源（Provenance）

- 源目录：`D:\Users\hapicomputer\Desktop\工作空间2\skills开发\grill-me（s)`
- 打包方式：将源目录下 8 个 skill 文件夹整体复制至 `skills/`，SKILL.md 正文与支持文件原样保留，未改写实现内容。
- Logo：`assets/avatar.svg` 为本插件生成的占位图标（烤架 + 火焰），非第三方素材。

## 校验

- 通过 create-plugin 自带离线校验器 `validate_qoder_plugin.py` 检查（清单、组件路径、SKILL.md frontmatter）。
