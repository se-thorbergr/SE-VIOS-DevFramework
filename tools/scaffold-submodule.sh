#!/usr/bin/env bash
set -euo pipefail

# Scaffold and add a submodule (PB script or Mixin) from templates.
#
# Usage:
#   tools/scaffold-submodule.sh pbscript <repo-path> <remote-url> <ProjectName> [--sln SE-VIOS-DevFramework.sln] [--branch main] [--readme]
#   tools/scaffold-submodule.sh mixin    <repo-path> <remote-url> <ProjectName> [--sln SE-VIOS-DevFramework.sln] [--branch main] [--readme]
#
# Examples:
#   tools/scaffold-submodule.sh pbscript Scripts/VIOS.Minimal git@github.com:se-thorbergr/VIOS.Minimal.git VIOS.Minimal --sln SE-VIOS-DevFramework.sln
#   tools/scaffold-submodule.sh mixin Mixins/Modules/Power git@github.com:se-thorbergr/Power.git Power --sln SE-VIOS-DevFramework.sln --branch main --readme
#
# Notes:
# - Copies from tools/templates/<kind>/ (must contain baseline files).
# - Replaces __NAME__ in *.csproj, *.mdk.ini (pbscript), Program.cs, and README.md (if present).
# - Commits inside the submodule and pushes (first push may be no-op if remote has content protection).
# - Records submodule pointer and optionally adds the project to the solution.

kind="${1:-}"
subpath="${2:-}"
remote="${3:-}"
proj="${4:-}"
shift $(( $#>=4 ? 4 : $# ))

sln=""
branch="main"
seed_readme=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sln) sln="$2"; shift 2;;
    --branch) branch="$2"; shift 2;;
    --readme) seed_readme=1; shift 1;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ -z "$kind" || -z "$subpath" || -z "$remote" || -z "$proj" ]]; then
  echo "Usage: tools/scaffold-submodule.sh <pbscript|mixin> <repo-path> <remote-url> <ProjectName> [--sln <sln-file>] [--branch <branch>] [--readme]" >&2
  exit 2
fi

case "$kind" in
  pbscript|mixin) ;;
  *) echo "Unknown kind: $kind (expected pbscript|mixin)" >&2; exit 2;;
esac

repo_root="$(pwd)"
tmpl_root="tools/templates/${kind}"

if [[ ! -d "$tmpl_root" ]]; then
  echo "Template not found: $tmpl_root" >&2
  exit 1
fi

# 1) Add submodule pointing to remote on selected branch (fallback if branch not present)
if git submodule status -- "$subpath" >/dev/null 2>&1; then
  echo "Submodule already present at $subpath (skipping add)."
else
  echo "Adding submodule $remote -> $subpath (branch: $branch)"
  if ! git submodule add -b "$branch" "$remote" "$subpath"; then
    echo "Submodule add with -b '$branch' failed; retrying without -b (default branch)…"
    git submodule add "$remote" "$subpath"
  fi
fi

pushd "$subpath" >/dev/null

# 2) Copy template files (non-destructive: only if missing)
copy_if_missing () {
  local src="$1"; local dst="$2"
  if [[ -f "$dst" ]]; then
    echo "  keep existing: $dst"
  elif [[ -f "$src" ]]; then
    echo "  + $dst"
    cp "$src" "$dst"
  fi
}

echo "Seeding baseline files from $tmpl_root…"
copy_if_missing "$repo_root/$tmpl_root/.gitignore"              "./.gitignore"
copy_if_missing "$repo_root/$tmpl_root/.gitattributes"          "./.gitattributes"
copy_if_missing "$repo_root/$tmpl_root/.editorconfig"           "./.editorconfig"
copy_if_missing "$repo_root/$tmpl_root/Directory.Build.props"   "./Directory.Build.props"

if [[ "$kind" == "pbscript" ]]; then
  copy_if_missing "$repo_root/$tmpl_root/__NAME__.csproj"        "./${proj}.csproj"
  copy_if_missing "$repo_root/$tmpl_root/__NAME__.mdk.ini"       "./${proj}.mdk.ini"
  copy_if_missing "$repo_root/$tmpl_root/Program.cs"             "./Program.cs"
elif [[ "$kind" == "mixin" ]]; then
  copy_if_missing "$repo_root/$tmpl_root/__NAME__.csproj"        "./${proj}.csproj"
  copy_if_missing "$repo_root/$tmpl_root/Program.cs"             "./Program.cs"
  copy_if_missing "$repo_root/$tmpl_root/Class1.cs"              "./Class1.cs"
fi

# Optional README from template (or create a tiny one)
if [[ $seed_readme -eq 1 ]]; then
  if [[ -f "$repo_root/$tmpl_root/README.md" ]]; then
    copy_if_missing "$repo_root/$tmpl_root/README.md" "./README.md"
  else
    if [[ ! -f "./README.md" ]]; then
      echo "# ${proj}" > ./README.md
      echo "" >> ./README.md
      echo "- Kind: ${kind}" >> ./README.md
      echo "- Scaffolded from ${tmpl_root}" >> ./README.md
    fi
  fi
fi

# 3) Replace placeholders for friendliness
replace_placeholder () {
  local file="$1"
  [[ -f "$file" ]] || return 0
  # macOS/BSD sed compatibility: try gsed first, fallback to sed -i ''
  if command -v gsed >/dev/null 2>&1; then
    gsed -i "s/__NAME__/${proj}/g" "$file"
  else
    case "$(uname -s)" in
      Darwin) sed -i '' "s/__NAME__/${proj}/g" "$file" ;;
      *)      sed -i "s/__NAME__/${proj}/g" "$file" ;;
    esac
  fi
}

for f in "./${proj}.csproj" "./${proj}.mdk.ini" "./Program.cs" "./README.md"; do
  replace_placeholder "$f"
done

# 4) Initial commit inside submodule (only if there are staged/unstaged changes)
if [[ -n "$(git status --porcelain)" ]]; then
  git add .
  git commit -m "scaffold: initial import for ${proj} (${kind}) from template (incl. .editorconfig/.gitattributes)"
  # First push may fail if repo is protected/empty or you lack rights; ignore push failure
  git push -u origin HEAD || true
else
  echo "No changes to commit in submodule (already initialized)."
fi

popd >/dev/null

# 5) Record submodule pointer in super-repo
git add .gitmodules "$subpath" || true
if [[ -n "$(git status --porcelain | grep -E '(^A|^M).*\.gitmodules|^A|^M')" ]]; then
  git commit -m "chore(submodule): add ${proj} at ${subpath}"
  git push || true
else
  echo "No super-repo changes to commit."
fi

# 6) Optionally add project to solution
if [[ -n "$sln" ]]; then
  if [[ -f "$sln" ]]; then
    # Add all csproj in subpath (covers mixins with more than one in the future)
    added=0
    while IFS= read -r -d '' p; do
      echo "Adding to solution: $p"
      dotnet sln "$sln" add "$p" || true
      added=1
    done < <(find "$subpath" -maxdepth 1 -name "*.csproj" -print0)
    if [[ $added -eq 1 ]]; then
      git add "$sln"
      git commit -m "sln: add ${proj} project(s)"
      git push || true
    fi
  else
    echo "Solution file not found: $sln (skipping sln add)"
  fi
fi

echo "✅ Done. Submodule ${proj} (${kind}) at ${subpath}"
