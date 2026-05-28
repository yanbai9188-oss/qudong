#requires -Version 5.1
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'engine\DriverEngine.ps1') -AppRoot (Split-Path $PSScriptRoot -Parent)
$root = Split-Path $PSScriptRoot -Parent
$m = Get-Content (Join-Path $root 'driver_packages.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$scan = @(Invoke-DriverScanEngine)
$match = Invoke-DriverMatchEngine -ScanResults $scan -Manifest $m -SkipLocalIndex
$s = Get-RepairSummary -FixPlan $match.FixPlan -ScanResults $scan
$s | Format-List *
Write-Host '--- Items ---'
foreach ($item in (Get-VisibleFixPlanItems -FixPlan $match.FixPlan)) {
    $tier = Get-RecommendTier -Item $item
    $name = Get-DeviceDisplayName -Device $item.Device -Package $item.Package
    $deps = @($item.Dependencies | ForEach-Object { $_.Package.Title })
    $depStr = if ($deps.Count -gt 0) { " deps=[$($deps -join ',')]" } else { '' }
    Write-Host ("  [{0}] {1} -> {2}{3}" -f $tier, $name, $item.Package.Title, $depStr)
}
