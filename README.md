# FlowFinder Native

Swift & AppKit native UI + Rust core engine via FFI.

## Architecture

```
+--------------------------------------------------+
|  Swift / AppKit UI Layer                         |
|  - NSTableView, NSSplitView, NSMenu              |
|  - Quick Look (QLPreviewPanel)                   |
|  - Spotlight Search (SpotlightBridge)            |
|  - Drag & Drop (NSDraggingDestination)           |
+--------------------------------------------------+
                        |
                        | FFI (C ABI)
                        v
+--------------------------------------------------+
|  Rust Core Engine                                |
|  - bulk_read: getattrlistbulk(2) single syscall  |
|  - scanner: FileEntrySkeleton + metadata          |
|  - dedup_engine: 3-phase MD5/BLAKE3 dedup        |
|  - cow_copy: APFS copy-on-write clones           |
|  - dir_cache: LRU metadata cache                 |
|  - path_guard: Absolute path validation          |
+--------------------------------------------------+
```

## Requirements

- macOS 13.0+
- Xcode 15+
- Rust 1.75+
- Swift 5.9+

## Build Instructions

### Quick Start

```bash
# Clone the repository
git clone <repo-url>
cd flowfinder-native

# Setup environment (installs dependencies)
make setup

# Build everything (Rust core + Swift project)
make build
```

### Manual Build

```bash
# Build Rust core library
cd rust-core
cargo build

# Build Swift project
cd ../FlowFinderNative
swift build
```

### Release Build

```bash
make release
```

## Test Instructions

### Run All Tests

```bash
make test
```

### Run Rust Unit Tests

```bash
make rust-test
# or
cd rust-core && cargo test
```

### Run Swift Unit Tests

```bash
make swift-test
```

### Run Integration Tests

```bash
make integration-test
```

### Run Performance Benchmarks

```bash
bash scripts/benchmark.sh
```

## Performance

| Metric | Tauri Version | Native Version | Improvement |
|--------|--------------|----------------|-------------|
| Directory listing (cold) | ~15-30 ms | ~0.5-1.0 ms | **10-30x** |
| Directory listing (warm) | ~5-10 ms | ~0.2-0.5 ms | **10-20x** |
| Memory footprint | ~50-100 MB | ~20-30 MB | **2-3x** |
| Startup time | ~2-3s | ~0.5s | **4-6x** |
| Binary size | ~80-100 MB | ~15-20 MB | **5-6x** |

### Benchmark Results

Run `scripts/benchmark.sh` for live performance comparison against `ls` and `find`.

Example output:

```
Benchmark: /tmp
  Entries found: 12
  Rust FFI ff_list_dir:  0.523 ms (avg over 10 runs)
  ls -la:                2.145 ms (avg over 10 runs)
  find:                  3.012 ms (avg over 10 runs)
  Rust FFI vs ls:   4.10x faster
  Rust FFI vs find: 5.76x faster
```

## Project Structure

```
flowfinder-native/
├── rust-core/          # Rust core library (cdylib)
│   ├── src/
│   │   ├── lib.rs
│   │   ├── ffi/
│   │   │   └── mod.rs          # FFI export layer
│   │   └── core/
│   │       ├── mod.rs
│   │       ├── bulk_read.rs    # getattrlistbulk directory listing
│   │       ├── scanner.rs      # FileEntrySkeleton + metadata
│   │       ├── dedup_engine.rs # 3-phase duplicate detection
│   │       ├── cow_copy.rs     # APFS copy-on-write
│   │       ├── dir_cache.rs    # LRU metadata cache
│   │       ├── path_guard.rs   # Path validation
│   │       └── utils.rs
│   ├── Cargo.toml
│   └── include/
│       └── ff_ffi.h            # C header for FFI
├── FlowFinderNative/   # Swift Xcode project
│   ├── FlowFinderNative/
│   │   ├── App/
│   │   │   ├── AppDelegate.swift
│   │   │   └── FlowFinderApp.swift
│   │   ├── Bridge/
│   │   │   ├── CoreBridge.swift
│   │   │   └── FFIFunctions.swift
│   │   ├── Model/
│   │   │   ├── FileEntry.swift
│   │   │   └── FileEntryViewModel.swift
│   │   ├── UI/
│   │   │   ├── ContentView.swift
│   │   │   ├── FileListView.swift
│   │   │   ├── MainWindowController.swift
│   │   │   └── SidebarView.swift
│   │   └── Resources/
│   │       └── Info.plist
│   ├── Tests/
│   │   └── FlowFinderNativeTests/
│   │       └── FlowFinderNativeTests.swift
│   └── Package.swift
├── scripts/
│   ├── build-rust.sh       # Rust build script
│   ├── integration-test.sh  # Integration test suite
│   ├── setup.sh             # Environment setup
│   └── benchmark.sh         # Performance benchmark
├── docs/
│   └── VERIFICATION.md    # Verification checklist
├── Makefile
└── README.md
```

