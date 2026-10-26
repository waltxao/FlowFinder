#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: prepare_mirror.sh --source DIR --mirror DIR [options]

Mirror a macOS Xcode project to an internal disk without touching the source
tree. Optionally replace only the app target's PRODUCT_BUNDLE_IDENTIFIER in the
mirror's project.pbxproj to isolate the XCTest host.

Required:
  --source DIR               Absolute source root
  --mirror DIR               Absolute mirror root (must not be inside source)

Options:
  --project-rel PATH         project.pbxproj path relative to mirror
                             (required with bundle-id options)
  --app-bundle-id ID         Existing app target bundle ID
  --isolated-bundle-id ID    Replacement bundle ID (e.g. com.example.app.fulltest)
  --exclude PATTERN          Additional rsync exclude; repeatable
  --dry-run                  Print commands without writing
  --help                     Show this help

Intended for the initial mirror. For incremental sync after code changes,
rsync only the source/test directories so the isolated bundle ID survives.
Never uses rsync --delete. Never modifies --source.
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

abspath() {
  local p="$1"
  if [ -d "$p" ]; then
    (cd "$p" && pwd -P)
  else
    local parent
    parent=$(dirname "$p")
    if [ -d "$parent" ]; then
      printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$(basename "$p")"
    else
      printf '%s\n' "$p"
    fi
  fi
}

