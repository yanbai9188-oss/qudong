#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

$quick = Invoke-DriverHealthEngine -QuickOnly
if ($quick.HealthScore -lt 0 -or $quick.HealthScore -gt 100) { throw 'Invalid quick score' }

$full = Invoke-DriverHealthEngine -RunScan -FastMatch -OnLog { param($m) Write-Host $m }
if ($full.HealthScore -lt 0 -or $full.HealthScore -gt 100) { throw 'Invalid full score' }

$cached = Get-DriverHealthCache
if (-not $cached) { throw 'Health cache not written' }

Write-Host ("Quick={0}% Full={1}% Problems={2}" -f $quick.HealthScore, $full.HealthScore, $full.ProblemCount)
Write-Host 'test_health.ps1 OK'
