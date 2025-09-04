param(
  [string]$RepoRoot = ".",
  [switch]$EmitAnnotations,
  [string]$CommentsOut = ""
)
$ErrorActionPreference = 'Stop'

function Fail($msg) { Write-Error $msg; exit 1 }
function Warn($msg) { Write-Warning $msg }

# Helpers
function RelPath([string]$abs) {
  $root = (Resolve-Path $RepoRoot).Path
  $p = $abs.Replace($root, "").TrimStart('\','/')
  return $p -replace '\\','/'
}
$comments = @()
function Add-Comment([string]$file,[int]$line,[string]$body,[string]$kind='error') {
  $rel = RelPath $file
  if ($EmitAnnotations) {
    $prefix = ($kind -eq 'warning') ? '::warning' : '::error'
    Write-Host "$prefix file=$rel,line=$line::$body"
  }
  $comments += [pscustomobject]@{ path=$rel; line=$line; body=$body }
}

# 1) Ensure required files exist
$csproj = Get-ChildItem -Path $RepoRoot -Recurse -Filter *.csproj | Select-Object -First 1
if (-not $csproj) { Fail "No .csproj found." }

# 2) Verify project settings
$xml = [xml](Get-Content -Path $csproj.FullName -Raw)
$tfm = $xml.Project.PropertyGroup.TargetFramework | Select-Object -First 1
$lang = $xml.Project.PropertyGroup.LangVersion | Select-Object -First 1
if ($tfm -ne 'netframework48') { Add-Comment $csproj.FullName 1 "TargetFramework must be netframework48 (found '$tfm')." }
if ($lang -ne '6') { Add-Comment $csproj.FullName 1 "LangVersion must be 6 (C# 6) (found '$lang')." }

# 3) Verify MDK2 packages present
$packages = @('Mal.Mdk2.PbAnalyzers','Mal.Mdk2.PbPackager','Mal.Mdk2.References')
$present = @()
$xml.Project.ItemGroup.PackageReference | ForEach-Object { $present += $_.Include }
foreach ($p in $packages) {
  if ($present -notcontains $p) { Add-Comment $csproj.FullName 1 "Missing required package: $p" }
}

# 4) Collect C# files (exclude bin/obj)
$files = Get-ChildItem -Path $RepoRoot -Recurse -Include *.cs -File |
  Where-Object { $_.FullName -notmatch '\\bin\\|\\obj\\' }
if (-not $files) { Fail "No .cs files found." }

# 5) License header check (top lines)
foreach ($f in $files) {
  $head = (Get-Content -Path $f.FullName -TotalCount 12 -Raw)
  if ($head -notmatch 'Viking Industries Operating System' -and $head -notmatch 'MIT License') {
    Add-Comment $f.FullName 1 "Missing license header (MIT / VIOS banner)."
  }
}

# 6) Enclosure: inside IngameScript + partial Program (heuristic)
foreach ($f in $files) {
  $txt = Get-Content -Path $f.FullName -Raw
  if ($txt -notmatch 'namespace\s+IngameScript' -or $txt -notmatch 'partial\s+class\s+Program') {
    Add-Comment $f.FullName 1 "Source should be wrapped in namespace IngameScript { partial class Program { ... } } (heuristic)."
  }
}

# 7) Class naming rules for VIOS brand (with line numbers)
$regexType = '^\s*(class|interface|struct)\s+([A-Za-z0-9_]+)'
foreach ($f in $files) {
  $matches = Select-String -Path $f.FullName -Pattern $regexType -AllMatches
  foreach ($m in $matches) {
    $name = $m.Matches[0].Groups[2].Value
    if ($name.ToLower().Contains('vios') -and ($name -notmatch 'VIOS')) {
      Add-Comment $f.FullName $m.LineNumber "Type names containing 'vios' must use uppercase 'VIOS': $name"
    }
  }
}

# 7b) Warn if modules use branded type names (preferred neutral)
$moduleFiles = $files | Where-Object { $_.FullName -match '\\Modules\\' }
foreach ($f in $moduleFiles) {
  $matches = Select-String -Path $f.FullName -Pattern $regexType -AllMatches
  foreach ($m in $matches) {
    $name = $m.Matches[0].Groups[2].Value
    if ($name -match '^VIOS') {
      Add-Comment $f.FullName $m.LineNumber "Module classes should use neutral names (branding reserved for core): $name" 'warning'
    }
  }
}

# 8) Discourage heavy APIs (non-fatal)
foreach ($f in $files) {
  $hit = Select-String -Path $f.FullName -Pattern '\bSystem\.Linq\b' -SimpleMatch
  if ($hit) {
    Add-Comment $f.FullName $hit.LineNumber "Consider avoiding System.Linq in PB hot paths (VRage-first)." 'warning'
  }
}

# Output JSON for PR review comments
if ($CommentsOut) {
  $comments | ConvertTo-Json -Depth 5 | Set-Content -Path $CommentsOut -NoNewline
}

# Fail the job if any errors were emitted
$hasErrors = $comments | Where-Object { $_.body -like '[Ee]rror*' } | Measure-Object | Select-Object -ExpandProperty Count
# More simply: assume anything we added without 'warning' is an error
$errors = $comments | Where-Object { $_.body -notmatch 'warning' }
if ($errors.Count -gt 0) { Fail "Policy violations found. See inline annotations or PR review comments." }

Write-Host "All checks passed."
