<#
  # Policy: docs/policies/VIOS-Template-Sync-Policy.md
  # MODE: $env:MODE = 'STRICT' to fail on .csproj drift; default RELAXED
  Verify-TemplatesSync.ps1
  ------------------------
  Verifies submodules under Scripts/ (pbscript) and Mixins/ (mixin) against
  tools/templates/pbscript and tools/templates/mixin.

  - PB: Program.cs is NOT hard-diffed; we only enforce the enclosure
        'public partial class Program : MyGridProgram'.
        Exactly one *.csproj and one *.mdk.ini required,
        validates <Mdk2ProjectType>mdk2pbscript</...> and package set,
        compares infra + mdk.ini.
  - MIXIN: flexible code filenames, requires at least ONE *.cs with
           'partial class Program' (no visibility/base),
           forbids ': MyGridProgram', exactly one *.csproj with mdk2mixin + required packages.
  - Uses __NAME__ literal substitution (no regex) to compare templates to actual files.
  - Emits ::error/::warning/::notice for GitHub Actions.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------
$MODE   = if ($env:MODE) { $env:MODE } else { 'RELAXED' }  # RELAXED | STRICT
$PB_TPL = Join-Path 'tools/templates' 'pbscript'
$MX_TPL = Join-Path 'tools/templates' 'mixin'

# For PB: compare infra + __NAME__.mdk.ini (Program.cs is enclosure-only)
$PB_FILES = @(
  '.gitignore:.gitignore',
  '.gitattributes:.gitattributes',
  '.editorconfig:.editorconfig',
  'Directory.Build.props:Directory.Build.props',
  '__NAME__.mdk.ini:__NAME__.mdk.ini'
)

# For MIXIN: compare only infra + __NAME__.csproj (code filenames are flexible)
$MX_FILES = @(
  '.gitignore:.gitignore',
  '.gitattributes:.gitattributes',
  '.editorconfig:.editorconfig',
  'Directory.Build.props:Directory.Build.props',
  '__NAME__.csproj:__NAME__.csproj'
)

# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------
$script:Failed = $false
# Track summary
$script:Missing    = New-Object System.Collections.ArrayList
$script:Drift      = New-Object System.Collections.ArrayList
$script:Violations = New-Object System.Collections.ArrayList

function Notice([string]$msg) { Write-Host "::notice::$msg" }
function Warn  ([string]$msg) { Write-Host "::warning::$msg" }
function Fail  ([string]$msg) { $script:Failed = $true; Write-Host "::error::$msg" }

function Add-Missing([string]$what) {
  $script:Missing.Add($what) | Out-Null
  Fail "Missing in submodule: $what"
}
function Add-Violation([string]$what) {
  $script:Violations.Add($what) | Out-Null
  Fail $what
}
function Add-DriftRecord([string]$path) {
  $script:Drift.Add($path) | Out-Null
}
function Apply-DriftPolicy([string]$compareKind) {
  # compareKind: 'static' | 'semi'
  if ($compareKind -eq 'static') {
    $script:Failed = $true
  } elseif ($compareKind -eq 'semi' -and $MODE -eq 'STRICT') {
    $script:Failed = $true
  }
}

# Strip allowed differences to reduce false positives
function Apply-Ignores([string]$Text,[string]$Path,[string]$RoleKind) {
  if ($null -eq $Text) { return $null }

  # 1) XML comments (csproj)
  if ($Path -like '*.csproj') {
    $Text = [regex]::Replace($Text, '<!--.*?-->', '', 'Singleline')
    # Ignore ItemGroup with only ProjectReference elements
    $Text = [regex]::Replace(
      $Text,
      '(?s)<ItemGroup>\s*(?:<ProjectReference\b.*?</ProjectReference>\s*)+</ItemGroup>',
      ''
    )
    # Collapse whitespace runs
    $Text = [regex]::Replace($Text, '\s+', ' ')
  }

  # 2) Program.cs banner (PB only): strip leading // comments until first 'namespace' or 'using'
  if ($Path -like '*Program.cs' -and $RoleKind -eq 'pb') {
    $Text = [regex]::Replace($Text, '^(?:(?:\s*//.*)\r?\n)+', '', 'Multiline')
  }

  # Normalize final newline presence
  if ($Text -notmatch "\n$") { $Text = $Text + "`n" }

  return $Text
}

