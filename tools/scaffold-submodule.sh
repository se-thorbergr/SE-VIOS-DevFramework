#!/usr/bin/env bash
set -euo pipefail

# Scaffold and add a submodule (PB script or Mixin) from templates.
#
# Usage:
#   tools/scaffold-submodule.sh pbscript <repo-path> <remote-url> <ProjectName> \
#       [--sln <sln-file>] [--branch <branch>] [--readme] [--class <ClassName>] [--dry-run]
#   tools/scaffold-submodule.sh mixin    <repo-path> <remote-url> <ProjectName> \
#       [--sln <sln-file>] [--branch <branch>] [--readme] [--class <ClassName>] [--dry-run]
#
# Examples:
#   tools/scaffold-submodule.sh pbscript Scripts/VIOS.Minimal git@github.com:se-thorbergr/VIOS.Minimal.git VIOS.Minimal --sln SE-VIOS-DevFramework.sln
#   tools/scaffold-submodule.sh mixin    Mixins/Modules/Power  git@github.com:se-thorbergr/Power.git       Power         --sln SE-VIOS-DevFramework.sln --readme --class PowerModule
#
# Notes:
# - Copies from tools/templates/<kind> (must exist): .gitignore, .gitattributes, .editorconfig, Directory.Build.props
# - PB: copies __NAME__.csproj, __NAME__.mdk.ini, Program.cs
# - Mixin: copies __NAME__.csproj (if present) and **__NAME__.cs → <Class>.cs** (contains partial Program)
# - Placeholders replaced: __NAME__ (project/repo), __CLASS__ (primary type; defaults to sanitized ProjectName or --class)
# - SCAFFOLD-STRIP blocks are removed from copied files (between // SCAFFOLD-STRIP-START and // SCAFFOLD-STRIP-END)
# - Commits inside submodule (if changes) and attempts a push (non-fatal if it fails)
# - Records submodule pointer in the super repo and optionally adds project(s) to a solution
# - --dry-run: print planned actions only; DO NOT modify anything
#
# Requirements:
# - git, bash; optional: dotnet (for --sln integration), dos2unix (for CRLF->LF normalization)

# -------------------------
# Parse & validate args
# -------------------------
kind="${1:-}"; subpath="${2:-}"; remote="${3:-}"; proj="${4:-}"
if [[ -z "${kind}" || -z "${subpath}" || -z "${remote}" || -z "${proj}" ]]; then
  echo "Usage: tools/scaffold-submodule.sh <pbscript|mixin> <repo-path> <remote-url> <ProjectName> [--sln <sln-file>] [--branch <branch>] [--readme] [--class <ClassName>] [--dry-run]" >&2
  exit 2
fi
case "${kind}" in pbscript|mixin) ;; *) echo "Unknown kind: ${kind} (expected pbscript|mixin)" >&2; exit 2;; esac

shift 4 || true
sln=""; branch="main"; seed_readme=0; dry_run=0; class_name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sln)     sln="${2:-}"; shift 2;;
    --branch)  branch="${2:-}"; shift 2;;
    --readme)  seed_readme=1; shift 1;;
    --class)   class_name="${2:-}"; shift 2;;
    --dry-run) dry_run=1; shift 1;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

# -------------------------
# Setup
# -------------------------
repo_root="$(pwd)"
tmpl_root="tools/templates/${kind}"
if [[ ! -d "${tmpl_root}" ]]; then
  echo "Template not found: ${tmpl_root}" >&2
  exit 1
fi

# Derive default class name (sanitize) if not supplied
sanitize_class () {
  local raw="$1"
  # Replace invalid chars with underscore; ensure first char is letter or underscore
  local s="${raw//[^A-Za-z0-9_]/_}"
  [[ "$s" =~ ^[A-Za-z_] ]] || s="M_${s}"
  printf "%s" "$s"
}
if [[ -z "${class_name}" ]]; then
  class_name="$(sanitize_class "${proj}")"
else
  class_name="$(sanitize_class "${class_name}")"
fi

# Escapes for sed
escape_sed_repl () { printf '%s' "$1" | sed -e 's/[\/&\\]/\\&/g'; }
proj_escaped="$(escape_sed_repl "${proj}")"
class_escaped="$(escape_sed_repl "${class_name}")"

# Require git only in non-dry mode (dry-run can run even outside a git repo)
if [[ $dry_run -eq 0 ]]; then
  command -v git >/dev/null 2>&1 || { echo "git not found on PATH" >&2; exit 1; }
fi

# -------------------------
# Add submodule (idempotent)
# -------------------------
if [[ $dry_run -eq 1 ]]; then
  echo "Would add submodule ${remote} -> ${subpath} (branch: ${branch})"
