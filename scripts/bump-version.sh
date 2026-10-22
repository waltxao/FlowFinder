#!/bin/bash
# ============================================================================
# 迭代构建号自动递增（版本命名规则 A.B.C-yymmddxx）
# ============================================================================
# 用户裁定（2026-10-21）：每次迭代构建都要更新内部版本号，形式 `A.B.C-yymmddxx`。
# 落到工程里的分工：
#   MARKETING_VERSION（CFBundleShortVersionString）= 纯 A.B.C，必须保持 x.y.z，
#     系统兼容性要求它不能带后缀，因此不改它。
#   CURRENT_PROJECT_VERSION（CFBundleVersion）= 8 位 yymmddxx，
#     yymmdd = 当天日期，xx = 当日序号（01 起，同一天再次构建自动 +1）。
#   显示层 FFBuildInfo.displayVersion 把两者拼成 `0.8.0-26102101 Beta`。
#
# 用法：
#   bash scripts/bump-version.sh            # 写入工程并打印新版本串
#   bash scripts/bump-version.sh --dry-run  # 只打印，不写文件
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib-version.sh
source "$SCRIPT_DIR/lib-version.sh"

PBXPROJ="$FF_PROJECT_DIR/FlowFinder/FlowFinder.xcodeproj/project.pbxproj"
TODAY="$(date +%y%m%d)"

if [[ "$FF_BUILD" == "$TODAY"[0-9]* ]]; then
    NEXT_SEQ=$(( 10#${FF_BUILD#"$TODAY"} + 1 ))
else
    NEXT_SEQ=1
fi
NEXT_BUILD="$(printf '%s%02d' "$TODAY" "$NEXT_SEQ")"

if [[ "${1:-}" == "--dry-run" ]]; then
    echo "$FF_VERSION-$NEXT_BUILD"
    exit 0
fi

sed -i '' -E "s/^([[:space:]]*CURRENT_PROJECT_VERSION = )[^;]+;/\1${NEXT_BUILD};/" "$PBXPROJ"
echo "$FF_VERSION-$NEXT_BUILD"
