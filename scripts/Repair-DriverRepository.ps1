#requires -Version 5.1
<#
.SYNOPSIS
  Audit and optionally repair local driver repository (manifest SHA256, missing ZIP/INF).
#>
param(
    [string]$AppRoot = '',
    [switch]$UpdateManifestSha,
    [switch]$DownloadMissing,
    [switch]$ReportOnly
)

$ErrorActionPreference = 'Stop'
$root = if ($AppRoot) { $AppRoot } else { Split-Path $PSScriptRoot -Parent }
. (Join-Path $root 'engine\Initialize-Engine.ps1') -AppRoot $root

$health = Repair-DriverRepository -AppRoot $root -UpdateManifestSha:($UpdateManifestSha -and -not $ReportOnly) -DownloadMissing:($DownloadMissing -and -not $ReportOnly)

Write-Host ''
Write-Host 'Driver Repository Health' -ForegroundColor Cyan
Write-Host ('Total packages : {0}' -f $health.TotalPackages)
Write-Host ('Valid          : {0}' -f $health.Valid) -ForegroundColor Green
Write-Host ('Warning        : {0}' -f $health.Warning) -ForegroundColor Yellow
Write-Host ('Failed         : {0}' -f $health.Failed) -ForegroundColor Red
Write-Host ('Health score   : {0}%' -f $health.HealthPercent) -ForegroundColor Cyan
Write-Host $health.SummaryLine
if ($health.ManifestUpdated) {
    Write-Host 'Manifest SHA256 values were updated for matching local ZIP files.' -ForegroundColor Green
}

Write-Host ''
Write-Host 'Details:' -ForegroundColor DarkGray
foreach ($d in $health.Details) {
    $color = switch ($d.Level) {
        'pass' { 'Green' }
        'warn' { 'Yellow' }
        default { 'Red' }
    }
    $issueText = if ($d.Issues.Count -gt 0) { $d.Issues -join ', ' } else { 'ok' }
    Write-Host ("  [{0}] {1} : {2}" -f $d.Level, $d.Id, $issueText) -ForegroundColor $color
}

$reportPath = Join-Path $root ('Logs\RepoHealth_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$dir = Split-Path $reportPath -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
($health | ConvertTo-Json -Depth 6) | Set-Content $reportPath -Encoding UTF8
Write-Host ''
Write-Host ('Report saved: {0}' -f $reportPath)

if ($health.Failed -gt 0) {
    exit 1
}
exit 0
