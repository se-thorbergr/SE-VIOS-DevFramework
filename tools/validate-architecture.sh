#!/usr/bin/env bash
# Simple validator for docs/architecture/VIOS-Architecture.md
# - Verifies structure/headings
# - Verifies MDK² enclosure snippet
# - Compiles all ```mermaid code fences via mermaid-cli
set -euo pipefail

DOC="docs/architecture/VIOS-Architecture.md"

die() { echo "::error::$*"; exit 1; }
note() { echo "::notice::$*"; }

[ -f "$DOC" ] || die "Missing $DOC"

# 1) Required headings (update these if you rename sections)
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

# 2) MDK² enclosure snippet present
grep -q 'namespace IngameScript' "$DOC" \
  || die "Expected enclosure snippet (namespace IngameScript) not found"
grep -q 'partial class Program' "$DOC" \
  || die "Expected enclosure snippet (partial class Program) not found"

# 3) Extract and compile all mermaid code fences
# Requires 'mmdc' (installed by CI step)
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

count=0
in_block=0
outfile=""
while IFS='' read -r line; do
  if [[ $in_block -eq 0 && "$line" =~ ^\`\`\`mermaid ]]; then
    in_block=1
    outfile="$TMPDIR/block_$count.mmd"
    : > "$outfile"
    continue
  fi
  if [[ $in_block -eq 1 && "$line" =~ ^\`\`\`$ ]]; then
    in_block=0
    # compile this block
    # mmdc needs an output file; we discard it to tmp
    if ! mmdc -i "$outfile" -o "$TMPDIR/block_$count.svg" >/dev/null 2>&1; then
      echo "::group::Mermaid block that failed (index $count)"
      cat "$outfile" || true
      echo "::endgroup::"
      die "Mermaid compilation failed for block index $count"
    fi
    count=$((count+1))
    continue
  fi
  if [[ $in_block -eq 1 ]]; then
    printf '%s\n' "$line" >> "$outfile"
  fi
done < "$DOC"

note "Validated $DOC — $count mermaid block(s) compiled successfully."

