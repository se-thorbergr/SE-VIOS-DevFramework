#!/usr/bin/env bash
# Policy: see docs/policies/VIOS-Template-Sync-Policy.md
# MODE: set MODE=STRICT to fail on semi-static (.csproj) drift; default RELAXED
set -euo pipefail

# Verify that submodules under Scripts/ and Mixins/ are in sync with templates.
# - For Scripts/* (pbscript) compare against tools/templates/pbscript
# - For Mixins/*  (mixin)    compare against tools/templates/mixin
# - Compares presence + content of baseline infra files; allows __NAME__ substitution.
# - Enforces MDK² role flag (Mdk2ProjectType) and package set per role.
#
# Flexible rules:
# - MIXIN: filenames are flexible. Require at least one *.cs declaring `partial class Program` (no visibility/base).
# - PB: Program.cs is not hard-diffed; we only enforce the MyGridProgram enclosure and require the file to exist.
# - Both: .csproj name can vary; must be exactly one and content validated.

# ---------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------
PB_TPL="tools/templates/pbscript"
MX_TPL="tools/templates/mixin"
MODE="${MODE:-RELAXED}"  # RELAXED (default) or STRICT

# File maps per kind (template path -> submodule path) using __NAME__ placeholder
# PB scripts: keep __NAME__.mdk.ini comparisons; csproj name is resolved dynamically
PB_FILES=(
  ".gitignore:.gitignore"
  ".gitattributes:.gitattributes"
  ".editorconfig:.editorconfig"
  "Directory.Build.props:Directory.Build.props"
  "__NAME__.mdk.ini:__NAME__.mdk.ini"
)
# Mixins: compare only infra; csproj validated separately; code files are flexible
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

# Summary buckets
missing_list=()
drift_list=()
violations_list=()

missing()   { echo "::error::Missing: $*";                   fail=1; missing_list+=("$*"); }
drift()     { echo "::warning::Drift vs template: $*";       drift_list+=("$*"); }
violation() { echo "::error::Validation: $*";                fail=1; violations_list+=("$*"); }

# ---------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------

_apply_ignores() {
  local path="$1"
  # cat normalized content from stdin to stdout with allowed differences stripped
  if [[ "$path" == *.csproj ]]; then
    # drop XML comments
    sed -E 's/<!--([^-]|-[^-]|--[^>])*-->//g' |
    # drop ItemGroup made only of ProjectReference
    sed -E ':a;N;$!ba; s#<ItemGroup>[[:space:]]*(<ProjectReference[^>]*>[^<]*</ProjectReference>[[:space:]]*)+</ItemGroup>##g' |
    # collapse whitespace
    tr -s '[:space:]' ' '
  elif [[ "$path" == */Program.cs ]]; then
    # strip leading banner comments (// …) before first using/namespace
    sed -E '1,/^(using|namespace)/{ s#^//.*$##; }'
  else
    cat
  fi
}

# Normalize endings to LF and substitute __NAME__ → project name
_subst_and_norm() {
  local src="$1" proj="$2"
  # substitute name, strip CR, strip UTF-8 BOM
  sed "s/__NAME__/${proj}/g" "$src" \
  | sed 's/\r$//' \
  | sed '1s/^\xEF\xBB\xBF//'
}

# Show unified diff if different, after substituting __NAME__ -> project name
diff_file() {
  local tpl="$1" dst="$2" proj="$3" kind="${4:-static}"  # kind: static | semi

  if [[ ! -f "$dst" ]]; then
    # Do not call err here; missing() already marks failure & records.
    missing "$dst"
    return 1
  fi
  if [[ ! -f "$tpl" ]]; then
    warn "Template missing: $tpl"
    return 0
  fi

  local left right
  left="$(mktemp)"; right="$(mktemp)"
  _subst_and_norm "$tpl" "$proj" | _apply_ignores "$dst" > "$left"
  sed 's/\r$//' "$dst" | sed '1s/^\xEF\xBB\xBF//' | _apply_ignores "$dst" > "$right"

  if ! diff -u --strip-trailing-cr "$left" "$right" >/dev/null; then
    echo "::group::Drift in $dst"
    diff -u --strip-trailing-cr "$left" "$right" || true
    echo "::endgroup::"
    # Record drift and decide whether it's fatal
    drift "$dst"
    if [[ "$kind" == "static" ]]; then
      # static drift is already an error
      fail=1
    else
      # semi-static drift (e.g., .csproj): only fail in STRICT mode
      [[ "$MODE" == "STRICT" ]] && fail=1
    fi
    rm -f "$left" "$right"
    return 1
  fi
  rm -f "$left" "$right"
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
  local proj; proj="$(basename "$mod")"
  echo "== Scripts (pbscript) :: $mod =="

  # Presence + content vs template (infra + nominal .mdk.ini)
  for map in "${PB_FILES[@]}"; do
    IFS=: read -r src dst <<<"$map"
    local tpl="$PB_TPL/$src"
    local out="$mod/${dst/__NAME__/$proj}"
    if [[ ! -f "$out" ]]; then
      missing "$out"
      continue
    fi
    diff_file "$tpl" "$out" "$proj" static || true
  done

  # Program.cs must exist and declare the enclosure (not hard-diffed)
  local pb_prog="$mod/Program.cs"
  if [[ ! -f "$pb_prog" ]]; then
    violation "$mod is missing Program.cs (required for PB scripts)"
  else
    if ! grep -Eq 'public[[:space:]]+partial[[:space:]]+class[[:space:]]+Program[[:space:]]*:[[:space:]]*MyGridProgram' "$pb_prog"; then
      violation "$pb_prog must declare 'public partial class Program : MyGridProgram'"
    fi
  fi

  # csproj: require exactly one, and validate role + package set; also try best-effort diff to template
  local csproj; csproj="$(one_file_or_empty "$mod" "*.csproj")"
  if [[ -z "$csproj" ]]; then
    violation "Expected exactly one .csproj in $mod"
  else
    grep -Eq '<Mdk2ProjectType>[[:space:]]*mdk2pbscript[[:space:]]*</Mdk2ProjectType>' "$csproj" \
      || violation "$csproj missing <Mdk2ProjectType>mdk2pbscript</Mdk2ProjectType>"
    grep -q 'Include="Mal.Mdk2.PbPackager"'  "$csproj" || violation "$csproj missing Mal.Mdk2.PbPackager (PB scripts need it)"
    grep -q 'Include="Mal.Mdk2.PbAnalyzers"' "$csproj" || violation "$csproj missing Mal.Mdk2.PbAnalyzers"
    grep -q 'Include="Mal.Mdk2.References"'  "$csproj" || violation "$csproj missing Mal.Mdk2.References"
    diff_file "$PB_TPL/__NAME__.csproj" "$csproj" "$proj" semi || true
  fi

  # mdk.ini: must exist (exactly one) and contain type=programmableblock
  local ini; ini="$(one_file_or_empty "$mod" "*.mdk.ini")"
  if [[ -z "$ini" ]]; then
    violation "Expected exactly one *.mdk.ini in $mod"
  else
    grep -Eiq '(^|[[:space:]])type[[:space:]]*=[[:space:]]*programmableblock([[:space:]]|$)' "$ini" \
      || violation "$ini should contain 'type=programmableblock'"
    # If the expected ${proj}.mdk.ini exists, compare to template strictly
    local expected="$mod/${proj}.mdk.ini"
    if [[ -f "$expected" ]]; then
      diff_file "$PB_TPL/__NAME__.mdk.ini" "$expected" "$proj" static || true
    fi
  fi
}

