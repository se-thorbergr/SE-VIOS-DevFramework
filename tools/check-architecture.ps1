<#  tools/check-architecture.ps1
    Guardrails for VIOS repo on CI and local dev.

    Checks:
      - .csproj discovery (recurses into submodules)
      - TargetFramework == netframework48 (from project or Directory.Build.props)
      - LangVersion == 6 (from project or Directory.Build.props)
      - Package shape:
          PB scripts: Mal.Mdk2.PbPackager + Mal.Mdk2.PbAnalyzers + Mal.Mdk2.References
          Mixins:     Mal.Mdk2.PbAnalyzers + Mal.Mdk2.References (no PbPackager)
      - Program enclosure rules (regex on .cs):
          Scripts/*/Program.cs -> 'public partial class Program : MyGridProgram'
          Mixins/**            -> 'partial class Program' (no 'public', no ': MyGridProgram')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail($msg) { Write-Error $msg; exit 1 }
function Info($msg) { Write-Host $msg }
function Notice($msg) { Write-Host "::notice::$msg" }
function Warn($msg) { Write-Host "::warning::$msg" }

# Ensure repo root (heuristic)
if (-not (Test-Path ".git")) { Fail "Run this script from the repository root (no .git directory found)." }

# Helper: get first node inner text by XPath
function Get-NodeText {
  param([xml]$Xml, [string]$XPath)
  try {
    $node = $Xml.SelectSingleNode($XPath)
    if ($null -ne $node -and $node.InnerText) { return $node.InnerText.Trim() }
  } catch { }
  return $null
}

# Load Directory.Build.props (optional fallbacks)
$dirPropsPath = Join-Path (Get-Location) "Directory.Build.props"
$dirLang = $null; $dirTFM = $null
if (Test-Path $dirPropsPath) {
  try {
    [xml]$dirXml = Get-Content -LiteralPath $dirPropsPath -Raw
    $dirTFM  = Get-NodeText $dirXml '//Project/PropertyGroup/TargetFramework'
    $dirLang = Get-NodeText $dirXml '//Project/PropertyGroup/LangVersion'
  } catch {
    Warn "Failed parsing Directory.Build.props: $($_.Exception.Message)"
  }
}

# Discover projects; try to init submodules once if missing
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

$hadError = $false

Write-Host "::group::Project checks"
foreach ($proj in $csproj) {
  $relPath = (Resolve-Path -Relative $proj.FullName) -replace '\\','/'
  try {
    [xml]$xml = Get-Content -LiteralPath $proj.FullName -Raw

    # Read TFM/Lang via XPath with fallback to Directory.Build.props
    $tfm  = Get-NodeText $xml '//Project/PropertyGroup/TargetFramework'
    if (-not $tfm) {
      $tfmMulti = Get-NodeText $xml '//Project/PropertyGroup/TargetFrameworks'
      if ($tfmMulti) { $tfm = ($tfmMulti -split ';' | Select-Object -First 1).Trim() }
    }
    if (-not $tfm) { $tfm = $dirTFM }

    if ($tfm -ne 'netframework48') {
      Write-Host "::error file=$relPath::TargetFramework must be 'netframework48' (found '$tfm')"
      $hadError = $true
    } else { Info "[$relPath] TargetFramework OK: $tfm" }

    $lang = Get-NodeText $xml '//Project/PropertyGroup/LangVersion'
    if (-not $lang) { $lang = $dirLang }
    if (-not $lang) {
      Write-Host "::warning file=$relPath::LangVersion not set (expected '6'); relying on default may break PB."
    } elseif ($lang -ne '6') {
      Write-Host "::error file=$relPath::LangVersion must be '6' (found '$lang')"
      $hadError = $true
    } else { Info "[$relPath] LangVersion OK: $lang" }

    # Package shape via XPath
    $pkgNodes = $xml.SelectNodes('//Project/ItemGroup/PackageReference')
    $pkgs = @{}
    foreach ($n in $pkgNodes) {
      if ($n -and $n.Include) { $pkgs[$n.Include] = $true }
    }

    $pathLower = $relPath.ToLowerInvariant()
    $isScript = ($pathLower -like "*/scripts/*/*.csproj")
    $isMixin  = ($pathLower -like "*/mixins/*/*.csproj")

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
    Write-Host "::error file=$relPath::Failed to parse project: $($_.Exception.Message)"
    $hadError = $true
  }
}
Write-Host "::endgroup::"

# Source enclosure checks
Write-Host "::group::Source enclosure checks"
# PB Program.cs must have public partial + MyGridProgram
$scriptPrograms = Get-ChildItem -Path ./Scripts -Recurse -Filter Program.cs -ErrorAction SilentlyContinue
foreach ($f in $scriptPrograms) {
  $rel = (Resolve-Path -Relative $f.FullName) -replace '\\','/'
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

# Mixins must NOT inherit MyGridProgram; avoid 'public' on partial Program
$mixinFiles = Get-ChildItem -Path ./Mixins -Recurse -Include *.cs -ErrorAction SilentlyContinue
foreach ($f in $mixinFiles) {
  $rel = (Resolve-Path -Relative $f.FullName) -replace '\\','/'
  $txt = Get-Content -LiteralPath $f.FullName -Raw
  if ($txt -match 'public\s+partial\s+class\s+Program\s*:\s*MyGridProgram') {
    Write-Host "::error file=$rel::Mixin must NOT declare 'public partial class Program : MyGridProgram'"
    $hadError = $true
  }
  if ($txt -match 'partial\s+class\s+Program\s*:\s*MyGridProgram') {
    Write-Host "::error file=$rel::Mixin must NOT inherit MyGridProgram"
    $hadError = $true
  }
  if ($txt -match 'public\s+partial\s+class\s+Program\b') {
    Write-Host "::warning file=$rel::Mixin should not use 'public' on partial Program; prefer internal/default"
  }
}
Write-Host "::endgroup::"

if ($hadError) { Fail "One or more policy checks failed." }
else { Write-Host "OK — Architecture/policy checks passed." }
