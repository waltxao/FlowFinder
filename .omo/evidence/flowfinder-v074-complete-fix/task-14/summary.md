# T14 — 超大模块行为覆盖后拆分

状态：完成（直接实施）
日期：2026-08-14

## 拆分清单
1. rust-core/src/ffi/mod.rs：4897 → 3119 行。1778 行测试模块拆出到 rust-core/src/ffi/tests.rs（mod.rs 加 #[cfg(test)] mod tests;）
2. UI/MainWindowController.swift：2678 → 1873 行。Menu Actions 扩展（803 行）拆出到 UI/MainWindowController+MenuActions.swift
3. 跨文件扩展可见性：private/fileprivate → internal（activePaneViewModel/showError/activePane/updateViewMode/clipboardItems/clipboardOperation/ClipboardOperation/sidebarView/fileInfoWindowController/refreshPane/leftPaneViewModel/rightPaneViewModel/ffUndoManager/taskProgressBar/taskProgressBarHeightConstraint + 8 个 @objc handleFileList* 方法）

## pbxproj 重建（T11 修改曾被 git checkout 误还原，本任务完整重建）
- test target FlowFinderNativeTests（productType bundle.unit-test、Sources/Frameworks phase、TEST_HOST/BUNDLE_LOADER、GENERATE_INFOPLIST_FILE、HEADER_SEARCH_PATHS、LD_RUNPATH）
- PBXContainerItemProxy/PBXTargetDependency（containerPortal=FF000060 PBXProject）
- Products group FF000062、app Frameworks phase FF000054
- ContentIndexBridge.swift + MainWindowController+MenuActions.swift 加入 app target（Bridge/UI group children）
- Build Rust Core / Copy Dylib shell phase 修复（install_name_tool -id @rpath + codesign --force --sign -）
- 测试 group path = Tests/FlowFinderNativeTests（与 xcodeproj 同级的物理位置）

## 验证
- cargo test --all-features：202 passed / 0 failed（Rust tests.rs 拆分后）
- xcodebuild test：70 tests / 0 failures（Swift 拆分 + pbxproj 重建后）
- plutil -lint pbxproj OK；xcodebuild -list 显示两个 target + FlowFinderNativeTests scheme
