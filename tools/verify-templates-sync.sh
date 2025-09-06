#!/usr/bin/env bash
set -euo pipefail

# Verify that submodules under Scripts/ and Mixins/ are in sync with templates.
# - For Scripts/* (pbscript) compare against tools/templates/pbscript
# - For Mixins/*  (mixin)    compare against tools/templates/mixin
# - Compares *presence* and *content* of baseline infra files; allows __NAME__ substitution.
# - Enforces MDK² role flag (Mdk2ProjectType) and package set per role.
#
# Changes vs previous:
# - MIXIN: no longer requires specific filenames (Program.cs / Class1.cs).
#          Instead: requires at least one *.cs that declares `partial class Program` (no visibility/base).
# - MIXIN & PB: csproj name can vary; we require exactly one *.csproj in the folder and validate content.
# - PB: still compares Program.cs to the template (entry driver is intentional & helpful to keep aligned).

# ---------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------
PB_TPL="tools/templates/pbscript"
MX_TPL="tools/templates/mixin"

# File maps per kind (template path -> submodule path) using __NAME__ placeholder
# PB scripts: keep Program.cs & __NAME__.mdk.ini comparisons; csproj name is resolved dynamically
PB_FILES=(
  ".gitignore:.gitignore"
  ".gitattributes:.gitattributes"
  ".editorconfig:.editorconfig"
  "Directory.Build.props:Directory.Build.props"
  "Program.cs:Program.cs"
  "__NAME__.mdk.ini:__NAME__.mdk.ini"
)
# Mixins: compare only infra & csproj; code files are flexible
MX_FILES=(
  ".gitignore:.gitignore"
  ".gitattributes:.gitattributes"
  ".editorconfig:.editorconfig"
  "Directory.Build.props:Directory.Build.props"
  "__NAME__.csproj:__NAME__.csproj"
)

fail=0

notice() { echo "::notice::$*"; }
warn()   { echo "::warning::$*"; }
err()    { echo "::error::$*"; fail=1; }

# ---------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------

# Show a unified diff if different, after substituting __NAME__ -> project name
diff_file() {
  local tpl="$1" dst="$2" proj="$3"
  if [[ ! -f "$dst" ]]; then
    err "Missing file: $dst"
    return 1
  fi
  if [[ ! -f "$tpl" ]]; then
    warn "Template missing: $tpl"
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  # Normalize line endings and substitute __NAME__
  sed "s/__NAME__/${proj}/g" "$tpl" | sed 's/\r$//' > "$tmp"
  if ! diff -u --strip-trailing-cr "$tmp" <(sed 's/\r$//' "$dst") >/dev/null; then
    echo "::group::Drift in $dst"
    diff -u --strip-trailing-cr "$tmp" <(sed 's/\r$//' "$dst") || true
    echo "::endgroup::"
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
  return 0
}

