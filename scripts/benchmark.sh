#!/usr/bin/env bash
# ============================================================================
# FlowFinder Native — Performance Benchmark Script
# ============================================================================
# Compares Rust FFI `ff_list_dir` against native `ls` and `find` commands.
# Runs 10 iterations and calculates average time.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/rust-core"
BUILD_DIR="$RUST_DIR/target/debug"
HEADER_DIR="$RUST_DIR/include"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

BOLD='\033[1m'

ITERATIONS=10

# Test directories
TEST_DIRS=("/tmp" "/usr/local")

# Large test directory (create if needed)
LARGE_DIR="/tmp/ff_benchmark_large"

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}===================================="
    echo "  $1"
    echo -e "====================================${NC}"
}

# ---------------------------------------------------------------------------
# Build the benchmark C program
# ---------------------------------------------------------------------------

build_benchmark() {
    log_info "Building benchmark program..."

    cat > "$PROJECT_ROOT/.tmp_benchmark.c" << 'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include "ff_ffi.h"

static int entry_count = 0;
static int total_size = 0;

void callback(const FFEntryRef *entry, void *user_data) {
    entry_count++;
    total_size += entry->size;
}

static double get_time_ms() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <directory>\n", argv[0]);
        return 1;
    }

    const char *path = argv[1];
    int iterations = 1;
    if (argc > 2) {
        iterations = atoi(argv[2]);
        if (iterations < 1) iterations = 1;
    }

    double total_time = 0.0;
    int total_entries = 0;

    for (int i = 0; i < iterations; i++) {
        entry_count = 0;
        total_size = 0;

        double start = get_time_ms();
        ff_error_t result = ff_list_dir(path, callback, NULL);
        double end = get_time_ms();

        if (result != FF_OK) {
            fprintf(stderr, "ff_list_dir failed for %s\n", path);
            return 1;
        }

        double elapsed = end - start;
        total_time += elapsed;
        total_entries += entry_count;
    }

    double avg_time = total_time / iterations;
    int avg_entries = total_entries / iterations;

    printf("%.3f,%d,%.3f\n", avg_time, avg_entries, total_time);

    return 0;
}
EOF

    cd "$PROJECT_ROOT"
    if ! clang -O2 -o ".tmp_benchmark" ".tmp_benchmark.c" -I"$HEADER_DIR" -L"$BUILD_DIR" -lflowfinder_core -Wl,-rpath,"$BUILD_DIR" 2>&1; then
        log_error "Failed to compile benchmark program"
        exit 1
    fi

    log_success "Benchmark program built successfully"
}

# ---------------------------------------------------------------------------
# Create large test directory
# ---------------------------------------------------------------------------

setup_large_dir() {
    if [[ -d "$LARGE_DIR" ]]; then
        log_info "Using existing large test directory: $LARGE_DIR"
        return 0
    fi

    log_info "Creating large test directory with 1000 files..."
    mkdir -p "$LARGE_DIR"

    # Create files with different sizes
    for i in $(seq 1 500); do
        dd if=/dev/zero of="$LARGE_DIR/file_${i}.txt" bs=1024 count=$((RANDOM % 100 + 1)) 2>/dev/null
    done

    # Create subdirectories with files
    for d in $(seq 1 20); do
        mkdir -p "$LARGE_DIR/subdir_$d"
        for f in $(seq 1 25); do
            dd if=/dev/zero of="$LARGE_DIR/subdir_$d/nested_${f}.bin" bs=1024 count=$((RANDOM % 50 + 1)) 2>/dev/null
        done
    done

    log_success "Large test directory created: $LARGE_DIR"
}

# ---------------------------------------------------------------------------
# Run benchmark for a single directory
# ---------------------------------------------------------------------------