else
  if git submodule status -- "${subpath}" >/dev/null 2>&1; then
    echo "Submodule already present at ${subpath} (skipping add)."
  else
    echo "Adding submodule ${remote} -> ${subpath} (branch: ${branch})"
    if ! git submodule add -b "${branch}" "${remote}" "${subpath}" 2>/dev/null; then
      echo "  note: remote may not expose branch '${branch}' yet; retrying without -b"
      git submodule add "${remote}" "${subpath}"
    fi
    git submodule update --init -- "${subpath}"
    git config -f .gitmodules "submodule.${subpath}.branch" "${branch}" || true
  fi
fi

# -------------------------
# Seeding files from template
# -------------------------
# In dry-run we don't pushd; we operate using dest_root=<subpath>
# In real mode we pushd into the submodule and set dest_root="." for simpler ops.
if [[ $dry_run -eq 1 ]]; then
  dest_root="${subpath}"
  echo "Would seed baseline files into ${subpath} from ${tmpl_root}"
else
  mkdir -p "${subpath}"
  pushd "${subpath}" >/dev/null
  dest_root="."
fi

# Copy helper with SCAFFOLD-STRIP filter and placeholder replacement
copy_with_filter () {
  local src="$1"; local dst="$2"
  local dst_dir
  dst_dir="$(dirname "${dst}")"

  if [[ $dry_run -eq 1 ]]; then
    if [[ -f "${dst}" ]]; then
      echo "  would keep existing: ${dst}"
      return 0
    fi
    if [[ -f "${src}" ]]; then
      echo "  would copy: ${src} -> ${dst}"
      # Mention SCAFFOLD-STRIP removal intent in dry-run
      if grep -q 'SCAFFOLD-STRIP-START' "${src}" 2>/dev/null; then
        echo "    (dry-run) would strip SCAFFOLD-STRIP blocks in ${dst}"
      fi
    else
      echo "  (template missing) ${src} (skipped)"
    fi
    return 0
  fi

  [[ -d "${dst_dir}" ]] || mkdir -p "${dst_dir}"

  if [[ -f "${dst}" ]]; then
    echo "  keep existing: ${dst}"
    return 0
  fi

  if [[ ! -f "${src}" ]]; then
    echo "  (template missing) ${src} (skipped)"
    return 0
  fi

  # Strip scaffold notes then write
  if grep -q 'SCAFFOLD-STRIP-START' "${src}" 2>/dev/null; then
    awk '
      BEGIN {drop=0}
      /SCAFFOLD-STRIP-START/ {drop=1; next}
      /SCAFFOLD-STRIP-END/   {drop=0; next}
      { if (!drop) print }
    ' "${src}" > "${dst}.tmp"
    mv "${dst}.tmp" "${dst}"
  else
    cp -f "${src}" "${dst}"
  fi

  # Placeholder replacements (both __NAME__ and __CLASS__)
  if command -v gsed >/dev/null 2>&1; then
    gsed -i -e "s/__NAME__/${proj_escaped}/g" -e "s/__CLASS__/${class_escaped}/g" "${dst}"
  else
    case "$(uname -s)" in
      Darwin) sed -i '' -e "s/__NAME__/${proj_escaped}/g" -e "s/__CLASS__/${class_escaped}/g" "${dst}" ;;
      *)      sed -i     -e "s/__NAME__/${proj_escaped}/g" -e "s/__CLASS__/${class_escaped}/g" "${dst}" ;;
    esac
  fi

  echo "  + ${dst}"
}

echo "Seeding baseline files from ${tmpl_root}…"
copy_with_filter "${repo_root}/${tmpl_root}/.gitignore"            "${dest_root}/.gitignore"
copy_with_filter "${repo_root}/${tmpl_root}/.gitattributes"        "${dest_root}/.gitattributes"
copy_with_filter "${repo_root}/${tmpl_root}/.editorconfig"         "${dest_root}/.editorconfig"
copy_with_filter "${repo_root}/${tmpl_root}/Directory.Build.props" "${dest_root}/Directory.Build.props"

if [[ "${kind}" == "pbscript" ]]; then
  copy_with_filter "${repo_root}/${tmpl_root}/__NAME__.csproj"     "${dest_root}/${proj}.csproj"
  copy_with_filter "${repo_root}/${tmpl_root}/__NAME__.mdk.ini"    "${dest_root}/${proj}.mdk.ini"
  copy_with_filter "${repo_root}/${tmpl_root}/Program.cs"          "${dest_root}/Program.cs"
