Param()
$ErrorActionPreference = 'Stop'

# Always call the template-driven stamper first
$stamper = Join-Path $PSScriptRoot "..\tools\Add-LicenseHeader.ps1"
if (Test-Path $stamper) { & pwsh $stamper }

# Re-stage files that just got stamped
$modified = git ls-files -m | Where-Object { $_ -like "*.cs" }
if ($modified) { git add $modified }

# Final check: any staged .cs without header?
$staged = git diff --cached --name-only --diff-filter=ACM | Where-Object { $_ -like "*.cs" }
$missing = @()
foreach ($f in $staged) {
  if (-not (Test-Path $f)) { continue }
  $head = Get-Content -Path $f -TotalCount 12 -Raw
  if ($head -notmatch "MIT License" -and $head -notmatch "Viking Industries Operating System") {
    $missing += $f
  }
}
if ($missing.Count -gt 0) {
  Write-Host "Auto-stamping missing headers:"; $missing | ForEach-Object { Write-Host " - $_" }
  & pwsh $stamper
  git add $missing
}

exit 0
