#!/usr/bin/env bash
# Headless-friendly validator for docs/architecture/VIOS-Architecture.md
# Strategy: Docker mermaid-cli (preferred) → local mmdc with headless Chromium → Kroki HTTP render
# Fails with actionable guidance if none are available.
set -euo pipefail

DOC="docs/architecture/VIOS-Architecture.md"

die() { echo "::error::$*"; exit 1; }
warn() { echo "::warning::$*"; }
note() { echo "::notice::$*"; }

# ------------------------------------------------------------
# 0) Sanity: doc exists and headings are present
# ------------------------------------------------------------
[ -f "$DOC" ] || die "Missing $DOC"

grep -qE '^# +VIOS Architecture' "$DOC" \
  || die "Missing H1 '# VIOS Architecture'"

grep -qE '^## +2\. MDK² Hard Constraints & Enclosure Rule' "$DOC" \
  || die "Missing '## 2. MDK² Hard Constraints & Enclosure Rule'"

grep -qE '^## +3\. Repository & Project Layout' "$DOC" \
  || die "Missing '## 3. Repository & Project Layout'"

grep -qE '^## +6\. Kernel Lifecycle & Tick Pipeline' "$DOC" \
  || die "Missing '## 6. Kernel Lifecycle & Tick Pipeline'"

grep -qE '^## +16\. Diagrams \(Mermaid\)' "$DOC" \
  || die "Missing '## 16. Diagrams (Mermaid)'"

# PB vs Mixin enclosure examples present
grep -qE 'public[[:space:]]+partial[[:space:]]+class[[:space:]]+Program[[:space:]]*:[[:space:]]*MyGridProgram' "$DOC" \
  || die "Expected PB Script enclosure 'public partial class Program : MyGridProgram' not found in doc"

grep -qE 'partial[[:space:]]+class[[:space:]]+Program([[:space:]]*\{|[[:space:]]|$)' "$DOC" \
  || die "Expected Mixin enclosure 'partial class Program { ... }' not found in doc"

# ------------------------------------------------------------
# 1) Extract mermaid blocks into a temp workspace
# ------------------------------------------------------------
REPOROOT="$(pwd)"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# Normalize to pure ASCII arrows & safe chars for Mermaid v10
# (only for the temp files; does not modify your doc)
sanitize_line() {
  sed -e 's/→/->/g' -e 's/—/-/g' -e 's/–/-/g'
}

count=0
in_block=0
lineno=0
start_line=0
BLOCKS=()

while IFS='' read -r line; do
  lineno=$((lineno+1))
  if [[ $in_block -eq 0 && "$line" =~ ^\`\`\`mermaid ]]; then
    in_block=1
    start_line=$lineno
    fn="$TMPROOT/block_$count.mmd"
    : > "$fn"
    BLOCKS+=("$start_line:$fn")
    continue
  fi
  if [[ $in_block -eq 1 && "$line" =~ ^\`\`\`$ ]]; then
    in_block=0
    count=$((count+1))
    continue
  fi
  if [[ $in_block -eq 1 ]]; then
    printf '%s\n' "$line" | sanitize_line >> "$fn"
  fi
done < "$DOC"

[[ $count -gt 0 ]] || die "No mermaid code blocks found in $DOC (but 'Diagrams (Mermaid)' section exists)."

# ------------------------------------------------------------
# 2) Pick a renderer: Docker → local mmdc → Kroki
# ------------------------------------------------------------
have_docker() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

have_mmdc() {
  command -v mmdc >/dev/null 2>&1
}

have_kroki() {
  command -v curl >/dev/null 2>&1
}

# Renderers
render_with_docker() {
  local in="$1" out="$2"
  docker run --rm -v "$TMPROOT:/work" -w /work ghcr.io/mermaid-js/mermaid-cli:10 mmdc -i "$(basename "$in")" -o "$(basename "$out")" >/dev/null 2>&1
}

render_with_mmdc_headless() {
  local in="$1" out="$2"
  # 1) First try plain mmdc (respects PUPPETEER_EXECUTABLE_PATH if set)
  if mmdc -i "$in" -o "$out" >/dev/null 2>&1; then
    return 0
  fi

  # 2) Retry with explicit puppeteer config + headless flag variants
  local pconf="$TMPROOT/puppeteer.config.cjs"
  local exe="${PUPPETEER_EXECUTABLE_PATH:-}"
  if [[ -z "$exe" ]]; then
    exe="$(command -v chromium || true)"
    [[ -z "$exe" ]] && exe="$(command -v chromium-browser || true)"
    [[ -z "$exe" ]] && exe="$(command -v google-chrome || true)"
    [[ -z "$exe" ]] && exe="$(command -v google-chrome-stable || true)"
  fi

  # If we still don't have a browser, fail early
  if [[ -z "$exe" ]]; then
    return 1
  fi

  for head in "--headless=new" "--headless=chrome" "--headless"; do
    cat > "$pconf" <<EOF
module.exports = {
  executablePath: "$exe",
  args: [
    "$head",
    "--no-sandbox",
    "--disable-gpu",
    "--disable-dev-shm-usage"
  ]
};
EOF
    if mmdc -p "$pconf" -i "$in" -o "$out" >/dev/null 2>&1; then
      return 0
    fi
  done

  return 1
}

render_with_kroki() {
  # Kroki Mermaid API: https://kroki.io
  # POST mermaid source → SVG
  local in="$1" out="$2"
  curl -fsS -X POST -H "Content-Type: text/plain" --data-binary @"$in" https://kroki.io/mermaid/svg -o "$out" >/dev/null 2>&1
}

# Choose renderer
RENDER_MODE=""
if have_docker; then
  RENDER_MODE="docker"
elif have_mmdc; then
  RENDER_MODE="mmdc"
elif have_kroki; then
  RENDER_MODE="kroki"
else
  die "No renderer available. Install one of:\n - Docker (recommended) to use ghcr.io/mermaid-js/mermaid-cli\n - or mermaid-cli (npm i -g @mermaid-js/mermaid-cli@10) + chromium\n - or allow HTTP and install curl to use Kroki"
fi

# ------------------------------------------------------------
# 3) Render each block
# ------------------------------------------------------------
idx=0
for item in "${BLOCKS[@]}"; do
  start="${item%%:*}"
  file="${item##*:}"
  svg="$file.svg"

  if [[ "$RENDER_MODE" == "docker" ]]; then
    if ! render_with_docker "$file" "$svg"; then
      echo "::group::Mermaid block that failed (index $idx, lines $start-?)"
      cat "$file" || true
      echo "::endgroup::"
      die "Mermaid (Docker) compilation failed for block index $idx"
    fi
  elif [[ "$RENDER_MODE" == "mmdc" ]]; then
    if ! render_with_mmdc_headless "$file" "$svg"; then
      echo "::group::Mermaid block that failed (index $idx, lines $start-?)"
      cat "$file" || true
      echo "::endgroup::"
      # Helpful next steps:
      echo "::error::mmdc failed headlessly. Ensure chromium is installed and/or set PUPPETEER_EXECUTABLE_PATH to its path (e.g. /usr/bin/chromium)."
      die "Mermaid (mmdc) compilation failed for block index $idx"
    fi
  else
    if ! render_with_kroki "$file" "$svg"; then
      echo "::group::Mermaid block that failed (index $idx, lines $start-?)"
      cat "$file" || true
      echo "::endgroup::"
      die "Mermaid (Kroki) rendering failed for block index $idx"
    fi
  fi

  idx=$((idx+1))
done

note "Validated $DOC — $idx mermaid block(s) compiled successfully via $RENDER_MODE."
echo "OK"
