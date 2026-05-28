#requires -Version 5.1
param([string]$Out = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

$r = Export-HardwareDriverRequestEngine -OutputPath $Out -OnLog { param($m) Write-Host $m }
if ($r.Success) {
    Write-Host ("Exported: {0}" -f $r.Message)
    exit 0
}
Write-Host $r.Message -ForegroundColor Red
exit 1
