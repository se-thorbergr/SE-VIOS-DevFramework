param(
[string]$Root = ".",
[string[]]$Folders = @("Mixins","Modules"),
[string[]]$Extensions = @(".cs"),
[string[]]$ExcludeFiles = @("Program.cs","AssemblyInfo.cs"),
[string]$TemplatePath = "tools/license_header.tmpl",
[string]$Owner = "Thorbergr",
[int]$Year = (Get-Date).ToUniversalTime().Year,
[string]$GitHubOwner = "geho",
[string]$GitHubRepo = "SE-VIOS-DevFramework",
[string]$WorkshopId = "0000000000"
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $TemplatePath)) { throw "Header template not found: $TemplatePath" }

$template = Get-Content -Path $TemplatePath -Raw
$header = $template.Replace("{{YEAR}}", "$Year").
  Replace("{{WORKSHOP_ID}}", $WorkshopId).
  Replace("{{GITHUB_OWNER}}", $GitHubOwner).
  Replace("{{GITHUB_REPO}}", $GitHubRepo)

function Has-Header([string]$path) {
  try {
    $first = Get-Content -Path $path -TotalCount 12 -Raw -ErrorAction Stop
    return ($first -match "MIT License" -or $first -match "Viking Industries Operating System")
  } catch { return $true }
}

$processed = 0; $stamped = 0; $skipped = 0
foreach ($folder in $Folders) {
  $full = Join-Path $Root $folder
  if (-not (Test-Path $full)) { Write-Host "Skip missing folder: $full"; continue }

  Get-ChildItem -Path $full -Recurse -File | Where-Object { $_.Extension -in $Extensions -and $_.Name -notin $ExcludeFiles } | ForEach-Object {
    $p = $_.FullName; $processed++
    if (Has-Header $p) { $skipped++; return }
    try {
      $content = Get-Content -Path $p -Raw
      $tmp = "$p.tmp"
      Set-Content -Path $tmp -Value ($header + "`r`n`r`n" + $content) -NoNewline
      Move-Item -Force $tmp $p
      $stamped++
    } catch { Write-Warning "Failed to stamp: $p ($_ )" }
  }
}

Write-Host "Processed: $processed | Stamped: $stamped | Skipped: $skipped"
