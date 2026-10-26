#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  bash fetch-phosphor.sh <destination-icons-dir> <icon-name> [icon-name ...]

Example:
  bash fetch-phosphor.sh /path/to/Resources/Icons file folder file-zip

Downloads from phosphor-icons/core:
  assets/regular/<name>.svg
  assets/duotone/<name>-duotone.svg
  LICENSE

Stores:
  <dest>/Phosphor/regular/<name>.svg
  <dest>/Phosphor/duotone/<name>-duotone.svg
  <dest>/Phosphor/LICENSE-phosphor.txt

Existing valid files are skipped. Delete a file to force a re-download.
Missing or invalid assets are reported and cause a non-zero exit.
EOF
  exit 2
}

[[ $# -ge 2 ]] || usage

DEST="${1%/}"
shift
NAMES=("$@")

BASE="https://raw.githubusercontent.com/phosphor-icons/core/main"
REGULAR_DIR="$DEST/Phosphor/regular"
DUOTONE_DIR="$DEST/Phosphor/duotone"
LICENSE_PATH="$DEST/Phosphor/LICENSE-phosphor.txt"

mkdir -p "$REGULAR_DIR" "$DUOTONE_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

download() {
  local url="$1"
  local out="$2"
  local kind="$3"

  if [[ -s "$out" ]]; then
    if [[ "$kind" != "svg" ]] || grep -q '<svg' "$out"; then
      echo "SKIP $out (valid existing file)"
      return 0
    fi
    echo "REPLACE $out (existing file is not an SVG)" >&2
    rm -f "$out"
  fi

  local tmpfile
  tmpfile="$(mktemp "$TMP_DIR/download.XXXXXX")"

  if ! curl -fsSL --retry 2 --connect-timeout 15 -o "$tmpfile" "$url"; then
    rm -f "$tmpfile"
    return 1
  fi

  if [[ ! -s "$tmpfile" ]]; then
    echo "Empty response: $url" >&2
    rm -f "$tmpfile"
    return 1
  fi

  if [[ "$kind" == "svg" ]] && ! grep -q '<svg' "$tmpfile"; then
    echo "Not an SVG: $url" >&2
    rm -f "$tmpfile"
    return 1
  fi

  mv "$tmpfile" "$out"
}

MISSING=()

for name in "${NAMES[@]}"; do
  if download "$BASE/assets/regular/$name.svg" "$REGULAR_DIR/$name.svg" svg; then
    echo "OK regular $name"
  else
    echo "MISSING regular $name ($BASE/assets/regular/$name.svg)" >&2
    MISSING+=("$name (regular)")
  fi

  if download "$BASE/assets/duotone/$name-duotone.svg" "$DUOTONE_DIR/$name-duotone.svg" svg; then
    echo "OK duotone $name"
  else
    echo "MISSING duotone $name ($BASE/assets/duotone/$name-duotone.svg)" >&2
    MISSING+=("$name (duotone)")
  fi
done

if download "$BASE/LICENSE" "$LICENSE_PATH" text; then
  echo "OK license"
else
  echo "MISSING license ($BASE/LICENSE)" >&2
  MISSING+=("LICENSE")
fi

if (( ${#MISSING[@]} > 0 )); then
  printf '\nMissing or invalid:\n' >&2
  printf '  - %s\n' "${MISSING[@]}" >&2
  echo "FAILED: ${#MISSING[@]} item(s) missing or invalid" >&2
  exit 1
fi

echo "DONE: ${#NAMES[@]} icon name(s), regular + duotone under $DEST/Phosphor"
