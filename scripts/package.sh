#!/bin/bash
set -euo pipefail

# ============================================================================
# FlowFinder Native — Release Build & DMG Packaging Script
# ============================================================================
# Builds the Release .app bundle via xcodebuild, signs it (ad-hoc by default
# or with a Developer ID if DEVELOPER_ID is set), then produces a
# distributable .dmg via hdiutil.
#
# Usage:
#   ./scripts/package.sh                     # ad-hoc signed DMG
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/package.sh
# ============================================================================

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
XCODEPROJ="$PROJECT_DIR/FlowFinderNative/FlowFinderNative.xcodeproj"
APP_NAME="FlowFinderNative"
DMG_NAME="FlowFinder"
SCHEME_NAME="FlowFinderNative"
TARGET_NAME="FlowFinderNative"
CONFIGURATION="Release"
BUILD_DIR="$PROJECT_DIR/build"
VERSION="0.6.02"
BUILD_NUMBER="602"

# Optional Developer ID signing (set via environment)
DEVELOPER_ID="${DEVELOPER_ID:-}"

# Entitlements file — applied at codesign time (Hardened Runtime requires it
# to whitelist the self-built Rust dylib and unsigned-executable-memory usage).
ENTITLEMENTS_PATH="$PROJECT_DIR/FlowFinderNative/FlowFinderNative/FlowFinderNative.entitlements"

# Temp paths (populated later, declared here so trap can read them safely)
TMP_DMG=""
STAGING_DIR=""

# Colors for output (consistent with build-rust.sh / setup.sh)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
die()         { log_error "$1"; exit 1; }

# ---------------------------------------------------------------------------
# Cleanup trap — remove temp DMG & staging dir on exit (success or failure)
# ---------------------------------------------------------------------------

