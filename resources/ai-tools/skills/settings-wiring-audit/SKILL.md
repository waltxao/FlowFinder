---
name: settings-wiring-audit
description: "Read-only audit to verify whether settings, preferences, toggles, or configuration controls are actually wired to production code and change observable behavior. Use when asked whether a setting is unused, ignored, saved but never read, written only by the settings page, missing a bridge or FFI call, or when a feature looks dead; also use before releasing settings changes. Search both constant names and persisted string literals, exclude the settings UI as a consumer, trace notifications, computed properties, services and observers, distinguish an unused bridge from a dead feature, and close with behavior tests or minimal runtime evidence. 适用于设置项/开关不生效、配置空转、偏好未接线、设置页有控件但功能没反应的审计。Not for documentation-drift audits or visual QA."
---

# Settings Wiring Audit

## Overview

Determine whether every settings control has a complete, reachable path:

`control -> writer -> persisted key -> production reader -> indirect propagation -> observable effect`

Treat "no reader found" as a hypothesis until every representation of the key and every alternative implementation path has been checked.

## When to use

- 用户问“这个设置项/开关到底生效吗”“是不是只保存不生效”“设置页是不是空转”。
- 发布前检查新增或修改的偏好设置是否真正接入生产路径。
- 审计中发现某个 key 没有直接读取方，但尚不能确认功能死亡。
- 发现桥接函数或 FFI 符号没有调用方，需要判断是“桥接闲置”还是“功能不可用”。

## Do not use for

- 需求文档、验收文档与代码之间的漂移审计；使用 `requirement-docs-code-audit`。
- 纯视觉、布局或设计系统检查；使用 `design-review` 相关技能。
- 单点 bug 调试、性能分析、安全审计或普通代码审查。
- 仅要求解释某个设置项的实现，而不判断其有效性。

## Non-negotiables

1. Search every representation of the key: constant symbol, persisted literal, naming variants, config path, environment variable, and migration or fallback key. A zero-hit constant search is not evidence of missing wiring.
2. Never count the settings page itself as a production consumer. Reading a stored value to render a switch is not a behavior path.
3. Never infer that a feature is dead from one unused bridge or FFI symbol. Search for native implementations, service aggregators, producers, callbacks, dynamic dispatch, and user-reachable paths first.
4. Do not issue a "working" verdict from static references alone. Separate static wiring evidence from runtime effect evidence.
5. Stay read-only by default. Do not modify source, configuration, or user data. Obtain explicit permission before adding tests or changing code.
6. Support every verdict and every "not found" claim with `file:line` evidence and a coverage statement.

## Workflow

### 1. Frame the audit

- Identify the app, platform, version/build, target configuration, settings surfaces, and storage mechanism.
- Build the control list from the settings UI code and its backing model, not from stale documentation.
- Record evidence level for each finding: runtime verified, static complete, partial, or name match only.
- Note what is out of scope and which modules or runtime surfaces cannot be inspected.

### 2. Build the control-key inventory

- For each control, record its label, type, default, write API and call site, persisted key, and any migration or alias.
- Create a key-form matrix before searching: constant name, persisted literal, camelCase, snake_case, dotted form, plist or JSON path, and fallback key.
- Search all application targets, extensions, helpers, plugins, bridge layers, generated code, and startup paths. Treat tests, fixtures, previews, and documentation as evidence only, never as production consumers.
- Distinguish a visible control with a dead key from an orphan key with no UI. Both are gaps, but they require different remediation.

### 3. Find production readers

- Search every key representation across the whole repository, then read each hit instead of trusting match counts.
- Exclude settings-page rendering, default registration, migration writes, tests, samples, logs, and documentation from the consumer set.
- For each candidate reader, follow the value into a service, policy, view model, command, or other observable behavior.
- Mark "value is read but discarded" separately from "value is never read".

### 4. Trace indirect wiring

- Check notifications, KVO, Combine, delegates, event buses, computed properties, observers, dependency injection, environment objects, schedulers, app-launch hooks, and configuration reload paths.
- Build one end-to-end chain per consumer and cite `file:line` at every hop.
- Look for multiple keys controlling the same feature, compatibility aliases, fallback defaults, and key migrations.
- Do not stop at the first getter if its result only changes a local variable or an unused model field.

