#!/usr/bin/env bash
set -euo pipefail

# Verify that submodules under Scripts/ and Mixins/ are in sync with templates.
# - For Scripts/* (pbscript) compare against tools/templates/pbscript
# - For Mixins/*  (mixin)    compare against tools/templates/mixin
# - Compares *presence* and *content* of baseline files; allows __NAME__ substitution.
# - Enforces MDK² role flag (Mdk2ProjectType) and package set per role.

# ---------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------
PB_TPL="tools/templates/pbscript"
MX_TPL="tools/templates/mixin"

# File maps per kind (template path -> submodule path) using __NAME__ placeholder
PB_FILES=(
  ".gitignore:.gitignore"
  ".gitattributes:.gitattributes"
  ".editorconfig:.editorconfig"
  "Directory.Build.props:Directory.Build.props"
  "Program.cs:Program.cs"
  "__NAME__.csproj:__NAME__.csproj"
  "__NAME__.mdk.ini:__NAME__.mdk.ini"
)
MX_FILES=(
  ".gitignore:.gitignore"
  ".gitattributes:.gitattributes"
  ".editorconfig:.editorconfig"
  "Directory.Build.props:Directory.Build.props"
  "Program.cs:Program.cs"
  "__NAME__.csproj:__NAME__.csproj"
  "Class1.cs:Class1.cs"
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

# ---------------------------------------------------------------------
# PB script checks
# ---------------------------------------------------------------------
check_pbscript() {
  local mod="$1" # submodule path (e.g., Scripts/VIOS.Minimal)
  local proj
  proj="$(basename "$mod")"
  echo "== Scripts (pbscript) :: $mod =="

  # Presence + content vs template
  for map in "${PB_FILES[@]}"; do
    IFS=: read -r src dst <<<"$map"
    local tpl="$PB_TPL/$src"
    local out="$mod/${dst/__NAME__/$proj}"
    if [[ ! -f "$out" ]]; then
      err "Missing in submodule: $out"
      continue
    fi
    diff_file "$tpl" "$out" "$proj" || fail=1
  done

  # Program enclosure
  if ! grep -qE 'public\s+partial\s+class\s+Program\s*:\s*MyGridProgram' "$mod/Program.cs"; then
    err "$mod/Program.cs must declare 'public partial class Program : MyGridProgram'"
  fi

  # csproj role + package set
  local csproj="$mod/${proj}.csproj"
  if [[ -f "$csproj" ]]; then
    if ! grep -q '<Mdk2ProjectType>mdk2pbscript</Mdk2ProjectType>' "$csproj"; then
      err "$csproj missing <Mdk2ProjectType>mdk2pbscript</Mdk2ProjectType>"
    fi
    if ! grep -q 'Include="Mal.Mdk2.PbPackager"' "$csproj"; then
      err "$csproj missing Mal.Mdk2.PbPackager (PB scripts need it)"
    fi
    if ! grep -q 'Include="Mal.Mdk2.PbAnalyzers"' "$csproj"; then
      err "$csproj missing Mal.Mdk2.PbAnalyzers"
    fi
    if ! grep -q 'Include="Mal.Mdk2.References"' "$csproj"; then
      err "$csproj missing Mal.Mdk2.References"
    fi
  else
    err "Missing csproj: $csproj"
  fi

  # mdk.ini sanity
  local ini="$mod/${proj}.mdk.ini"
  if [[ -f "$ini" ]]; then
    if ! grep -q '^type=programmableblock' "$ini"; then
      err "$ini should contain 'type=programmableblock'"
    fi
  else
    err "Missing mdk.ini: $ini"
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

  # Presence + content vs template
  for map in "${MX_FILES[@]}"; do
    IFS=: read -r src dst <<<"$map"
    local tpl="$MX_TPL/$src"
    local out="$mod/${dst/__NAME__/$proj}"
    if [[ ! -f "$out" ]]; then
      err "Missing in submodule: $out"
      continue
    fi
    diff_file "$tpl" "$out" "$proj" || fail=1
  done

  # Program enclosure: MUST be partial (no visibility or base)
  if ! grep -qE '(^|\s)partial\s+class\s+Program(\s*{|\s*$)' "$mod/Program.cs"; then
    err "$mod/Program.cs must declare 'partial class Program' (no visibility/base)"
  fi
  if grep -qE ':\s*MyGridProgram' "$mod/Program.cs"; then
    err "$mod/Program.cs should NOT inherit MyGridProgram in mixins"
  fi

  # csproj role + package set
  local csproj="$mod/${proj}.csproj"
  if [[ -f "$csproj" ]]; then
    if ! grep -q '<Mdk2ProjectType>mdk2mixin</Mdk2ProjectType>' "$csproj"; then
      err "$csproj missing <Mdk2ProjectType>mdk2mixin</Mdk2ProjectType>"
    fi
    if grep -q 'Include="Mal.Mdk2.PbPackager"' "$csproj"; then
      err "$csproj must NOT include Mal.Mdk2.PbPackager"
    fi
    if ! grep -q 'Include="Mal.Mdk2.PbAnalyzers"' "$csproj"; then
      err "$csproj missing Mal.Mdk2.PbAnalyzers"
    fi
    if ! grep -q 'Include="Mal.Mdk2.References"' "$csproj"; then
      err "$csproj missing Mal.Mdk2.References"
    fi
  else
    err "Missing csproj: $csproj"
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