function Get-OneFileOrEmpty([string]$dir,[string]$pattern) {
  $files = @(Get-ChildItem -LiteralPath $dir -Filter $pattern -File -ErrorAction SilentlyContinue)
  if ($files.Count -eq 1) { return $files[0].FullName }
  return ''
}

function Get-NormalizedContent([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop
  $text = $text.Replace("`r","")                # normalize CRLF -> LF
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
    $text = $text.Substring(1)                   # strip UTF-8 BOM
  }
  return $text
}

function Compare-TemplateToActual {
  param(
    [Parameter(Mandatory)][string]$tplPath,
    [Parameter(Mandatory)][string]$actualPath,
    [Parameter(Mandatory)][string]$projectName,
    [Parameter(Mandatory)][ValidateSet('pb','mixin')][string]$roleKind,
    [Parameter(Mandatory)][ValidateSet('static','semi')][string]$compareKind
  )
  if (-not (Test-Path -LiteralPath $actualPath)) { Add-Missing $actualPath; return }
  if (-not (Test-Path -LiteralPath $tplPath))   { Warn "Template missing: $tplPath"; return }

  $tpl = (Get-Content -LiteralPath $tplPath -Raw -Encoding UTF8).Replace("`r","")
  if ($tpl.Length -gt 0 -and $tpl[0] -eq [char]0xFEFF) { $tpl = $tpl.Substring(1) }
  $tpl = $tpl.Replace('__NAME__', $projectName)
  $dst = Get-NormalizedContent $actualPath

  # Apply role-aware “ignore patterns” before comparing
  $tpl = Apply-Ignores -Text $tpl -Path $actualPath -RoleKind $roleKind
  $dst = Apply-Ignores -Text $dst -Path $actualPath -RoleKind $roleKind

  $tmpL = New-TemporaryFile; $tmpR = New-TemporaryFile
  Set-Content -LiteralPath $tmpL -NoNewline -Encoding UTF8 -Value $tpl
  Set-Content -LiteralPath $tmpR -NoNewline -Encoding UTF8 -Value $dst

  & git --no-pager diff --no-index --ignore-cr-at-eol -- "$tmpL" "$tmpR" *> $null
  $different = ($LASTEXITCODE -ne 0)

  if ($different) {
    Write-Host "::group::Drift in $actualPath"
    & git --no-pager diff --no-index --ignore-cr-at-eol -- "$tmpL" "$tmpR"
    Write-Host "::endgroup::"
    Add-DriftRecord $actualPath
    Apply-DriftPolicy $compareKind
  }

  Remove-Item $tmpL,$tmpR -Force -ErrorAction SilentlyContinue
}

function Dir-NameOf([string]$path) { Split-Path -Path $path -Leaf }

