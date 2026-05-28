#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

Write-Host '=== test_os ==='
$os = Get-SystemOsProfile
Write-Host ("  OS={0} build={1} family={2}" -f $os.Label, $os.Build, $os.Family)
if (-not $os.IsSupported) { throw 'OS not supported' }

$manifest = Get-EngineManifest
$packages = Get-ManifestPackages -Manifest $manifest
if (-not $manifest.target_os) { Write-Host 'WARN manifest missing target_os' }
if (-not $manifest.primary_os) { Write-Host 'WARN manifest missing primary_os' }

$pkg = $packages['Seed_Intel_Chipset_INF']
$c = ConvertTo-PackageCandidate -PackageKey 'Seed_Intel_Chipset_INF' -PackageRaw $pkg -Device $null
if (-not (Test-PackageOsCompatible -Package $c)) { throw 'Chipset should be OS compatible' }

$blocked = ConvertTo-PackageCandidate -PackageKey 'Test' -PackageRaw ([PSCustomObject]@{
  id = 'test'; os = @('win11'); title = 'Win11 only'
}) -Device $null
if ($os.IsWin10 -and (Test-PackageOsCompatible -Package $blocked)) {
  throw 'Win11-only package should be blocked on Win10'
}

Write-Host 'PASS os profile and compatibility'
exit 0
