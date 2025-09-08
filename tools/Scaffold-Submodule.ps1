#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Scaffold and add a submodule (PB script or Mixin) from templates.

.DESCRIPTION
  - Creates/links a Git submodule at the given path.
  - Seeds it from tools/templates/<kind> with baseline files:
      .editorconfig, .gitattributes, .gitignore, Directory.Build.props
    For PB:
      __NAME__.csproj, __NAME__.mdk.ini, Program.cs
    For Mixin:
      __NAME__.csproj (if present), __NAME__.cs -> <ClassName>.cs
  - Replaces placeholders:
      __NAME__  -> Project/Repo name
      __CLASS__ -> primary type (defaults to sanitized ProjectName, or -ClassName)
  - Removes SCAFFOLD-STRIP blocks (between // SCAFFOLD-STRIP-START and // SCAFFOLD-STRIP-END).
  - Commits inside the submodule (if changes) and attempts a push (non-fatal if it fails).
  - Records the submodule pointer in the super-repo and optionally adds projects to a solution.
  - -DryRun prints planned actions only and does not modify anything.

.PARAMETER Kind
  Either 'pbscript' or 'mixin'.

.PARAMETER DestPath
  Path for the submodule within the super-repo (e.g., Scripts/VIOS.Minimal or Mixins/Modules/Power).

.PARAMETER RemoteUrl
  Git remote URL for the submodule repository.

.PARAMETER ProjectName
  Project/repo name used for file naming and token substitution (__NAME__).

.PARAMETER Sln
  Optional .sln file to add the new project(s) to.

.PARAMETER Branch
  Branch to track for the submodule (default: main). Falls back to default branch if missing.

.PARAMETER Readme
  Seed README.md from template if present; otherwise create a tiny stub.

.PARAMETER ClassName
  (Mixin only) Primary type/class name placed into <ClassName>.cs and replaces __CLASS__.
  Defaults to a sanitized version of ProjectName.

.PARAMETER DryRun
  Print planned actions only; do not touch filesystem or run git/dotnet mutations.

.EXAMPLES
  tools/Scaffold-Submodule.ps1 -Kind pbscript `
    -DestPath Scripts/VIOS.Minimal `
    -RemoteUrl git@github.com:se-thorbergr/VIOS.Minimal.git `
    -ProjectName VIOS.Minimal `
    -Sln SE-VIOS-DevFramework.sln `
    -Branch main `
    -Readme

  tools/Scaffold-Submodule.ps1 -Kind mixin `
    -DestPath Mixins/Modules/Power `
    -RemoteUrl git@github.com:se-thorbergr/Power.git `
    -ProjectName Power `
    -ClassName PowerModule `
    -Sln SE-VIOS-DevFramework.sln `
    -Readme `
    -DryRun
#>

[CmdletBinding(PositionalBinding=$false)]
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
  [switch]$Readme,
  [string]$ClassName = "",
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ---------------------------------------
# Helpers
# ---------------------------------------
function Write-Info($msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host $msg -ForegroundColor Green }
function Write-Err($msg)  { Write-Host $msg -ForegroundColor Red }

# Sanitize a C# class name (letters/digits/_; leading char must be letter/_)
function Sanitize-ClassName([string]$Raw) {
  $s = ($Raw -replace '[^A-Za-z0-9_]', '_')
  if ($s -notmatch '^[A-Za-z_].*') { $s = "M_$s" }
  return $s
}

if ([string]::IsNullOrWhiteSpace($ClassName)) {
  $ClassName = Sanitize-ClassName $ProjectName
} else {
  $ClassName = Sanitize-ClassName $ClassName
}

# Regex escape for replacement tokens
function Escape-Regex([string]$Text) {
  return [Regex]::Escape($Text)
}
$NameRepl  = Escape-Regex $ProjectName
$ClassRepl = Escape-Regex $ClassName

# Resolve repo root (script lives in tools/)
$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot  = Resolve-Path (Join-Path $ScriptDir "..")
$TemplateDir = Join-Path $ScriptDir ("templates/" + $Kind)

if (-not (Test-Path $TemplateDir)) {
  throw "Template dir missing: $TemplateDir"
}

# Only require git/dotnet when NOT in -DryRun
function Require-Cmd($cmd) {
  if ($DryRun) { return }
  $null = Get-Command $cmd -ErrorAction SilentlyContinue
  if (-not $?) {
    throw "Required command not found on PATH: $cmd"
  }
}
Require-Cmd git

# ---------------------------------------
# Submodule (idempotent)
# ---------------------------------------
if ($DryRun) {
  Write-Info "Would add submodule $RemoteUrl -> $DestPath (branch: $Branch)"
} else {
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
      Write-Info "  note: remote may not expose branch '$Branch'; retry default branch"
      try {
        git submodule add $RemoteUrl $DestPath | Out-Null
      } catch {
        $added = $false
        throw "Failed to add submodule $RemoteUrl at ${DestPath}: $_"
      }
    }
    if ($added) {
      git submodule update --init -- "$DestPath" | Out-Null
      git config -f .gitmodules "submodule.$DestPath.branch" "$Branch" | Out-Null
      Write-Ok "Submodule registered."
    }
  }
}

# ---------------------------------------
# Seeding & copy with filter (strip + tokens)
# ---------------------------------------
# In DryRun we don't Push-Location; operate with absolute/relative paths
if (-not $DryRun) {
  if (-not (Test-Path $DestPath)) { New-Item -ItemType Directory -Path $DestPath | Out-Null }
}
$DestRoot = $DestPath

function Copy-WithFilter([string]$Src, [string]$Dst) {
  if ($DryRun) {
    if (Test-Path $Dst) {
      Write-Info "  would keep existing: $Dst"
      return
    }
    if (Test-Path $Src) {
      Write-Info "  would copy: $Src -> $Dst"
      $probe = Get-Content -LiteralPath $Src -ErrorAction SilentlyContinue
      if ($probe -match 'SCAFFOLD-STRIP-START') {
        Write-Info "    (dry-run) would strip SCAFFOLD-STRIP blocks in $Dst"
      }
    } else {
      Write-Info "  (template missing) $Src (skipped)"
    }
    return
  }

  $DstDir = Split-Path -Parent $Dst
  if ($DstDir -and -not (Test-Path $DstDir)) { New-Item -ItemType Directory -Path $DstDir | Out-Null }

  if (Test-Path $Dst) {
    Write-Info "  keep existing: $Dst"
    return
  }
  if (-not (Test-Path $Src)) {
    Write-Info "  (template missing) $Src (skipped)"
    return
  }

  # Read, strip, replace
  $raw = Get-Content -Raw -LiteralPath $Src

  # Strip SCAFFOLD-STRIP blocks (singleline regex so dot matches newlines)
  $stripped = [Regex]::Replace(
    $raw,
    '(?s)//\s*SCAFFOLD-STRIP-START.*?//\s*SCAFFOLD-STRIP-END\s*',
    ''
  )

  # Replace tokens (__NAME__, __CLASS__)
  $stripped = $stripped -replace '__NAME__',  $ProjectName
  $stripped = $stripped -replace '__CLASS__', $ClassName

  Set-Content -LiteralPath $Dst -Value $stripped -Encoding UTF8
  Write-Info "  + $Dst"
}

Write-Info ("Seeding baseline files from {0}..." -f $TemplateDir)
Copy-WithFilter (Join-Path $TemplateDir ".gitignore")            (Join-Path $DestRoot ".gitignore")
Copy-WithFilter (Join-Path $TemplateDir ".gitattributes")        (Join-Path $DestRoot ".gitattributes")
Copy-WithFilter (Join-Path $TemplateDir ".editorconfig")         (Join-Path $DestRoot ".editorconfig")
Copy-WithFilter (Join-Path $TemplateDir "Directory.Build.props") (Join-Path $DestRoot "Directory.Build.props")

switch ($Kind) {
  'pbscript' {
    Copy-WithFilter (Join-Path $TemplateDir "__NAME__.csproj")  (Join-Path $DestRoot "$ProjectName.csproj")
    Copy-WithFilter (Join-Path $TemplateDir "__NAME__.mdk.ini") (Join-Path $DestRoot "$ProjectName.mdk.ini")
    Copy-WithFilter (Join-Path $TemplateDir "Program.cs")       (Join-Path $DestRoot "Program.cs")
  }
  'mixin' {
    Copy-WithFilter (Join-Path $TemplateDir "__NAME__.csproj")  (Join-Path $DestRoot "$ProjectName.csproj")
    # Primary mixin source: __NAME__.cs -> <ClassName>.cs
    Copy-WithFilter (Join-Path $TemplateDir "__NAME__.cs")      (Join-Path $DestRoot "$ClassName.cs")
  }
}

# Optional README
if ($Readme) {
  $TmplReadme = Join-Path $TemplateDir "README.md"
  if (Test-Path $TmplReadme) {
    Copy-WithFilter $TmplReadme (Join-Path $DestRoot "README.md")
  } else {
    if ($DryRun) {
      if (-not (Test-Path (Join-Path $DestRoot "README.md"))) {
        Write-Info ("  would create {0} (simple fallback)" -f (Join-Path $DestRoot 'README.md'))
      } else {
        Write-Info ("  would keep existing: {0}" -f (Join-Path $DestRoot 'README.md'))
      }
    } else {
      $ReadmePath = Join-Path $DestRoot "README.md"
      if (-not (Test-Path $ReadmePath)) {
        @(
          "# $ProjectName"
          ""
          "- Kind: $Kind"
          "- Scaffolded from templates/$Kind"
        ) | Set-Content -Encoding UTF8 $ReadmePath
        Write-Info "  + $ReadmePath"
      }
    }
  }
}

# ---------------------------------------
# Normalize CRLF -> LF (best-effort)
# ---------------------------------------
function Normalize-LF([string]$Pattern) {
  # Only file rewrites outside DryRun
  $files = Get-ChildItem -Path $DestRoot -Filter $Pattern -File -ErrorAction SilentlyContinue
  foreach ($f in $files) {
    if ($DryRun) {
      Write-Info ("(dry-run) would normalize {0} to LF" -f $f.FullName)
    } else {
      $raw = Get-Content -Raw -LiteralPath $f.FullName
      $lf  = $raw -replace "`r`n", "`n"
      if ($lf -ne $raw) {
        [IO.File]::WriteAllText($f.FullName, $lf, (New-Object System.Text.UTF8Encoding($false)))
      }
    }
  }
}
Normalize-LF "*.csproj"
Normalize-LF "*.cs"
Normalize-LF "*.ini"
Normalize-LF "*.md"

