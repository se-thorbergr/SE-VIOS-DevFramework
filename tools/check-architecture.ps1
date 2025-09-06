<# tools/check-architecture.ps1
   Guardrails for VIOS repo + all Git submodules.

   For each repo (root + each submodule):
     - Read Directory.Build.props for defaults (TargetFramework, LangVersion, RootNamespace).
     - Validate every *.csproj:
         TargetFramework == netframework48
         LangVersion == 6
         RootNamespace == IngameScript
         Package shape:
           Scripts/* (pb):    PbPackager + PbAnalyzers + References
           Mixins/* (mixin):  PbAnalyzers + References (NO PbPackager)
     - Validate source enclosure rules:
         Scripts/*/Program.cs -> public partial class Program : MyGridProgram
         Mixins/**            -> partial class Program   (no base, no 'public' required)
     - Heuristic naming: uppercase VIOS in type identifiers.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail($msg) { Write-Error $msg; exit 1 }
function Info($msg) { Write-Host $msg }
function Warn($msg) { Write-Host "::warning::$msg" }
function Notice($msg) { Write-Host "::notice::$msg" }

# ---------- helpers ----------
function Load-XmlFile([string]$Path) {
  [xml](Get-Content -LiteralPath $Path -Raw)
}

function Get-XmlPropXPath([xml]$Xml, [string]$Name) {
  # Return inner text of the FIRST <PropertyGroup>/<Name> found via XPath
  # Support both TargetFramework and TargetFrameworks
  $node = $Xml.SelectSingleNode("//Project/PropertyGroup/$Name")
  if ($null -ne $node -and -not [string]::IsNullOrWhiteSpace($node.InnerText)) {
    return $node.InnerText.Trim()
  }
  return $null
}

function File-Contains([string]$Path, [string]$Pattern) {
  $text = Get-Content -LiteralPath $Path -Raw
  return [System.Text.RegularExpressions.Regex]::IsMatch($text, $Pattern, 'Singleline')
}

function Invoke-ChecksForRepo([string]$RepoPath) {
  Push-Location $RepoPath
  try {
    $repoLabel = "."
    try { $repoLabel = (Resolve-Path -Relative .) -replace '\\','/' } catch { $repoLabel = "." }

    # Load repo-local defaults (Directory.Build.props)
    $defaults = @{ TargetFramework=$null; LangVersion=$null; RootNamespace=$null }
    $propsPath = Join-Path (Get-Location) "Directory.Build.props"
    if (Test-Path $propsPath) {
      try {
        $propsXml = Load-XmlFile $propsPath
        $defaults.TargetFramework = Get-XmlPropXPath $propsXml "TargetFramework"
        if (-not $defaults.TargetFramework) {
          $tfms = Get-XmlPropXPath $propsXml "TargetFrameworks"
          if ($tfms) { $defaults.TargetFramework = ($tfms -split ';' | Select-Object -First 1).Trim() }
        }
        $defaults.LangVersion   = Get-XmlPropXPath $propsXml "LangVersion"
        $defaults.RootNamespace = Get-XmlPropXPath $propsXml "RootNamespace"
      } catch {
        Warn "[$repoLabel] Could not parse Directory.Build.props: $($_.Exception.Message)"
      }
    }

    # Find projects (force array)
    $csproj = @(
      Get-ChildItem -Path . -Recurse -Filter *.csproj -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '[\\/](ThirdParty)[\\/]'}
    )

    if ($csproj.Count -eq 0) {
      Notice "[$repoLabel] No .csproj found — skipping."
      return $true
    }

    Write-Host "::group::[$repoLabel] Project property checks"
    $ok = $true
    foreach ($proj in $csproj) {
      $relPath = try { (Resolve-Path -Relative $proj.FullName) -replace '\\','/' } catch { $proj.FullName }

      try {
        $xml = Load-XmlFile $proj.FullName

        $tfm = Get-XmlPropXPath $xml "TargetFramework"
        if (-not $tfm) {
          $tfms = Get-XmlPropXPath $xml "TargetFrameworks"
          if ($tfms) { $tfm = ($tfms -split ';' | Select-Object -First 1).Trim() }
        }
        if (-not $tfm) { $tfm = $defaults.TargetFramework }

        if ($tfm -ne 'netframework48') {
          Write-Host "::error file=$relPath::TargetFramework must be 'netframework48' (found '$tfm')"
          $ok = $false
        } else { Info "[$relPath] TargetFramework OK: $tfm" }

        $lang = Get-XmlPropXPath $xml "LangVersion"; if (-not $lang) { $lang = $defaults.LangVersion }
        if (-not $lang) {
          Write-Host "::error file=$relPath::LangVersion missing (expected '6' or via Directory.Build.props)"
          $ok = $false
        } elseif ($lang -ne '6') {
          Write-Host "::error file=$relPath::LangVersion must be '6' (found '$lang')"
          $ok = $false
        } else { Info "[$relPath] LangVersion OK: $lang" }

        $rootNs = Get-XmlPropXPath $xml "RootNamespace"; if (-not $rootNs) { $rootNs = $defaults.RootNamespace }
        if (-not $rootNs) {
          Write-Host "::error file=$relPath::RootNamespace missing (expected 'IngameScript' or via Directory.Build.props)"
          $ok = $false
        } elseif ($rootNs -ne 'IngameScript') {
          Write-Host "::error file=$relPath::RootNamespace must be 'IngameScript' (found '$rootNs')"
          $ok = $false
        } else { Info "[$relPath] RootNamespace OK: $rootNs" }

        # Package shape
        $pkgNodes = @($xml.SelectNodes('//Project/ItemGroup/PackageReference'))
        $pkgs = @{}
        foreach ($n in $pkgNodes) {
          if ($n -and $n.Include) { $pkgs[$n.Include] = $true }
        }

        $lower = $relPath.ToLowerInvariant()
        $isScript = ($lower -like "*/scripts/*/*.csproj")
        $isMixin  = ($lower -like "*/mixins/*/*.csproj")

        if ($isScript) {
          $need = @('Mal.Mdk2.PbPackager','Mal.Mdk2.PbAnalyzers','Mal.Mdk2.References')
          foreach ($n in $need) {
            if (-not $pkgs.ContainsKey($n)) {
              Write-Host "::error file=$relPath::PB script must reference $n"
              $ok = $false
            }
          }
        }
        if ($isMixin) {
          if ($pkgs.ContainsKey('Mal.Mdk2.PbPackager')) {
            Write-Host "::error file=$relPath::Mixin may NOT reference Mal.Mdk2.PbPackager"
            $ok = $false
          }
          $need = @('Mal.Mdk2.PbAnalyzers','Mal.Mdk2.References')
          foreach ($n in $need) {
            if (-not $pkgs.ContainsKey($n)) {
              Write-Host "::error file=$relPath::Mixin must reference $n"
              $ok = $false
            }
          }
        }
      } catch {
        Write-Host "::error file=$relPath::Failed to parse project: $($_.Exception.Message)"
        $ok = $false
      }
    }
    Write-Host "::endgroup::"

    Write-Host "::group::[$repoLabel] Source enclosure checks"
    $allCs = @(
      Get-ChildItem -Path . -Recurse -Filter *.cs -ErrorAction SilentlyContinue |
      Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        $_.FullName -notmatch '[\\/](ThirdParty)[\\/]'
      }
    )

    foreach ($f in $allCs) {
      $rel = try { (Resolve-Path -Relative $f.FullName) -replace '\\','/' } catch { $f.FullName }
      $relLower = $rel.ToLowerInvariant()
      $txt = Get-Content -LiteralPath $f.FullName -Raw

      if ($relLower -like "scripts/*") {
        if ($txt -notmatch 'namespace\s+IngameScript\s*\{[\s\S]*?public\s+partial\s+class\s+Program\s*:\s*MyGridProgram') {
          Write-Host "::error file=$rel::Scripts enclosure invalid; expect 'public partial class Program : MyGridProgram' inside namespace IngameScript."
          $ok = $false
        }
      } elseif ($relLower -like "mixins/*") {
        if ($txt -match 'partial\s+class\s+Program\s*:\s*MyGridProgram') {
          Write-Host "::error file=$rel::Mixins must NOT inherit MyGridProgram."
          $ok = $false
        }
        if ($txt -notmatch 'namespace\s+IngameScript\s*\{[\s\S]*?partial\s+class\s+Program(?![\s]*:)') {
          Write-Host "::error file=$rel::Mixins enclosure invalid; expect 'partial class Program' (no base) inside namespace IngameScript."
          $ok = $false
        }
      }

      # Stricter VIOS casing check: only type identifiers in Scripts/Mixins
      if ($relLower -like "scripts/*" -or $relLower -like "mixins/*") {
        if ($txt -match '\b(class|interface|struct)\s+Vios\w*\b') {
          Write-Host "::error file=$rel::Found non-standard VIOS casing in type name (use uppercase 'VIOS')."
          $ok = $false
        }
      }
    }
    Write-Host "::endgroup::"

    return $ok
  } finally {
    Pop-Location
  }
}

# --- main ---
if (-not (Test-Path ".git")) { Fail "Run from the repository root (no .git found)." }

$overallOk = $true

# 1) Root repo
$overallOk = (Invoke-ChecksForRepo (Get-Location).Path) -and $overallOk

# 2) Enumerate submodules via .gitmodules and check each
$subPaths = @()
if (Test-Path .gitmodules) {
  $lines = git config -f .gitmodules --get-regexp path 2>$null
  foreach ($ln in $lines) {
    $parts = $ln -split "\s+", 2
    if ($parts.Count -eq 2) { $subPaths += $parts[1] }
  }
}

foreach ($p in $subPaths) {
  if (-not (Test-Path $p)) {
    Warn "Submodule path missing on disk (did you run submodule update?): $p"
    $overallOk = $false
    continue
  }
  $abs = Resolve-Path $p
  $ok = Invoke-ChecksForRepo $abs.Path
  $overallOk = $ok -and $overallOk
}

if (-not $overallOk) {
  Fail "One or more policy checks failed."
} else {
  Write-Host "OK — Architecture/policy checks passed for root and all submodules."
}
