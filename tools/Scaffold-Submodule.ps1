#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Scaffold and add a submodule (PB script or Mixin) from templates.

.DESCRIPTION
  - Creates/links a Git submodule at the given path.
  - Seeds it from tools/templates/<kind> with baseline files:
      .editorconfig, .gitattributes, .gitignore, Directory.Build.props,
      __NAME__.csproj (+ __NAME__.mdk.ini for pbscript), Program.cs, etc.
  - Replaces __NAME__ in .csproj / .mdk.ini / Program.cs / README.md.
  - Commits and pushes inside the submodule (non-fatal if push blocked).
  - Records the submodule pointer in the super-repo.
  - Optionally adds the project to the solution (.sln).

.EXAMPLE
  tools/Scaffold-Submodule.ps1 -Kind pbscript `
    -DestPath Scripts/VIOS.Minimal `
    -RemoteUrl git@github.com:se-thorbergr/VIOS.Minimal.git `
    -ProjectName VIOS.Minimal `
    -Sln SE-VIOS-DevFramework.sln `
    -Branch main `
    -Readme

.EXAMPLE
  tools/Scaffold-Submodule.ps1 -Kind mixin `
    -DestPath Mixins/Modules/Power `
    -RemoteUrl git@github.com:se-thorbergr/Power.git `
    -ProjectName Power -Sln SE-VIOS-DevFramework.sln
#>

param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("pbscript","mixin")]
  [string]$Kind,

  [Parameter(Mandatory=$true)]
  [string]$DestPath,

  [Parameter(Mandatory=$true)]
  [string]$RemoteUrl,

  [Parameter(Mandatory=$true)]
  [string]$ProjectName,

  [string]$Sln = "",
  [string]$Branch = "main",
  [switch]$Readme
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Info($msg) { Write-Host "› $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Warning $msg }
function Write-Ok($msg)   { Write-Host "✓ $msg" -ForegroundColor Green }

# Resolve repo root (script lives in tools/)
$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot  = Resolve-Path (Join-Path $ScriptDir "..")
$TemplateDir = Join-Path $ScriptDir ("templates/" + $Kind)

if (-not (Test-Path $TemplateDir)) {
  throw "Template dir missing: $TemplateDir"
}

# Ensure parent folder of DestPath exists
$Parent = Split-Path -Parent $DestPath
if ($Parent -and -not (Test-Path $Parent)) {
  New-Item -ItemType Directory -Path $Parent | Out-Null
}

# Helper: non-destructive copy
function Copy-IfMissing([string]$Src, [string]$Dst) {
  if (Test-Path $Dst) {
    Write-Info "keep existing: $Dst"
  } elseif (Test-Path $Src) {
    Write-Info "add: $Dst"
    Copy-Item -LiteralPath $Src -Destination $Dst -Force
  }
}

# 1) Add submodule (skip if already present)
$submoduleExists = $false
try {
  git submodule status -- "$DestPath" | Out-Null
  $submoduleExists = $LASTEXITCODE -eq 0
} catch { $submoduleExists = $false }

if ($submoduleExists) {
  Write-Info "Submodule already present at $DestPath (skipping add)."
} else {
  Write-Info "Adding submodule: $RemoteUrl -> $DestPath (branch: $Branch)"
  $added = $true
  try {
    git submodule add -b $Branch $RemoteUrl $DestPath | Out-Null
  } catch {
    Write-Warn "Adding with '-b $Branch' failed; retry default branch."
    try {
      git submodule add $RemoteUrl $DestPath | Out-Null
    } catch {
      $added = $false
      throw "Failed to add submodule $RemoteUrl at ${DestPath}: $_"
    }
  }
  if ($added) { Write-Ok "Submodule registered." }
}

Push-Location $DestPath

# 2) Seed baseline files from templates (non-destructive)
Write-Info "Seeding baseline from $TemplateDir …"
Copy-IfMissing (Join-Path $TemplateDir ".gitignore")            ".gitignore"
Copy-IfMissing (Join-Path $TemplateDir ".gitattributes")        ".gitattributes"
Copy-IfMissing (Join-Path $TemplateDir ".editorconfig")         ".editorconfig"
Copy-IfMissing (Join-Path $TemplateDir "Directory.Build.props") "Directory.Build.props"

switch ($Kind) {
  "pbscript" {
    Copy-IfMissing (Join-Path $TemplateDir "__NAME__.csproj")   ("$ProjectName.csproj")
    Copy-IfMissing (Join-Path $TemplateDir "__NAME__.mdk.ini")  ("$ProjectName.mdk.ini")
    Copy-IfMissing (Join-Path $TemplateDir "Program.cs")        "Program.cs"
  }
  "mixin" {
    Copy-IfMissing (Join-Path $TemplateDir "__NAME__.csproj")   ("$ProjectName.csproj")
    Copy-IfMissing (Join-Path $TemplateDir "Program.cs")        "Program.cs"
    Copy-IfMissing (Join-Path $TemplateDir "Class1.cs")         "Class1.cs"
  }
}

# Optional README (template or small stub)
if ($Readme.IsPresent) {
  $tmplReadme = Join-Path $TemplateDir "README.md"
  if (Test-Path $tmplReadme) {
    Copy-IfMissing $tmplReadme "README.md"
  } elseif (-not (Test-Path "README.md")) {
    @(
      "# $ProjectName"
      ""
      "- Kind: $Kind"
      "- Scaffolded from templates/$Kind"
    ) | Set-Content -Encoding UTF8 "README.md"
  }
}

# 3) Replace __NAME__ placeholder in common files
function Replace-Placeholder([string]$File) {
  if (-not (Test-Path $File)) { return }
  $raw = Get-Content -Raw -LiteralPath $File
  $new = $raw -replace '__NAME__', $ProjectName
  if ($new -ne $raw) {
    $enc = 'UTF8'
    Set-Content -LiteralPath $File -Value $new -Encoding $enc
    Write-Info "patched: $File"
  }
}

@(
  "$ProjectName.csproj",
  "$ProjectName.mdk.ini",
  "Program.cs",
  "README.md"
) | ForEach-Object { Replace-Placeholder $_ }

# 4) Initial commit inside the submodule (only if changes)
if ((git status --porcelain) -ne "") {
  git add .
  git commit -m "scaffold: initial import for $ProjectName ($Kind) from template (incl. .editorconfig/.gitattributes)" | Out-Null
  try {
    git push -u origin HEAD | Out-Null
  } catch {
    Write-Warn "Push failed (repo protections or perms?). Continue."
  }
} else {
  Write-Info "No changes to commit in submodule."
}

Pop-Location

# 5) Record submodule pointer in super-repo
git add .gitmodules $DestPath | Out-Null
if ((git status --porcelain) -ne "") {
  git commit -m "chore(submodule): add $ProjectName at $DestPath" | Out-Null
  try { git push | Out-Null } catch { Write-Warn "Push failed for super-repo (continuing)." }
} else {
  Write-Info "No super-repo changes to commit."
}

# 6) Optionally add to solution
if ($Sln -and (Test-Path $Sln)) {
  $added = $false
  Get-ChildItem -Path $DestPath -Filter *.csproj -File | ForEach-Object {
    Write-Info "Adding to solution: $($_.FullName)"
    try {
      dotnet sln $Sln add $_.FullName | Out-Null
      $added = $true
    } catch {
      Write-Warn "dotnet sln add failed for $($_.FullName): $_"
    }
  }
  if ($added) {
    git add $Sln | Out-Null
    if ((git status --porcelain) -ne "") {
      git commit -m "sln: add $ProjectName project(s)" | Out-Null
      try { git push | Out-Null } catch { Write-Warn "Push failed for solution update (continuing)." }
    }
  }
} elseif ($Sln) {
  Write-Warn "Solution file not found: $Sln (skipping sln add)."
}

Write-Ok "Done. Submodule $ProjectName ($Kind) at $DestPath"
