#requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'engine\DriverEngine.ps1') -AppRoot (Split-Path $PSScriptRoot -Parent)

$wifiDev = [PSCustomObject]@{
    FriendlyName = 'Intel(R) Dual Band Wireless-AC 7260'
    Class        = 'Net'
    InstanceId   = 'PCI\VEN_8086&DEV_08B1&SUBSYS_00008086&REV_73'
    HardwareIds  = @('PCI\VEN_8086&DEV_08B1')
    Status       = 'Error'
    IsProblem    = $true
}

$meiPkg = [PSCustomObject]@{
    id = 'intel_mei'; title = 'Intel 管理引擎 MEI'; category = 'mei'; deviceClass = 'mei'
    hwids = @('PCI\VEN_8086&DEV_43E0'); whql = $true; os = @('win10','win11')
}

$wifiPkg = [PSCustomObject]@{
    id = 'intel_wifi_7260'; title = 'Intel WiFi AC 7260 (Legacy)'; category = 'wifi'; deviceClass = 'network_wifi'
    hwids = @('PCI\VEN_8086&DEV_08B1'); whql = $true; os = @('win10','win11')
}

$chipsetPkg = [PSCustomObject]@{
    id = 'intel_chipset'; title = 'Intel Chipset INF'; category = 'chipset'; deviceClass = 'chipset'
    hwids = @('PCI\VEN_8086&DEV_43A3'); whql = $true; os = @('win10','win11')
}

if (-not (Test-DeviceClassCompatible -Device $wifiDev -PackageRaw $meiPkg)) { Write-Host 'OK: WiFi blocked from MEI' } else { throw 'FAIL: WiFi matched MEI' }
if (Test-DeviceClassCompatible -Device $wifiDev -PackageRaw $wifiPkg) { Write-Host 'OK: WiFi matches WiFi pkg' } else { throw 'FAIL: WiFi did not match WiFi pkg' }
if (-not (Test-DeviceClassCompatible -Device $wifiDev -PackageRaw $chipsetPkg)) { Write-Host 'OK: WiFi blocked from chipset' } else { throw 'FAIL: WiFi matched chipset' }

$cand = ConvertTo-PackageCandidate -PackageKey 'Seed_Intel_WiFi_7260' -PackageRaw $wifiPkg -Device $wifiDev
$cand | Add-Member -NotePropertyName _MatchHwids -NotePropertyValue @($wifiPkg.hwids) -Force
$tier = Get-RecommendTier -Item ([PSCustomObject]@{
    Device = $wifiDev
    Package = $cand
    Action = 'DownloadThenInstall'
    ConfidencePercent = 85
    ExactHwidMatch = $true
})
if ($tier -notlike '*不建议*' -and $tier) { Write-Host "OK: tier=$tier" } else { throw "FAIL: tier=$tier" }

Write-Host 'test_class_guard.ps1 OK'
