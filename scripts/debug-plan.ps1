#requires -Version 5.1
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'engine\DriverEngine.ps1') -AppRoot (Split-Path $PSScriptRoot -Parent)
$root = Split-Path $PSScriptRoot -Parent
$m = Get-Content (Join-Path $root 'driver_packages.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$scan = @(Invoke-DriverScanEngine)
$match = Invoke-DriverMatchEngine -ScanResults $scan -Manifest $m -SkipLocalIndex
Write-Host "Full plan count: $($match.FixPlan.Count)"
foreach ($item in $match.FixPlan) {
    $hide = if ($item.HideFromList) { 'HIDE' } else { 'SHOW' }
    $dep = if ($item.IsDependency) { 'DEP' } else { 'PRI' }
    $attached = if ($item.AttachedToParent) { 'ATT' } else { '' }
    $deps = if ($item.Dependencies) { @($item.Dependencies).Count } else { 0 }
    Write-Host ("  [{0}/{1}/{2}] {3} pkg={4} childDeps={5}" -f $hide,$dep,$attached,
        (Get-DeviceDisplayName -Device $item.Device -Package $item.Package),
        $(if($item.Package){$item.Package.Id}else{'none'}), $deps)
}
