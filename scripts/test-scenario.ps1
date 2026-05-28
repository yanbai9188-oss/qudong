#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

$m = Get-Content (Join-Path $root 'driver_packages.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$scan = @(Invoke-DriverScanEngine)
$full = @(Invoke-DriverMatchEngine -ScanResults $scan -Manifest $m -SkipLocalIndex).FixPlan

$fail = 0
foreach ($sc in @('network', 'usb', 'audio')) {
    $filtered = @(Filter-FixPlanByScenario -FixPlan $full -Scenario $sc)
    Write-Host ("SCENARIO {0}: {1} items" -f $sc, $filtered.Count)
    foreach ($item in $filtered) {
        $cls = Get-EffectiveDeviceClass -Device $item.Device
        $name = Get-DeviceDisplayName -Device $item.Device -Package $item.Package
        Write-Host ("  - [{0}] {1}" -f $cls, $name)
    }

    if ($sc -eq 'usb') {
        $bad = @($filtered | Where-Object { (Get-EffectiveDeviceClass -Device $_.Device) -eq 'bluetooth' })
        if ($bad.Count -gt 0) { Write-Host "FAIL: bluetooth in usb scenario"; $fail++ }
        else { Write-Host "OK: no bluetooth in usb scenario" }
    }
    if ($sc -eq 'network') {
        $bad = @($filtered | Where-Object { (Get-EffectiveDeviceClass -Device $_.Device) -eq 'usb_storage' })
        if ($bad.Count -gt 0) { Write-Host "FAIL: usb_storage in network scenario"; $fail++ }
        else { Write-Host "OK: no usb_storage in network scenario" }
    }
}

if ($fail -gt 0) { exit 1 }
Write-Host 'test-scenario.ps1 OK'
exit 0
