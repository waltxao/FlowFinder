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