# ---------------------------------------------------------------------
# Mixin checks
# ---------------------------------------------------------------------
check_mixin() {
  local mod="$1"
  local proj; proj="$(basename "$mod")"
  echo "== Mixins (mixin) :: $mod =="

  # Infra vs template (skip __NAME__.csproj here; validated below)
  for map in "${MX_FILES[@]}"; do
    IFS=: read -r src dst <<<"$map"
    local tpl="$MX_TPL/$src"
    local out="$mod/${dst/__NAME__/$proj}"
    if [[ "$src" == "__NAME__.csproj" ]]; then
      continue
    fi
    if [[ ! -f "$out" ]]; then
      missing "$out"
      continue
    fi
    diff_file "$tpl" "$out" "$proj" static || true
  done

  # Enclosure: at least one *.cs declares 'partial class Program' (no visibility/base)
  if ! grep -RIl --include="*.cs" -E '(^|[[:space:]])partial[[:space:]]+class[[:space:]]+Program([[:space:]]*{|[[:space:]]*$)' "$mod" >/dev/null 2>&1; then
    violation "$mod must contain at least one *.cs declaring 'partial class Program' (no visibility/base)"
  fi
  # No MyGridProgram inheritance in mixins
  if grep -RIl --include="*.cs" -E ':[[:space:]]*MyGridProgram' "$mod" >/dev/null 2>&1; then
    violation "$mod contains a mixin file inheriting MyGridProgram (not allowed)"
  fi

  # csproj: require exactly one, validate role + packages; best-effort diff
  local csproj; csproj="$(one_file_or_empty "$mod" "*.csproj")"
  if [[ -z "$csproj" ]]; then
    violation "Expected exactly one .csproj in $mod"
  else
    grep -Eq '<Mdk2ProjectType>[[:space:]]*mdk2mixin[[:space:]]*</Mdk2ProjectType>' "$csproj" \
      || violation "$csproj missing <Mdk2ProjectType>mdk2mixin</Mdk2ProjectType>"
    if grep -q 'Include="Mal.Mdk2.PbPackager"' "$csproj"; then
      violation "$csproj must NOT include Mal.Mdk2.PbPackager"
    fi
    grep -q 'Include="Mal.Mdk2.PbAnalyzers"' "$csproj" || violation "$csproj missing Mal.Mdk2.PbAnalyzers"
    grep -q 'Include="Mal.Mdk2.References"'  "$csproj" || violation "$csproj missing Mal.Mdk2.References"
    diff_file "$MX_TPL/__NAME__.csproj" "$csproj" "$proj" semi || true
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
    case "$mod" in
      Mixins/VIOS.Core|Mixins/Modules/*|Mixins/Components/*)
        check_mixin "$mod"
        ;;
      *) : ;;
    esac
  done < <(find Mixins -mindepth 1 -maxdepth 2 -type d -print0)
fi

# ---------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------
echo "===== verify-templates-sync: Summary ====="
if ((${#missing_list[@]})); then
  echo "Missing files (${#missing_list[@]}):"
  for f in "${missing_list[@]}"; do echo "  - $f"; done
else
  echo "Missing files: none"
fi

if ((${#drift_list[@]})); then
  echo "Drift vs template (${#drift_list[@]}):"
  for f in "${drift_list[@]}"; do echo "  - $f"; done
else
  echo "Drift vs template: none"
fi

if ((${#violations_list[@]})); then
  echo "Validation issues (${#violations_list[@]}):"
  for m in "${violations_list[@]}"; do echo "  - $m"; done
else
  echo "Validation issues: none"
fi
echo "=========================================="

if [[ $fail -ne 0 ]]; then
  err "Template sync FAILED"
  exit 1
fi

notice "Template sync OK"
