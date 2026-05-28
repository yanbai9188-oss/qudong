#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

$hw = Get-HardwareProfile -Refresh
Write-Host "Machine: $($hw.MachineTitle)"
Write-Host "Platform: $($hw.PlatformLine)"
Write-Host "CPU: $($hw.CPU)"
Write-Host "GPU: $($hw.GPU)"
Write-Host "Network: $($hw.Network)"
Write-Host "Audio: $($hw.Audio)"
Write-Host "BIOS: $($hw.BIOS)"

if ([string]::IsNullOrWhiteSpace($hw.MachineTitle)) { throw 'MachineTitle empty' }
if ($hw.Platform -notin @('Intel', 'AMD', '未知')) { throw "Unexpected platform: $($hw.Platform)" }

Write-Host 'test_hardware.ps1 OK'
