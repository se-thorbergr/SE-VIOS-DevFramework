#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$PB_TPL = "tools/templates/pbscript"
$MX_TPL = "tools/templates/mixin"

$pbFiles = @(
  ".gitignore:.gitignore",
  ".gitattributes:.gitattributes",
  ".editorconfig:.editorconfig",
  "Directory.Build.props:Directory.Build.props",
  "Program.cs:Program.cs",
  "__NAME__.csproj:__NAME__.csproj",
  "__NAME__.mdk.ini:__NAME__.mdk.ini"
)
$mxFiles = @(
  ".gitignore:.gitignore",
  ".gitattributes:.gitattributes",
  ".editorconfig:.editorconfig",
  "Directory.Build.props:Directory.Build.props",
  "Program.cs:Program.cs",
  "__NAME__.csproj:__NAME__.csproj",
  "Class1.cs:Class1.cs"
)

$fail = 0

function Diff-File($tpl, $dst, $proj) {
  if (-not (Test-Path $dst)) { Write-Error "Missing file: $dst"; return $false }
  $tmp = New-TemporaryFile
  try {
    (Get-Content -Raw -LiteralPath $tpl) -replace '__NAME__', $proj | Set-Content -LiteralPath $tmp -Encoding UTF8
    $a = (Get-Content -Raw -LiteralPath $tmp)
    $b = (Get-Content -Raw -LiteralPath $dst)
    if ($a -ne $b) {
      Write-Host "::group::Drift in $dst"
      # Show a minimal diff (line-wise)
      $al = $a -split "`r?`n"
      $bl = $b -split "`r?`n"
      $max = [Math]::Max($al.Count, $bl.Count)
      for ($i=0; $i -lt $max; $i++) {
        $l = if ($i -lt $al.Count) { $al[$i] } else { "" }
        $r = if ($i -lt $bl.Count) { $bl[$i] } else { "" }
        if ($l -ne $r) { Write-Host ("- " + $l); Write-Host ("+ " + $r) }
      }
      Write-Host "::endgroup::"
      return $false
    }
    return $true
  } finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
  }
}

function Check-PbScript($mod) {
  $proj = Split-Path $mod -Leaf
  Write-Host "== Scripts (pbscript) :: $mod =="

  foreach ($map in $pbFiles) {
    $parts = $map -split ':',2
    $src = Join-Path $PB_TPL $parts[0]
    $dstRel = $parts[1].Replace('__NAME__', $proj)
    $dst = Join-Path $mod $dstRel
    if (-not (Test-Path $src)) { Write-Warning "Template missing: $src"; continue }
    if (-not (Test-Path $dst)) { Write-Error "Missing in submodule: $dst"; $script:fail++ ; continue }
    if (-not (Diff-File $src $dst $proj)) { $script:fail++ }
  }

  $prog = Join-Path $mod "Program.cs"
  $content = Get-Content -Raw -LiteralPath $prog
  if ($content -notmatch 'public\s+partial\s+class\s+Program\s*:\s*MyGridProgram') {
    Write-Error "$prog must declare 'public partial class Program : MyGridProgram'"; $script:fail++
  }

  $csproj = Join-Path $mod "$proj.csproj"
  $cs = Get-Content -Raw -LiteralPath $csproj
  if ($cs -notmatch 'Mal\.Mdk2\.PbPackager') { Write-Error "$csproj missing Mal.Mdk2.PbPackager"; $script:fail++ }
  if ($cs -notmatch 'Mal\.Mdk2\.PbAnalyzers') { Write-Error "$csproj missing Mal.Mdk2.PbAnalyzers"; $script:fail++ }
  if ($cs -notmatch 'Mal\.Mdk2\.References') { Write-Error "$csproj missing Mal.Mdk2.References"; $script:fail++ }
}

function Check-Mixin($mod) {
  $proj = Split-Path $mod -Leaf
  Write-Host "== Mixins (mixin) :: $mod =="

  foreach ($map in $mxFiles) {
    $parts = $map -split ':',2
    $src = Join-Path $MX_TPL $parts[0]
    $dstRel = $parts[1].Replace('__NAME__', $proj)
    $dst = Join-Path $mod $dstRel
    if (-not (Test-Path $src)) { Write-Warning "Template missing: $src"; continue }
    if (-not (Test-Path $dst)) { Write-Error "Missing in submodule: $dst"; $script:fail++ ; continue }
    if (-not (Diff-File $src $dst $proj)) { $script:fail++ }
  }

  $prog = Join-Path $mod "Program.cs"
  $content = Get-Content -Raw -LiteralPath $prog
  if ($content -notmatch '(^|\s)partial\s+class\s+Program(\s*{|\s*$)') {
    Write-Error "$prog must declare 'partial class Program' (no visibility/base)"; $script:fail++
  }
  if ($content -match ':\s*MyGridProgram') {
    Write-Error "$prog should NOT inherit MyGridProgram in mixins"; $script:fail++
  }

  $csproj = Join-Path $mod "$proj.csproj"
  $cs = Get-Content -Raw -LiteralPath $csproj
  if ($cs -match 'Mal\.Mdk2\.PbPackager') { Write-Error "$csproj must NOT reference Mal.Mdk2.PbPackager"; $script:fail++ }
  if ($cs -notmatch 'Mal\.Mdk2\.PbAnalyzers') { Write-Error "$csproj missing Mal.Mdk2.PbAnalyzers"; $script:fail++ }
  if ($cs -notmatch 'Mal\.Mdk2\.References') { Write-Error "$csproj missing Mal.Mdk2.References"; $script:fail++ }
}

if (Test-Path "Scripts") {
  Get-ChildItem -Path "Scripts" -Directory | ForEach-Object {
    Check-PbScript $_.FullName
  }
}
if (Test-Path "Mixins") {
  # VIOS.Core + Modules/* + Components/*
  Get-ChildItem -Path "Mixins" -Directory | ForEach-Object {
    if ($_.Name -eq "VIOS.Core") { Check-Mixin $_.FullName }
    if ($_.Name -in @("Modules","Components")) {
      Get-ChildItem -Path $_.FullName -Directory | ForEach-Object { Check-Mixin $_.FullName }
    }
  }
}

if ($fail -ne 0) {
  Write-Error "Template sync FAILED ($fail issue(s))"
  exit 1
}
Write-Host "::notice::Template sync OK"
