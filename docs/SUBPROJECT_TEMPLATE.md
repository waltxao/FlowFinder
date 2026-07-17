# 子项目跟踪 Issue 模板

> 用于创建单个迁移子项目的跟踪 Issue。复制此模板并填写对应子项目信息。

---

## 基本信息

- **子项目编号**: #N
- **子项目名称**: [在此填写名称]
- **优先级**: [P0 / P1 / P2]
- **所属阶段**: [Phase 1 / Phase 2 / Phase 3 / Phase 4]
- **估计工时**: [X 天]
- **依赖子项目**: [列出依赖的 #编号]
- **负责人**: [待分配]

---

## 功能描述

### 目标
[用 2-3 句话描述此子项目的目标：实现什么功能，解决什么问题]

### 范围
- **包含**:
  - [列出明确包含的功能点]
- **不包含**:
  - [列出明确排除的功能点，避免范围蔓延]

### 验收标准
- [ ] 标准 1: [具体、可测试的验收条件]
- [ ] 标准 2: [具体、可测试的验收条件]
- [ ] 标准 3: [具体、可测试的验收条件]

---

## Rust Core 变更

### 新增 FFI 函数

```rust
// 函数 1: 功能描述
#[no_mangle]
pub extern "C" fn ff_xxx_xxx(
    // 参数列表
) -> c_int;

// 函数 2: 功能描述
#[no_mangle]
pub extern "C" fn ff_xxx_xxx(
    // 参数列表
) -> c_int;
```

### 新增 C 结构体

```c
typedef struct {
    // 字段定义
} FFXxxStruct;
```

### 新增回调类型

```c
typedef void (*FFXxxCallback)(
    const FFXxxStruct* data,
    void* user_data
);
```

### 修改的 Rust 模块
- [ ] `rust-core/src/core/xxx.rs` — [修改说明]
- [ ] `rust-core/src/ffi/mod.rs` — 添加 FFI 导出
- [ ] `rust-core/include/ff_ffi.h` — 更新 C 头文件

### 新增 Rust 模块
- [ ] `rust-core/src/core/xxx.rs` — [新模块功能描述]

---

## Swift UI 变更

### 新增 Swift 组件

| 组件名称 | 类型 | 职责 | 文件路径 |
|---------|------|------|---------|
| `XxxManager` | Manager | [职责描述] | `FlowFinderNative/Xxx/XxxManager.swift` |
| `XxxView` | NSView | [职责描述] | `FlowFinderNative/Xxx/XxxView.swift` |
| `XxxPanel` | NSPanel | [职责描述] | `FlowFinderNative/Xxx/XxxPanel.swift` |

### 修改的 Swift 组件
- [ ] `FlowFinderNative/Bridge/CoreBridge.swift` — [修改说明]
- [ ] `FlowFinderNative/Bridge/FFIFunctions.swift` — [修改说明]
- [ ] `FlowFinderNative/UI/MainWindowController.swift` — [修改说明]

---

## 数据模型

### 新增 Swift 模型

```swift
/// [模型描述]
public struct XxxModel: Identifiable, Equatable {
    public let id = UUID()
    // 属性定义
}
```

### FFI ↔ Swift 映射

| Rust 类型 | FFI 类型 | Swift 类型 |
|----------|---------|-----------|
| `rust_core::Xxx` | `FFXxx` | `XxxModel` |

---

## 测试计划

### Rust 单元测试

- [ ] 测试 1: [测试描述]
- [ ] 测试 2: [测试描述]
- [ ] 测试 3: [测试描述]

### Swift 单元测试

- [ ] 测试 1: [测试描述]
- [ ] 测试 2: [测试描述]
- [ ] 测试 3: [测试描述]

### 集成测试

- [ ] 测试 1: [测试描述]
- [ ] 测试 2: [测试描述]

### 性能基准测试

- [ ] 基准 1: [基准描述和预期指标]

---

## 实现步骤

### Step 1: Rust Core 实现
- [ ] 实现核心逻辑
- [ ] 添加 FFI 导出函数
- [ ] 更新 C 头文件
- [ ] 编写 Rust 单元测试
- [ ] 运行 `cargo test` 确保通过

### Step 2: Swift 桥接层
- [ ] 在 `FFIFunctions.swift` 声明新 FFI 函数
- [ ] 在 `CoreBridge.swift` 添加桥接方法
- [ ] 处理错误码和内存管理

### Step 3: Swift UI 实现
- [ ] 创建数据模型
- [ ] 实现 UI 组件
- [ ] 绑定 ViewModel
- [ ] 编写 Swift 单元测试

### Step 4: 集成与验证
- [ ] 运行 `make integration-test`
- [ ] 运行 `scripts/benchmark.sh`
- [ ] 更新 `docs/VERIFICATION.md`
- [ ] 代码审查

---

## 风险与问题

| 风险 | 影响 | 状态 | 缓解措施 |
|------|------|------|---------|
| [风险描述] | 高/中/低 | 开放/已缓解 | [措施] |

---

## 相关文档

- [MIGRATION_PLAN.md](MIGRATION_PLAN.md) — 总迁移计划
- [VERIFICATION.md](VERIFICATION.md) — 验证清单
- [README.md](../README.md) — 项目文档

---

## 进度跟踪

| 阶段 | 状态 | 完成日期 | 备注 |
|------|------|---------|------|
| 设计评审 | ⏳ 待开始 | — | — |
| Rust Core 实现 | ⏳ 待开始 | — | — |
| Swift 桥接层 | ⏳ 待开始 | — | — |
| Swift UI 实现 | ⏳ 待开始 | — | — |
| 单元测试 | ⏳ 待开始 | — | — |
| 集成测试 | ⏳ 待开始 | — | — |
| 代码审查 | ⏳ 待开始 | — | — |
| 合并到主分支 | ⏳ 待开始 | — | — |

---

## 备注

[任何额外的说明、参考链接、设计决策记录等]

---

*此 Issue 由 [MIGRATION_PLAN.md](MIGRATION_PLAN.md) 自动生成。创建后请根据实际子项目信息填写并跟踪进度。*
