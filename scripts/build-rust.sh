#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FlowFinder Native — Rust Core Build Script
# ============================================================================
# Detects build mode (Debug/Release), runs cargo build, copies the resulting
# .dylib to the appropriate location, and handles errors gracefully.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_DIR="$PROJECT_ROOT/rust-core"
OUTPUT_DIR="$PROJECT_ROOT/FlowFinderNative/FlowFinderNative/Libraries"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

die() {
    log_error "$1"
    exit 1
}

# ---------------------------------------------------------------------------
# Detect build mode
# ---------------------------------------------------------------------------

BUILD_MODE="${1:-Debug}"

if [[ "$BUILD_MODE" == "Release" || "$BUILD_MODE" == "release" ]]; then
    CARGO_FLAG="--release"
    BUILD_PROFILE="release"
    log_info "Building in Release mode..."
else
    CARGO_FLAG=""
    BUILD_PROFILE="debug"
    log_info "Building in Debug mode..."
fi

# ---------------------------------------------------------------------------
# Verify environment
# ---------------------------------------------------------------------------

# Cargo may not be in PATH when invoked from Xcode build phases (sanitized
# environment). Fall back to common install locations.
if ! command -v cargo &> /dev/null; then
    for _candidate in /opt/homebrew/bin /usr/local/bin "$HOME/.cargo/bin"; do
        if [[ -x "$_candidate/cargo" ]]; then
            export PATH="$_candidate:$PATH"
            break
        fi
    done
fi

if ! command -v cargo &> /dev/null; then
    die "Rust/Cargo not found. Please install Rust: https://rustup.rs"
fi

RUST_VERSION=$(rustc --version 2>/dev/null || echo "unknown")
log_info "Rust version: $RUST_VERSION"

if [[ ! -d "$RUST_DIR" ]]; then
    die "Rust core directory not found: $RUST_DIR"
fi

if [[ ! -f "$RUST_DIR/Cargo.toml" ]]; then
    die "Cargo.toml not found in: $RUST_DIR"
fi

# ---------------------------------------------------------------------------
# Determine target architecture
# ---------------------------------------------------------------------------

ARCH=$(uname -m)
TARGET=""
if [[ "$ARCH" == "arm64" ]]; then
    TARGET="aarch64-apple-darwin"
    log_info "Target architecture: Apple Silicon (arm64)"
elif [[ "$ARCH" == "x86_64" ]]; then
    TARGET="x86_64-apple-darwin"
    log_info "Target architecture: Intel (x86_64)"
else
    log_warn "Unknown architecture: $ARCH, using default target"
    TARGET=""
fi

# ---------------------------------------------------------------------------
# Build Rust core
# ---------------------------------------------------------------------------

cd "$RUST_DIR"

if [[ -n "$TARGET" ]]; then
    log_info "Running: cargo build $CARGO_FLAG --target $TARGET"
    if ! cargo build $CARGO_FLAG --target "$TARGET"; then
        die "Cargo build failed for target $TARGET"
    fi
    BUILD_TARGET_DIR="target/$TARGET/$BUILD_PROFILE"
else
    log_info "Running: cargo build $CARGO_FLAG"
    if ! cargo build $CARGO_FLAG; then
        die "Cargo build failed"
    fi
    BUILD_TARGET_DIR="target/$BUILD_PROFILE"
fi

log_success "Rust build completed successfully"

# ---------------------------------------------------------------------------
# Find and copy the built library
# ---------------------------------------------------------------------------

DYLIB_NAME="libflowfinder_core.dylib"
STATICLIB_NAME="libflowfinder_core.a"

DYLIB_PATH="$RUST_DIR/$BUILD_TARGET_DIR/$DYLIB_NAME"
STATICLIB_PATH="$RUST_DIR/$BUILD_TARGET_DIR/$STATICLIB_NAME"

if [[ ! -f "$DYLIB_PATH" ]]; then
    die "Built library not found: $DYLIB_PATH"
fi

log_info "Found library: $DYLIB_PATH"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Relink dylib from static library using Xcode ld
# ---------------------------------------------------------------------------
# Rust's default linker (rust-lld) produces dylibs with a mis-aligned LINKEDIT
# string pool that Xcode 27 beta's ld rejects with "mis-aligned LINKEDIT string
# pool" when linking the final .app. Using RUSTFLAGS to switch to Xcode ld
# breaks proc-macro dylibs (dlopen rejects them). The workaround: build
# normally with rust-lld (proc-macros work), then relink the final dylib from
# the static library (.a) using Xcode ld, which produces properly-aligned
# output. The static library contains all object files; -force_load ensures
# every object is included so all ff_* FFI symbols are exported.
if [[ ! -f "$STATICLIB_PATH" ]]; then
    die "Static library not found for relink: $STATICLIB_PATH"
