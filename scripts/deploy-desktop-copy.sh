#!/usr/bin/env bash
# 将刚构建的 Debug 包覆盖到桌面副本并重启。
# 用法：deploy-desktop-copy.sh <FlowFinder.app>
# 环境变量：
#   FF_DESKTOP_RELAUNCH=0   只覆盖不重启（自动化/截图场景）
#   FF_DESKTOP_BACKUP_DIR   备份目录，默认 /tmp/ff-desktop-backup
set -euo pipefail

SRC="${1:?用法: deploy-desktop-copy.sh <FlowFinder.app>}"
DESKTOP="${HOME}/Desktop/FlowFinder.app"
BACKUP_DIR="${FF_DESKTOP_BACKUP_DIR:-/tmp/ff-desktop-backup}"

if [ ! -d "$SRC" ]; then
  echo "✗ 构建产物不存在: $SRC" >&2
  exit 1
fi
if [ ! -f "$SRC/Contents/Info.plist" ]; then
  echo "✗ 不是有效的 .app: $SRC" >&2
  exit 1
fi

SRC_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SRC/Contents/Info.plist" 2>/dev/null || true)
if [ -z "$SRC_VERSION" ]; then
  echo "✗ 无法读取构建版本号" >&2
  exit 1
fi

# 门禁 1：签名
codesign --verify --deep --strict "$SRC" >/dev/null 2>&1 || {
  echo "✗ 构建产物签名校验失败: $SRC" >&2
  exit 1
}

# 备份旧桌面副本（版本不同才备份，避免重复）
mkdir -p "$BACKUP_DIR"
if [ -d "$DESKTOP" ]; then
  OLD_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DESKTOP/Contents/Info.plist" 2>/dev/null || true)
  if [ -n "$OLD_VERSION" ] && [ "$OLD_VERSION" != "$SRC_VERSION" ]; then
    BACKUP="$BACKUP_DIR/FlowFinder-$OLD_VERSION.app"
    if [ ! -d "$BACKUP" ]; then
      ditto "$DESKTOP" "$BACKUP"
      echo "✓ 已备份旧桌面副本 $OLD_VERSION → $BACKUP"
    fi
  fi
fi

# 覆盖
rm -rf "$DESKTOP"
ditto "$SRC" "$DESKTOP"

# 门禁 2：覆盖后签名与版本
codesign --verify --deep --strict "$DESKTOP" >/dev/null 2>&1 || {
  echo "✗ 桌面副本签名校验失败" >&2
  exit 1
}
NEW_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DESKTOP/Contents/Info.plist" 2>/dev/null || true)
if [ "$NEW_VERSION" != "$SRC_VERSION" ]; then
  echo "✗ 桌面副本版本不一致: $NEW_VERSION != $SRC_VERSION" >&2
  exit 1
fi

# 重启桌面副本（只匹配桌面路径，避免误杀测试/缓存构建）
if [ "${FF_DESKTOP_RELAUNCH:-1}" != "0" ]; then
  pkill -f "$DESKTOP/Contents/MacOS/FlowFinder" 2>/dev/null || true
  sleep 1
  open "$DESKTOP"
  echo "✓ 桌面副本已重启: $DESKTOP ($NEW_VERSION)"
else
  echo "✓ 桌面副本已覆盖（未重启）: $DESKTOP ($NEW_VERSION)"
fi
