# Publie chaque dossier projet sur sa branche GitHub project/*
# Usage : depuis la racine du depot, sur main a jour :
#   .\scripts\publish-project-branches.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Set-Location $RepoRoot

if (-not (Test-Path ".git")) {
  throw "Pas un depot git : $RepoRoot"
}

$Projects = @(
  @{ Branch = "project/01-rtos";            Dir = "01-rtos" },
  @{ Branch = "project/02-linux-embarque"; Dir = "02-linux-embarque" },
  @{ Branch = "project/03-affichage-data";  Dir = "03-affichage-data" },
  @{ Branch = "project/04-mobile-flutter";  Dir = "04-mobile-flutter" },
  @{ Branch = "project/05-iot-mqtt";        Dir = "05-iot-mqtt" },
  @{ Branch = "project/06-iot-web-dashboard"; Dir = "06-iot-web-dashboard" },
  @{ Branch = "project/07-oled-ssd1306";    Dir = "07-oled-ssd1306" },
  @{ Branch = "project/08-esp32-unified";   Dir = "08-esp32-unified" }
)

$currentBranch = git rev-parse --abbrev-ref HEAD
if ($currentBranch -ne "main") {
  git checkout main
}

$stamp = Get-Date -Format "yyyy-MM-dd HH:mm"

foreach ($p in $Projects) {
  $branch = $p.Branch
  $dir = $p.Dir
  $src = Join-Path $RepoRoot $dir

  if (-not (Test-Path $src)) {
    Write-Warning "Ignore $branch : dossier absent $dir"
    continue
  }

  Write-Host "`n=== Publication $branch <= $dir ===" -ForegroundColor Cyan

  $temp = Join-Path $env:TEMP "eljezi-publish-$($dir -replace '[^a-zA-Z0-9]','-')"
  if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
  New-Item -ItemType Directory -Path $temp | Out-Null
  Copy-Item -Path (Join-Path $src "*") -Destination $temp -Recurse -Force

  $mono = @"
# Branche projet ``$branch``

Contenu isole depuis le monorepo [El-Jezi-Ghassen-Embarquee](https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee) (``main``).

| | |
|---|---|
| Dossier source | ``$dir/`` |
| Publie le | $stamp |

Pour le depot complet : ``git clone https://github.com/GhassenEl/El-Jezi-Ghassen-Embarquee.git``
"@
  Set-Content -Path (Join-Path $temp "MONOREPO.md") -Value $mono -Encoding UTF8

  git checkout main 2>&1 | Out-Null
  cmd /c "git branch -D $branch 2>nul"
  git checkout --orphan $branch

  Get-ChildItem -Path $RepoRoot -Force | Where-Object { $_.Name -ne ".git" } | ForEach-Object {
    Remove-Item $_.FullName -Recurse -Force
  }

  Copy-Item -Path (Join-Path $temp "*") -Destination $RepoRoot -Recurse -Force
  Remove-Item $temp -Recurse -Force

  git add -A
  git -c user.name="Ghassen El Jezi" -c user.email="GhassenEl@users.noreply.github.com" `
    commit -m "Publish $dir on branch $branch"

  git push -u origin $branch --force
  if ($LASTEXITCODE -ne 0) { throw "Push echoue pour $branch" }

  Write-Host "OK $branch" -ForegroundColor Green
}

git checkout main
Write-Host "`nTermine. Branches project/* publiees depuis main." -ForegroundColor Green
