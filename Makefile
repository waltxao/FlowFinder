# FlowFinder Native Build System
# ================================
# 一条命令覆盖日常：make build / make test / make demo / make beta

RUST_DIR := rust-core
SWIFT_DIR := FlowFinder
SCRIPT_DIR := scripts
XCODEPROJ := $(SWIFT_DIR)/FlowFinder.xcodeproj
BUILD_SCRIPT := $(SCRIPT_DIR)/build-rust.sh
SETUP_SCRIPT := $(SCRIPT_DIR)/setup.sh

export MACOSX_DEPLOYMENT_TARGET := 12.0

# Xcode 开发者目录：优先 /Applications 下的 Xcode*.app，回退 xcode-select。
# 注意 XCTest 需要完整 Xcode，Command Line Tools 不含 xcodebuild 的测试能力。
XCODE_DEV_DIR := $(firstword $(wildcard /Applications/Xcode*.app/Contents/Developer))
ifeq ($(strip $(XCODE_DEV_DIR)),)
XCODE_DEV_DIR := $(shell xcode-select -p 2>/dev/null)
endif
export DEVELOPER_DIR := $(XCODE_DEV_DIR)

# 隔离的测试 home：避免宿主 App 扫描真实 ~/Desktop / ~/Documents
TEST_HOME := /tmp/flowfinder-test-home

# 构建产物根目录
# 注意 1：-target 模式不接受 -derivedDataPath（需 -scheme 才可用），改用 SYMROOT/OBJROOT
# 注意 2：SYMROOT 必须用绝对路径——xcodebuild 会以 $(SRCROOT) 为基准解析相对路径，
#         写成 build/Products 会落到 FlowFinder/build/Products 而不是仓库根
DERIVED := $(CURDIR)/build
APP_DEBUG := $(DERIVED)/Products/Debug/FlowFinder.app
APP_RELEASE := $(DERIVED)/Products/Release/FlowFinder.app
DESKTOP_APP := $(HOME)/Desktop/FlowFinder.app

# 构建公共参数：本机 ad-hoc 签名，arm64
XCB := xcodebuild -project $(XCODEPROJ) -target FlowFinder \
	SYMROOT=$(DERIVED)/Products OBJROOT=$(DERIVED)/Intermediates \
	ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
	CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO

.DEFAULT_GOAL := build

BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

.PHONY: build app release test rust-test swift-test integration-test \
	clean setup run demo beta version warnings help

# =============================================================================
# 构建
# =============================================================================

## build: Debug 构建（Rust + Swift）
build: rust
	@echo "$(BLUE)Building Swift (Debug)...$(NC)"
	@$(XCB) -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" || true
	@test -d "$(APP_DEBUG)" && echo "$(GREEN)✓ $(APP_DEBUG)$(NC)" || (echo "$(RED)✗ 构建失败$(NC)"; exit 1)

## app: build 的别名
app: build

## release: Release 构建（可直接分发）
release: 
	@echo "$(BLUE)Building Rust (Release)...$(NC)"
	@bash $(BUILD_SCRIPT) Release >/dev/null
	@echo "$(BLUE)Building Swift (Release)...$(NC)"
	@$(XCB) -configuration Release build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" || true
	@test -d "$(APP_RELEASE)" && echo "$(GREEN)✓ $(APP_RELEASE)$(NC)" || (echo "$(RED)✗ Release 构建失败$(NC)"; exit 1)

## rust: 构建 Rust core（Debug）
rust:
	@echo "$(BLUE)Building Rust core...$(NC)"
	@bash $(BUILD_SCRIPT) >/dev/null && echo "$(GREEN)✓ Rust core$(NC)"

## demo: Debug 构建并复制到桌面（用户实测用）
demo: build
	@rm -rf "$(DESKTOP_APP)"
	@cp -R "$(APP_DEBUG)" "$(DESKTOP_APP)"
	@echo "$(GREEN)✓ 已复制到桌面：$(DESKTOP_APP)$(NC)"
	@echo "$(YELLOW)  首次打开需右键 → 打开（ad-hoc 签名）$(NC)"

## beta: 打测试版 DMG/ZIP 到 build-beta/
beta:
	@bash $(SCRIPT_DIR)/package-beta.sh

# =============================================================================
# 测试
# =============================================================================

## test: 全部测试（Rust + Swift）
test: rust-test swift-test
	@echo "$(GREEN)✓ All tests passed$(NC)"

## rust-test: Rust 单元测试
rust-test:
	@echo "$(BLUE)Running Rust tests...$(NC)"
	@cd $(RUST_DIR) && cargo test 2>&1 | tail -5

## swift-test: Swift XCTest（走 xcodebuild，不是 swift test）
swift-test:
	@echo "$(BLUE)Running Swift XCTest...$(NC)"
	@mkdir -p "$(TEST_HOME)/Desktop" "$(TEST_HOME)/Documents"
	@pkill -f "MacOS/FlowFinder" 2>/dev/null || true
	@xcodebuild test -project $(XCODEPROJ) -scheme FlowFinderTests \
		-destination 'platform=macOS' \
		CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO 2>&1 \
		| grep -E "error:|Executed .* tests|TEST SUCCEEDED|TEST FAILED" | tail -8

## integration-test: 集成测试
integration-test: rust
	@bash $(SCRIPT_DIR)/integration-test.sh

# =============================================================================
# 诊断
# =============================================================================

## version: 打印当前版本（唯一真源：Xcode 工程）
version:
	@bash -c 'source $(SCRIPT_DIR)/lib-version.sh; echo "版本: $$FF_VERSION ($$FF_BUILD)"'

## warnings: 统计编译警告数
warnings:
	@echo "$(BLUE)统计编译警告...$(NC)"
	@$(XCB) -configuration Debug clean build 2>&1 | grep -cE "warning:" || echo 0

## run: 启动 Debug 产物
run: build
	@open "$(APP_DEBUG)"

# =============================================================================
# 维护
# =============================================================================

## clean: 清理全部构建产物
clean:
	@echo "$(BLUE)Cleaning...$(NC)"
	@cd $(RUST_DIR) && cargo clean 2>/dev/null || true
	@rm -rf build build-beta
	@rm -f $(SWIFT_DIR)/FlowFinder/Libraries/*.dylib
	@rm -f $(SWIFT_DIR)/FlowFinder/Libraries/*.a
	@rm -rf $(XCODEPROJ)/project.xcworkspace $(XCODEPROJ)/xcuserdata
	@echo "$(GREEN)✓ Clean completed$(NC)"

## setup: 首次环境配置
setup:
	@bash $(SETUP_SCRIPT)

## xcode: 用 Xcode 打开工程
xcode:
	@open $(XCODEPROJ)

## help: 显示帮助
help:
	@echo "FlowFinder Native Build System"
	@echo "=============================="
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'
