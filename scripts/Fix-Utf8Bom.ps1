#requires -Version 5.1
$enc = New-Object System.Text.UTF8Encoding $true
$root = Split-Path $PSScriptRoot -Parent
$files = @(
    'DriverBooster.ps1'
    'lib\AppStartup.ps1'
    'lib\UserFriendlyText.ps1'
    'lib\DeviceClassGuard.ps1'
    'lib\DeviceDeduplicator.ps1'
    'lib\PackageDeduplicator.ps1'
    'lib\DeviceDisplayFormatter.ps1'
    'lib\ScenarioFilter.ps1'
    'lib\RecommendTier.ps1'
    'lib\GuiDriverRow.ps1'
    'lib\DeviceNameResolver.ps1'
    'lib\RepairSummary.ps1'
    'lib\DriverRepoHealth.ps1'
    'lib\ManifestV3.ps1'
    '使用说明.txt'
)
foreach ($rel in $files) {
    $f = Join-Path $root $rel
    if (Test-Path $f) {
        $c = [System.IO.File]::ReadAllText($f)
        [System.IO.File]::WriteAllText($f, $c, $enc)
        Write-Host "BOM: $rel"
    }
}