SOURCE=""
MIRROR=""
PROJECT_REL=""
APP_BUNDLE_ID=""
ISOLATED_BUNDLE_ID=""
DRY_RUN=0
EXCLUDES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --source)
      [ $# -ge 2 ] || die "--source needs a value"
      SOURCE="$2"; shift 2 ;;
    --mirror)
      [ $# -ge 2 ] || die "--mirror needs a value"
      MIRROR="$2"; shift 2 ;;
    --project-rel)
      [ $# -ge 2 ] || die "--project-rel needs a value"
      PROJECT_REL="$2"; shift 2 ;;
    --app-bundle-id)
      [ $# -ge 2 ] || die "--app-bundle-id needs a value"
      APP_BUNDLE_ID="$2"; shift 2 ;;
    --isolated-bundle-id)
      [ $# -ge 2 ] || die "--isolated-bundle-id needs a value"
      ISOLATED_BUNDLE_ID="$2"; shift 2 ;;
    --exclude)
      [ $# -ge 2 ] || die "--exclude needs a value"
      EXCLUDES+=("--exclude=$2"); shift 2 ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

[ -n "$SOURCE" ] || die "--source is required"
[ -n "$MIRROR" ] || die "--mirror is required"
case "$SOURCE" in /*) ;; *) die "--source must be an absolute path" ;; esac
case "$MIRROR" in /*) ;; *) die "--mirror must be an absolute path" ;; esac

SOURCE=$(abspath "$SOURCE")
MIRROR=$(abspath "$MIRROR")

[ -d "$SOURCE" ] || die "source does not exist: $SOURCE"
[ "$SOURCE" != "$MIRROR" ] || die "source and mirror must differ"
case "$MIRROR/" in
  "$SOURCE/"*) die "mirror must not be inside source" ;;
esac
case "$SOURCE/" in
  "$MIRROR/"*) die "source must not be inside mirror" ;;
esac

if { [ -n "$APP_BUNDLE_ID" ] && [ -z "$ISOLATED_BUNDLE_ID" ]; } || \
   { [ -z "$APP_BUNDLE_ID" ] && [ -n "$ISOLATED_BUNDLE_ID" ]; }; then
  die "--app-bundle-id and --isolated-bundle-id must be used together"
fi
if [ -n "$APP_BUNDLE_ID" ]; then
  [ -n "$PROJECT_REL" ] || die "--project-rel is required with bundle-id options"
fi

RSYNC_ARGS=(-a --exclude='.git' --exclude='.DS_Store' --exclude='*.xcresult')
if [ ${#EXCLUDES[@]} -gt 0 ]; then
  RSYNC_ARGS+=("${EXCLUDES[@]}")
fi

if [ -n "$PROJECT_REL" ] && [ -n "$ISOLATED_BUNDLE_ID" ] && [ -f "$MIRROR/$PROJECT_REL" ]; then
  if grep -q -F "PRODUCT_BUNDLE_IDENTIFIER = ${ISOLATED_BUNDLE_ID};" "$MIRROR/$PROJECT_REL"; then
    die "mirror already contains isolated bundle id; use rsync of source/test dirs for incremental sync, not this script"
  fi
fi

echo "SOURCE=$SOURCE"
echo "MIRROR=$MIRROR"

if [ "$DRY_RUN" -eq 1 ]; then
  printf 'rsync'
  printf ' %q' "${RSYNC_ARGS[@]}"
  printf ' %q/ %q/\n' "$SOURCE" "$MIRROR"
else
  mkdir -p "$MIRROR"
  rsync "${RSYNC_ARGS[@]}" "$SOURCE/" "$MIRROR/"
fi

PROJECT_FILE=""
if [ -n "$PROJECT_REL" ]; then
  PROJECT_FILE="$MIRROR/$PROJECT_REL"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "would verify project file: $PROJECT_FILE"
  else
    [ -f "$PROJECT_FILE" ] || die "project file not found in mirror: $PROJECT_FILE"
  fi
fi

if [ -n "$APP_BUNDLE_ID" ]; then
  case "$APP_BUNDLE_ID" in
    *[!A-Za-z0-9._-]*) die "unsafe app bundle id: $APP_BUNDLE_ID" ;;
  esac
  case "$ISOLATED_BUNDLE_ID" in
    *[!A-Za-z0-9._-]*) die "unsafe isolated bundle id: $ISOLATED_BUNDLE_ID" ;;
  esac

  OLD="PRODUCT_BUNDLE_IDENTIFIER = ${APP_BUNDLE_ID};"
  NEW="PRODUCT_BUNDLE_IDENTIFIER = ${ISOLATED_BUNDLE_ID};"

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "would replace in $PROJECT_FILE:"
    echo "  $OLD"
    echo "  $NEW"
  else
    OLD_COUNT=$(grep -c -F "$OLD" "$PROJECT_FILE" || true)
    [ "$OLD_COUNT" -gt 0 ] || die "bundle id not found in project file: $APP_BUNDLE_ID"

    TEST_OLD="PRODUCT_BUNDLE_IDENTIFIER = ${APP_BUNDLE_ID}.tests;"
    TEST_BEFORE=$(grep -c -F "$TEST_OLD" "$PROJECT_FILE" || true)

    BACKUP="$PROJECT_FILE.bak-before-isolation.$(date +%Y%m%d%H%M%S)"
    cp "$PROJECT_FILE" "$BACKUP"

    OLD_ESCAPED="${OLD//./\\.}"
    sed -i '' "s/${OLD_ESCAPED}/${NEW}/g" "$PROJECT_FILE"

    NEW_COUNT=$(grep -c -F "$NEW" "$PROJECT_FILE" || true)
    OLD_AFTER=$(grep -c -F "$OLD" "$PROJECT_FILE" || true)
    TEST_AFTER=$(grep -c -F "$TEST_OLD" "$PROJECT_FILE" || true)

    [ "$NEW_COUNT" -gt 0 ] || die "replacement did not produce the isolated id"
    [ "$OLD_AFTER" -eq 0 ] || die "old app bundle id remains"
    [ "$TEST_BEFORE" -eq "$TEST_AFTER" ] || die "test bundle id changed unexpectedly"

    echo "Replaced $OLD_COUNT app bundle id occurrence(s)."
    echo "Test bundle id unchanged ($TEST_AFTER occurrence(s))."
    echo "Backup: $BACKUP"
  fi
fi

echo "Done. Mirror is ready: $MIRROR"
echo "Next: verify the project, then run scripts/run_xctest_batches.sh"
