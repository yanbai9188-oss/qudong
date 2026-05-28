#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$log = Join-Path $env:TEMP 'driverbooster_launch.log'
try {
    $root = Split-Path $PSScriptRoot -Parent
    & (Join-Path $root 'DriverBooster.ps1')
} catch {
    $_ | Out-String | Add-Content $log
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Driver Booster Error')
    throw
}
