#requires -Version 5.1
# Build intel_graphics driver folder via pnputil export (run on machine with Intel iGPU installed)
param(
    [string]$PublishedInf = 'oem1.inf',
    [string]$DestFolder = 'intel_graphics'
)

$ErrorActionPreference = 'Stop'
$AppRoot = Split-Path $PSScriptRoot -Parent
$dest = Join-Path (Join-Path $AppRoot 'Drivers') $DestFolder

Write-Host "Export Intel graphics: $PublishedInf -> $DestFolder"
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$out = pnputil /export-driver $PublishedInf $dest 2>&1
$out | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { throw "pnputil export failed (exit $LASTEXITCODE)" }

$files = Get-ChildItem $dest -Recurse -File
if ($files.Count -eq 0) { throw 'Export folder is empty' }

Set-Content -Path (Join-Path $dest 'source.txt') -Encoding UTF8 -Value @(
    "Source: pnputil /export-driver $PublishedInf",
    "Built: $(Get-Date -Format o)",
    "Files: $($files.Count)",
    "SizeMB: $([math]::Round(($files | Measure-Object Length -Sum).Sum / 1MB, 1))"
)

Write-Host "Done: $dest ($($files.Count) files)" -ForegroundColor Green
Write-Host "Next: qudong-repo\Publish-Release.ps1"
