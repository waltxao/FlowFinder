#!/bin/bash
# Deploy a verified FlowFinder Debug product to ~/Desktop/FlowFinder.app.
# Default is dry-run; only --apply writes to the Desktop copy.
set -euo pipefail

REPO="${FF_REPO:-/Volumes/Iris-Data/文件管理系统/flowfinder-native}"
DERIVED="${FLOWFINDER_DERIVED:-$HOME/Library/Caches/FlowFinderBuild}"
SRC="${FF_SRC_APP:-$DERIVED/Products/Debug/FlowFinder.app}"
DEST="$HOME/Desktop/FlowFinder.app"
BACKUP_ROOT="${FF_BACKUP_DIR:-/tmp/ff-desktop-backup}"
APPLY=0

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --src=*) SRC="${arg#--src=}" ;;
    --repo=*) REPO="${arg#--repo=}" ;;
    --dest=*) DEST="${arg#--dest=}" ;;
    -h|--help)
      echo "usage: deploy_debug_to_desktop.sh [--src=APP] [--repo=REPO] [--dest=APP] [--apply]"
      exit 0 ;;
  esac
done

fail() { echo "BLOCKED: $1"; exit 1; }
ver_of() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || echo unknown; }

[ -d "$SRC" ] || fail "源产物不存在：$SRC（先跑 make build，或用 --src 指定）"
[ -f "$SRC/Contents/MacOS/FlowFinder" ] || fail "源产物缺少可执行文件"
BIN_MTIME=$(stat -f %m "$SRC/Contents/MacOS/FlowFinder")

# --- Gate 1: the source product must be newer than every source file ---
STALE=$(find "$REPO/FlowFinder" "$REPO/rust-core" "$REPO/scripts" "$REPO/Makefile" \
  \( -name '*.swift' -o -name '*.rs' -o -name '*.pbxproj' -o -name '*.plist' -o -name '*.sh' \) \
  -not -path '*/target/*' -not -path '*/build*' -newer "$SRC/Contents/MacOS/FlowFinder" \
  -print -quit 2>/dev/null || true)
if [ -n "$STALE" ]; then
  echo "产物早于源码，不可复用（须先 make build，产物会递增构建号）："
  echo "  $STALE"
  exit 1
fi
echo "GATE 1 新鲜度：通过（二进制 $(date -r "$BIN_MTIME" '+%F %H:%M') 晚于全部源码）"

# --- Gate 2: signature of the source product ---
if codesign --verify --deep --strict "$SRC" 2>/dev/null; then
  echo "GATE 2 源产物 codesign --verify --deep：通过"
else
  fail "源产物 codesign --verify --deep 失败，不部署"
fi

SRC_BUILD=$(ver_of "$SRC" CFBundleVersion)
SRC_SHORT=$(ver_of "$SRC" CFBundleShortVersionString)
if [ -d "$DEST" ]; then
  DEST_BUILD=$(ver_of "$DEST" CFBundleVersion)
  BACKUP="$BACKUP_ROOT/FlowFinder-$DEST_BUILD.app"
else
  DEST_BUILD="(none)"
  BACKUP="(nothing to back up)"
fi

echo "计划："
echo "  源    ：$SRC  ($SRC_SHORT-$SRC_BUILD)"
echo "  目标  ：$DEST  (当前 $DEST_BUILD)"
echo "  备份到：$BACKUP"
echo "  覆盖  ：rm -rf 后 cp -R（保留构建号，不重跑 make demo）"

if [ "$APPLY" -eq 0 ]; then
  echo "DRY-RUN：未做任何修改。取得用户授权后加 --apply。"
  exit 0
fi

mkdir -p "$BACKUP_ROOT"
if [ -d "$DEST" ]; then
  if [ -e "$BACKUP" ]; then
    BACKUP="$BACKUP_ROOT/FlowFinder-$DEST_BUILD.$(date +%H%M%S).app"
  fi
  cp -R "$DEST" "$BACKUP"
  echo "STEP 备份：已保存旧包 $BACKUP"
fi
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
echo "STEP 覆盖：已部署 $SRC_SHORT-$SRC_BUILD"

if codesign --verify --deep --strict "$DEST" 2>/dev/null; then
  echo "STEP 校验：桌面副本 codesign --verify --deep 通过"
else
  echo "STEP 校验：桌面副本 codesign --verify --deep 失败 —— 部署不完整，须报告"
  exit 1
fi
echo "DEPLOYED version=$SRC_SHORT-$SRC_BUILD dest=$DEST"
echo "下一步：用 verify_desktop_instance.sh 取得运行实例证据，再同步文档当前态。"
