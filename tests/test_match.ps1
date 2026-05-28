#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

Write-Host '=== test_match ==='
$manifest = Get-EngineManifest
if (-not $manifest) { throw 'Manifest not loaded' }
if ($manifest.schema_version -lt 3) { Write-Host 'WARN manifest schema < 3' }

$packages = Get-ManifestPackages -Manifest $manifest

$sampleDevice = [PSCustomObject]@{
    FriendlyName   = 'Realtek Test'
    InstanceId     = 'HDAUDIO\FUNC_01&VEN_10EC&DEV_0897'
    HardwareIds    = @('HDAUDIO\FUNC_01&VEN_10EC&DEV_0897')
    DriverVersion  = '6.0.9000.0'
    Status         = 'Error'
    IsProblem      = $true
    Class          = 'MEDIA'
    CategoryLabel  = 'Audio'
}

$candidates = Get-CandidatePackages -Device $sampleDevice -Packages $packages
if ($candidates.Count -eq 0) { throw 'No candidates for sample device' }

$best = Select-BestScoredCandidate -Candidates $candidates -Device $sampleDevice
if (-not $best) { throw 'Scoring returned null' }
if ($best.ConfidencePercent -le 0) { throw 'Confidence should be > 0' }

Write-Host ("  best={0} v={1} score={2} conf={3}%" -f $best.Title, $best.Version, $best.Score, $best.ConfidencePercent)

$plan = @(Build-DriverFixPlan -ScanResults @($sampleDevice) -Manifest $manifest)
if ($plan.Count -eq 0) { throw 'FixPlan empty for sample device' }

Write-Host ("PASS match candidates={0} plan={1}" -f $candidates.Count, $plan.Count)
exit 0
