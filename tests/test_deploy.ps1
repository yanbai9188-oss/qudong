#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

$result = Invoke-DeployModeEngine -AutoFix:$false -ExportReport -FastMatch -AppVersion '1.4.0' `
    -OnLog { param($m) Write-Host $m }

Write-Host "Status: $($result.Status)"
Write-Host "Report: $($result.ReportPath)"
if (-not $result.ReportPath -or -not (Test-Path $result.ReportPath)) {
    throw 'Deploy report not created'
}
if (-not $result.HardwareProfile.MachineTitle) {
    throw 'Hardware profile missing'
}

Write-Host 'test_deploy.ps1 OK'
