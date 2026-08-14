# 开发者文档

FlowFinder 原生 macOS 文件管理器开发指南。项目结构见 [README](../README.md)。

## 环境要求

- macOS 13+（Apple Silicon）
- Xcode（含 Command Line Tools；`xcodebuild` 需完整 Xcode，路径如 `/Applications/Xcode*.app/Contents/Developer`）
- Rust stable（`cargo`）
- 依赖安装：`make setup`

## 构建

```bash
# 构建全部（Rust Core + Swift）
make build

# 仅 Rust Core
make rust

# 仅 Swift（SwiftPM 开发构建）
make swift

# Release 打包（DMG，走 scripts/package.sh）
bash scripts/package.sh
```

## 测试

```bash
# 全部测试（Rust + Swift XCTest + 集成）
make test

# Rust 单元测试
make rust-test

# Swift XCTest（必须经 xcodebuild；SwiftPM 无 testTarget）
make swift-test

# 集成测试（Rust FFI C/Swift 冒烟）
make integration-test
```

`make swift-test` 会自动定位 `/Applications/Xcode*.app/Contents/Developer`，
等价手动命令：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
    -project FlowFinderNative/FlowFinderNative.xcodeproj \
    -scheme FlowFinderNativeTests \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

## 常用目标

| 命令 | 说明 |
|---|---|
| `make run` | 构建并启动调试版 |
| `make xcode` | 在 Xcode 中打开工程 |
| `make release` | Release 模式构建 |
| `make clean` | 清理构建产物 |
| `make help` | 查看全部目标 |

## 目录结构

```
rust-core/        Rust 核心（FFI cdylib）
FlowFinderNative/ Swift Xcode 工程（AppKit UI + Bridge + Model）
docs/             文档
scripts/          构建/打包/基准脚本
```

## 发布流程

见 [MIGRATION_LOG.md](./MIGRATION_LOG.md) 与 `scripts/package.sh`。发布涉及
Developer ID 签名与公证，需在 CI/发布机配置凭据。