### 5. Test feature liveness

- When a bridge or FFI symbol has no direct caller, search wrapper layers, alternate native implementations, aggregator services, task schedulers, registration tables, callbacks, reflection or dynamic lookup, plugins, and remote paths.
- Identify the real producers and consumers of the feature. A task panel may aggregate tasks created by several service-layer operations even when a generic submit FFI is unused.
- Report `BRIDGE_UNUSED_NATIVE_OK` separately from `FEATURE_DEAD`. Do not collapse a symbol-level gap into a user-facing feature verdict.
- If the producer or consumer path remains unknown, record the exact unsearched surface and mark the result inconclusive.

### 6. Verify behavior

- Prefer existing automated tests that toggle the setting and assert an observable effect. Record the command, environment, and result.
- If no suitable test exists, use an isolated defaults suite, temporary config directory, or test profile. Compare default and toggled behavior, and verify persistence or relaunch behavior when the setting is startup-scoped.
- Use an observable result: UI state, policy decision, file operation, process or network effect, emitted event, or persisted state. A log line alone is weak evidence unless it represents the actual behavior.
- Restore any changed test state. Never write to production preferences or user data without permission.
- If runtime verification is impossible, report static evidence only and state the blocker.

### 7. Classify and report

- Fill the control matrix with evidence for each control.
- Add a coverage appendix listing searched key forms, roots, modules, exclusions, dynamic surfaces, and commands used.
- Recommend remediation only after the verdict. Separate quick wiring fixes from feature-level product decisions.

## Verdicts

| Verdict | Meaning | Minimum evidence |
|---|---|---|
| `WIRED_VERIFIED` | Control affects production behavior and the effect was observed. | Writer, production reader, reachable chain, runtime evidence |
| `WIRED_STATIC` | Complete source-level chain exists, but runtime behavior was not verified. | Writer, production reader, reachable chain with `file:line` |
| `ORPHAN_WRITE` | Key is written or registered but no production reader exists. | Exhaustive key-form search and exclusion list |
| `PARTIAL` | Some paths honor the setting while others ignore it. | Per-path evidence, including the ignored paths |
| `BRIDGE_UNUSED_NATIVE_OK` | Expected bridge or FFI call is absent, but another production path implements the feature. | Alternative implementation and user-reachable producer path |
| `FEATURE_DEAD` | The user-facing feature has no reachable producer or consumer path. | Feature-level search, including alternatives and runtime check |
| `INCONCLUSIVE` | Dynamic dispatch, generated code, or another unknown blocks a verdict. | Exact unknown surface and what evidence is still needed |

## Failure modes to prevent

| Trap | Required correction |
|---|---|
| Constant-name search returns zero hits, so the key is declared unused. | Search the persisted literal and naming variants; production code may bypass the constants file. |
| A generic FFI or bridge submit has no caller, so the whole feature is declared dead. | Search service aggregators and native implementations before judging the feature. |
| The settings page reads the value to render a switch, so it is counted as wired. | Require a production consumer outside the settings UI. |
| A test or sample app reads the key, so production is assumed to read it. | Classify tests as evidence only and verify the production target. |
| A getter exists, so the setting is assumed to work. | Follow the value into observable behavior and verify it at runtime when possible. |
| A key has no UI, so it is reported as a broken control. | Classify it as an orphan key and decide separately whether to add a control or remove the key. |

## Output contract

Produce a table with these columns:

`Control | Key forms | Default | Production reader | Indirect path | Reachability | Behavior evidence | Verdict | Next action`

Add a coverage appendix with:

- key forms and exact search terms;
- source roots, targets, and modules searched;
- excluded paths and reasons;
- dynamic, generated, or runtime surfaces not searched;
- tests or probes run, environment, and results;
- overall counts by verdict and the highest-risk gaps.

Use `assets/audit-report-template.md` when a reusable report file is useful.

## Resources

- Read `references/search-playbook.md` when building searches, handling a new stack, or investigating an unused bridge.
- Use `assets/audit-report-template.md` to structure the final audit without omitting coverage evidence.
