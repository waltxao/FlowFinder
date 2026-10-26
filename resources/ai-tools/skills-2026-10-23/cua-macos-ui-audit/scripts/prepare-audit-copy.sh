#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: prepare-audit-copy.sh /absolute/path/App.app

Copy a macOS app to a unique temporary directory, assign a unique Bundle ID,
ad-hoc sign the copy, and print the paths needed for a CUA audit.

The source app is never modified, launched, or deleted.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

if [ "$#" -eq 1 ]; then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
elif [ "$#" -ne 1 ]; then
  usage >&2
  exit 2
fi

SOURCE_INPUT="$1"
[ -d "$SOURCE_INPUT" ] || die "not a directory: $SOURCE_INPUT"

SOURCE_NAME="$(basename "$SOURCE_INPUT")"
case "$SOURCE_NAME" in
  *.app) ;;
  *) die "expected a .app bundle: $SOURCE_INPUT" ;;
esac

SOURCE_PARENT="$(cd "$(dirname "$SOURCE_INPUT")" && pwd -P)" \
  || die "cannot resolve parent of: $SOURCE_INPUT"
SOURCE_APP="$SOURCE_PARENT/$SOURCE_NAME"
INFO_PLIST="$SOURCE_APP/Contents/Info.plist"

[ -f "$INFO_PLIST" ] || die "missing Info.plist: $INFO_PLIST"

ORIGINAL_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$INFO_PLIST" 2>/dev/null)" \
  || die "Info.plist has no CFBundleIdentifier"
BUNDLE_EXECUTABLE="$(plutil -extract CFBundleExecutable raw "$INFO_PLIST" 2>/dev/null)" \
  || die "Info.plist has no CFBundleExecutable"
EXECUTABLE="$SOURCE_APP/Contents/MacOS/$BUNDLE_EXECUTABLE"
[ -x "$EXECUTABLE" ] || die "executable is missing or not executable: $EXECUTABLE"

BUNDLE_VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST" 2>/dev/null || true)"
[ -n "$BUNDLE_VERSION" ] || BUNDLE_VERSION="unknown"

VERIFY_DIR="$(mktemp -d /tmp/cua-macos-ui-audit.XXXXXX)" \
  || die "could not create a temporary audit directory"
APP_COPY="$VERIFY_DIR/$SOURCE_NAME"

ditto "$SOURCE_APP" "$APP_COPY" \
  || die "copy failed; partial directory: $VERIFY_DIR"

COPY_INFO="$APP_COPY/Contents/Info.plist"
[ -f "$COPY_INFO" ] || die "copied app has no Info.plist: $APP_COPY"

SAFE_BUNDLE_ID="$(printf '%s' "$ORIGINAL_BUNDLE_ID" | LC_ALL=C tr -cd 'A-Za-z0-9.-')"
[ -n "$SAFE_BUNDLE_ID" ] || SAFE_BUNDLE_ID="local.cua-audit"
NEW_BUNDLE_ID="${SAFE_BUNDLE_ID}.audit.$(date +%Y%m%d%H%M%S).$$"

plutil -replace CFBundleIdentifier -string "$NEW_BUNDLE_ID" "$COPY_INFO" \
  || die "could not set CFBundleIdentifier; partial copy: $APP_COPY"

set_optional_label() {
  local key="$1"
  local value
  if value="$(plutil -extract "$key" raw "$COPY_INFO" 2>/dev/null)"; then
    plutil -replace "$key" -string "$value Audit" "$COPY_INFO"
  fi
}

set_optional_label CFBundleName
set_optional_label CFBundleDisplayName

codesign --force --deep --sign - "$APP_COPY" >/dev/null 2>&1 \
  || die "ad-hoc signing failed; partial copy: $APP_COPY"
codesign --verify --deep --strict "$APP_COPY" >/dev/null 2>&1 \
  || die "signature verification failed; partial copy: $APP_COPY"

printf 'SOURCE_APP=%s\n' "$SOURCE_APP"
printf 'ORIGINAL_BUNDLE_ID=%s\n' "$ORIGINAL_BUNDLE_ID"
printf 'VERIFY_DIR=%s\n' "$VERIFY_DIR"
printf 'APP_COPY=%s\n' "$APP_COPY"
printf 'BUNDLE_ID=%s\n' "$NEW_BUNDLE_ID"
printf 'EXECUTABLE=%s\n' "$APP_COPY/Contents/MacOS/$BUNDLE_EXECUTABLE"
printf 'VERSION=%s\n' "$BUNDLE_VERSION"
