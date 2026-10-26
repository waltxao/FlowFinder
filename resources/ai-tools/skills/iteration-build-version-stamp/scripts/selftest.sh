#!/bin/bash
# Fixture-based self-test for bump-version.sh.
# It never reads or modifies a real Xcode project.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUMP="$SCRIPT_DIR/bump-version.sh"
TODAY="261022"
TMP_DIR=""
FAILURES=0
LAST_OUTPUT=""
LAST_ERROR=""
LAST_STATUS=0

cleanup() {
  if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bump-version-selftest.XXXXXX")"

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

new_fixture() {
  local path="$1"
  cat > "$path" <<'EOF'
// !$*UTF8*$!
{
  objects = {
    CONFIG_A = {
      buildSettings = {
        CURRENT_PROJECT_VERSION = 8001;
        MARKETING_VERSION = 0.8.0;
      };
    };
    CONFIG_B = {
      buildSettings = {
        CURRENT_PROJECT_VERSION = 8001;
        MARKETING_VERSION = 0.8.0;
      };
    };
  };
}
EOF
}

set_all_builds() {
  local file="$1"
  local value="$2"
  sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = ${value};/g" "$file"
}

set_mixed_builds() {
  local file="$1"
  local first="$2"
  local second="$3"
  awk -v first="$first" -v second="$second" '
    /CURRENT_PROJECT_VERSION = / {
      seen++
      if (seen == 1) {
        sub(/CURRENT_PROJECT_VERSION = [^;]+;/, "CURRENT_PROJECT_VERSION = " first ";")
      } else {
        sub(/CURRENT_PROJECT_VERSION = [^;]+;/, "CURRENT_PROJECT_VERSION = " second ";")
      }
    }
    { print }
  ' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

hash_file() {
  shasum "$1" | awk '{ print $1 }'
}

count_matches() {
  grep -c "$2" "$1" 2>/dev/null || true
}

run_capture() {
  local out_file="$TMP_DIR/capture.out"
  local err_file="$TMP_DIR/capture.err"
  set +e
  "$@" > "$out_file" 2> "$err_file"
  LAST_STATUS=$?
  set -e
  LAST_OUTPUT="$(cat "$out_file")"
  LAST_ERROR="$(cat "$err_file")"
}

# Same-day dry-run: 01 -> 02, zero writes.
f="$TMP_DIR/same-day.pbxproj"
new_fixture "$f"
set_all_builds "$f" "${TODAY}01"
before="$(hash_file "$f")"
run_capture bash "$BUMP" --pbxproj "$f" --dry-run --date "$TODAY"
after="$(hash_file "$f")"
if [[ "$LAST_STATUS" -eq 0 ]]; then pass "same-day dry-run exits 0"; else fail "same-day dry-run exited $LAST_STATUS: $LAST_OUTPUT"; fi
if [[ "$before" == "$after" ]]; then pass "same-day dry-run does not write"; else fail "same-day dry-run modified the file"; fi
if grep -q '^NEW_BUILD=26102202$' <<< "$LAST_OUTPUT"; then pass "same-day increments to 02"; else fail "same-day output was: $LAST_OUTPUT"; fi
if grep -q '^BRANCH=increment$' <<< "$LAST_OUTPUT"; then pass "same-day reports increment branch"; else fail "same-day branch was not increment"; fi

# Cross-day dry-run: yesterday -> today 01.
f="$TMP_DIR/cross-day.pbxproj"
new_fixture "$f"
set_all_builds "$f" "26102103"
run_capture bash "$BUMP" --pbxproj "$f" --dry-run --quiet --date "$TODAY"
if [[ "$LAST_STATUS" -eq 0 && "$LAST_OUTPUT" == "26102201" ]]; then
  pass "cross-day resets to 01"
else
  fail "cross-day expected 26102201, got status $LAST_STATUS: $LAST_OUTPUT"
fi

# Legacy 8001 -> today 01; both configs updated; marketing untouched; mode preserved.
f="$TMP_DIR/legacy.pbxproj"
new_fixture "$f"
chmod 640 "$f"
run_capture bash "$BUMP" --pbxproj "$f" --quiet --date "$TODAY"
if [[ "$LAST_STATUS" -eq 0 && "$LAST_OUTPUT" == "26102201" ]]; then
  pass "legacy value writes today 01"
else
  fail "legacy write expected 26102201, got status $LAST_STATUS: $LAST_OUTPUT"
fi
if [[ "$(count_matches "$f" 'CURRENT_PROJECT_VERSION = 26102201;')" -eq 2 ]]; then
  pass "legacy write updates every config"
else
  fail "legacy write did not update every config"
fi
if [[ "$(count_matches "$f" 'MARKETING_VERSION = 0.8.0;')" -eq 2 ]]; then
  pass "MARKETING_VERSION is preserved"
else
  fail "MARKETING_VERSION changed or disappeared"
fi
if [[ "$(stat -f '%Lp' "$f")" == "640" ]]; then
  pass "file mode is preserved"
else
  fail "file mode changed to $(stat -f '%Lp' "$f")"
fi

# Empty value -> today 01.
f="$TMP_DIR/empty.pbxproj"
new_fixture "$f"
set_all_builds "$f" ""
run_capture bash "$BUMP" --pbxproj "$f" --dry-run --date "$TODAY"
if [[ "$LAST_STATUS" -eq 0 ]] && grep -q '^NEW_BUILD=26102201$' <<< "$LAST_OUTPUT"; then
  pass "empty value resets to 01"
else
  fail "empty value expected 26102201, got status $LAST_STATUS: $LAST_OUTPUT"
fi
if grep -q '^BRANCH=reset-empty$' <<< "$LAST_OUTPUT"; then
  pass "empty value reports reset-empty branch"
else
  fail "empty value branch was wrong"
fi

# 99 -> refuse to build a 9-digit value, no write.
f="$TMP_DIR/limit.pbxproj"
new_fixture "$f"
set_all_builds "$f" "${TODAY}99"
before="$(hash_file "$f")"
run_capture bash "$BUMP" --pbxproj "$f" --date "$TODAY"
if [[ "$LAST_STATUS" -eq 1 ]] && grep -q 'exceeded 99' <<< "$LAST_ERROR"; then
  pass "99 is rejected"
else
  fail "99 expected exit 1, got status $LAST_STATUS: $LAST_ERROR"
fi
if [[ "$before" == "$(hash_file "$f")" ]]; then
  pass "99 rejection does not write"
else
  fail "99 rejection modified the file"
fi

# Different config values -> fail without writing.
f="$TMP_DIR/mismatch.pbxproj"
new_fixture "$f"
set_mixed_builds "$f" "${TODAY}01" "${TODAY}02"
before="$(hash_file "$f")"
run_capture bash "$BUMP" --pbxproj "$f" --date "$TODAY"
if [[ "$LAST_STATUS" -eq 1 ]] && grep -q 'values differ' <<< "$LAST_ERROR"; then
  pass "mismatched configs are rejected"
else
  fail "mismatch expected exit 1, got status $LAST_STATUS: $LAST_ERROR"
fi
if [[ "$before" == "$(hash_file "$f")" ]]; then
  pass "mismatch rejection does not write"
else
  fail "mismatch rejection modified the file"
fi

# Non-literal value -> fail without overwriting a build-setting reference.
f="$TMP_DIR/non-literal.pbxproj"
cat > "$f" <<'EOF'
{
  buildSettings = {
    CURRENT_PROJECT_VERSION = $(FF_BUILD);
    MARKETING_VERSION = 0.8.0;
  };
}
EOF
run_capture bash "$BUMP" --pbxproj "$f" --date "$TODAY"
if [[ "$LAST_STATUS" -eq 1 ]] && grep -q 'literal number' <<< "$LAST_ERROR"; then
  pass "non-literal value is rejected"
else
  fail "non-literal expected exit 1, got status $LAST_STATUS: $LAST_ERROR"
fi

# Missing key -> fail.
f="$TMP_DIR/missing.pbxproj"
cat > "$f" <<'EOF'
{
  buildSettings = {
    MARKETING_VERSION = 0.8.0;
  };
}
EOF
run_capture bash "$BUMP" --pbxproj "$f" --date "$TODAY"
if [[ "$LAST_STATUS" -eq 1 ]] && grep -q 'no CURRENT_PROJECT_VERSION' <<< "$LAST_ERROR"; then
  pass "missing key is rejected"
else
  fail "missing key expected exit 1, got status $LAST_STATUS: $LAST_ERROR"
fi

# Invalid date -> fail.
f="$TMP_DIR/invalid-date.pbxproj"
new_fixture "$f"
run_capture bash "$BUMP" --pbxproj "$f" --dry-run --date "261332"
if [[ "$LAST_STATUS" -eq 1 ]] && grep -q 'not a valid calendar date' <<< "$LAST_ERROR"; then
  pass "invalid date is rejected"
else
  fail "invalid date expected exit 1, got status $LAST_STATUS: $LAST_ERROR"
fi

# Unknown argument -> usage error.
run_capture bash "$BUMP" --pbxproj "$f" --wat
if [[ "$LAST_STATUS" -eq 2 ]]; then
  pass "unknown argument exits 2"
else
  fail "unknown argument expected exit 2, got $LAST_STATUS"
fi

# Help -> exit 0.
run_capture bash "$BUMP" --help
if [[ "$LAST_STATUS" -eq 0 ]] && grep -q '^Usage:' <<< "$LAST_OUTPUT"; then
  pass "help exits 0"
else
  fail "help expected exit 0, got $LAST_STATUS"
fi

if [[ "$FAILURES" -ne 0 ]]; then
  printf '\n%d test(s) failed\n' "$FAILURES" >&2
  exit 1
fi

printf '\nALL TESTS PASSED\n'
