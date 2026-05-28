#requires -Version 5.1
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'lib\AppStartup.ps1')
Initialize-CIODIYEngine -AppRoot $root
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root
if (-not (Get-Command Test-IsAdmin -ErrorAction SilentlyContinue)) {
    Write-Host 'FAIL: Test-IsAdmin missing after engine load'
    exit 1
}
Write-Host 'OK: Test-IsAdmin available'
Write-Host ('OK: IsAdmin=' + (Test-IsAdmin))
exit 0
