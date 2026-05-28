#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

$fail = 0
$item = [PSCustomObject]@{
    Device = [PSCustomObject]@{
        FriendlyName = 'Intel WiFi'
        DriverVersion = '18.0.0.1'
        InstanceId = 'PCI\VEN_8086'
        DeviceClass = 'network_wifi'
        IsProblem = $false
        Status = 'OK'
        DriverProvider = 'Intel'
    }
    Package = [PSCustomObject]@{
        Id = 'intel_wifi'
        Title = 'Intel WiFi'
        Version = '18.33.17.1'
        Whql = $true
        Vendor = 'Intel'
        Url = 'https://github.com/test/intel_wifi.zip'
        LocalPath = $null
    }
    Action = 'DownloadThenInstall'
    TargetVersion = '18.33.17.1'
    ConfidencePercent = 90
    ExactHwidMatch = $true
    IsOutdated = $true
}

$d = Get-DriverFixItemDetails -Item $item
if ($d.TrustBadge -match 'WHQL' -and $d.DetailText -match 'Current') { Write-Host 'OK: details' }
else { Write-Host 'FAIL: details'; $fail++ }

$r = Get-FixPlanRiskAssessment -FixPlan @($item)
if ($r.LowRisk -ge 1) { Write-Host 'OK: risk low' } else { Write-Host 'FAIL: risk'; $fail++ }

$vs = Get-DriverVersionStatusSummary -FixPlan @($item)
if ($vs.Outdated -ge 1) { Write-Host 'OK: version summary' } else { Write-Host 'FAIL: version'; $fail++ }

if ($fail -gt 0) { exit 1 }
Write-Host 'test_driver_details.ps1 OK'
exit 0