# ---------------------------------------
# Commit & push inside submodule
# ---------------------------------------
if ($DryRun) {
  Write-Info "Would 'git add/commit/push' inside $DestPath if changes are present"
} else {
  Push-Location $DestPath
  $dirty = (git status --porcelain)
  if (-not [string]::IsNullOrWhiteSpace($dirty)) {
    git add . | Out-Null
    git commit -m "scaffold: initial import for $ProjectName ($Kind) from template (class=$ClassName)" | Out-Null
    try {
      git push -u origin HEAD | Out-Null
    } catch {
      Write-Info "  (info) initial push failed or not permitted; you may push later"
    }
  } else {
    Write-Info "No changes to commit in submodule (already initialized)."
  }
  Pop-Location
}

# ---------------------------------------
# Record in super-repo & optionally add to solution
# ---------------------------------------
if ($DryRun) {
  Write-Info ("Would stage .gitmodules and {0}, commit 'chore(submodule): add {1}...', and push" -f $DestPath, $ProjectName)
} else {
  git add .gitmodules "$DestPath" | Out-Null
  $rootDirty = (git status --porcelain)
  if (-not [string]::IsNullOrWhiteSpace($rootDirty)) {
    git commit -m "chore(submodule): add $ProjectName at $DestPath" | Out-Null
    try { git push | Out-Null } catch { Write-Info "  (info) super-repo push skipped/failed; commit recorded locally" }
  } else {
    Write-Info "No super-repo changes to commit."
  }
}

