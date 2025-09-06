param(
  [Parameter(Mandatory=$true)]
  [ValidateSet('pbscript','mixin')]
  [string]$Kind,

  [Parameter(Mandatory=$true)]
  [string]$RepoPath,

  [Parameter(Mandatory=$true)]
  [string]$RemoteUrl,

  [Parameter(Mandatory=$true)]
  [string]$ProjectName,

  [string]$Solution = "SE-VIOS-DevFramework.sln"
)

$ErrorActionPreference = 'Stop'

function Copy-IfMissing($src,$dst) {
  if (-not (Test-Path $dst)) { Copy-Item -LiteralPath $src -Destination $dst -Force }
}

$tmplRoot = Join-Path "tools/templates" $Kind
if (-not (Test-Path $tmplRoot)) { throw "Template not found: $tmplRoot" }

# 1) Add submodule
try {
  git submodule add -b main $RemoteUrl $RepoPath | Out-Null
} catch {
  git submodule add $RemoteUrl $RepoPath | Out-Null
}

Push-Location $RepoPath
try {
  # 2) Copy template files
  Copy-IfMissing (Join-Path $tmplRoot ".gitignore") ".gitignore"
  Copy-IfMissing (Join-Path $tmplRoot ".gitattributes") ".gitattributes"
  Copy-IfMissing (Join-Path $tmplRoot "Directory.Build.props") "Directory.Build.props"

  if ($Kind -eq 'pbscript') {
    Copy-IfMissing (Join-Path $tmplRoot "__NAME__.csproj") "$ProjectName.csproj"
    Copy-IfMissing (Join-Path $tmplRoot "__NAME__.mdk.ini") "$ProjectName.mdk.ini"
    Copy-IfMissing (Join-Path $tmplRoot "Program.cs") "Program.cs"

    (Get-Content -Raw "Program.cs") -replace '__NAME__', $ProjectName | Set-Content "Program.cs" -NoNewline
  } else {
    Copy-IfMissing (Join-Path $tmplRoot "__NAME__.csproj") "$ProjectName.csproj"
    Copy-IfMissing (Join-Path $tmplRoot "Program.cs") "Program.cs"
    Copy-IfMissing (Join-Path $tmplRoot "Class1.cs") "Class1.cs"
  }

  git add .
  git commit -m "chore: scaffold $ProjectName ($Kind) from template" | Out-Null
  git push -u origin HEAD | Out-Null
}
finally {
  Pop-Location
}

# 3) Record pointer in super-repo
git add $RepoPath
git commit -m "chore: add submodule $ProjectName at $RepoPath" | Out-Null

# 4) Optionally add to solution
if (Test-Path $Solution) {
  dotnet sln $Solution add (Join-Path $RepoPath "$ProjectName.csproj") | Out-Null
  git add $Solution
  git commit -m "chore: add $ProjectName to solution" | Out-Null
} else {
  Write-Warning "Solution not found: $Solution (skipping sln add)"
}

Write-Host "Done. Submodule $ProjectName ($Kind) at $RepoPath"

