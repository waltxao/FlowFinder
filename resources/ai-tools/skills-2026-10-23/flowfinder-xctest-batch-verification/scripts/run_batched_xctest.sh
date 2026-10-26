#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run_batched_xctest.sh --mirror DIR [options]

Run FlowFinder XCTest classes in sequential batches against an already-isolated
mirror under /tmp. The script never edits the project, never kills a desktop app,
and never deletes the mirror.

Required:
  --mirror DIR           Absolute FlowFinder mirror root under /tmp

Options:
  --batch-size N         Classes per batch (default: 5)
  --timeout SECONDS      Timeout per batch (default: 150)
  --log-dir DIR          Absolute log directory (default: /tmp/flowfinder-xctest-batches)
  --skip TARGET          Class or Class/method to skip; repeatable
  --list-only            Print discovered classes and counts, then exit
  --dry-run              Print batch commands without running xcodebuild
  --help                 Show this help

Fixed FlowFinder paths:
  project      FlowFinder/FlowFinder.xcodeproj
  scheme       FlowFinderTests
  tests root   FlowFinder/Tests/FlowFinderTests
  module       FlowFinderTests
  derivedData  /tmp/flowfinder-xctest-derived

Exit codes:
  0  every batch completed with no failures
  1  complete coverage but one or more test failures
  2  incomplete coverage, build/setup failure, hang, or skipped targets
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

