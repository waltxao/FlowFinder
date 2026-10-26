#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: verify_app_copy.sh --built <App.app> --deployed <App.app> [options]

Read-only comparison of a built .app and the copy the user actually opens.
Never overwrites, launches, or terminates anything unless --launch is given.

Options:
  --bundle-id <id>  Require the deployed bundle ID to equal <id>.
  --full            Also compare a hash of all regular files in both bundles.
  --launch          Launch the deployed copy with `open -n` only when it matches.
  -h, --help        Show this help.

Exit codes:
  0  match
  1  mismatch
  2  usage or unreadable bundle
EOF
}

BUILT=""
DEPLOYED=""
EXPECTED_BUNDLE=""
FULL=0
LAUNCH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --built)
      [[ $# -ge 2 ]] || { echo "Missing value for --built" >&2; exit 2; }
      BUILT="$2"
      shift 2
      ;;
    --deployed)
      [[ $# -ge 2 ]] || { echo "Missing value for --deployed" >&2; exit 2; }
      DEPLOYED="$2"
      shift 2
      ;;
    --bundle-id)
      [[ $# -ge 2 ]] || { echo "Missing value for --bundle-id" >&2; exit 2; }
      EXPECTED_BUNDLE="$2"
      shift 2
      ;;
    --full)
      FULL=1
      shift
      ;;
    --launch)
      LAUNCH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$BUILT" || -z "$DEPLOYED" ]]; then
  echo "Both --built and --deployed are required." >&2
  usage >&2
  exit 2
fi

for app in "$BUILT" "$DEPLOYED"; do
  if [[ ! -d "$app" ]]; then
    echo "Not an app bundle directory: $app" >&2
    exit 2
  fi
  if [[ ! -f "$app/Contents/Info.plist" ]]; then
    echo "Missing Contents/Info.plist: $app" >&2
    exit 2
  fi
done

plist_raw() {
  /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null || true
}

hash_file() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

mtime_of() {
  /usr/bin/stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S%z' "$1"
}

require_value() {
  if [[ -z "$2" ]]; then
    echo "Missing $1 in $3" >&2
    exit 2
  fi
}

require_executable() {
  if [[ ! -x "$1" ]]; then
    echo "Missing or non-executable binary: $1" >&2
    exit 2
  fi
}

full_bundle_hash() {
  local app="$1"
  (
    cd "$app" || exit 2
    /usr/bin/find . -type f -print0 \
      | /usr/bin/xargs -0 /usr/bin/shasum -a 256 \
      | LC_ALL=C /usr/bin/sort \
      | /usr/bin/shasum -a 256 \
      | /usr/bin/awk '{print $1}'
  )
}

built_plist="$BUILT/Contents/Info.plist"
deployed_plist="$DEPLOYED/Contents/Info.plist"

built_bundle="$(plist_raw "$built_plist" CFBundleIdentifier)"
deployed_bundle="$(plist_raw "$deployed_plist" CFBundleIdentifier)"
require_value CFBundleIdentifier "$built_bundle" "$built_plist"
require_value CFBundleIdentifier "$deployed_bundle" "$deployed_plist"

built_version="$(plist_raw "$built_plist" CFBundleShortVersionString)"
deployed_version="$(plist_raw "$deployed_plist" CFBundleShortVersionString)"
require_value CFBundleShortVersionString "$built_version" "$built_plist"
require_value CFBundleShortVersionString "$deployed_version" "$deployed_plist"

built_build="$(plist_raw "$built_plist" CFBundleVersion)"
deployed_build="$(plist_raw "$deployed_plist" CFBundleVersion)"
require_value CFBundleVersion "$built_build" "$built_plist"
require_value CFBundleVersion "$deployed_build" "$deployed_plist"

built_exec_name="$(plist_raw "$built_plist" CFBundleExecutable)"
deployed_exec_name="$(plist_raw "$deployed_plist" CFBundleExecutable)"
require_value CFBundleExecutable "$built_exec_name" "$built_plist"
require_value CFBundleExecutable "$deployed_exec_name" "$deployed_plist"

built_exec="$BUILT/Contents/MacOS/$built_exec_name"
deployed_exec="$DEPLOYED/Contents/MacOS/$deployed_exec_name"
require_executable "$built_exec"
require_executable "$deployed_exec"

built_exec_hash="$(hash_file "$built_exec")"
deployed_exec_hash="$(hash_file "$deployed_exec")"
built_plist_hash="$(hash_file "$built_plist")"
deployed_plist_hash="$(hash_file "$deployed_plist")"

mismatches=0

mismatch() {
  echo "MISMATCH: $1" >&2
  mismatches=$((mismatches + 1))
}

[[ "$built_bundle" == "$deployed_bundle" ]] \
  || mismatch "bundle id: built=$built_bundle deployed=$deployed_bundle"

if [[ -n "$EXPECTED_BUNDLE" && "$deployed_bundle" != "$EXPECTED_BUNDLE" ]]; then
  mismatch "deployed bundle id: expected=$EXPECTED_BUNDLE actual=$deployed_bundle"
fi

[[ "$built_version" == "$deployed_version" ]] \
  || mismatch "short version: built=$built_version deployed=$deployed_version"

[[ "$built_build" == "$deployed_build" ]] \
  || mismatch "build version: built=$built_build deployed=$deployed_build"

[[ "$built_exec_hash" == "$deployed_exec_hash" ]] \
  || mismatch "executable hash differs"

if [[ "$built_plist_hash" != "$deployed_plist_hash" ]]; then
  echo "WARN: Info.plist differs; use --full to compare all bundle files." >&2
fi

built_full_hash=""
deployed_full_hash=""
if (( FULL )); then
  built_full_hash="$(full_bundle_hash "$BUILT")"
  deployed_full_hash="$(full_bundle_hash "$DEPLOYED")"
  [[ "$built_full_hash" == "$deployed_full_hash" ]] \
    || mismatch "full bundle content hash differs"
fi

echo "BUILT=$BUILT"
echo "DEPLOYED=$DEPLOYED"
echo "BUNDLE_ID=$deployed_bundle"
echo "VERSION=$deployed_version"
echo "BUILD=$deployed_build"
echo "BUILT_EXECUTABLE=$built_exec"
echo "DEPLOYED_EXECUTABLE=$deployed_exec"
echo "BUILT_EXECUTABLE_SHA256=$built_exec_hash"
echo "DEPLOYED_EXECUTABLE_SHA256=$deployed_exec_hash"
echo "BUILT_INFO_PLIST_SHA256=$built_plist_hash"
echo "DEPLOYED_INFO_PLIST_SHA256=$deployed_plist_hash"
echo "BUILT_MTIME=$(mtime_of "$BUILT")"
echo "DEPLOYED_MTIME=$(mtime_of "$DEPLOYED")"
if (( FULL )); then
  echo "BUILT_FULL_SHA256=$built_full_hash"
  echo "DEPLOYED_FULL_SHA256=$deployed_full_hash"
fi

if (( mismatches == 0 )); then
  echo "RESULT=MATCH"
  if (( LAUNCH )); then
    /usr/bin/open -n "$DEPLOYED"
    echo "LAUNCHED=$DEPLOYED"
  fi
  exit 0
fi

echo "RESULT=MISMATCH"
if (( LAUNCH )); then
  echo "NOT_LAUNCHED=mismatch detected" >&2
fi
exit 1