# ---------------------------------------------------------------------
# PB script check
# ---------------------------------------------------------------------
function Check-PbScript([string]$modPath) {
  $proj = Dir-NameOf $modPath
  Write-Host "== Scripts (pbscript) :: $modPath =="

  foreach ($map in $PB_FILES) {
    $parts = $map.Split(':',2)
    $src = $parts[0]; $dst = $parts[1]
    $tpl = Join-Path $PB_TPL $src
    $outName = $dst.Replace('__NAME__', $proj)     # literal replace
    $out = Join-Path $modPath $outName
    if (-not (Test-Path -LiteralPath $out)) {
      Add-Missing $out
      continue
    }
    # All PB infra & mdk.ini are static comparisons
    Compare-TemplateToActual -tplPath $tpl -actualPath $out -projectName $proj -roleKind 'pb' -compareKind 'static'
  }

  # Program enclosure (strict)
  $programPath = Join-Path $modPath 'Program.cs'
  if (-not (Test-Path -LiteralPath $programPath)) {
    Add-Missing "$programPath"
  } else {
    $hasEnclosure = Select-String -LiteralPath $programPath -Pattern 'public\s+partial\s+class\s+Program\s*:\s*MyGridProgram' -Quiet
    if (-not $hasEnclosure) { Add-Violation "$programPath must declare 'public partial class Program : MyGridProgram'" }
  }

  # Exactly one .csproj
  $csproj = Get-OneFileOrEmpty $modPath '*.csproj'
  if ([string]::IsNullOrEmpty($csproj)) {
    Add-Violation "Expected exactly one .csproj in $modPath"
  } else {
    $cs = Get-NormalizedContent $csproj
    if ($cs -notmatch '<Mdk2ProjectType>\s*mdk2pbscript\s*</Mdk2ProjectType>') { Add-Violation "$csproj missing <Mdk2ProjectType>mdk2pbscript</Mdk2ProjectType>" }
    if ($cs -notmatch 'Include="Mal\.Mdk2\.PbPackager"')  { Add-Violation "$csproj missing Mal.Mdk2.PbPackager (PB scripts need it)" }
    if ($cs -notmatch 'Include="Mal\.Mdk2\.PbAnalyzers"') { Add-Violation "$csproj missing Mal.Mdk2.PbAnalyzers" }
    if ($cs -notmatch 'Include="Mal\.Mdk2\.References"')  { Add-Violation "$csproj missing Mal.Mdk2.References" }
    $tplCsproj = Join-Path $PB_TPL '__NAME__.csproj'
    if (Test-Path -LiteralPath $tplCsproj) {
      Compare-TemplateToActual -tplPath $tplCsproj -actualPath $csproj -projectName $proj -roleKind 'pb' -compareKind 'semi'
    }
  }

  # Exactly one *.mdk.ini, contains type=programmableblock; compare if named $proj.mdk.ini
  $ini = Get-OneFileOrEmpty $modPath '*.mdk.ini'
  if ([string]::IsNullOrEmpty($ini)) {
    Add-Violation "Expected exactly one *.mdk.ini in $modPath"
  } else {
    $iniText = Get-NormalizedContent $ini
    if ($iniText -notmatch '(?m)^\s*type\s*=\s*programmableblock\s*$') {
      Add-Violation "$ini should contain 'type=programmableblock'"
    }
    $expected = Join-Path $modPath ($proj + '.mdk.ini')
    $tplIni = Join-Path $PB_TPL '__NAME__.mdk.ini'
    if ((Test-Path -LiteralPath $expected) -and (Test-Path -LiteralPath $tplIni)) {
      Compare-TemplateToActual -tplPath $tplIni -actualPath $expected -projectName $proj -roleKind 'pb' -compareKind 'static'
    }
  }
}