MIRROR=""
BATCH_SIZE=5
TIMEOUT_SECS=150
LOG_DIR="/tmp/flowfinder-xctest-batches"
LIST_ONLY=0
DRY_RUN=0
SKIPS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --mirror)
      [ $# -ge 2 ] || die "--mirror needs a value"
      MIRROR="$2"; shift 2 ;;
    --batch-size)
      [ $# -ge 2 ] || die "--batch-size needs a value"
      BATCH_SIZE="$2"; shift 2 ;;
    --timeout)
      [ $# -ge 2 ] || die "--timeout needs a value"
      TIMEOUT_SECS="$2"; shift 2 ;;
    --log-dir)
      [ $# -ge 2 ] || die "--log-dir needs a value"
      LOG_DIR="$2"; shift 2 ;;
    --skip)
      [ $# -ge 2 ] || die "--skip needs a value"
      case "$2" in
        -*) die "--skip target must not start with '-': $2" ;;
      esac
      SKIPS+=("$2"); shift 2 ;;
    --list-only)
      LIST_ONLY=1; shift ;;
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
[ -d "$MIRROR" ] || die "mirror does not exist: $MIRROR"
MIRROR=$(cd "$MIRROR" && pwd -P)
case "$MIRROR" in
  /tmp/*|/private/tmp/*) ;;
  *) die "mirror must be under /tmp (got: $MIRROR)" ;;
esac

case "$BATCH_SIZE" in
  ''|*[!0-9]*) die "--batch-size must be a positive integer" ;;
esac
[ "$BATCH_SIZE" -gt 0 ] || die "--batch-size must be greater than zero"

case "$TIMEOUT_SECS" in
  ''|*[!0-9]*) die "--timeout must be a positive integer" ;;
esac
[ "$TIMEOUT_SECS" -gt 0 ] || die "--timeout must be greater than zero"

case "$LOG_DIR" in /*) ;; *) die "--log-dir must be an absolute path" ;; esac

PROJECT="$MIRROR/FlowFinder/FlowFinder.xcodeproj"
TESTS_ROOT="$MIRROR/FlowFinder/Tests/FlowFinderTests"
SCHEME="FlowFinderTests"
MODULE="FlowFinderTests"
DERIVED="/tmp/flowfinder-xctest-derived"
HOST_PATH="$DERIVED/Build/Products/Debug/FlowFinder.app/Contents/MacOS/FlowFinder"

[ -e "$PROJECT" ] || die "project not found: $PROJECT"
[ -d "$TESTS_ROOT" ] || die "tests root not found: $TESTS_ROOT"

PBXPROJ="$PROJECT/project.pbxproj"
[ -f "$PBXPROJ" ] || die "project.pbxproj not found: $PBXPROJ"

grep -q -F 'PRODUCT_BUNDLE_IDENTIFIER = com.flowfinder.native.tests;' "$PBXPROJ" \
  || die "FlowFinderTests bundle id is missing from the mirror"
if grep -q -F 'PRODUCT_BUNDLE_IDENTIFIER = com.flowfinder.native;' "$PBXPROJ"; then
  die "App bundle id is not isolated; replace com.flowfinder.native only in the mirror before running"
fi

command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found"

TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
fi
if [ "$LIST_ONLY" -eq 0 ] && [ "$DRY_RUN" -eq 0 ] && [ -z "$TIMEOUT_BIN" ]; then
  die "neither 'timeout' nor 'gtimeout' is available"
fi
DISPLAY_TIMEOUT="${TIMEOUT_BIN:-timeout}"

CLASSES_TEXT=$(grep -RhE '(^|[[:space:]])(final[[:space:]]+)?class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*XCTestCase' "$TESTS_ROOT" 2>/dev/null \
  | sed -E 's/.*class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
  | sort -u || true)
[ -n "$CLASSES_TEXT" ] || die "no XCTestCase classes found under $TESTS_ROOT"

CLASS_COUNT=$(printf '%s\n' "$CLASSES_TEXT" | grep -c . || true)
BATCHES_TOTAL=$(( (CLASS_COUNT + BATCH_SIZE - 1) / BATCH_SIZE ))

echo "MIRROR=$MIRROR"
echo "PROJECT=$PROJECT"
echo "SCHEME=$SCHEME"
echo "CLASSES=$CLASS_COUNT"
echo "BATCHES=$BATCHES_TOTAL"
echo "BATCH_SIZE=$BATCH_SIZE"
echo "DERIVED=$DERIVED"

if [ "$LIST_ONLY" -eq 1 ]; then
  printf '%s\n' "$CLASSES_TEXT"
  exit 0
fi

CLASS_ARRAY=()
while IFS= read -r class_name; do
  [ -n "$class_name" ] && CLASS_ARRAY+=("$class_name")
done <<< "$CLASSES_TEXT"

SKIP_ARGS=()
if [ ${#SKIPS[@]} -gt 0 ]; then
  for skip_target in "${SKIPS[@]}"; do
    SKIP_ARGS+=("-skip-testing:${MODULE}/${skip_target}")
  done
fi

cleanup_host() {
  local pids pid cmd
  pids=$(pgrep -f -- "$HOST_PATH" 2>/dev/null || true)
  [ -n "$pids" ] || return 0
  for pid in $pids; do
    [ "$pid" = "$$" ] && continue
    cmd=$(ps -p "$pid" -o command= 2>/dev/null || true)
    case "$cmd" in
      "$HOST_PATH"*) kill "$pid" 2>/dev/null || true ;;
    esac
  done
}

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$LOG_DIR"
  printf '%s\n' "$CLASSES_TEXT" > "$LOG_DIR/classes.txt"
  : > "$LOG_DIR/summary.txt"
  cleanup_host
fi

TOTAL_TESTS=0
TOTAL_FAILURE_ASSERTIONS=0
TOTAL_FAILED_TESTS=0
HUNG_BATCHES=0
BUILD_FAILURES=0
INCOMPLETE_BATCHES=0
FAILED_TESTS_LIST=""

i=0
batch=0
while [ "$i" -lt "$CLASS_COUNT" ]; do
  batch=$((batch + 1))
  ONLY_ARGS=()
  NAMES=""
  j=$i
  while [ "$j" -lt $((i + BATCH_SIZE)) ] && [ "$j" -lt "$CLASS_COUNT" ]; do
    ONLY_ARGS+=("-only-testing:${MODULE}/${CLASS_ARRAY[$j]}")
    NAMES="${NAMES}${CLASS_ARRAY[$j]} "
    j=$((j + 1))
  done

  XCB_ARGS=(
    test
    -project "$PROJECT"
    -scheme "$SCHEME"
    -destination "platform=macOS"
    -derivedDataPath "$DERIVED"
  )
  if [ ${#SKIP_ARGS[@]} -gt 0 ]; then
    XCB_ARGS+=("${SKIP_ARGS[@]}")
  fi
  XCB_ARGS+=("${ONLY_ARGS[@]}")
  XCB_ARGS+=(
    CODE_SIGN_IDENTITY=-
    CODE_SIGNING_REQUIRED=NO
  )

  BATCH_LOG="$LOG_DIR/batch-$(printf '%02d' "$batch").log"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'BATCH %d: %s\n' "$batch" "$NAMES"
    printf '  %s %s xcodebuild' "$DISPLAY_TIMEOUT" "$TIMEOUT_SECS"
    printf ' %q' "${XCB_ARGS[@]}"
    printf ' > %q\n' "$BATCH_LOG"
    i=$((i + BATCH_SIZE))
    continue
  fi

  echo "BATCH $batch: $NAMES"
  set +e
  ( cd "$MIRROR" && LC_ALL=C "$TIMEOUT_BIN" "$TIMEOUT_SECS" xcodebuild "${XCB_ARGS[@]}" ) > "$BATCH_LOG" 2>&1
  STATUS=$?
  set -e

  cleanup_host

  SUMMARY=$(grep -E "Executed [0-9]+ tests, with [0-9]+ failures?" "$BATCH_LOG" 2>/dev/null | tail -1 || true)
  if [ -z "$SUMMARY" ]; then
    HUNG_BATCHES=$((HUNG_BATCHES + 1))
    LINE="BATCH $batch status=$STATUS TIMEOUT/NO-SUMMARY :: $NAMES"
    printf '%s\n' "$LINE" | tee -a "$LOG_DIR/summary.txt"
    i=$((i + BATCH_SIZE))
    continue
  fi

  TESTS=$(printf '%s\n' "$SUMMARY" | sed -E 's/.*Executed ([0-9]+) tests, with ([0-9]+) failures?.*/\1/')
  FAILS=$(printf '%s\n' "$SUMMARY" | sed -E 's/.*Executed ([0-9]+) tests, with ([0-9]+) failures?.*/\2/')

  FAILED_NAMES=$(sed -nE "s/.*Test Case '-\\[([^]]+)\\]' failed.*/\\1/p" "$BATCH_LOG" | sort -u || true)
  FAILED_COUNT=0
  if [ -n "$FAILED_NAMES" ]; then
    FAILED_COUNT=$(printf '%s\n' "$FAILED_NAMES" | grep -c . || true)
  fi

  SUCCESS_MARKER=$(grep -c -F '** TEST SUCCEEDED **' "$BATCH_LOG" || true)
  FAILURE_MARKER=$(grep -c -F '** TEST FAILED **' "$BATCH_LOG" || true)

  CLASSIFICATION="OK"
  if [ "$FAILS" -gt 0 ] || [ "$FAILURE_MARKER" -gt 0 ]; then
    CLASSIFICATION="TEST-FAILURES"
  elif [ "$STATUS" -ne 0 ]; then
    CLASSIFICATION="BUILD-OR-SETUP-FAILURE"
    BUILD_FAILURES=$((BUILD_FAILURES + 1))
  elif [ "$TESTS" -eq 0 ] || [ "$SUCCESS_MARKER" -eq 0 ]; then
    CLASSIFICATION="INCOMPLETE"
    INCOMPLETE_BATCHES=$((INCOMPLETE_BATCHES + 1))
  fi

  TOTAL_TESTS=$((TOTAL_TESTS + TESTS))
  TOTAL_FAILURE_ASSERTIONS=$((TOTAL_FAILURE_ASSERTIONS + FAILS))
  TOTAL_FAILED_TESTS=$((TOTAL_FAILED_TESTS + FAILED_COUNT))
  if [ -n "$FAILED_NAMES" ]; then
    FAILED_TESTS_LIST="${FAILED_TESTS_LIST}${FAILED_NAMES}"$'\n'
  fi

  LINE="BATCH $batch status=$STATUS tests=$TESTS failure_assertions=$FAILS failed_tests=$FAILED_COUNT class=$CLASSIFICATION :: $NAMES"
  printf '%s\n' "$LINE" | tee -a "$LOG_DIR/summary.txt"

  i=$((i + BATCH_SIZE))
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN complete; no xcodebuild invocation was executed"
  exit 0
