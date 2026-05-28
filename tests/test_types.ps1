#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

$fail = 0

function Assert($name, [scriptblock]$Test) {
    try {
        if (-not (& $Test)) { Write-Host "FAIL: $name"; $script:fail++ }
        else { Write-Host "OK: $name" }
    } catch {
        Write-Host "FAIL: $name - $($_.Exception.Message)"
        $script:fail++
    }
}

Assert 'OperationResult success' {
    $r = New-CIODIYOperationResult -Success $true -Message 'ok'
    $r.Success -and $r.Code -eq 'OK'
}

Assert 'OperationResult failure' {
    $r = New-CIODIYOperationResult -Success $false -Code 'ERR' -Message 'no'
    (-not $r.Success) -and $r.Code -eq 'ERR'
}

Assert 'FixPlanItem fields' {
    $item = New-CIODIYFixPlanItem -DeviceKey 'k1' -DisplayName 'WiFi' -RecommendTier 'recommended'
    $item.DeviceKey -eq 'k1' -and $item.RecommendTier -eq 'recommended'
}

Assert 'ConvertTo-CIODIYFixPlanItem' {
    $internal = [PSCustomObject]@{
        Device = [PSCustomObject]@{
            InstanceId = 'PCI\VEN_8086'
            FriendlyName = 'Intel WiFi'
            DeviceClass = 'network_wifi'
            MergeKey = 'wifi1'
            IsProblem = $true
            Status = 'Error'
        }
        Package = [PSCustomObject]@{ Id = 'intel_wifi'; Title = 'Intel WiFi Driver'; Version = '1.0' }
        Action = 'InstallLocal'
        ConfidencePercent = 85
        MergeKey = 'wifi1'
    }
    $view = ConvertTo-CIODIYFixPlanItem -InternalItem $internal
    $view.DeviceKey -eq 'wifi1' -and $view.Confidence -eq 85 -and $view.Raw -eq $internal
}

Assert 'Invoke-DriverAppScanEngine returns OperationResult' {
    $r = Invoke-DriverAppScanEngine -Scenario 'all' -FastMatch
    $r.Success -and $r.Data.ScanResults -ne $null
}

if ($fail -gt 0) { exit 1 }
Write-Host 'test_types.ps1 OK'
exit 0
