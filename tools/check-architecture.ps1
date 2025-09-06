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
     - Gentle warnings for LINQ in hot paths; VIOS casing in types.

   Excludes ThirdParty/* inside each repo.
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
function Get-XmlProp([xml]$Xml, [string]$Name) {
  foreach ($pg in $Xml.Project.PropertyGroup) {
    if ($pg.$Name) {
      $val = [string]$pg.$Name
      if (-not [string]::IsNullOrWhiteSpace($val)) { return $val }
    }
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
    $repoLabel = if ($RepoPath -eq (Get-Location).Path) { "." } else { (Resolve-Path -Relative .) -replace '\\','/' }

    # Load repo-local defaults (Directory.Build.props)
    $defaults = @{ TargetFramework=$null; LangVersion=$null; RootNamespace=$null }
    $propsPath = Join-Path (Get-Location) "Directory.Build.props"
    if (Test-Path $propsPath) {
      try {
        $propsXml = Load-XmlFile $propsPath
        $defaults.TargetFramework = Get-XmlProp $propsXml "TargetFramework"
        $defaults.LangVersion     = Get-XmlProp $propsXml "LangVersion"
        $defaults.RootNamespace   = Get-XmlProp $propsXml "RootNamespace"
      } catch {
        Warn "[$repoLabel] Could not parse Directory.Build.props: $($_.Exception.Message)"
      }
    }

    # Find projects (use filesystem; submodules might not be tracked by super git)
    $csproj = Get-ChildItem -Path . -Recurse -Filter *.csproj -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '^.*[\\/](ThirdParty)[\\/].*$' }

    if (-not $csproj -or $csproj.Count -eq 0) {
      Notice "[$repoLabel] No .csproj found — skipping."
      return $true
    }

    Write-Host "::group::[$repoLabel] Project property checks"
    $ok = $true
    foreach ($proj in $csproj) {
      $relPath = (Resolve-Path -Relative $proj.FullName) -replace '\\','/'

      try {
        $xml = Load-XmlFile $proj.FullName

        $tfm = Get-XmlProp $xml "TargetFramework"
        if (-not $tfm) {
          $tfms = Get-XmlProp $xml "TargetFrameworks"
          if ($tfms) { $tfm = ($tfms -split ';' | Select-Object -First 1).Trim() }
        }
        if (-not $tfm) { $tfm = $defaults.TargetFramework }

        if ($tfm -ne 'netframework48') {
          Write-Host "::error file=$relPath::TargetFramework must be 'netframework48' (found '$tfm')"
          $ok = $false
        } else { Info "[$relPath] TargetFramework OK: $tfm" }

        $lang = Get-XmlProp $xml "LangVersion"; if (-not $lang) { $lang = $defaults.LangVersion }
        if (-not $lang) {
          Write-Host "::error file=$relPath::LangVersion missing (expected '6' or via Directory.Build.props)"
          $ok = $false
        } elseif ($lang -ne '6') {
          Write-Host "::error file=$relPath::LangVersion must be '6' (found '$lang')"
          $ok = $false
        } else { Info "[$relPath] LangVersion OK: $lang" }

        $rootNs = Get-XmlProp $xml "RootNamespace"; if (-not $rootNs) { $rootNs = $defaults.RootNamespace }
        if (-not $rootNs) {
          Write-Host "::error file=$relPath::RootNamespace missing (expected 'IngameScript' or via Directory.Build.props)"
          $ok = $false
        } elseif ($rootNs -ne 'IngameScript') {
          Write-Host "::error file=$relPath::RootNamespace must be 'IngameScript' (found '$rootNs')"
          $ok = $false
        } else { Info "[$relPath] RootNamespace OK: $rootNs" }

        # Package shape
        $pkgNodes = $xml.SelectNodes('//Project/ItemGroup/PackageReference')
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
    $allCs = Get-ChildItem -Path . -Recurse -Filter *.cs -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '^.*[\\/](ThirdParty)[\\/].*$' }

    foreach ($f in $allCs) {
      $rel = (Resolve-Path -Relative $f.FullName) -replace '\\','/'
      $txt = Get-Content -LiteralPath $f.FullName -Raw

      if ($rel -like "Scripts/*") {
        if ($txt -notmatch 'namespace\s+IngameScript\s*\{[\s\S]*?public\s+partial\s+class\s+Program\s*:\s*MyGridProgram') {
          Write-Host "::error file=$rel::Scripts enclosure invalid; expect 'public partial class Program : MyGridProgram' inside namespace IngameScript."
          $ok = $false
        }
      } elseif ($rel -like "Mixins/*") {
        if ($txt -match 'partial\s+class\s+Program\s*:\s*MyGridProgram') {
          Write-Host "::error file=$rel::Mixins must NOT inherit MyGridProgram."
          $ok = $false
        }
        if ($txt -notmatch 'namespace\s+IngameScript\s*\{[\s\S]*?partial\s+class\s+Program(?![\s]*:)') {
          Write-Host "::error file=$rel::Mixins enclosure invalid; expect 'partial class Program' (no base) inside namespace IngameScript."
          $ok = $false
        }
      }

      # Naming: enforce VIOS uppercase in type identifiers (heuristic)
      if ($txt -match '\bVios[A-Za-z_]\w*' -or $txt -match '\bVioS[A-Za-z_]\w*') {
        Write-Host "::error file=$rel::Found non-standard VIOS casing (use uppercase 'VIOS' in type names)."
        $ok = $false
      }

      if ($txt -match '\bSystem\.Linq\b') {
        Warn "System.Linq referenced in $rel — avoid in hot tick paths."
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
  # Parse paths from .gitmodules
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
