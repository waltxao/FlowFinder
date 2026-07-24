# FlowFinder Native Build System
# ================================

# Configuration
RUST_DIR := rust-core
SWIFT_DIR := FlowFinderNative
SCRIPT_DIR := scripts
BUILD_SCRIPT := $(SCRIPT_DIR)/build-rust.sh
SETUP_SCRIPT := $(SCRIPT_DIR)/setup.sh

# macOS deployment target (minimum supported macOS version)
export MACOSX_DEPLOYMENT_TARGET := 12.0

# Default target
.DEFAULT_GOAL := build

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

# =============================================================================
# Main targets
# =============================================================================

.PHONY: build test clean setup rust swift integration-test help

## build: Build both Rust core and Swift project
build: rust swift
	@echo "$(GREEN)✓ Build completed successfully$(NC)"

## rust: Build the Rust core library
rust:
	@echo "$(BLUE)Building Rust core...$(NC)"
	@bash $(BUILD_SCRIPT)

## swift: Build the Swift project
swift:
	@echo "$(BLUE)Building Swift project...$(NC)"
	@cd $(SWIFT_DIR) && swift build

## test: Run all tests (Rust + Swift + Integration)
test: rust-test swift-test integration-test
	@echo "$(GREEN)✓ All tests passed$(NC)"

## rust-test: Run Rust unit tests
rust-test:
	@echo "$(BLUE)Running Rust tests...$(NC)"
	@cd $(RUST_DIR) && cargo test

## swift-test: Run Swift unit tests
swift-test:
	@echo "$(BLUE)Running Swift tests...$(NC)"
	@cd $(SWIFT_DIR) && swift test

## integration-test: Run integration tests
integration-test: rust
	@echo "$(BLUE)Running integration tests...$(NC)"
	@bash $(SCRIPT_DIR)/integration-test.sh

## clean: Remove all build artifacts
clean:
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	@cd $(RUST_DIR) && cargo clean 2>/dev/null || true
	@cd $(SWIFT_DIR) && swift package clean 2>/dev/null || true
	@rm -rf $(SWIFT_DIR)/Libraries/*.dylib
	@rm -rf $(SWIFT_DIR)/Libraries/*.a
	@rm -rf $(SWIFT_DIR)/.build
	@rm -rf $(SWIFT_DIR)/FlowFinderNative.xcodeproj/project.xcworkspace
	@rm -rf $(SWIFT_DIR)/FlowFinderNative.xcodeproj/xcuserdata
	@echo "$(GREEN)✓ Clean completed$(NC)"

## setup: Run initial environment setup
setup:
	@echo "$(BLUE)Running setup...$(NC)"
	@bash $(SETUP_SCRIPT)

## release: Build everything in release mode
release:
	@echo "$(BLUE)Building Release mode...$(NC)"
	@bash $(BUILD_SCRIPT) Release
	@cd $(SWIFT_DIR) && swift build -c release
	@echo "$(GREEN)✓ Release build completed$(NC)"

## xcode: Open the project in Xcode
xcode:
	@open $(SWIFT_DIR)/FlowFinderNative.xcodeproj

## help: Show this help message
help:
	@echo "FlowFinder Native Build System"
	@echo "=============================="
	@echo ""
	@echo "Available targets:"
	@echo "  $(GREEN)build$(NC)            - Build both Rust and Swift"
	@echo "  $(GREEN)rust$(NC)             - Build Rust core library"
	@echo "  $(GREEN)swift$(NC)            - Build Swift project"
	@echo "  $(GREEN)test$(NC)             - Run all tests (Rust + Swift + Integration)"
	@echo "  $(GREEN)rust-test$(NC)        - Run Rust unit tests"
	@echo "  $(GREEN)swift-test$(NC)       - Run Swift unit tests"
	@echo "  $(GREEN)integration-test$(NC) - Run integration tests"
	@echo "  $(GREEN)clean$(NC)            - Remove all build artifacts"
	@echo "  $(GREEN)setup$(NC)            - Run initial environment setup"
	@echo "  $(GREEN)release$(NC)          - Build everything in release mode"
	@echo "  $(GREEN)xcode$(NC)            - Open project in Xcode"
	@echo "  $(GREEN)help$(NC)             - Show this help message"
