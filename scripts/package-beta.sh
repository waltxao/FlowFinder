#!/bin/bash
set -euo pipefail

# ============================================================================
# FlowFinder Native — 测试版（Beta）打包脚本
# ============================================================================
# 与 scripts/package.sh 的区别：
#   1. 产物输出到 build-beta/，不污染正式版的 build/。
#   2. 产物名带 beta 标签（CFBundleShortVersionString 仍是 x.y.z）。
#   3. 不含公证流程（ad-hoc 签名，DMG 内附首次打开说明）。
#
# 版本号取自 Xcode 工程的 MARKETING_VERSION / CURRENT_PROJECT_VERSION，
# 见 scripts/lib-version.sh —— 不要在脚本里硬编码版本。
#
# 用法：
#   bash scripts/package-beta.sh
#   BETA_LABEL=beta.2 bash scripts/package-beta.sh       # 迭代第二个测试版
#   INSTALL=1 bash scripts/package-beta.sh               # 打包后安装到 /Applications
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
XCODEPROJ="$PROJECT_DIR/FlowFinder/FlowFinder.xcodeproj"
APP_NAME="FlowFinder"
DMG_NAME="FlowFinder"
SCHEME_NAME="FlowFinder"
TARGET_NAME="FlowFinder"
# Release 构建。此前因 Homebrew rustc fat LTO 的 LINKEDIT mis-aligned 无法出包，
# 临时降级为 Debug；该问题已在 rust-core/Cargo.toml 改 thin LTO + build-rust.sh
# 用 Xcode ld 重链接解决（2026-10-17），测试版恢复 Release 构建。
CONFIGURATION="Release"
BUILD_DIR="$PROJECT_DIR/build-beta"

# 版本号唯一真源：Xcode 工程 MARKETING_VERSION / CURRENT_PROJECT_VERSION
# beta 标签只用于产物文件名，不进入 CFBundleShortVersionString（必须 x.y.z）
# shellcheck source=scripts/lib-version.sh
source "$SCRIPT_DIR/lib-version.sh"
VERSION="$FF_VERSION"
BUILD_NUMBER="$FF_BUILD"
BETA_LABEL="${BETA_LABEL:-${FF_BETA_LABEL:-beta.1}}"
LABEL="$VERSION-$BETA_LABEL"

ENTITLEMENTS_PATH="$PROJECT_DIR/FlowFinder/FlowFinder/FlowFinder.entitlements"

TMP_DMG=""
STAGING_DIR=""

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
die()         { log_error "$1"; exit 1; }

cleanup() {
    local rc=$?
    [ -n "$TMP_DMG" ] && [ -f "$TMP_DMG" ] && rm -f "$TMP_DMG"
    [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ] && rm -rf "$STAGING_DIR"
    exit "$rc"
}
trap cleanup EXIT

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"

echo ""
echo "=== FlowFinder Native 测试版打包 ==="
echo "标签:   $LABEL"
echo "配置:   ${CONFIGURATION}（Release 通道在当前环境不可用，见脚本头注释）"
echo "Rust:   $(rustc --version 2>/dev/null || echo unknown)"
echo ""

# --- 环境检查 ---------------------------------------------------------------
[ -d "$XCODEPROJ" ] || die "Xcode 工程未找到: $XCODEPROJ"
command -v xcodebuild &>/dev/null || die "xcodebuild 未找到"
command -v hdiutil    &>/dev/null || die "hdiutil 未找到"
command -v codesign   &>/dev/null || die "codesign 未找到"
[ -f "$ENTITLEMENTS_PATH" ] || die "Entitlements 未找到: $ENTITLEMENTS_PATH"

if [ -z "${DEVELOPER_DIR:-}" ]; then
    XCODE_DEV_DIR="$(ls -d /Applications/Xcode*.app/Contents/Developer 2>/dev/null | head -1 || true)"
    [ -n "$XCODE_DEV_DIR" ] || die "未设置 DEVELOPER_DIR 且未在 /Applications 找到 Xcode.app"
    export DEVELOPER_DIR="$XCODE_DEV_DIR"
    log_warn "DEVELOPER_DIR 未设置，自动使用 $DEVELOPER_DIR"
fi

# --- scheme / target 探测（与 package.sh 一致：-target 模式不支持 -derivedDataPath）---
detect_build_selector() {
    local list_output
    list_output=$(xcodebuild -project "$XCODEPROJ" -list 2>&1) || { echo ""; return; }
    local schemes_section
    schemes_section=$(echo "$list_output" \
        | awk '/^[[:space:]]*Schemes:/{flag=1;next}flag&&/^[[:space:]]*$/{flag=0}flag')
    if echo "$schemes_section" | grep -qE "^[[:space:]]*${SCHEME_NAME}[[:space:]]*$"; then
        echo "scheme:${SCHEME_NAME}"; return
    fi
    local targets_section
    targets_section=$(echo "$list_output" \
        | awk '/^[[:space:]]*Targets:/{flag=1;next}flag&&/^[[:space:]]*$/{flag=0}flag')
    if echo "$targets_section" | grep -qE "^[[:space:]]*${TARGET_NAME}[[:space:]]*$"; then
        echo "target:${TARGET_NAME}"; return
    fi
    echo ""
}

