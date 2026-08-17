# F1-F4 最终验证波次 — APPROVE

日期：2026-08-14（v0.7.5 发布后）

## F1 计划合规审计 — APPROVE
- v0.7.4 tag 未变（a58423b）；v0.7.5 新 tag 指向 4858225
- 无越界文件：v0.7.4..v0.7.5 diff 仅含 rust-core/、FlowFinderNative/、docs/、README、CHANGELOG、Makefile、scripts/、.github/、.omo/（编排证据）
- Must-NOT-HAVE：README 标注 AI 能力为「规划中」；无 SwiftUI 迁移（FlowFinderApp.swift 的 import SwiftUI 为 v0.7.4 遗留、无实际使用）

## F2 代码质量/安全 — APPROVE
- cargo clippy：无 error（127 warnings，构建通过）
- 超大文件复查：ffi/mod.rs 3121（含文档，tests 已拆出）、MainWindowController 1873（MenuActions 已拆出）、FileListView 2117 / SidebarView 1763 / ExpandableDetailsBar 1733 / PaneState 1253（T12-T13 已评估处理）
- FFI 符号三方对比：66 个导出函数与 ff_ffi.h 100% 一致（3 个 typedef 不导出，符合预期）

## F3 真实手工 QA — APPROVE
- AppKit 冒烟：Release app 启动存活 6s，无崩溃输出（crash/fatal/panic 计数 0）
- 打包产物：DMG 3.5MB / ZIP 3.5MB，sha256 -c 校验通过，codesign --verify 满足 Designated Requirement
- 双测试套件：cargo 202 passed / XCTest 70 passed

## F4 范围保真/发布审计 — APPROVE
- 工作区干净（push 后 git status 0 改动）
- 版本对齐修复：README badge/下载表 → 0.7.5、CHANGELOG [0.7.5] — 2026-08-14、docs/index.html 版本标签 → 0.7.5（commit e21e2db 已推送）
- Release 资产：FlowFinder-0.7.5.{dmg,zip,sha256} 全部上传
- v0.7.4 历史资产未变（FlowFinder-0.7.4.{dmg,zip}）
- Pages 下载按钮指向 /releases（自动展示最新版），无需 URL 变更

## 已知遗留（如实记录，不阻断发布）
1. 公证未完成：无 Developer ID/notarytool 凭据，产物为 ad-hoc 签名（Release notes 已声明；配置 secrets 后 tag 触发 release.yml 自动公证）
2. clippy 127 warnings：预存在风格级警告，无 error，未在本计划范围内
3. FlowFinderApp.swift 遗留 import SwiftUI：v0.7.4 已有、无实际使用