fi

SKIP_COUNT=${#SKIPS[@]}
SKIPPED_DISPLAY="none"
if [ "$SKIP_COUNT" -gt 0 ]; then
  SKIPPED_DISPLAY=""
  for skip_target in "${SKIPS[@]}"; do
    SKIPPED_DISPLAY="${SKIPPED_DISPLAY}${skip_target}, "
  done
  SKIPPED_DISPLAY=${SKIPPED_DISPLAY%, }
fi

echo "TOTAL_TESTS=$TOTAL_TESTS"
echo "TOTAL_FAILED_TESTS=$TOTAL_FAILED_TESTS"
echo "TOTAL_FAILURE_ASSERTIONS=$TOTAL_FAILURE_ASSERTIONS"
echo "HUNG_BATCHES=$HUNG_BATCHES"
echo "BUILD_FAILURES=$BUILD_FAILURES"
echo "INCOMPLETE_BATCHES=$INCOMPLETE_BATCHES"
echo "SKIPPED=$SKIPPED_DISPLAY"
echo "LOGS=$LOG_DIR"

if [ -n "$FAILED_TESTS_LIST" ]; then
  echo "FAILED_TEST_NAMES:"
  printf '%s' "$FAILED_TESTS_LIST"
fi

if [ "$HUNG_BATCHES" -gt 0 ] || [ "$BUILD_FAILURES" -gt 0 ] || [ "$INCOMPLETE_BATCHES" -gt 0 ] || [ "$TOTAL_TESTS" -eq 0 ]; then
  echo "COVERAGE: incomplete"
  exit 2
fi

if [ "$SKIP_COUNT" -gt 0 ]; then
  echo "COVERAGE: complete-with-skips"
  exit 2
fi

if [ "$TOTAL_FAILURE_ASSERTIONS" -gt 0 ] || [ "$TOTAL_FAILED_TESTS" -gt 0 ]; then
  echo "COVERAGE: complete"
  exit 1
fi

echo "COVERAGE: complete"
exit 0