## License

MIT

---

## Roadmap

### 项目总览

FlowFinder Native 将原 Tauri 应用中的 **10 个核心功能模块** 迁移到 Native 架构。POC（子项目 #0）已完成，剩余 **9 个子项目** 待实现。

```
Phase 1 (MVP)        Phase 2 (增强)        Phase 3 (完善)        Phase 4 (收尾)
├─ #1 文件操作        ├─ #2 重复检测         ├─ #7 缩略图           ├─ #10 卷管理
├─ #3 搜索过滤        ├─ #5 目录缓存         ├─ #8 设置配置
└─ #4 QuickLook      └─ #6 批量重命名        └─ #9 任务调度
```

### 子项目状态

| # | 子项目 | 优先级 | 状态 | 依赖 | 估计工时 |
|---|--------|--------|------|------|---------|
| 0 | **POC: 基础框架** | — | ✅ 完成 | — | 已完成 |
| 1 | **文件操作** (Copy/Move/Delete) | P0 | ⏳ 待开始 | #0 | 3 天 |
| 2 | **重复文件检测** | P0 | ⏳ 待开始 | #0, #1 | 4 天 |
| 3 | **文件搜索与过滤** | P0 | ⏳ 待开始 | #0 | 3 天 |
| 4 | **文件预览 (QuickLook)** | P0 | ⏳ 待开始 | #0 | 2 天 |
| 5 | **目录缓存与 FSEvents** | P1 | ⏳ 待开始 | #0, #3 | 3 天 |
| 6 | **批量重命名与整理** | P1 | ⏳ 待开始 | #0, #1 | 3 天 |
| 7 | **缩略图生成** | P1 | ⏳ 待开始 | #0, #3 | 4 天 |
| 8 | **设置与配置** | P2 | ⏳ 待开始 | #0, #5 | 2 天 |
| 9 | **任务调度器** | P2 | ⏳ 待开始 | #0, #1, #6 | 3 天 |
| 10 | **卷管理与健康检查** | P2 | ⏳ 待开始 | #0, #5 | 2 天 |

### 优先级定义

- **P0 (Critical)**: 核心功能，无此功能应用不可用。MVP 阶段必须完成。
- **P1 (High)**: 重要功能，显著提升用户体验。P0 完成后立即开始。
- **P2 (Medium)**: 增强功能，可延后实现。P1 完成后安排。

### 时间表

| 阶段 | 时间 | 交付子项目 |
|------|------|-----------|
| **Phase 1: MVP** | 第 1-2 周 | #1 文件操作, #3 搜索过滤, #4 QuickLook |
| **Phase 2: 增强** | 第 3-4 周 | #2 重复检测, #5 目录缓存, #6 批量重命名 |
| **Phase 3: 完善** | 第 5-6 周 | #7 缩略图, #8 设置, #9 任务调度 |
| **Phase 4: 收尾** | 第 7 周 | #10 卷管理 |
| **Phase 5: 稳定** | 第 8 周 | 全面测试、优化、发布准备 |

### 依赖关系

```
POC #0 (基础框架)
    │
    ├──► #1 文件操作 ─────┬──► #2 重复检测
    │                     │
    ├──► #3 搜索过滤 ─────┼──► #5 目录缓存/FSEvents
    │                     │         │
    ├──► #4 QuickLook ────┤         ├──► #8 设置配置
    │                     │         │
    │                     └──► #6 批量重命名 ──► #9 任务调度
    │
    └──► #7 缩略图

#10 卷管理 (依赖 #5)
```

### 相关文档

- [迁移计划](docs/MIGRATION_PLAN.md) — 详细的 9 个子项目迁移计划
- [子项目模板](docs/SUBPROJECT_TEMPLATE.md) — 创建子项目 Issue 的模板
- [验证清单](docs/VERIFICATION.md) — POC 验证结果和测试报告