SELECTOR=$(detect_build_selector)
[ -n "$SELECTOR" ] || die "无法在工程中找到 scheme 或 target: $SCHEME_NAME"
SELECTOR_KIND="${SELECTOR%%:*}"
SELECTOR_NAME="${SELECTOR#*:}"
log_success "使用 ${SELECTOR_KIND}: ${SELECTOR_NAME}"

if [ "$SELECTOR_KIND" = "scheme" ]; then
    XCODEBUILD_SELECTOR=(-scheme "$SELECTOR_NAME")
    DERIVED_DATA_ARGS=(-derivedDataPath "$BUILD_DIR/DerivedData")
else
    XCODEBUILD_SELECTOR=(-target "$SELECTOR_NAME")
    DERIVED_DATA_ARGS=(SYMROOT="$BUILD_DIR/DerivedData/Build/Products" OBJROOT="$BUILD_DIR/DerivedData/Build/Intermediates")
fi

# --- [1/5] 编译 Rust core（Debug）------------------------------------------
echo ""
echo "=== [1/5] 编译 Rust core（Debug）==="
bash "$SCRIPT_DIR/build-rust.sh" Debug

# --- [2/5] xcodebuild Debug ------------------------------------------------
echo ""
echo "=== [2/5] 编译 .app（${CONFIGURATION}）==="
log_info "清理旧产物: $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild \
    -project "$XCODEPROJ" \
    "${XCODEBUILD_SELECTOR[@]}" \
    -configuration "$CONFIGURATION" \
    "${DERIVED_DATA_ARGS[@]}" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_REQUIRED=NO \
    build 2>&1 | tail -25

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/$CONFIGURATION/$APP_NAME.app"
[ -d "$APP_PATH" ] || die ".app 未找到: $APP_PATH"
log_success ".app 生成: $APP_PATH"

# --- [3/5] 校验 bundle -----------------------------------------------------
echo ""
echo "=== [3/5] 校验 bundle 结构 ==="
for p in "可执行文件:$APP_PATH/Contents/MacOS/$APP_NAME" \
         "Rust dylib:$APP_PATH/Contents/Frameworks/libflowfinder_core.dylib" \
         "Info.plist:$APP_PATH/Contents/Info.plist"; do
    label="${p%%:*}"; path="${p#*:}"
    [ -e "$path" ] || die "缺失: $label ($path)"
    log_success "$label 存在"
done

# --- [4/5] 签名 ------------------------------------------------------------
echo ""
echo "=== [4/5] ad-hoc 签名（Hardened Runtime）==="
codesign --sign - --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS_PATH" "$APP_PATH"
codesign --verify --verbose=2 "$APP_PATH" || die "签名验证失败，已中止打包"
log_success "签名验证通过"

# --- [5/5] DMG / ZIP / checksum -------------------------------------------
echo ""
echo "=== [5/5] 生成 DMG / ZIP / checksum ==="

DMG_PATH="$BUILD_DIR/${DMG_NAME}-${LABEL}.dmg"
STAGING_DIR="$BUILD_DIR/dmg-staging"
TMP_DMG="$BUILD_DIR/tmp.dmg"

rm -rf "$STAGING_DIR"; mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -sf /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "$DMG_NAME $LABEL" -srcfolder "$STAGING_DIR" \
    -ov -fs HFS+ "$TMP_DMG" 2>&1 | tail -3
rm -f "$DMG_PATH"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 \
    -o "$DMG_PATH" 2>&1 | tail -3
rm -f "$TMP_DMG"; rm -rf "$STAGING_DIR"
TMP_DMG=""; STAGING_DIR=""

ZIP_PATH="$BUILD_DIR/${DMG_NAME}-${LABEL}.zip"
ZIP_STAGING="$BUILD_DIR/zip-staging"
rm -rf "$ZIP_STAGING"; mkdir -p "$ZIP_STAGING"
cp -R "$APP_PATH" "$ZIP_STAGING/${DMG_NAME}.app"
( cd "$ZIP_STAGING" && ditto -c -k --sequesterRsrc --keepParent "${DMG_NAME}.app" "$ZIP_PATH" )
rm -rf "$ZIP_STAGING"
[ -f "$ZIP_PATH" ] || die "ZIP 生成失败"

( cd "$BUILD_DIR" && shasum -a 256 "${DMG_NAME}-${LABEL}.dmg" "${DMG_NAME}-${LABEL}.zip" \
    > "${DMG_NAME}-${LABEL}.sha256" )

if [ "${INSTALL:-0}" = "1" ]; then
    log_info "安装到 /Applications ..."
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_PATH" "/Applications/$APP_NAME.app"
    log_success "已安装 /Applications/$APP_NAME.app"
fi

echo ""
echo "=== 测试版打包完成 ==="
echo "DMG:      $DMG_PATH"
echo "ZIP:      $ZIP_PATH"
echo "SHA256:   $BUILD_DIR/${DMG_NAME}-${LABEL}.sha256"
echo "版本:     $VERSION ($BUILD_NUMBER) / $CONFIGURATION / ad-hoc 签名"
echo "提示:     首次打开需右键 -> 打开（未公证）"
echo ""