fi

# Detect macOS deployment target & sysroot for the relink
RELINK_ARCH="$ARCH"  # arm64 or x86_64
RELINK_SYSROOT=""
RELINK_LD="ld"
if command -v xcrun &> /dev/null; then
    RELINK_SYSROOT="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
    RELINK_LD="$(xcrun -find ld 2>/dev/null || echo ld)"
fi
if [[ -z "$RELINK_SYSROOT" ]]; then
    log_warn "Could not determine macOS sysroot; relink may fail"
fi

log_info "Relinking dylib from static library using Xcode ld ($RELINK_LD)..."
RELINK_LDFLAGS=(
    -arch "$RELINK_ARCH"
    -dylib
    -platform_version macos 26.0 27.0
    -install_name @rpath/libflowfinder_core.dylib
    -compatibility_version 0.0.0
    -current_version 0.0.0
    -force_load "$STATICLIB_PATH"
    -liconv
    -framework CoreFoundation
    -lSystem
)
if [[ -n "$RELINK_SYSROOT" ]]; then
    RELINK_LDFLAGS+=(-syslibroot "$RELINK_SYSROOT")
fi

# Relink: suppress "was built for newer macOS" warnings (harmless for our use
# case); capture real errors. Fall back to the rust-lld dylib if relink fails.
RELINK_OUTPUT=$("$RELINK_LD" "${RELINK_LDFLAGS[@]}" -o "$OUTPUT_DIR/$DYLIB_NAME" 2>&1 || true)
if echo "$RELINK_OUTPUT" | grep -qiE "error|undefined symbol"; then
    log_warn "Xcode ld relink had errors:"
    echo "$RELINK_OUTPUT" | grep -iE "error|undefined" | head -10 >&2
    log_warn "Falling back to copied dylib (may hit LINKEDIT alignment issues)"
    if ! cp "$DYLIB_PATH" "$OUTPUT_DIR/"; then
        die "Failed to copy $DYLIB_NAME (fallback)"
    fi
elif [[ -f "$OUTPUT_DIR/$DYLIB_NAME" ]]; then
    log_success "Relinked dylib from static library"
else
    die "Relink produced no output and no error was detected"
fi

# Copy static library (optional, useful for debugging)
if cp "$STATICLIB_PATH" "$OUTPUT_DIR/" 2>/dev/null; then
    log_success "Copied $STATICLIB_NAME to $OUTPUT_DIR"
else
    log_warn "Failed to copy static library (non-fatal)"
fi

# ---------------------------------------------------------------------------
# Set library permissions and codesign (for macOS)
# ---------------------------------------------------------------------------

chmod +x "$OUTPUT_DIR/$DYLIB_NAME"

if command -v codesign &> /dev/null; then
    log_info "Codesigning library..."
    if codesign --sign - --force "$OUTPUT_DIR/$DYLIB_NAME" 2>/dev/null; then
        log_success "Library codesigned successfully"
    else
        log_warn "Codesigning failed (non-fatal, may work without it)"
    fi
fi

# ---------------------------------------------------------------------------
# Verify the library
# ---------------------------------------------------------------------------

if file "$OUTPUT_DIR/$DYLIB_NAME" | grep -q "Mach-O"; then
    log_success "Library verification: valid Mach-O dynamic library"
else
    log_warn "Library verification: may not be a valid Mach-O file"
fi

# ---------------------------------------------------------------------------
# Print summary
# ---------------------------------------------------------------------------

echo ""
echo "========================================"
echo "  Build Summary"
echo "========================================"
echo "  Mode:        $BUILD_MODE"
echo "  Profile:     $BUILD_PROFILE"
echo "  Target:      ${TARGET:-default}"
echo "  Output:      $OUTPUT_DIR/$DYLIB_NAME"
echo "  Size:        $(du -h "$OUTPUT_DIR/$DYLIB_NAME" | cut -f1)"
echo "========================================"
echo ""

log_success "Rust core build completed successfully!"
exit 0