# ---------------------------------------------------------------------
# Mixin check (flexible filenames)
# ---------------------------------------------------------------------
function Check-Mixin([string]$modPath) {
  $proj = Dir-NameOf $modPath
  Write-Host "== Mixins (mixin) :: $modPath =="

  # Compare infra (skip csproj here, handle below)
  foreach ($map in $MX_FILES) {
    $parts = $map.Split(':',2)
    $src = $parts[0]; $dst = $parts[1]
    if ($src -eq '__NAME__.csproj') { continue }
    $tpl = Join-Path $MX_TPL $src
    $outName = $dst.Replace('__NAME__', $proj)
    $out = Join-Path $modPath $outName
    if (-not (Test-Path -LiteralPath $out)) {
      Add-Missing $out
      continue
    }
    Compare-TemplateToActual -tplPath $tpl -actualPath $out -projectName $proj -roleKind 'mixin' -compareKind 'static'
  }

  # Enclosure rule: some *.cs must declare 'partial class Program' (no visibility/base)
  $anyPartial = $false
  $anyInheritance = $false
  $csFiles = @(Get-ChildItem -LiteralPath $modPath -Recurse -Filter *.cs -File -ErrorAction SilentlyContinue)
  foreach ($f in $csFiles) {
    $txt = Get-NormalizedContent $f.FullName
    if ($txt -match '(^|\s)partial\s+class\s+Program(\s*{|\s*$)') { $anyPartial = $true }
    if ($txt -match ':\s*MyGridProgram') { $anyInheritance = $true }
  }
  if (-not $anyPartial) { Add-Violation "$modPath must contain at least one *.cs declaring 'partial class Program' (no visibility/base)" }
  if ($anyInheritance)  { Add-Violation "$modPath contains a mixin file inheriting MyGridProgram (not allowed in mixins)" }

  # Exactly one .csproj; validate
  $csproj = Get-OneFileOrEmpty $modPath '*.csproj'
  if ([string]::IsNullOrEmpty($csproj)) {
    Add-Violation "Expected exactly one .csproj in $modPath"
  } else {
    $cs = Get-NormalizedContent $csproj
    if ($cs -notmatch '<Mdk2ProjectType>\s*mdk2mixin\s*</Mdk2ProjectType>') { Add-Violation "$csproj missing <Mdk2ProjectType>mdk2mixin</Mdk2ProjectType>" }
    if ($cs -match 'Include="Mal\.Mdk2\.PbPackager"') { Add-Violation "$csproj must NOT include Mal.Mdk2.PbPackager" }
    if ($cs -notmatch 'Include="Mal\.Mdk2\.PbAnalyzers"') { Add-Violation "$csproj missing Mal.Mdk2.PbAnalyzers" }
    if ($cs -notmatch 'Include="Mal\.Mdk2\.References"')  { Add-Violation "$csproj missing Mal.Mdk2.References" }
    $tplCsproj = Join-Path $MX_TPL '__NAME__.csproj'
    if (Test-Path -LiteralPath $tplCsproj) {
      Compare-TemplateToActual -tplPath $tplCsproj -actualPath $csproj -projectName $proj -roleKind 'mixin' -compareKind 'semi'
    }
  }
}

# ---------------------------------------------------------------------
# Walk submodules
# ---------------------------------------------------------------------
if (Test-Path -LiteralPath 'Scripts') {
  Get-ChildItem -LiteralPath 'Scripts' -Directory | ForEach-Object {
    Check-PbScript $_.FullName
  }
}

if (Test-Path -LiteralPath 'Mixins') {
  Get-ChildItem -LiteralPath 'Mixins' -Directory -Recurse | ForEach-Object {
    $p = $_.FullName
    if ($p -like '*\VIOS.Core' -or $p -like '*\Mixins\Modules\*' -or $p -like '*\Mixins\Components\*') {
      # Limit to depth <= Mixins + 2
      $mix = (Resolve-Path 'Mixins').Path
      $mixDepth = ($mix -split [regex]::Escape([IO.Path]::DirectorySeparatorChar)).Count
      $pDepth   = ($p   -split [regex]::Escape([IO.Path]::DirectorySeparatorChar)).Count
      if ($pDepth -le ($mixDepth + 2)) { Check-Mixin $p }
    }
  }
}

# ---------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------
Write-Host '===== Verify-TemplatesSync.ps1: Summary ====='
if ($script:Missing.Count -gt 0) {
  Write-Host ("Missing files ({0}):" -f $script:Missing.Count)
  $script:Missing | ForEach-Object { Write-Host "  - $_" }
} else {
  Write-Host 'Missing files: none'
}

if ($script:Drift.Count -gt 0) {
  Write-Host ("Drift vs template ({0}):" -f $script:Drift.Count)
  $script:Drift | ForEach-Object { Write-Host "  - $_" }
} else {
  Write-Host 'Drift vs template: none'
}

if ($script:Violations.Count -gt 0) {
  Write-Host ("Validation issues ({0}):" -f $script:Violations.Count)
  $script:Violations | ForEach-Object { Write-Host "  - $_" }
} else {
  Write-Host 'Validation issues: none'
}
Write-Host '============================================='

if ($script:Failed) {
  Fail "Template sync FAILED"
  exit 1
} else {
  Notice "Template sync OK"
}
