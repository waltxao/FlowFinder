# T16 — 文档/版本/产品声明统一

状态：完成（直接实施，后台任务因模型配额取消）
日期：2026-08-14

## 改动清单
- CHANGELOG.md：补 [0.7.5](Unreleased)、[0.7.4]、[0.7.2] 条目（0.7.2 内容经 git log v0.6.7..v0.7.2 核实）
- rust-core/Cargo.toml + Cargo.lock：0.6.9 → 0.7.5（cargo build 验证通过）
- README.md：更新日志补 v0.7.5 开发中条目；手动构建改用 -target（无 app shared scheme）+ 推荐 package.sh；badge/下载表保留 0.7.4（已发布事实，未宣称 v0.7.5 已发布）
- Makefile：新增 run 目标（探测 SwiftPM 可执行产物，失败提示 make xcode）
- docs/DEVELOPMENT.md：新建（构建/测试/目录/发布流程）
- docs/HANDOVER.md：版本 0.6.9 → 0.7.4 已发布 + 0.7.5 开发中，日期更新
- docs/VERIFICATION.md：版本 0.1.0 → 0.7.5 开发中，测试数更新（Rust 202+、XCTest 65+），旧基线降为历史小节

## 验证
- 版本扫描：0.6.9 零残留（仅 CHANGELOG 历史条目）；0.7.4 仅存在于已发布事实引用（badge/下载表/历史条目）
- README 内部链接：docs/DEVELOPMENT.md、docs/MIGRATION_LOG.md、CHANGELOG.md 均存在
- cargo test --all-features：202 passed / 0 failed
- make 目标：build/clean/help/integration-test/release/run/rust/rust-test/setup/swift/swift-test/test/xcode

## 依赖与边界
- package.sh VERSION=0.7.4 留给 T17（发布脚本在 T17 范围）
- README badge/下载表在 T18 发布后由 T17/T18 更新为 0.7.5
