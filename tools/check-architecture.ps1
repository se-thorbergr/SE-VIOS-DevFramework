<#  tools/check-architecture.ps1
    Guardrails for VIOS repo on CI and local dev.

    Checks:
      - .csproj discovery (recurses into submodules)
      - TargetFramework == netframework48
      - LangVersion == 6 (project or Directory.Build.props)
      - Package shape:
          PB scripts: Mal.Mdk2.PbPackager + PbAnalyzers + References
          Mixins:     PbAnalyzers + References (no PbPackager)
      - Program enclosure rules (lightweight regex on .cs):
          Scripts/*/Program.cs    -> 'public partial class Program : MyGridProgram'
          Mixins/**               -> 'partial class Program' (no 'public' and no ': MyGridProgram')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail($msg) {
  Write-Error $msg
  exit 1
}

function Info($msg) { Write-Host $msg }
function Notice($msg) { Write-Host "::notice::$msg" }
function Warn($msg) { Write-Host "::warning::$msg" }

# Ensure we're at repo root (heuristic)
if (-not (Test-Path ".git")) {
  Fail "Run this script from the repository root (no .git directory found)."
}

# Try to ensure submodules exist when running locally
$csproj = Get-ChildItem -Path . -Recurse -Filter *.csproj -ErrorAction SilentlyContinue
if (-not $csproj -or $csproj.Count -eq 0) {
  Notice "No .csproj found; attempting 'git submodule update --init --recursive --depth=1'..."
  try { git submodule update --init --recursive --depth=1 | Out-Null } catch { }
  $csproj = Get-ChildItem -Path . -Recurse -Filter *.csproj -ErrorAction SilentlyContinue
}

if (-not $csproj -or $csproj.Count -eq 0) {
  Warn "No .csproj found after submodule init. Skipping checks."
  exit 0
}

# Optionally read Directory.Build.props for shared LangVersion/TFM hints
$dirProps = Join-Path (Get-Location) "Directory.Build.props"
$dirLangVersion = $null
$dirTFM = $null
if (Test-Path $dirProps) {
  try {
    [xml]$dirXml = Get-Content -LiteralPath $dirProps -Raw
    $dirLangVersion = $dirXml.Project.PropertyGroup.LangVersion | Select-Object -First 1
    $dirTFM = $dirXml.Project.PropertyGroup.TargetFramework | Select-Object -First 1
  } catch {
    Warn "Failed parsing Directory.Build.props: $($_.Exception.Message)"
  }
}

$hadError = $false

Write-Host "::group::Project checks"
foreach ($proj in $csproj) {
  try {
    [xml]$xml = Get-Content -LiteralPath $proj.FullName -Raw

    $projName = Split-Path $proj.FullName -Leaf
    $projDir  = Split-Path $proj.FullName -Parent
    $relPath  = Resolve-Path -Relative $proj.FullName

    $pg = $xml.Project.PropertyGroup | Select-Object -First 1

    # TargetFramework check
    $tfm = $pg.TargetFramework
    if (-not $tfm -and $pg.TargetFrameworks) {
      $tfm = ($pg.TargetFrameworks -split ';' | Select-Object -First 1)
    }
    if (-not $tfm) { $tfm = $dirTFM }

    if ($tfm -ne 'netframework48') {
      Write-Host "::error file=$relPath::TargetFramework must be 'netframework48' (found '$tfm')"
      $hadError = $true
    } else {
      Info "[$relPath] TargetFramework OK: $tfm"
    }

    # LangVersion check
    $lang = $pg.LangVersion
    if (-not $lang) { $lang = $dirLangVersion }
    if (-not $lang) {
      Write-Host "::warning file=$relPath::LangVersion not set (expected '6'); relying on default may break PB."
    } elseif ($lang -ne '6') {
      Write-Host "::error file=$relPath::LangVersion must be '6' (found '$lang')"
      $hadError = $true
    } else {
      Info "[$relPath] LangVersion OK: $lang"
    }

    # Package shape
    $pkgs = @{}
    foreach ($pkg in $xml.Project.ItemGroup.PackageReference) {
      $id = $pkg.Include
      if ($id) { $pkgs[$id] = $true }
    }

    $isScript = $false
    $isMixin  = $false
    $pathNorm = ($relPath -replace '\\','/').ToLowerInvariant()

    if ($pathNorm -like "*/scripts/*/*.csproj") {
      $isScript = $true
    } elseif ($pathNorm -like "*/mixins/*/*.csproj") {
      $isMixin = $true
    }

    if ($isScript) {
      $need = @('Mal.Mdk2.PbPackager','Mal.Mdk2.PbAnalyzers','Mal.Mdk2.References')
      foreach ($n in $need) {
        if (-not $pkgs.ContainsKey($n)) {
          Write-Host "::error file=$relPath::PB script must reference $n"
          $hadError = $true
        }
      }
    }
    if ($isMixin) {
      if ($pkgs.ContainsKey('Mal.Mdk2.PbPackager')) {
        Write-Host "::error file=$relPath::Mixin may NOT reference Mal.Mdk2.PbPackager"
        $hadError = $true
      }
      $need = @('Mal.Mdk2.PbAnalyzers','Mal.Mdk2.References')
      foreach ($n in $need) {
        if (-not $pkgs.ContainsKey($n)) {
          Write-Host "::error file=$relPath::Mixin must reference $n"
          $hadError = $true
        }
      }
    }

  } catch {
    Write-Host "::error file=$($proj.FullName)::Failed to parse project: $($_.Exception.Message)"
    $hadError = $true
  }
}
Write-Host "::endgroup::"

# Source enclosure checks
Write-Host "::group::Source enclosure checks"
# 1) PB Program.cs: must include the public partial + base
$scriptPrograms = Get-ChildItem -Path ./Scripts -Recurse -Filter Program.cs -ErrorAction SilentlyContinue
foreach ($f in $scriptPrograms) {
  $rel = Resolve-Path -Relative $f.FullName
  $txt = Get-Content -LiteralPath $f.FullName -Raw
  if ($txt -notmatch 'namespace\s+IngameScript') {
    Write-Host "::error file=$rel::Missing 'namespace IngameScript'"
    $hadError = $true
  }
  if ($txt -notmatch 'public\s+partial\s+class\s+Program\s*:\s*MyGridProgram') {
    Write-Host "::error file=$rel::PB Program.cs must declare 'public partial class Program : MyGridProgram'"
    $hadError = $true
  }
}

# 2) Mixins: partial Program but NOT public and NOT base class
$mixinFiles = Get-ChildItem -Path ./Mixins -Recurse -Include *.cs -ErrorAction SilentlyContinue
foreach ($f in $mixinFiles) {
  $rel = Resolve-Path -Relative $f.FullName
  $txt = Get-Content -LiteralPath $f.FullName -Raw
  if ($txt -match 'public\s+partial\s+class\s+Program\s*:\s*MyGridProgram') {
    Write-Host "::error file=$rel::Mixin must NOT declare 'public partial class Program : MyGridProgram'"
    $hadError = $true
  }
  if ($txt -match 'public\s+partial\s+class\s+Program\b') {
    Write-Host "::warning file=$rel::Mixin should not use 'public' on partial Program; prefer internal/default"
  }
  if ($txt -match 'partial\s+class\s+Program\s*:\s*MyGridProgram') {
    Write-Host "::error file=$rel::Mixin must NOT inherit MyGridProgram"
    $hadError = $true
  }
}
Write-Host "::endgroup::"

if ($hadError) {
  Fail "One or more policy checks failed."
} else {
  Write-Host "OK — Architecture/policy checks passed."
}
