#!/usr/bin/env bash
set -euo pipefail

# Scaffold and add a submodule (PB script or Mixin) from templates.
# Usage:
#   tools/scaffold-submodule.sh pbscript <repo-path> <remote-url> <ProjectName> [--sln SE-VIOS-DevFramework.sln]
#   tools/scaffold-submodule.sh mixin    <repo-path> <remote-url> <ProjectName> [--sln SE-VIOS-DevFramework.sln]
#
# Examples:
#   tools/scaffold-submodule.sh pbscript Scripts/VIOS.Minimal git@github.com:se-thorbergr/VIOS.Minimal.git VIOS.Minimal --sln SE-VIOS-DevFramework.sln
#   tools/scaffold-submodule.sh mixin Mixins/Modules/Power git@github.com:se-thorbergr/Power.git Power --sln SE-VIOS-DevFramework.sln

kind="${1:-}"
subpath="${2:-}"
remote="${3:-}"
proj="${4:-}"
shift $(( $#>=4 ? 4 : $# ))

sln=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sln) sln="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ -z "$kind" || -z "$subpath" || -z "$remote" || -z "$proj" ]]; then
  echo "Usage: tools/scaffold-submodule.sh <pbscript|mixin> <repo-path> <remote-url> <ProjectName> [--sln <sln-file>]" >&2
  exit 2
fi

repo_root="$(pwd)"
tmpl_root="tools/templates/${kind}"

if [[ ! -d "$tmpl_root" ]]; then
  echo "Template not found: $tmpl_root" >&2
  exit 1
fi

# 1) Add submodule pointing to remote on 'main' (or default)
git submodule add -b main "$remote" "$subpath" || git submodule add "$remote" "$subpath"

pushd "$subpath" >/dev/null

# 2) Copy template files
cp -n "$repo_root/$tmpl_root/.gitignore" . || true
cp -n "$repo_root/$tmpl_root/.gitattributes" . || true
cp -n "$repo_root/$tmpl_root/Directory.Build.props" . || true

if [[ "$kind" == "pbscript" ]]; then
  cp -n "$repo_root/$tmpl_root/__NAME__.csproj" "./${proj}.csproj"
  cp -n "$repo_root/$tmpl_root/__NAME__.mdk.ini" "./${proj}.mdk.ini"
  cp -n "$repo_root/$tmpl_root/Program.cs" "./Program.cs"
elif [[ "$kind" == "mixin" ]]; then
  cp -n "$repo_root/$tmpl_root/__NAME__.csproj" "./${proj}.csproj"
  cp -n "$repo_root/$tmpl_root/Program.cs" "./Program.cs"
  cp -n "$repo_root/$tmpl_root/Class1.cs" "./Class1.cs"
else
  echo "Unknown kind: $kind" >&2; exit 2
fi

# 3) Replace placeholders in Program.cs for friendly hello (scripts)
if [[ -f Program.cs ]]; then
  sed -i "s/__NAME__/${proj}/g" Program.cs || true
fi

# 4) Initial commit inside submodule
git add .
git commit -m "chore: scaffold ${proj} (${kind}) from template"

# 5) Push submodule
git push -u origin HEAD || true

popd >/dev/null

# 6) Record submodule pointer in super-repo
git add "$subpath"
git commit -m "chore: add submodule ${proj} at ${subpath}"

# 7) Optionally add to solution
if [[ -n "$sln" ]]; then
  if [[ -f "$sln" ]]; then
    dotnet sln "$sln" add "$subpath/${proj}.csproj" || true
    git add "$sln"
    git commit -m "chore: add ${proj} to solution"
  else
    echo "Solution file not found: $sln (skipping sln add)"
  fi
fi

echo "Done. Submodule ${proj} (${kind}) at ${subpath}"

