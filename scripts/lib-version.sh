#!/bin/bash
# ============================================================================
# 版本号单一真源读取器
# ============================================================================
# 唯一真源是 Xcode 工程的 MARKETING_VERSION / CURRENT_PROJECT_VERSION
# （即 FlowFinder.xcodeproj/project.pbxproj）。理由：
#   - Xcode 图形界面改的就是这里，不需要人肉同步第二份
#   - Info.plist 里 CFBundleShortVersionString = $(MARKETING_VERSION)，
#     关于页读 Bundle，天然跟随
#   - 打包脚本从 xcodebuild 读取，不再硬编码
#
# 用法：
#   source scripts/lib-version.sh
#   echo "$FF_VERSION ($FF_BUILD)"   # 0.8.0 (8000)
# ============================================================================

FF_PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FF_XCODEPROJ="$FF_PROJECT_DIR/FlowFinder/FlowFinder.xcodeproj"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

_ff_read_settings() {
    xcodebuild -project "$FF_XCODEPROJ" \
        -target FlowFinder \
        -configuration Release \
        -showBuildSettings 2>/dev/null
}

# 优先走 xcodebuild（最准确，含 xcconfig/pbxproj 全部继承链）
if command -v xcodebuild >/dev/null 2>&1; then
    _FF_SETTINGS="$(_ff_read_settings)"
    FF_VERSION="$(echo "$_FF_SETTINGS" | awk -F' = ' '/^[[:space:]]+MARKETING_VERSION = /{print $2; exit}' | tr -d '[:space:]')"
    FF_BUILD="$(echo "$_FF_SETTINGS" | awk -F' = ' '/^[[:space:]]+CURRENT_PROJECT_VERSION = /{print $2; exit}' | tr -d '[:space:]')"
    unset _FF_SETTINGS
fi

# 兜底：直接解析 pbxproj（xcodebuild 不可用时）
if [[ -z "${FF_VERSION:-}" ]]; then
    FF_VERSION="$(grep -m1 'MARKETING_VERSION = ' "$FF_XCODEPROJ/project.pbxproj" | sed 's/.*= \(.*\);/\1/' | tr -d '[:space:]')"
fi
if [[ -z "${FF_BUILD:-}" ]]; then
    FF_BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION = ' "$FF_XCODEPROJ/project.pbxproj" | sed 's/.*= \(.*\);/\1/' | tr -d '[:space:]')"
fi

if [[ -z "$FF_VERSION" || -z "$FF_BUILD" ]]; then
    echo "[ERROR] 无法读取版本号：$FF_XCODEPROJ/project.pbxproj" >&2
    return 1 2>/dev/null || exit 1
fi

# beta 标签只影响产物文件名，不影响 CFBundleShortVersionString（必须 x.y.z）
FF_BETA_LABEL="${FF_BETA_LABEL:-}"

export FF_VERSION FF_BUILD FF_BETA_LABEL FF_PROJECT_DIR
