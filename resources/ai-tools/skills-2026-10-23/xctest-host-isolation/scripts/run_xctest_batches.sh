#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run_xctest_batches.sh --project PATH --scheme NAME --tests-root DIR \
         --module NAME --workdir DIR --derived-data DIR [options]

Run macOS XCTest classes in batches, with a timeout per batch, clean up the
test host by its exact executable path, and aggregate test/assertion counts.

Required:
  --project PATH          .xcodeproj path
  --scheme NAME           Test scheme
  --tests-root DIR        Directory containing XCTestCase subclasses
  --module NAME           Test module (e.g. FlowFinderTests)
  --workdir DIR           Mirror/worktree root (script cd's here before running)
  --derived-data DIR      Internal-disk derivedData path

Options:
  --host-path PATH        Exact test-host executable path used for cleanup
  --batch-size N          Classes per batch (default: 5)
  --timeout SECONDS       Timeout per batch (default: 150)
  --log-dir DIR           Absolute log directory (default: /tmp/xctest-batches)
  --skip TARGET           Class or Class/method to skip; repeatable
  --dry-run               Print commands; do not run xcodebuild
  --help                  Show this help

Exit codes: 0 clean and complete; 1 test failures but complete coverage;
2 coverage incomplete or skipped targets.
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

PROJECT=""
SCHEME=""
TESTS_ROOT=""
MODULE=""
WORKDIR=""
DERIVED=""
HOST_PATH=""
BATCH_SIZE=5
TIMEOUT_SECS=150
LOG_DIR="/tmp/xctest-batches"
DRY_RUN=0
SKIPS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      [ $# -ge 2 ] || die "--project needs a value"
      PROJECT="$2"; shift 2 ;;
    --scheme)
      [ $# -ge 2 ] || die "--scheme needs a value"
      SCHEME="$2"; shift 2 ;;
    --tests-root)
      [ $# -ge 2 ] || die "--tests-root needs a value"
      TESTS_ROOT="$2"; shift 2 ;;
    --module)
      [ $# -ge 2 ] || die "--module needs a value"
      MODULE="$2"; shift 2 ;;
    --workdir)
      [ $# -ge 2 ] || die "--workdir needs a value"
      WORKDIR="$2"; shift 2 ;;
    --derived-data)
      [ $# -ge 2 ] || die "--derived-data needs a value"
      DERIVED="$2"; shift 2 ;;
    --host-path)
      [ $# -ge 2 ] || die "--host-path needs a value"
      HOST_PATH="$2"; shift 2 ;;
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
    --dry-run)
      DRY_RUN=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

[ -n "$PROJECT" ] || die "--project is required"
[ -n "$SCHEME" ] || die "--scheme is required"
[ -n "$TESTS_ROOT" ] || die "--tests-root is required"
[ -n "$MODULE" ] || die "--module is required"
[ -n "$WORKDIR" ] || die "--workdir is required"
[ -n "$DERIVED" ] || die "--derived-data is required"

case "$PROJECT" in /*) ;; *) die "--project must be an absolute path" ;; esac
case "$TESTS_ROOT" in /*) ;; *) die "--tests-root must be an absolute path" ;; esac
case "$WORKDIR" in /*) ;; *) die "--workdir must be an absolute path" ;; esac
case "$DERIVED" in /*) ;; *) die "--derived-data must be an absolute path" ;; esac
case "$LOG_DIR" in /*) ;; *) die "--log-dir must be an absolute path" ;; esac

[ -e "$PROJECT" ] || die "project does not exist: $PROJECT"
[ -d "$TESTS_ROOT" ] || die "tests root does not exist: $TESTS_ROOT"
[ -d "$WORKDIR" ] || die "workdir does not exist: $WORKDIR"

case "$BATCH_SIZE" in
  ''|*[!0-9]*) die "--batch-size must be a positive integer" ;;
esac
[ "$BATCH_SIZE" -gt 0 ] || die "--batch-size must be greater than zero"
case "$TIMEOUT_SECS" in
  ''|*[!0-9]*) die "--timeout must be a positive integer" ;;
esac
[ "$TIMEOUT_SECS" -gt 0 ] || die "--timeout must be greater than zero"

command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found"

TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
fi

if [ "$DRY_RUN" -eq 0 ] && [ -z "$TIMEOUT_BIN" ]; then
  die "neither 'timeout' nor 'gtimeout' is available; install coreutils or run with a local wrapper"
fi
DISPLAY_TIMEOUT="${TIMEOUT_BIN:-timeout}"

if [ "$DRY_RUN" -eq 0 ]; then
  mkdir -p "$LOG_DIR"
fi

CLASS_FILE="$LOG_DIR/classes.txt"
CLASSES=$(grep -RhE '(^|[[:space:]])(final[[:space:]]+)?class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*XCTestCase' "$TESTS_ROOT" 2>/dev/null \
  | sed -E 's/.*class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
  | sort -u || true)

[ -n "$CLASSES" ] || die "no XCTestCase classes found under $TESTS_ROOT"
CLASS_COUNT=$(printf '%s\n' "$CLASSES" | grep -c . || true)

if [ "$DRY_RUN" -eq 0 ]; then
  printf '%s\n' "$CLASSES" > "$CLASS_FILE"
fi

echo "PROJECT=$PROJECT"
echo "SCHEME=$SCHEME"
echo "MODULE=$MODULE"
echo "CLASSES=$CLASS_COUNT"
if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' "$CLASSES"
fi
if [ -n "$HOST_PATH" ]; then
  echo "HOST_PATH=$HOST_PATH"
else
  echo "WARN: --host-path not set; leftover test hosts will not be cleaned up"
fi

SKIP_ARGS=()
if [ ${#SKIPS[@]} -gt 0 ]; then
  for s in "${SKIPS[@]}"; do
    SKIP_ARGS+=("-skip-testing:${MODULE}/${s}")
  done
fi

CLASS_ARRAY=()
while IFS= read -r c; do
  [ -n "$c" ] && CLASS_ARRAY+=("$c")
done <<< "$CLASSES"

TOTAL_TESTS=0
TOTAL_FAILURE_ASSERTIONS=0
TOTAL_FAILED_TESTS=0
HUNG_BATCHES=0
BUILD_FAILURES=0
BATCH=0
FAILED_TESTS_LIST=""
SUMMARY_FILE="$LOG_DIR/summary.txt"

if [ "$DRY_RUN" -eq 0 ]; then
  : > "$SUMMARY_FILE"
fi

i=0
while [ "$i" -lt "$CLASS_COUNT" ]; do
  BATCH=$((BATCH + 1))
  ONLY_ARGS=()
  NAMES=""
  j="$i"
  while [ "$j" -lt $((i + BATCH_SIZE)) ] && [ "$j" -lt "$CLASS_COUNT" ]; do
    ONLY_ARGS+=("-only-testing:${MODULE}/${CLASS_ARRAY[$j]}")
    NAMES="${NAMES}${CLASS_ARRAY[$j]} "
    j=$((j + 1))
  done

  BATCH_LOG="$LOG_DIR/batch-$(printf '%02d' "$BATCH").log"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'BATCH %d: %s\n' "$BATCH" "$NAMES"
    printf '  %s %s xcodebuild test -project %q -scheme %q -destination %q -derivedDataPath %q' \
      "$DISPLAY_TIMEOUT" "$TIMEOUT_SECS" "$PROJECT" "$SCHEME" "platform=macOS" "$DERIVED"
    if [ ${#SKIP_ARGS[@]} -gt 0 ]; then
      printf ' %q' "${SKIP_ARGS[@]}"
    fi
    printf ' %q' "${ONLY_ARGS[@]}"
    printf ' CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO > %q\n' "$BATCH_LOG"
    i=$((i + BATCH_SIZE))
    continue
  fi

  echo "BATCH $BATCH: $NAMES"
  set +e
  if [ ${#SKIP_ARGS[@]} -gt 0 ]; then
    (cd "$WORKDIR" && "$TIMEOUT_BIN" "$TIMEOUT_SECS" xcodebuild test \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination 'platform=macOS' \
      -derivedDataPath "$DERIVED" \
      "${SKIP_ARGS[@]}" \
      "${ONLY_ARGS[@]}" \
      CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO) > "$BATCH_LOG" 2>&1
  else
    (cd "$WORKDIR" && "$TIMEOUT_BIN" "$TIMEOUT_SECS" xcodebuild test \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination 'platform=macOS' \
      -derivedDataPath "$DERIVED" \
      "${ONLY_ARGS[@]}" \
      CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO) > "$BATCH_LOG" 2>&1
  fi
  STATUS=$?
  set -e

  if [ -n "$HOST_PATH" ]; then
    for p in $(pgrep -f -- "$HOST_PATH" 2>/dev/null || true); do
      kill "$p" 2>/dev/null || true
    done
  fi

  SUMMARY=$(grep -E "Executed [0-9]+ tests, with [0-9]+ failures?" "$BATCH_LOG" 2>/dev/null | tail -1 || true)
  if [ -z "$SUMMARY" ]; then
    HUNG_BATCHES=$((HUNG_BATCHES + 1))
    LINE="BATCH $BATCH HUNG/NO-SUMMARY status=$STATUS :: $NAMES"
    printf '%s\n' "$LINE" | tee -a "$SUMMARY_FILE"
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

  CLASSIFICATION="OK"
  if [ "$FAILS" -gt 0 ]; then
    CLASSIFICATION="TEST-FAILURES"
  elif [ "$STATUS" -ne 0 ]; then
    CLASSIFICATION="BUILD-OR-SETUP-FAILURE"
    BUILD_FAILURES=$((BUILD_FAILURES + 1))
  fi

  if [ "$STATUS" -ne 0 ] && [ "$TESTS" -lt "$BATCH_SIZE" ]; then
    CLASSIFICATION="${CLASSIFICATION}/LOW-TEST-COUNT"
    echo "WARN: batch $BATCH ran only $TESTS tests for $BATCH_SIZE classes; inspect build/setup errors" >&2
  fi

  TOTAL_TESTS=$((TOTAL_TESTS + TESTS))
  TOTAL_FAILURE_ASSERTIONS=$((TOTAL_FAILURE_ASSERTIONS + FAILS))
  TOTAL_FAILED_TESTS=$((TOTAL_FAILED_TESTS + FAILED_COUNT))
  if [ -n "$FAILED_NAMES" ]; then
    FAILED_TESTS_LIST="${FAILED_TESTS_LIST}${FAILED_NAMES}"$'\n'
  fi

  LINE="BATCH $BATCH status=$STATUS tests=$TESTS failure_assertions=$FAILS failed_tests=$FAILED_COUNT class=$CLASSIFICATION :: $NAMES"
  printf '%s\n' "$LINE" | tee -a "$SUMMARY_FILE"

  i=$((i + BATCH_SIZE))
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY-RUN complete; no xcodebuild invocation was executed"
  exit 0
fi

SKIPPED_DISPLAY="none"
if [ ${#SKIPS[@]} -gt 0 ]; then
  SKIPPED_DISPLAY=$(printf '%s, ' "${SKIPS[@]}")
  SKIPPED_DISPLAY=${SKIPPED_DISPLAY%, }
fi

COVERAGE="complete"
if [ ${#SKIPS[@]} -gt 0 ]; then
  COVERAGE="complete-with-skips"
fi
if [ "$HUNG_BATCHES" -gt 0 ] || [ "$BUILD_FAILURES" -gt 0 ]; then
  COVERAGE="incomplete"
fi

FINAL="TOTAL tests=$TOTAL_TESTS failure_assertions=$TOTAL_FAILURE_ASSERTIONS failed_tests=$TOTAL_FAILED_TESTS hung_batches=$HUNG_BATCHES build_or_setup_failures=$BUILD_FAILURES"
printf '%s\n' "$FINAL" | tee -a "$SUMMARY_FILE"
printf 'SKIPPED: %s\n' "$SKIPPED_DISPLAY" | tee -a "$SUMMARY_FILE"
printf 'COVERAGE: %s\n' "$COVERAGE" | tee -a "$SUMMARY_FILE"
if [ -n "$FAILED_TESTS_LIST" ]; then
  echo "FAILED_TESTS:"
  printf '%s' "$FAILED_TESTS_LIST" | sort -u
fi

if [ "$COVERAGE" != "complete" ]; then
  exit 2
fi
if [ "$TOTAL_FAILED_TESTS" -gt 0 ] || [ "$TOTAL_FAILURE_ASSERTIONS" -gt 0 ]; then
  exit 1
fi
exit 0
