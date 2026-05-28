#requires -Version 5.1
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'lib\AppStartup.ps1')

function LoadEngineWrong {
    param([string]$AppRoot)
    Initialize-CIODIYEngine -AppRoot $AppRoot
}
LoadEngineWrong -AppRoot $root
Write-Host "After wrong load, Test-IsAdmin: $(Get-Command Test-IsAdmin -ErrorAction SilentlyContinue)"

. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root
Write-Host "After script-level load, Test-IsAdmin: $(Get-Command Test-IsAdmin -ErrorAction SilentlyContinue)"