# Return exactly one match for pattern in dir (empty string if not exactly one)
one_file_or_empty() {
  local dir="$1" pattern="$2"
  shopt -s nullglob
  local arr=( "$dir"/$pattern )
  shopt -u nullglob
  if (( ${#arr[@]} == 1 )); then echo "${arr[0]}"; else echo ""; fi
}

# ---------------------------------------------------------------------
# PB script checks
# ---------------------------------------------------------------------
check_pbscript() {
  local mod="$1" # submodule path (e.g., Scripts/VIOS.Minimal)
  local proj
  proj="$(basename "$mod")"
  echo "== Scripts (pbscript) :: $mod =="

  # Presence + content vs template for infra & Program.cs & mdk.ini placeholder name
  for map in "${PB_FILES[@]}"; do
    IFS=: read -r src dst <<<"$map"
    local tpl="$PB_TPL/$src"
    local out="$mod/${dst/__NAME__/$proj}"
    if [[ ! -f "$out" ]]; then
      err "Missing in submodule: $out"
      continue
    fi
    diff_file "$tpl" "$out" "$proj" || true
  done

  # Program enclosure (strict)
  if ! grep -qE 'public\s+partial\s+class\s+Program\s*:\s*MyGridProgram' "$mod/Program.cs"; then
    err "$mod/Program.cs must declare 'public partial class Program : MyGridProgram'"
  fi

  # csproj: allow any name, but require exactly one
  local csproj; csproj="$(one_file_or_empty "$mod" "*.csproj")"
  if [[ -z "$csproj" ]]; then
    err "Expected exactly one .csproj in $mod"
  else
    # Role flag
    grep -q '<Mdk2ProjectType>mdk2pbscript</Mdk2ProjectType>' "$csproj" || \
      err "$csproj missing <Mdk2ProjectType>mdk2pbscript</Mdk2ProjectType>"
    # Packages
    grep -q 'Include="Mal.Mdk2.PbPackager"'  "$csproj" || err "$csproj missing Mal.Mdk2.PbPackager (PB scripts need it)"
    grep -q 'Include="Mal.Mdk2.PbAnalyzers"' "$csproj" || err "$csproj missing Mal.Mdk2.PbAnalyzers"
    grep -q 'Include="Mal.Mdk2.References"'  "$csproj" || err "$csproj missing Mal.Mdk2.References"
    # Also compare csproj content to template with placeholder (best-effort)
    diff_file "$PB_TPL/__NAME__.csproj" "$csproj" "$proj" || true
  fi

  # mdk.ini sanity — accept any name but require exactly one *.mdk.ini
  local ini; ini="$(one_file_or_empty "$mod" "*.mdk.ini")"
  if [[ -z "$ini" ]]; then
    err "Expected exactly one *.mdk.ini in $mod"
  else
    grep -q '^type=programmableblock' "$ini" || err "$ini should contain 'type=programmableblock'"
    # Compare to template placeholder if filename matches ${proj}.mdk.ini
    local expected="$mod/${proj}.mdk.ini"
    if [[ -f "$expected" ]]; then
      diff_file "$PB_TPL/__NAME__.mdk.ini" "$expected" "$proj" || true
    fi
  fi
}

# ---------------------------------------------------------------------
# Mixin checks
# ---------------------------------------------------------------------
check_mixin() {
  local mod="$1" # e.g. Mixins/VIOS.Core or Mixins/Modules/Power
  local proj
  proj="$(basename "$mod")"
  echo "== Mixins (mixin) :: $mod =="

  # Presence + content vs template (infra files only)
  for map in "${MX_FILES[@]}"; do
    IFS=: read -r src dst <<<"$map"
    local tpl="$MX_TPL/$src"
    local out="$mod/${dst/__NAME__/$proj}"
    # For csproj, we'll handle name-flex below, so skip comparing __NAME__.csproj here
    if [[ "$src" == "__NAME__.csproj" ]]; then
      continue
    fi
    if [[ ! -f "$out" ]]; then
      err "Missing in submodule: $out"
      continue
    fi
    diff_file "$tpl" "$out" "$proj" || true
  done

  # Enclosure rule: At least one *.cs declares 'partial class Program' (no visibility/base)
  if ! grep -RIl --include="*.cs" -E '(^|\s)partial\s+class\s+Program(\s*{|\s*$)' "$mod" >/dev/null 2>&1; then
    err "$mod must contain at least one *.cs declaring 'partial class Program' (no visibility/base)"
  fi
  # Ensure no mixin file inherits MyGridProgram
  if grep -RIl --include="*.cs" -E ':\s*MyGridProgram' "$mod" >/dev/null 2>&1; then
    err "$mod contains a mixin file inheriting MyGridProgram (not allowed in mixins)"
  fi

  # csproj: allow any name, but require exactly one, and validate
  local csproj; csproj="$(one_file_or_empty "$mod" "*.csproj")"
  if [[ -z "$csproj" ]]; then
    err "Expected exactly one .csproj in $mod"
  else
    grep -q '<Mdk2ProjectType>mdk2mixin</Mdk2ProjectType>' "$csproj" || \
      err "$csproj missing <Mdk2ProjectType>mdk2mixin</Mdk2ProjectType>"
    if grep -q 'Include="Mal.Mdk2.PbPackager"' "$csproj"; then
      err "$csproj must NOT include Mal.Mdk2.PbPackager"
    fi
    grep -q 'Include="Mal.Mdk2.PbAnalyzers"' "$csproj" || err "$csproj missing Mal.Mdk2.PbAnalyzers"
    grep -q 'Include="Mal.Mdk2.References"'  "$csproj" || err "$csproj missing Mal.Mdk2.References"
    # Try a best-effort diff against template with placeholder (won't block)
    diff_file "$MX_TPL/__NAME__.csproj" "$csproj" "$proj" || true
  fi
}

# ---------------------------------------------------------------------
# Walk submodules and check
# ---------------------------------------------------------------------
if [[ -d Scripts ]]; then
  while IFS= read -r -d '' mod; do
    check_pbscript "$mod"
  done < <(find Scripts -mindepth 1 -maxdepth 1 -type d -print0)
fi

if [[ -d Mixins ]]; then
  while IFS= read -r -d '' mod; do
    # Only check expected mixin roots: VIOS.Core, Modules/*, Components/*
    case "$mod" in
      Mixins/VIOS.Core|Mixins/Modules/*|Mixins/Components/*)
        check_mixin "$mod"
        ;;
      *) : ;; # ignore other dirs
    esac
  done < <(find Mixins -mindepth 1 -maxdepth 2 -type d -print0)
fi

if [[ $fail -ne 0 ]]; then
  err "Template sync FAILED ($fail issue(s))"
  exit 1
fi

notice "Template sync OK"
