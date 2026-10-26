#!/bin/bash
# Increment CURRENT_PROJECT_VERSION in an Xcode project.pbxproj.
# Rule: yymmddNN; same day increments, any other value resets to 01.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bump-version.sh --pbxproj <path> [--dry-run] [--quiet] [--date YYMMDD]

Required:
  --pbxproj <path>  Path to project.pbxproj; all CURRENT_PROJECT_VERSION values must match

Options:
  --dry-run         Print the planned result without modifying the file
  --quiet           Print only the new build number (for Makefile capture)
  --date YYMMDD     Override today's date; fixture/testing use only
  -h, --help        Show this help

Exit codes: 0 success, 1 invalid project state, 2 usage error.
USAGE
}

die() {
  echo "[bump-version] ERROR: $*" >&2
  exit 1
}

usage_error() {
  echo "[bump-version] ERROR: $*" >&2
  usage >&2
  exit 2
}

PBXPROJ=""
DRY_RUN=0
QUIET=0
DATE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pbxproj)
      [[ $# -ge 2 ]] || usage_error "--pbxproj requires a path"
      PBXPROJ="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    --date)
      [[ $# -ge 2 ]] || usage_error "--date requires YYMMDD"
      DATE_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage_error "unknown argument: $1"
      ;;
  esac
done

[[ -n "$PBXPROJ" ]] || usage_error "--pbxproj is required"
[[ -f "$PBXPROJ" ]] || die "file not found: $PBXPROJ"
[[ -r "$PBXPROJ" ]] || die "file is not readable: $PBXPROJ"
if [[ "$DRY_RUN" -eq 0 && ! -w "$PBXPROJ" ]]; then
  die "file is not writable: $PBXPROJ"
fi

if [[ -n "$DATE_OVERRIDE" ]]; then
  [[ "$DATE_OVERRIDE" =~ ^[0-9][0-9][0-9][0-9][0-9][0-9]$ ]] \
    || die "--date must be six digits in YYMMDD form"
  date -j -f "%y%m%d" "$DATE_OVERRIDE" "+%y%m%d" >/dev/null 2>&1 \
    || die "--date is not a valid calendar date: $DATE_OVERRIDE"
  TODAY="$DATE_OVERRIDE"
else
  TODAY="$(date +%y%m%d)"
fi

ROWS_FILE=""
BACKUP_FILE=""
NEW_FILE=""

cleanup() {
  [[ -z "$ROWS_FILE" ]] || rm -f "$ROWS_FILE"
  [[ -z "$BACKUP_FILE" ]] || rm -f "$BACKUP_FILE"
  [[ -z "$NEW_FILE" ]] || rm -f "$NEW_FILE"
}
trap cleanup EXIT

ROWS_FILE="$(mktemp "${TMPDIR:-/tmp}/bump-version-rows.XXXXXX")" \
  || die "cannot create a temporary file"

awk '
  /^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=/ {
    value = $0
    sub(/^[^=]*=[[:space:]]*/, "", value)
    sub(/[[:space:]]*;.*/, "", value)
    gsub(/\r/, "", value)
    gsub(/^[[:space:]]+/, "", value)
    gsub(/[[:space:]]+$/, "", value)
    print NR "\t" value
  }
' "$PBXPROJ" > "$ROWS_FILE"

COUNT="$(wc -l < "$ROWS_FILE" | tr -d ' ')"
[[ "$COUNT" -gt 0 ]] || die "no CURRENT_PROJECT_VERSION found in $PBXPROJ"

FIRST_VALUE="$(awk -F '\t' 'NR == 1 { print $2 }' "$ROWS_FILE")"

MISMATCH="$(awk -F '\t' -v first="$FIRST_VALUE" '
  $2 != first {
    printf "line %s = %s\n", $1, ($2 == "" ? "<empty>" : $2)
    exit
  }
' "$ROWS_FILE")"

if [[ -n "$MISMATCH" ]]; then
  {
    echo "[bump-version] ERROR: CURRENT_PROJECT_VERSION values differ:"
    while IFS=$'\t' read -r line value; do
      printf '  line %s: %s\n' "$line" "${value:-<empty>}"
    done < "$ROWS_FILE"
  } >&2
  exit 1
fi

if [[ -n "$FIRST_VALUE" && ! "$FIRST_VALUE" =~ ^[0-9]+$ ]]; then
  die "CURRENT_PROJECT_VERSION must be a literal number; found '$FIRST_VALUE'. Check xcconfig or inherited build settings."
fi

CURRENT_VALUE="$FIRST_VALUE"
NEXT_SEQ=1
if [[ -z "$CURRENT_VALUE" ]]; then
  BRANCH="reset-empty"
elif [[ "$CURRENT_VALUE" =~ ^${TODAY}([0-9][0-9])$ ]]; then
  SEQ_STR="${BASH_REMATCH[1]}"
  NEXT_SEQ=$((10#$SEQ_STR + 1))
  BRANCH="increment"
else
  BRANCH="reset"
fi

if [[ "$NEXT_SEQ" -gt 99 ]]; then
  die "daily sequence exceeded 99 (current '$CURRENT_VALUE'); extend the format deliberately before building"
fi

NEXT_BUILD="$(printf '%s%02d' "$TODAY" "$NEXT_SEQ")"
LINE_NUMBERS="$(awk -F '\t' '
  BEGIN { first = 1 }
  {
    if (!first) printf ","
    printf "%s", $1
    first = 0
  }
  END { print "" }
' "$ROWS_FILE")"

if [[ "$BRANCH" == "reset" ]]; then
  echo "[bump-version] NOTE: '$CURRENT_VALUE' does not match ${TODAY}NN; resetting to 01" >&2
elif [[ "$BRANCH" == "reset-empty" ]]; then
  echo "[bump-version] NOTE: empty CURRENT_PROJECT_VERSION; resetting to 01" >&2
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  if [[ "$QUIET" -eq 1 ]]; then
    printf '%s\n' "$NEXT_BUILD"
  else
    printf 'OLD_BUILD=%s\nNEW_BUILD=%s\nBRANCH=%s\nCOUNT=%s\nLINES=%s\nPBXPROJ=%s\nDRY_RUN=1\n' \
      "$CURRENT_VALUE" "$NEXT_BUILD" "$BRANCH" "$COUNT" "$LINE_NUMBERS" "$PBXPROJ"
  fi
  exit 0
fi

MARKETING_BEFORE="$(grep -E '^[[:space:]]*MARKETING_VERSION[[:space:]]*=' "$PBXPROJ" || true)"

BACKUP_FILE="$(mktemp "${TMPDIR:-/tmp}/bump-version-backup.XXXXXX")" \
  || die "cannot create a backup file"
cp -p "$PBXPROJ" "$BACKUP_FILE" || die "cannot back up $PBXPROJ"

NEW_FILE="$(mktemp "$(dirname "$PBXPROJ")/.pbxproj.bump.XXXXXX")" \
  || die "cannot create a temporary file next to $PBXPROJ"

awk -v new="$NEXT_BUILD" '
  /^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=/ {
    sub(/CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*[^;]*;/, "CURRENT_PROJECT_VERSION = " new ";")
  }
  { print }
' "$PBXPROJ" > "$NEW_FILE" || die "failed to create the updated pbxproj"

NEW_COUNT="$(grep -cE "^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*${NEXT_BUILD};" "$NEW_FILE" || true)"
[[ -n "$NEW_COUNT" ]] || NEW_COUNT=0
[[ "$NEW_COUNT" -eq "$COUNT" ]] \
  || die "internal error: expected $COUNT replacements, found $NEW_COUNT"

if MODE="$(stat -f '%Lp' "$PBXPROJ" 2>/dev/null)"; then
  chmod "$MODE" "$NEW_FILE"
fi

mv "$NEW_FILE" "$PBXPROJ" || die "failed to replace $PBXPROJ"
NEW_FILE=""

VERIFY="$(awk '
  /^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=/ {
    value = $0
    sub(/^[^=]*=[[:space:]]*/, "", value)
    sub(/[[:space:]]*;.*/, "", value)
    gsub(/\r/, "", value)
    gsub(/^[[:space:]]+/, "", value)
    gsub(/[[:space:]]+$/, "", value)
    print value
  }
' "$PBXPROJ" | sort -u)"

if [[ "$VERIFY" != "$NEXT_BUILD" ]]; then
  cp -p "$BACKUP_FILE" "$PBXPROJ" 2>/dev/null || true
  die "post-write verification failed; original file restored"
fi

MARKETING_AFTER="$(grep -E '^[[:space:]]*MARKETING_VERSION[[:space:]]*=' "$PBXPROJ" || true)"
if [[ "$MARKETING_BEFORE" != "$MARKETING_AFTER" ]]; then
  cp -p "$BACKUP_FILE" "$PBXPROJ" 2>/dev/null || true
  die "MARKETING_VERSION changed unexpectedly; original file restored"
fi

if [[ "$QUIET" -eq 1 ]]; then
  printf '%s\n' "$NEXT_BUILD"
else
  printf 'OLD_BUILD=%s\nNEW_BUILD=%s\nBRANCH=%s\nCOUNT=%s\nLINES=%s\nPBXPROJ=%s\nDRY_RUN=0\nWRITTEN=1\n' \
    "$CURRENT_VALUE" "$NEXT_BUILD" "$BRANCH" "$COUNT" "$LINE_NUMBERS" "$PBXPROJ"
fi