else
  # mixin
  copy_with_filter "${repo_root}/${tmpl_root}/__NAME__.csproj"     "${dest_root}/${proj}.csproj"
  # The primary mixin source: __NAME__.cs → <ClassName>.cs (contains partial Program)
  copy_with_filter "${repo_root}/${tmpl_root}/__NAME__.cs"         "${dest_root}/${class_name}.cs"
fi

# Optional README (template if present; else minimal fallback)
if [[ ${seed_readme} -eq 1 ]]; then
  if [[ -f "${repo_root}/${tmpl_root}/README.md" ]]; then
    copy_with_filter "${repo_root}/${tmpl_root}/README.md" "${dest_root}/README.md"
  else
    if [[ $dry_run -eq 1 ]]; then
      if [[ ! -f "${dest_root}/README.md" ]]; then
        echo "  would create ${dest_root}/README.md (simple fallback)"
      else
        echo "  would keep existing: ${dest_root}/README.md"
      fi
    else
      if [[ ! -f "${dest_root}/README.md" ]]; then
        {
          echo "# ${proj}"
          echo
          echo "- Kind: ${kind}"
          echo "- Scaffolded from ${tmpl_root}"
        } > "${dest_root}/README.md"
        echo "  + ${dest_root}/README.md"
      fi
    fi
  fi
fi

# -------------------------
# Normalize CRLF -> LF (best-effort)
# -------------------------
normalize_glob() {
  local pattern="$1"
  if command -v dos2unix >/dev/null 2>&1; then
    if [[ $dry_run -eq 1 ]]; then
      if [[ -d "${dest_root}" ]]; then
        while IFS= read -r -d '' f; do
          echo "(dry-run) dos2unix -q ${f}"
        done < <(find "${dest_root}" -maxdepth 1 -type f -name "${pattern}" -print0)
      else
        echo "(dry-run) would normalize ${dest_root}/${pattern} to LF"
      fi
    else
      while IFS= read -r -d '' f; do
        dos2unix -q "${f}" 2>/dev/null || true
      done < <(find "${dest_root}" -maxdepth 1 -type f -name "${pattern}" -print0)
    fi
  fi
}
normalize_glob "*.csproj"
normalize_glob "*.cs"
normalize_glob "*.ini"
normalize_glob "*.md"

# -------------------------
# Commit & push inside submodule
# -------------------------
if [[ $dry_run -eq 1 ]]; then
  echo "Would 'git add/commit/push' inside ${subpath} if changes are present"
else
  if [[ -n "$(git -C "${subpath}" status --porcelain)" ]]; then
    git -C "${subpath}" add .
    git -C "${subpath}" commit -m "scaffold: initial import for ${proj} (${kind}) from template (class=${class_name})"
    git -C "${subpath}" push -u origin HEAD || echo "  (info) initial push failed or not permitted; you may push later"
  else
    echo "No changes to commit in submodule (already initialized)."
  fi
  popd >/dev/null
fi

# -------------------------
# Record in super-repo & optionally add to solution
# -------------------------
if [[ $dry_run -eq 1 ]]; then
  echo "Would stage .gitmodules and ${subpath}, commit 'chore(submodule): add ${proj}…', and push"
else
  git add .gitmodules "${subpath}" || true
  if ! git diff --cached --quiet; then
    git commit -m "chore(submodule): add ${proj} at ${subpath}"
    git push || echo "  (info) super-repo push skipped/failed; commit recorded locally"
  else
    echo "No super-repo changes to commit."
  fi
fi

# Solution integration (optional)
if [[ -n "${sln}" ]]; then
  if [[ -f "${sln}" ]]; then
    if command -v dotnet >/dev/null 2>&1; then
      if [[ $dry_run -eq 1 ]]; then
        echo "Would add any *.csproj under ${subpath} to solution ${sln} via 'dotnet sln add'"
      else
        echo "Adding project(s) under ${subpath} to solution ${sln}"
        added=0
        while IFS= read -r -d '' p; do
          echo "  dotnet sln add ${p}"
          dotnet sln "${sln}" add "${p}" || true
          added=1
        done < <(find "${subpath}" -maxdepth 1 -name "*.csproj" -print0)
        if [[ ${added} -eq 1 ]]; then
          git add "${sln}" && git commit -m "sln: add ${proj} project(s)" && git push || true
        fi
      fi
    else
      echo "dotnet CLI not found; skipping solution integration."
    fi
  else
    echo "Solution file not found: ${sln} (skipping sln add)"
  fi
fi

echo "✅ Done. Submodule ${proj} (${kind}) at ${subpath}${dry_run:+ (dry-run)} (class=${class_name})"
