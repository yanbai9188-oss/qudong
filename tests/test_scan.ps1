#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

Write-Host '=== test_scan ==='
$results = @(Invoke-DriverScan)
if ($results.Count -eq 0) { throw 'Scan returned no devices' }
Write-Host ("PASS scan devices={0} problems={1}" -f $results.Count, @($results | Where-Object IsProblem).Count)
exit 0
