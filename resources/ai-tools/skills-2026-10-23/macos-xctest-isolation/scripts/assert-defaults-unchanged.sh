#!/usr/bin/env bash

# Snapshot selected UserDefaults keys around a command and fail if any change.
set -uo pipefail

usage() {
    cat <<'EOF'
Usage:
  assert-defaults-unchanged.sh --domain <bundle-id> --keys <key1,key2> -- <command...>

Example:
  assert-defaults-unchanged.sh \
    --domain com.example.app \
    --keys last_left_path,last_right_path \
    -- xcodebuild test -project App.xcodeproj -scheme AppTests \
       -destination 'platform=macOS'

Exits 1 if a key was created, changed, or removed, or if the command failed.
EOF
}

domain=""
keys_csv=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)
            [[ $# -ge 2 ]] || { echo "ERROR: --domain requires a value" >&2; exit 2; }
            domain="$2"
            shift 2
            ;;
        --keys)
            [[ $# -ge 2 ]] || { echo "ERROR: --keys requires a value" >&2; exit 2; }
            keys_csv="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[[ -n "$domain" ]] || { echo "ERROR: --domain is required" >&2; exit 2; }
[[ -n "$keys_csv" ]] || { echo "ERROR: --keys is required" >&2; exit 2; }
[[ $# -gt 0 ]] || { echo "ERROR: command after -- is required" >&2; exit 2; }

IFS=',' read -r -a keys <<< "$keys_csv"
[[ ${#keys[@]} -gt 0 ]] || { echo "ERROR: --keys is empty" >&2; exit 2; }

for i in "${!keys[@]}"; do
    key="${keys[$i]}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    [[ -n "$key" ]] || { echo "ERROR: empty key in --keys" >&2; exit 2; }
    keys[$i]="$key"
done

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/defaults-guard.XXXXXX")" || exit 2
trap 'rm -rf "$tmpdir"' EXIT

snapshot() {
    local phase="$1"
    local idx=0
    for key in "${keys[@]}"; do
        idx=$((idx + 1))
        local value
        if value="$(defaults read "$domain" "$key" 2>/dev/null)"; then
            printf '%s' "$value" > "$tmpdir/${phase}.${idx}.value"
            printf 'set' > "$tmpdir/${phase}.${idx}.state"
        else
            : > "$tmpdir/${phase}.${idx}.value"
            printf 'unset' > "$tmpdir/${phase}.${idx}.state"
        fi
    done
}

describe() {
    local state="$1"
    local value="$2"
    if [[ "$state" == "unset" ]]; then
        printf '<unset>'
    else
        printf '%s' "$value" | head -n 1 | cut -c1-200
    fi
}

snapshot before

echo "Running command; defaults keys under guard: ${keys_csv}"
"$@"
cmd_status=$?

snapshot after

changed=0
idx=0
for key in "${keys[@]}"; do
    idx=$((idx + 1))
    before_state="$(cat "$tmpdir/before.${idx}.state")"
    before_value="$(cat "$tmpdir/before.${idx}.value")"
    after_state="$(cat "$tmpdir/after.${idx}.state")"
    after_value="$(cat "$tmpdir/after.${idx}.value")"

    if [[ "$before_state" == "$after_state" && "$before_value" == "$after_value" ]]; then
        printf 'PASS  %s: %s (unchanged)\n' "$key" "$(describe "$after_state" "$after_value")"
    else
        printf 'FAIL  %s: before=%s after=%s\n' \
            "$key" \
            "$(describe "$before_state" "$before_value")" \
            "$(describe "$after_state" "$after_value")"
        changed=1
    fi
done

if [[ $cmd_status -ne 0 ]]; then
    echo "FAIL: command exited with status $cmd_status"
    exit "$cmd_status"
fi

if [[ $changed -ne 0 ]]; then
    echo "FAIL: UserDefaults keys changed during the command"
    exit 1
fi

echo "PASS: all guarded UserDefaults keys unchanged"
exit 0