if ($Sln) {
  if (Test-Path $Sln) {
    if ($DryRun) {
      Write-Info ("Would add any *.csproj under {0} to solution {1} via 'dotnet sln add'" -f $DestPath, $Sln)
    } else {
      $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
      if ($dotnet) {
        $added = $false
        Get-ChildItem -Path $DestPath -Filter *.csproj -File | ForEach-Object {
          Write-Info ("  dotnet sln add {0}" -f $_.FullName)
          try {
            dotnet sln $Sln add $_.FullName | Out-Null
            $added = $true
          } catch {
            Write-Info "  (info) dotnet sln add failed: $_"
          }
        }
        if ($added) {
          git add $Sln | Out-Null
          if ((git status --porcelain) -ne "") {
            git commit -m "sln: add $ProjectName project(s)" | Out-Null
            try { git push | Out-Null } catch { }
          }
        }
      } else {
        Write-Info "dotnet CLI not found; skipping solution integration."
      }
    }
  } else {
    Write-Info ("Solution file not found: {0} (skipping sln add)" -f $Sln)
  }
}

# Final message (PS 5.1 compatible; no ternary)
$clsSuffix = if ([string]::IsNullOrWhiteSpace($ClassName)) { "" } else { " (class=$ClassName)" }
$drySuffix = if ($DryRun) { " (dry-run)" } else { "" }
Write-Ok ("Done. Submodule {0} ({1}) at {2}{3}{4}" -f $ProjectName, $Kind, $DestPath, $clsSuffix, $drySuffix)
