#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# FlowFinder Native — Environment Setup Script
# ============================================================================
# Performs initial environment setup for development.
# Run this once after cloning the repository.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
die() { log_error "$1"; exit 1; }

echo ""
echo "========================================"
echo "  FlowFinder Native — Setup"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Check macOS version
# ---------------------------------------------------------------------------

if [[ "$(uname)" != "Darwin" ]]; then
    die "This project requires macOS."
fi

MACOS_VERSION=$(sw_vers -productVersion)
log_info "macOS version: $MACOS_VERSION"

# ---------------------------------------------------------------------------
# Check Rust installation
# ---------------------------------------------------------------------------

log_info "Checking Rust installation..."

if ! command -v rustc &> /dev/null; then
    log_warn "Rust not found. Installing via rustup..."
    if ! command -v curl &> /dev/null; then
        die "curl is required to install Rust"
    fi
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    RUST_VERSION=$(rustc --version)
    log_success "Rust found: $RUST_VERSION"
fi

# Ensure cargo is available
if ! command -v cargo &> /dev/null; then
    die "cargo not found. Please ensure Rust is properly installed."
fi

# ---------------------------------------------------------------------------
# Check Swift installation
# ---------------------------------------------------------------------------

log_info "Checking Swift installation..."

if ! command -v swift &> /dev/null; then
    log_warn "Swift not found. Please install Xcode Command Line Tools:"
    log_warn "  xcode-select --install"
    die "Swift is required to build this project"
fi

SWIFT_VERSION=$(swift --version 2>/dev/null | head -n1 || echo "unknown")
log_success "Swift found: $SWIFT_VERSION"

# ---------------------------------------------------------------------------
# Check Xcode Command Line Tools
# ---------------------------------------------------------------------------

log_info "Checking Xcode Command Line Tools..."

if ! xcode-select -p &> /dev/null; then
    log_warn "Xcode Command Line Tools not found."
    log_warn "Please run: xcode-select --install"
    die "Xcode Command Line Tools are required"
fi

XCODE_PATH=$(xcode-select -p)
log_success "Xcode tools found: $XCODE_PATH"

# ---------------------------------------------------------------------------
# Verify project structure
# ---------------------------------------------------------------------------

log_info "Verifying project structure..."

REQUIRED_DIRS=(
    "$PROJECT_ROOT/rust-core"
    "$PROJECT_ROOT/FlowFinderNative"
    "$PROJECT_ROOT/scripts"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        die "Required directory missing: $dir"
    fi
done

log_success "Project structure verified"

# ---------------------------------------------------------------------------
# Create necessary directories
# ---------------------------------------------------------------------------

log_info "Creating necessary directories..."

mkdir -p "$PROJECT_ROOT/FlowFinderNative/Libraries"
mkdir -p "$PROJECT_ROOT/FlowFinderNative/FlowFinderNative/Libraries"

log_success "Directories created"

# ---------------------------------------------------------------------------
# Build Rust core for the first time
# ---------------------------------------------------------------------------

log_info "Building Rust core (first time)..."

cd "$PROJECT_ROOT/rust-core"
if ! cargo build; then
    die "Initial Rust build failed"
fi

log_success "Rust core built successfully"

# ---------------------------------------------------------------------------
# Run the build script
# ---------------------------------------------------------------------------

log_info "Running build-rust.sh..."

if bash "$PROJECT_ROOT/scripts/build-rust.sh" Debug; then
    log_success "Build script executed successfully"
else
    die "Build script failed"
fi

# ---------------------------------------------------------------------------
# Verify Swift Package Manager can resolve
# ---------------------------------------------------------------------------

log_info "Verifying Swift Package Manager..."

cd "$PROJECT_ROOT/FlowFinderNative"
if swift package resolve 2>/dev/null; then
    log_success "Swift Package Manager resolved successfully"
else
    log_warn "Swift Package Manager resolution had warnings (may be normal for first run)"
fi

# ---------------------------------------------------------------------------
# Print summary
# ---------------------------------------------------------------------------

echo ""
echo "========================================"
echo "  Setup Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Run 'make build' to build the project"
echo "  2. Run 'make test' to run all tests"
echo "  3. Open in Xcode: make xcode"
echo ""
echo "Project structure:"
echo "  $(basename "$PROJECT_ROOT")/"
echo "    ├── rust-core/          # Rust core library"
echo "    ├── FlowFinderNative/   # Swift project"
echo "    ├── scripts/            # Build scripts"
echo "    └── Makefile            # Build automation"
echo ""

log_success "Environment setup complete!"
exit 0
