# Driver Engine bootstrap - load all modules once

param(
    [string]$AppRoot = $null
)

if ($AppRoot) {
    $script:AppRoot = $AppRoot
    $global:DriverBoosterAppRoot = $AppRoot
} elseif ($PSScriptRoot) {
    $script:AppRoot = Split-Path $PSScriptRoot -Parent
    $global:DriverBoosterAppRoot = $script:AppRoot
}

$lib = Join-Path $script:AppRoot 'lib'

. (Join-Path $lib 'Utils.ps1')
. (Join-Path $lib 'Types.ps1')
. (Join-Path $lib 'OsProfile.ps1')
. (Join-Path $lib 'DriverVersionAnalyzer.ps1')
. (Join-Path $lib 'DriverTrust.ps1')
. (Join-Path $lib 'DriverDetails.ps1')
. (Join-Path $lib 'FixRiskCheck.ps1')
. (Join-Path $lib 'CompatibilityDb.ps1')
. (Join-Path $lib 'ManifestChannel.ps1')
. (Join-Path $lib 'OfflineWorkflow.ps1')
. (Join-Path $lib 'HardwareProfile.ps1')
. (Join-Path $lib 'DeviceClassGuard.ps1')
. (Join-Path $lib 'DeviceDeduplicator.ps1')
. (Join-Path $lib 'PackageDeduplicator.ps1')
. (Join-Path $lib 'UserFriendlyText.ps1')
. (Join-Path $lib 'DeviceDisplayFormatter.ps1')
. (Join-Path $lib 'DeviceNameResolver.ps1')
. (Join-Path $lib 'RecommendTier.ps1')
. (Join-Path $lib 'RepairSummary.ps1')
. (Join-Path $lib 'DriverRepoHealth.ps1')
. (Join-Path $lib 'DriverScanner.ps1')
. (Join-Path $lib 'DriverScorer.ps1')
. (Join-Path $lib 'ManifestV3.ps1')
. (Join-Path $lib 'DriverMatcher.ps1')
. (Join-Path $lib 'DriverInfIndex.ps1')
. (Join-Path $lib 'ScenarioFilter.ps1')
. (Join-Path $lib 'AppBootstrap.ps1')
. (Join-Path $lib 'DriverMirror.ps1')
. (Join-Path $lib 'CatalogDownloader.ps1')
. (Join-Path $lib 'DriverDownloader.ps1')
. (Join-Path $lib 'DriverBackup.ps1')
. (Join-Path $lib 'InstallStats.ps1')
. (Join-Path $lib 'DriverVerifier.ps1')
. (Join-Path $lib 'DriverTransaction.ps1')
. (Join-Path $lib 'DriverInstaller.ps1')
. (Join-Path $lib 'DriverSourceStatus.ps1')
. (Join-Path $lib 'DriverHealth.ps1')
. (Join-Path $lib 'DriverRepoBuilder.ps1')
. (Join-Path $lib 'DeployReport.ps1')
. (Join-Path $lib 'DeployMode.ps1')

Initialize-AppFolders
