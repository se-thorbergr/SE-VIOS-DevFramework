#!/usr/bin/env bash
set -euo pipefail

ROOT=${1:-.}
TEMPLATE="${TEMPLATE:-tools/license_header.tmpl}"
YEAR=${YEAR:-$(date -u +%Y)}
OWNER=${OWNER:-Thorbergr}
GITHUB_OWNER=${GITHUB_OWNER:-geho}
GITHUB_REPO=${GITHUB_REPO:-SE-VIOS-DevFramework}
WORKSHOP_ID=${WORKSHOP_ID:-0000000000}

render_template() {
  sed \
    -e "s/{{YEAR}}/${YEAR}/g" \
    -e "s/{{WORKSHOP_ID}}/${WORKSHOP_ID}/g" \
    -e "s/{{GITHUB_OWNER}}/${GITHUB_OWNER}/g" \
    -e "s/{{GITHUB_REPO}}/${GITHUB_REPO}/g" \
    "$TEMPLATE"
}

HEADER=$(render_template)

stamp_file() {
  local f="$1"
  # Skip if header already present
  if head -n 12 "$f" | grep -E "MIT License|Viking Industries Operating System" >/dev/null 2>&1; then
    return 0
  fi
  local tmp="${f}.tmp"
  { printf "%s\n\n" "$HEADER"; cat "$f"; } > "$tmp"
  mv "$tmp" "$f"
}

for d in Mixins Modules; do
  [ -d "$ROOT/$d" ] || { echo "Skip missing folder: $ROOT/$d"; continue; }
  while IFS= read -r -d '' f; do
  base=$(basename "$f")
  case "$base" in
    Program.cs|AssemblyInfo.cs) continue;;
  esac
  stamp_file "$f"
  done < <(find "$ROOT/$d" -type f -name "*.cs" -print0)
done

echo "Stamping complete."