cleanup() {
    local rc=$?
    if [ -n "$TMP_DMG" ] && [ -f "$TMP_DMG" ]; then
        rm -f "$TMP_DMG"
    fi
    if [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ]; then
        rm -rf "$STAGING_DIR"
    fi
    exit "$rc"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

echo ""
echo "=== FlowFinder Native 打包脚本 ==="
echo "版本: $VERSION ($BUILD_NUMBER)"
echo "配置: $CONFIGURATION"
if [ -n "$DEVELOPER_ID" ]; then
    echo "签名: Developer ID ($DEVELOPER_ID)"
else
    echo "签名: ad-hoc（本地分发）"
fi
echo ""

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------

if [ ! -d "$XCODEPROJ" ]; then
    die "Xcode project not found: $XCODEPROJ"
fi
if ! command -v xcodebuild &> /dev/null; then
    die "xcodebuild not found. Install Xcode or Xcode Command Line Tools."
fi
if ! command -v hdiutil &> /dev/null; then
    die "hdiutil not found (macOS only)."
fi
if ! command -v codesign &> /dev/null; then
    die "codesign not found (macOS only)."
fi
if [ ! -f "$ENTITLEMENTS_PATH" ]; then
    die "Entitlements file not found: $ENTITLEMENTS_PATH"
fi

# ---------------------------------------------------------------------------
# Scheme / target detection
# ---------------------------------------------------------------------------
# The .xcscheme physical file may not exist in the project (xcschemes/ only
# contains xcschememanagement.plist). Try -scheme first; if xcodebuild -list
# does not list the scheme, fall back to -target which always works against
# the PBXNativeTarget defined in project.pbxproj.
# ---------------------------------------------------------------------------

detect_build_selector() {
    # Echoes either "scheme:<name>" or "target:<name>" or empty on failure.
    # Sections in `xcodebuild -list` are separated by blank lines; we capture
    # lines after the section header until the next blank line. POSIX character
    # classes are used for BSD awk compatibility on macOS.
    local list_output
    if ! list_output=$(xcodebuild -project "$XCODEPROJ" -list 2>&1); then
        echo ""
        return
    fi

    # Parse "Schemes:" section for our scheme name.
    local schemes_section
    schemes_section=$(echo "$list_output" \
        | awk '/^[[:space:]]*Schemes:/{flag=1;next}flag&&/^[[:space:]]*$/{flag=0}flag')
    if echo "$schemes_section" | grep -qE "^[[:space:]]*${SCHEME_NAME}[[:space:]]*$"; then
        echo "scheme:${SCHEME_NAME}"
        return
    fi

    # Parse "Targets:" section for our target name.
    local targets_section
    targets_section=$(echo "$list_output" \
        | awk '/^[[:space:]]*Targets:/{flag=1;next}flag&&/^[[:space:]]*$/{flag=0}flag')
    if echo "$targets_section" | grep -qE "^[[:space:]]*${TARGET_NAME}[[:space:]]*$"; then
        echo "target:${TARGET_NAME}"
        return
    fi

    echo ""
}

log_info "检测 Xcode scheme/target..."
SELECTOR=$(detect_build_selector)
if [ -z "$SELECTOR" ]; then
    die "无法在项目中找到 scheme 或 target: $SCHEME_NAME"
fi

SELECTOR_KIND="${SELECTOR%%:*}"
SELECTOR_NAME="${SELECTOR#*:}"
log_success "使用 ${SELECTOR_KIND}: ${SELECTOR_NAME}"

# Build the xcodebuild selector args
if [ "$SELECTOR_KIND" = "scheme" ]; then
    XCODEBUILD_SELECTOR=(-scheme "$SELECTOR_NAME")
else
    XCODEBUILD_SELECTOR=(-target "$SELECTOR_NAME")
fi

# ---------------------------------------------------------------------------
# [1/4] Clean & build Release
# ---------------------------------------------------------------------------

echo ""
echo "=== [1/4] 编译 Release ==="

log_info "清理旧产物: $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

log_info "运行 xcodebuild (Rust core 由 build phase 自动编译)..."
xcodebuild \
    -project "$XCODEPROJ" \
    "${XCODEBUILD_SELECTOR[@]}" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build 2>&1 | tail -30

# ---------------------------------------------------------------------------
# Locate & verify .app bundle
# ---------------------------------------------------------------------------

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    die ".app 未找到: $APP_PATH"
fi

# ---------------------------------------------------------------------------
# [2/4] Verify .app bundle structure
# ---------------------------------------------------------------------------

echo ""
echo "=== [2/4] 验证 .app bundle ==="
echo "路径: $APP_PATH"

verify_path() {
    local label="$1"
    local p="$2"
    if [ ! -e "$p" ]; then
        die "缺失: $label ($p)"
    fi
    ls -la "$p"
}

verify_path "可执行文件"       "$APP_PATH/Contents/MacOS/$APP_NAME"
verify_path "Rust dylib"      "$APP_PATH/Contents/Frameworks/libflowfinder_core.dylib"
verify_path "Info.plist"      "$APP_PATH/Contents/Info.plist"

log_success "Bundle 结构完整"

# ---------------------------------------------------------------------------
# [3/4] Code signing
# ---------------------------------------------------------------------------

echo ""
echo "=== [3/4] 代码签名 ==="

if [ -n "$DEVELOPER_ID" ]; then
    log_info "使用 Developer ID 签名 (Hardened Runtime): $DEVELOPER_ID"
    codesign --sign "$DEVELOPER_ID" --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS_PATH" "$APP_PATH"
else
    log_info "Ad-hoc 签名 (Hardened Runtime，本地分发，用户首次打开需右键 -> 打开)"
    codesign --sign - --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS_PATH" "$APP_PATH"
fi

log_info "验证签名..."
if codesign --verify --verbose=2 "$APP_PATH" 2>&1 | tail -5; then
    log_success "签名验证通过"
else
    log_warn "签名验证返回非零状态（可能仍可本地运行）"
fi

# ---------------------------------------------------------------------------
# [4/4] Create DMG
# ---------------------------------------------------------------------------

echo ""
echo "=== [4/4] 创建 DMG ==="

DMG_PATH="$BUILD_DIR/${DMG_NAME}-${VERSION}.dmg"
STAGING_DIR="$BUILD_DIR/dmg-staging"
TMP_DMG="$BUILD_DIR/tmp.dmg"

log_info "准备 staging 目录: $STAGING_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -sf /Applications "$STAGING_DIR/Applications"

log_info "创建临时 DMG (HFS+)..."
hdiutil create \
    -volname "$DMG_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -fs HFS+ \
    "$TMP_DMG" 2>&1 | tail -5

log_info "转换为压缩 DMG (UDZO, zlib-level=9)..."
rm -f "$DMG_PATH"
hdiutil convert \
    "$TMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" 2>&1 | tail -5

# Staging cleanup happens in trap as well, but clean now for tidy output.
rm -f "$TMP_DMG"
rm -rf "$STAGING_DIR"
TMP_DMG=""
STAGING_DIR=""

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo ""
echo "=== 打包完成 ==="
echo "DMG: $DMG_PATH"
if [ -f "$DMG_PATH" ]; then
    du -h "$DMG_PATH"
    log_success "FlowFinder $VERSION 打包成功"
else
    die "DMG 未生成: $DMG_PATH"
fi
echo ""
