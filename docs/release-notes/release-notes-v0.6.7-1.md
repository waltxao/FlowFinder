# FlowFinder Native v0.6.7-1 (671)

**发布日期：** 2026-07-29
**版本：** 0.6.7.1 (671)
**分支：** main

---

## 本次发布概述

v0.6.7-1 是 v0.6.7 的紧急修复版本，针对全应用 UI 重设计后发现的 34 个代码质量问题进行一次性修复，涵盖关键崩溃、内存安全、代码重复和错误处理四大类。

## 修复分类

### 关键崩溃修复 (6 项)

- **[CR-1]** `FFGlassView.swift`：移除 `generateNoiseImage()` 中的强制解包（`cgImage!`），改为安全守卫返回纯白回退图像
- **[CR-2]** `CoreBridge.swift`：移除 `populateCache()` 中 `buffer.baseAddress!` 强制解包，改用 `guard let` 安全解包
- **[CR-3]** `CoreBridge.swift`：FFI 回调闭包添加缺失的 `return` 语句，避免未定义行为
- **[CR-4]** `FFGlassView.swift`：`NSImage` 闭包添加 `return true`，修复 `missing return in closure expected to return 'Bool'`
- **[CR-5]** `FileGridView.swift`：将 `as!` 强制类型转换替换为 `as?` + 安全守卫
- **[CR-6]** `CoreBridge.swift`：`volumeInfoCallback` 修复 `userData` 内存绑定逻辑错误

### 内存安全修复 (8 项)

- **[MEM-1]** `CoreBridge.swift`：`ThreadSafeFFIResult<T>` 线程安全包装器，保护 FFI 结果的并发读写
- **[MEM-2]** `CoreBridge.swift`：`FSEventsContext` 使用 `final class` 持有闭包，防止回调期间被释放
- **[MEM-3]** `CoreBridge.swift`：`ProgressBox` 堆分配闭包盒子，支持 `@convention(c)` FFI 回调跨线程恢复
- **[MEM-4]** `CoreBridge.swift`：`populateCache` 中所有 `strdup` 分配的 C 字符串在使用后通过 `free()` 释放
- **[MEM-5]** `CoreBridge.swift`：`EntryCollectorContext` 等回调上下文使用栈分配 + `withUnsafeMutablePointer`，避免手动内存管理
- **[MEM-6]** `CoreBridge.swift`：`ff_cache_put` 调用后立即释放临时分配的 `FFEntryRef` 数组
- **[MEM-7]** `FFGlassView.swift`：`FFGlassNoise` 全局共享噪声纹理，避免每实例重复生成 CGImage
- **[MEM-8]** `FFGlassView.swift`：`allInstances` 使用 `NSHashTable.weakObjects()` 弱引用跟踪，防止内存泄漏

### 代码重复消除 (10 项)

- **[DUP-1]** 新建 `FFLog.swift`：统一日志工具（`FFLog.debug/info/warning/error`），基于 `os_log` 封装，替换散布各文件的 `print()` 和 `NSLog()`
- **[DUP-2]** 新建 `FFCommon.swift`：共享常量与工具函数（通知名称、共享尺寸、颜色辅助等）
- **[DUP-3]** `FFGlassView.swift`：移除重复的 `OSLog` 扩展，统一使用 `FFLog.glass`
- **[DUP-4]** `FFGlassView.swift`：移除重复的 `Notification.Name` 扩展，统一使用 `FFCommon` 中的定义
- **[DUP-5]** `FileGridView.swift`：移除重复的类型检查逻辑，使用共享工具函数
- **[DUP-6]** `CoreBridge.swift`：移除重复的错误处理模式，统一使用 `CoreBridgeError` 枚举
- **[DUP-7]** `FFLog.swift`：统一 `OSLog` 分类（ui/bridge/thumbnail/theme/task/glass），消除各文件自定义 category
- **[DUP-8]** `FFLog.swift`：修复 `OSLog` 无 `.general` / `.theme` 成员的问题，使用 `.default` 和自定义实例
- **[DUP-9]** `FFGlassView.swift`：合并重复的 `highlightPath` / `makeHighlightLayer` 逻辑
- **[DUP-10]** `CoreBridge.swift`：合并重复的回调上下文结构体定义

### 错误处理改进 (10 项)

- **[ERR-1]** `CoreBridge.swift`：`CoreBridgeError` 枚举实现 `LocalizedError`，提供人类可读错误描述
- **[ERR-2]** `CoreBridge.swift`：`listDirectory` 添加路径存在性验证和空路径守卫
- **[ERR-3]** `CoreBridge.swift`：FFI 调用使用串行队列 + 信号量确保线程安全
- **[ERR-4]** `CoreBridge.swift`：`populateCache` 实现最佳努力策略，缓存写入失败不影响目录列表功能
- **[ERR-5]** `CoreBridge.swift`：所有 FFI 回调添加 `guard let` 守卫，防止空指针解引用
- **[ERR-6]** `FFGlassView.swift`：`generateNoiseImage` 添加 CIFilter 可用性检查和回退路径
- **[ERR-7]** `FFGlassView.swift`：`setupPanelGlass` 使用 `material ?? .headerView` 默认值回退
- **[ERR-8]** `FFLog.swift`：`debug` 方法使用 `#if DEBUG` 条件编译，Release 构建零开销
- **[ERR-9]** `CoreBridge.swift`：FFI 回调上下文使用 `assumingMemoryBound` 前添加 `guard` 守卫
- **[ERR-10]** `FFGlassView.swift`：`panelInstanceCount` 超预算时仅 DEBUG 构建输出警告

## 构建验证

```
Rust Core:  cargo build --release  → SUCCESS (8 warnings, 0 errors)
Xcode:      xcodebuild -configuration Release  → BUILD SUCCEEDED
```

构建产物验证：
- `CFBundleShortVersionString` = 0.6.7.1
- `CFBundleVersion` = 671
- 代码签名：Sign to Run Locally
- 架构：arm64

## 系统要求

- macOS 13.0+（Apple Silicon）
- 建议 macOS 14.0+ 以获得完整视觉体验

## 下载

| 文件 | 大小 | 说明 |
|------|------|------|
| `FlowFinderNative-v0.6.7-1-mac.dmg` | 3.6 MB | DMG 安装镜像 |
| `FlowFinderNative-v0.6.7-1-mac.zip` | 3.1 MB | ZIP 压缩包（含 .app） |

## 从 v0.6.7 升级

直接替换 `/Applications/FlowFinderNative.app` 即可，用户数据和设置不受影响。
