#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sync_mirror.sh --mirror DIR [options]

Create or reuse a FlowFinder XCTest mirror under /tmp, sync the source worktree
into it without deleting anything, then re-apply the App bundle id isolation the
sync overwrites. Never writes to the source worktree, never kills a desktop app,
never deletes the mirror.

Required:
  --mirror DIR         Absolute mirror root under /tmp (created when missing)

Options:
  --source DIR         Source worktree (default:
                       /Volumes/Iris-Data/文件管理系统/flowfinder-native)
  --test-home DIR      Isolated HOME from the test scheme env (default:
                       /tmp/flowfinder-test-home)
  --check-only         Verify isolation and test home only; sync nothing
  --dry-run            Rsync in dry-run mode; do not edit the project or mkdir
  --help               Show this help

Isolation contract (mirror only, source untouched):
  App target   com.flowfinder.native      -> com.flowfinder.native.fulltest
  Test bundle  com.flowfinder.native.tests stays unchanged

Exit codes:
  0  mirror synced, isolated and verified
  1  argument, path, sync or isolation failure
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

MIRROR=""
SOURCE="/Volumes/Iris-Data/文件管理系统/flowfinder-native"
TEST_HOME="/tmp/flowfinder-test-home"
CHECK_ONLY=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --mirror)
      [ $# -ge 2 ] || die "--mirror needs a value"
      MIRROR="$2"; shift 2 ;;
    --source)
      [ $# -ge 2 ] || die "--source needs a value"
      SOURCE="$2"; shift 2 ;;
    --test-home)
      [ $# -ge 2 ] || die "--test-home needs a value"
      TEST_HOME="$2"; shift 2 ;;
    --check-only)
      CHECK_ONLY=1; shift ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

[ -n "$MIRROR" ] || die "--mirror is required"
case "$MIRROR" in /*) ;; *) die "--mirror must be an absolute path" ;; esac
case "$MIRROR" in
  /tmp/*|/private/tmp/*) ;;
  *) die "mirror must be under /tmp (got: $MIRROR)" ;;
esac
case "$TEST_HOME" in
  /tmp/*|/private/tmp/*) ;;
  *) die "--test-home must be under /tmp (got: $TEST_HOME)" ;;
esac

SOURCE=$(cd "$SOURCE" 2>/dev/null && pwd -P) || die "source does not exist: $SOURCE"
[ -d "$SOURCE" ] || die "source does not exist: $SOURCE"
case "$SOURCE" in
  /tmp/*|/private/tmp/*) die "--source must not be a /tmp mirror" ;;
esac
[ -f "$SOURCE/FlowFinder/FlowFinder.xcodeproj/project.pbxproj" ] \
  || die "source project.pbxproj not found under $SOURCE"

PBXPROJ="$MIRROR/FlowFinder/FlowFinder.xcodeproj/project.pbxproj"

verify_isolation() {
  local isolated
  [ -f "$PBXPROJ" ] || die "mirror project.pbxproj not found: $PBXPROJ"
  if grep -q -F 'PRODUCT_BUNDLE_IDENTIFIER = com.flowfinder.native;' "$PBXPROJ"; then
    die "App bundle id is not isolated in the mirror: bare com.flowfinder.native still present"
  fi
  grep -q -F 'PRODUCT_BUNDLE_IDENTIFIER = com.flowfinder.native.tests;' "$PBXPROJ" \
    || die "test bundle id com.flowfinder.native.tests is missing from the mirror"
  isolated=$(grep -c -F 'PRODUCT_BUNDLE_IDENTIFIER = com.flowfinder.native.fulltest;' "$PBXPROJ" || true)
  [ "${isolated:-0}" -gt 0 ] || die "no com.flowfinder.native.fulltest App bundle id in the mirror"
  echo "ISOLATED=$isolated"
}

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "MODE=check-only"
  echo "MIRROR=$MIRROR"
  verify_isolation
  [ -d "$TEST_HOME/Desktop" ] && [ -d "$TEST_HOME/Documents" ] \
    || die "test home is incomplete: $TEST_HOME (mkdir it before running tests)"
  echo "TEST_HOME=$TEST_HOME"
  echo "OK mirror is isolated; test home present"
  exit 0
fi

if [ ! -d "$MIRROR" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY-RUN would create mirror: $MIRROR"
  else
    mkdir -p "$MIRROR"
    echo "CREATED=$MIRROR"
  fi
else
  MIRROR=$(cd "$MIRROR" && pwd -P)
fi

echo "SOURCE=$SOURCE"
echo "MIRROR=$MIRROR"

RSYNC_ARGS=(-a --exclude='.git' --exclude='build-beta' --exclude='rust-core/target' \
  --exclude='.DS_Store' --exclude='*.xcresult')
if [ "$DRY_RUN" -eq 1 ]; then
  RSYNC_ARGS+=(-n)
fi
rsync "${RSYNC_ARGS[@]}" "$SOURCE/" "$MIRROR/"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN complete; project.pbxproj not edited, test home not created"
  exit 0
fi

[ -f "$PBXPROJ" ] || die "sync did not deliver project.pbxproj: $PBXPROJ"
[ -d "$MIRROR/FlowFinder/Tests/FlowFinderTests" ] \
  || die "sync did not deliver the tests root under $MIRROR"

if [ ! -f "$PBXPROJ.bak-before-isolation" ]; then
  cp "$PBXPROJ" "$PBXPROJ.bak-before-isolation"
  echo "BACKUP=$PBXPROJ.bak-before-isolation"
fi

sed -i '' \
  's/PRODUCT_BUNDLE_IDENTIFIER = com\.flowfinder\.native;/PRODUCT_BUNDLE_IDENTIFIER = com.flowfinder.native.fulltest;/g' \
  "$PBXPROJ"

verify_isolation

mkdir -p "$TEST_HOME/Desktop" "$TEST_HOME/Documents"
echo "TEST_HOME=$TEST_HOME"
echo "OK mirror synced and isolated"
