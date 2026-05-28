#requires -Version 5.1
# Frozen scoring weights (docs/ARCHITECTURE.md)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

Write-Host '=== test_scorer_frozen ==='

if ($script:ScoreWeightHwidExact -ne 50) { throw 'HWID weight must be 50' }
if ($script:ScoreWeightDeviceClass -ne 20) { throw 'DeviceClass weight must be 20' }
if ($script:ScoreWeightOsCompat -ne 10) { throw 'OS weight must be 10' }
if ($script:ScoreWeightWhql -ne 5) { throw 'WHQL weight must be 5' }
if ($script:ScoreWeightMachineVerify -ne 10) { throw 'MachineVerify weight must be 10' }
if ($script:ScoreWeightInstallRate -ne 5) { throw 'InstallRate weight must be 5' }
if ($script:ScoreMaxTotal -ne 100) { throw 'Max total must be 100' }

$device = [PSCustomObject]@{
    FriendlyName  = 'Test WiFi'
    InstanceId    = 'PCI\VEN_8086&DEV_2723'
    HardwareIds   = @('PCI\VEN_8086&DEV_2723')
    DriverVersion = ''
    Status        = 'Error'
    IsProblem     = $true
    Class         = 'NET'
}

$candidate = ConvertTo-PackageCandidate -PackageKey 'test_wifi' -PackageRaw @{
    id = 'test_wifi'; title = 'Test WiFi'; category = 'wifi'; vendor = 'intel'
    whql = $true; signed = $true; os = @('win10','win11'); win10_preferred = $true
    device_class = 'network_wifi'
} -Device $device
$candidate | Add-Member -NotePropertyName _MatchHwids -NotePropertyValue @('PCI\VEN_8086&DEV_2723') -Force
$candidate.DeviceClass = 'network_wifi'

$scored = Score-DriverCandidate -Candidate $candidate -Device $device
if ($scored.Disqualified) { throw 'Should not disqualify compatible candidate' }
if ($scored.Score -lt 80) {
    throw ("Expected high score for exact match, got $($scored.Score)")
}
if ($scored.ConfidencePercent -lt 80) {
    throw ("Expected confidence >= 80, got $($scored.ConfidencePercent)")
}

Write-Host ("PASS score={0} pct={1} tier={2}" -f $scored.Score, $scored.ConfidencePercent, $tier)
exit 0