run_benchmark() {
    local dir="$1"
    local label="$2"

    print_header "Benchmark: $label ($dir)"

    # --- Rust FFI benchmark ---
    log_info "Running Rust FFI ff_list_dir ($ITERATIONS iterations)..."
    export DYLD_LIBRARY_PATH="$BUILD_DIR:${DYLD_LIBRARY_PATH:-}"
    local ffi_result
    ffi_result=$("$PROJECT_ROOT/.tmp_benchmark" "$dir" "$ITERATIONS")
    local ffi_avg_time=$(echo "$ffi_result" | cut -d',' -f1)
    local ffi_entries=$(echo "$ffi_result" | cut -d',' -f2)
    local ffi_total_time=$(echo "$ffi_result" | cut -d',' -f3)

    # --- ls benchmark ---
    log_info "Running ls -la ($ITERATIONS iterations)..."
    local ls_total=0
    for i in $(seq 1 $ITERATIONS); do
        local start end elapsed
        start=$(python3 -c "import time; print(time.time() * 1000)")
        ls -la "$dir" >/dev/null 2>&1
        end=$(python3 -c "import time; print(time.time() * 1000)")
        elapsed=$(python3 -c "print($end - $start)")
        ls_total=$(python3 -c "print($ls_total + $elapsed)")
    done
    local ls_avg=$(python3 -c "print($ls_total / $ITERATIONS)")

    # --- find benchmark ---
    log_info "Running find ($ITERATIONS iterations)..."
    local find_total=0
    for i in $(seq 1 $ITERATIONS); do
        local start end elapsed
        start=$(python3 -c "import time; print(time.time() * 1000)")
        find "$dir" -maxdepth 1 >/dev/null 2>&1
        end=$(python3 -c "import time; print(time.time() * 1000)")
        elapsed=$(python3 -c "print($end - $start)")
        find_total=$(python3 -c "print($find_total + $elapsed)")
    done
    local find_avg=$(python3 -c "print($find_total / $ITERATIONS)")

    # --- Print results ---
    echo ""
    echo -e "${BOLD}Results for $label:${NC}"
    echo "  Directory: $dir"
    echo "  Entries found: $ffi_entries"
    echo ""
    echo -e "  ${GREEN}Rust FFI ff_list_dir:${NC}  ${ffi_avg_time} ms (avg over $ITERATIONS runs)"
    echo -e "  ${YELLOW}ls -la:${NC}                ${ls_avg} ms (avg over $ITERATIONS runs)"
    echo -e "  ${CYAN}find:${NC}                  ${find_avg} ms (avg over $ITERATIONS runs)"
    echo ""

    # Calculate ratios
    local ratio_ls=$(python3 -c "print('%.2f' % ($ffi_avg_time / $ls_avg))")
    local ratio_find=$(python3 -c "print('%.2f' % ($ffi_avg_time / $find_avg))")

    echo -e "  Rust FFI vs ls:    ${ratio_ls}x"
    echo -e "  Rust FFI vs find:  ${ratio_find}x"
    echo ""

    # Store results for summary
    echo "$label|$dir|$ffi_entries|$ffi_avg_time|$ls_avg|$find_avg|$ratio_ls|$ratio_find" >> "$PROJECT_ROOT/.benchmark_results.txt"
}

# ---------------------------------------------------------------------------
# Print summary
# ---------------------------------------------------------------------------

print_summary() {
    print_header "Benchmark Summary"

    if [[ ! -f "$PROJECT_ROOT/.benchmark_results.txt" ]]; then
        log_warn "No benchmark results found"
        return
    fi

    echo ""
    echo -e "${BOLD}%-20s %12s %12s %12s %10s %10s${NC}" "Directory" "Entries" "FFI (ms)" "ls (ms)" "find (ms)" "vs ls"
    echo "----------------------------------------------------------------------------------------------"

    while IFS='|' read -r label dir entries ffi ls find ratio_ls ratio_find; do
        printf "%-20s %12s %12s %12s %12s %10s\n" "$label" "$entries" "$ffi" "$ls" "$find" "${ratio_ls}x"
    done < "$PROJECT_ROOT/.benchmark_results.txt"

    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}${CYAN}=================================================="
echo "  FlowFinder Native — Performance Benchmark"
echo "==================================================${NC}"
echo ""

# Ensure Rust library is built
if [[ ! -f "$BUILD_DIR/libflowfinder_core.dylib" ]]; then
    log_info "Rust library not found, building..."
    cd "$RUST_DIR"
    cargo build --quiet
fi

# Clean up old results
rm -f "$PROJECT_ROOT/.benchmark_results.txt"

# Build benchmark program
build_benchmark

# Setup large directory
setup_large_dir

# Run benchmarks
for dir in "${TEST_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        run_benchmark "$dir" "$(basename "$dir")"
    else
        log_warn "Directory not found, skipping: $dir"
    fi
done

# Benchmark large directory
run_benchmark "$LARGE_DIR" "large_dir (1000+ files)"

# Print summary
print_summary

# Cleanup
rm -f "$PROJECT_ROOT/.tmp_benchmark.c" "$PROJECT_ROOT/.tmp_benchmark"

log_success "Benchmark completed!"
