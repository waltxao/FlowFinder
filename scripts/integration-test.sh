#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FlowFinder Native — Integration Test Script
# ============================================================================
# Verifies:
#   1. Rust library compiles
#   2. Swift can load the library
#   3. ff_list_dir returns valid data
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/rust-core"
SWIFT_DIR="$PROJECT_ROOT/FlowFinderNative"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }

print_header() {
    echo ""
    echo "========================================"
    echo "  $1"
    echo "========================================"
}

# ---------------------------------------------------------------------------
# Test 1: Rust library compiles
# ---------------------------------------------------------------------------

test_rust_compiles() {
    print_header "Test 1: Rust Library Compilation"

    cd "$RUST_DIR"

    if cargo build 2>&1; then
        log_success "Rust library compiled successfully"
        ((PASS++))
    else
        log_fail "Rust library compilation failed"
        ((FAIL++))
        return 1
    fi

    # Verify the library was created
    DYLIB_PATH="$RUST_DIR/target/debug/libflowfinder_core.dylib"
    if [[ -f "$DYLIB_PATH" ]]; then
        log_success "Dynamic library found: $DYLIB_PATH"
    else
        log_fail "Dynamic library not found at: $DYLIB_PATH"
        ((FAIL++))
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Test 2: Swift can load the library
# ---------------------------------------------------------------------------

test_swift_loads_library() {
    print_header "Test 2: Swift Library Loading"

    # Build Rust first
    cd "$RUST_DIR"
    cargo build --quiet 2>&1 || true

    # Create a temporary Swift test file
    TEST_SWIFT="$PROJECT_ROOT/.tmp_test_swift.swift"
    mkdir -p "$(dirname "$TEST_SWIFT")"

    cat > "$TEST_SWIFT" << 'EOF'
import Foundation
import Darwin

// Test that we can reference the C functions from the header
// This is a compile-time test
print("Swift test: Checking library loading...")

// Try to load the dylib
let dylibPath = "./rust-core/target/debug/libflowfinder_core.dylib"
let expandedPath = (dylibPath as NSString).expandingTildeInPath

if FileManager.default.fileExists(atPath: expandedPath) {
    print("Library file exists: \(expandedPath)")
    
    // Try to open the dylib
    let handle = dlopen(expandedPath, RTLD_LAZY)
    if handle != nil {
        print("Library loaded successfully")
        dlclose(handle)
        exit(0)
    } else {
        let error = String(cString: dlerror())
        print("Failed to load library: \(error)")
        exit(1)
    }
} else {
    print("Library file not found: \(expandedPath)")
    exit(1)
}
EOF

    cd "$PROJECT_ROOT"
    if swift "$TEST_SWIFT" 2>&1; then
        log_success "Swift can load the Rust library"
        ((PASS++))
    else
        log_fail "Swift failed to load the Rust library"
        ((FAIL++))
    fi

    rm -f "$TEST_SWIFT"
}

# ---------------------------------------------------------------------------
# Test 3: ff_list_dir returns valid data
# ---------------------------------------------------------------------------

test_ff_list_dir() {
    print_header "Test 3: ff_list_dir FFI Function"

    # Build Rust first
    cd "$RUST_DIR"
    cargo build --quiet 2>&1 || true

    # Create a C test program
    TEST_C="$PROJECT_ROOT/.tmp_test_ff_list_dir.c"
    cat > "$TEST_C" << 'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ff_ffi.h"

static int entry_count = 0;

void callback(const FFEntryRef *entry, void *user_data) {
    entry_count++;
    printf("Entry: %s (size: %llu)\n", entry->name, (unsigned long long)entry->size);
}

int main(int argc, char *argv[]) {
    const char *path = ".";
    if (argc > 1) {
        path = argv[1];
    }

    printf("Testing ff_list_dir on: %s\n", path);
    
    ff_error_t result = ff_list_dir(path, callback, NULL);
    
    if (result == FF_OK) {
        printf("SUCCESS: ff_list_dir returned %d entries\n", entry_count);
        return 0;
    } else {
        char *err = ff_last_error();
        printf("FAILED: ff_list_dir returned error %d: %s\n", result, err ? err : "unknown");
        if (err) ff_free_string(err);
        return 1;
    }
}
EOF

    cd "$PROJECT_ROOT"
    
    # Compile the test program
    DYLIB_PATH="$RUST_DIR/target/debug/libflowfinder_core.dylib"
    HEADER_DIR="$RUST_DIR/include"
    
    if clang -o ".tmp_test_ff_list_dir" "$TEST_C" -I"$HEADER_DIR" -L"$RUST_DIR/target/debug" -lflowfinder_core -Wl,-rpath,"$RUST_DIR/target/debug" 2>&1; then
        log_info "Test program compiled successfully"
        
        export DYLD_LIBRARY_PATH="$RUST_DIR/target/debug:${DYLD_LIBRARY_PATH:-}"
        if ./.tmp_test_ff_list_dir 2>&1; then
            log_success "ff_list_dir returns valid data"
            ((PASS++))
        else
            log_fail "ff_list_dir failed to return valid data"
            ((FAIL++))
        fi
    else
        log_fail "Failed to compile test program"
        ((FAIL++))
    fi

    rm -f "$TEST_C" ".tmp_test_ff_list_dir"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo ""
echo "========================================"
echo "  FlowFinder Native — Integration Tests"
echo "========================================"

# Run tests
test_rust_compiles
test_swift_loads_library
test_ff_list_dir

# Print summary
echo ""
echo "========================================"
echo "  Test Summary"
echo "========================================"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "========================================"

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
