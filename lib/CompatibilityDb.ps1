# Machine compatibility database (v1.8) — extends InstallStats

function Get-CompatibilityDbPath {
    return Join-Path (Join-Path (Get-AppDataRoot) 'Cache') 'compatibility_db.jsonl'
}

function Write-CompatibilityRecord {
    param(
        [Parameter(Mandatory)]$Result,
        [string]$TransactionId = '',
        [bool]$RebootRequired = $false
    )

    try {
        $hw = Get-HardwareProfile
        $os = Get-SystemOsProfile
        $devClass = if ($Result.DeviceClass) { $Result.DeviceClass } else { '' }

        $entry = [PSCustomObject]@{
            ts             = (Get-Date -Format 'o')
            machine        = $hw.MachineTitle
            platform       = $hw.PlatformLine
            os             = $os.Label
            build          = $os.Build
            deviceClass    = $devClass
            packageId      = if ($Result.PackageId) { [string]$Result.PackageId } else { '' }
            device         = if ($Result.Device) { [string]$Result.Device } else { '' }
            success        = [bool]$Result.Success
            rebootRequired = $RebootRequired
            tx             = $TransactionId
        }
        $path = Get-CompatibilityDbPath
        $dir = Split-Path $path -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Add-Content -Path $path -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

function Get-PackageCompatibilityHint {
    param(
        [string]$PackageId,
        [string]$DeviceClass = ''
    )

    $path = Get-CompatibilityDbPath
    if (-not $PackageId -or -not (Test-Path $path)) { return $null }

    $ok = 0
    $fail = 0
    $machines = @{}

    foreach ($line in (Get-Content $path -Encoding UTF8 -EA SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $e = $line | ConvertFrom-Json
        } catch { continue }
        if ($e.packageId -ne $PackageId) { continue }
        if ($DeviceClass -and $e.deviceClass -and $e.deviceClass -ne $DeviceClass) { continue }
        if ($e.success) { $ok++ } else { $fail++ }
        if ($e.machine) { $machines[[string]$e.machine] = $true }
    }

    $total = $ok + $fail
    if ($total -eq 0) { return $null }

    return [PSCustomObject]@{
        SuccessCount   = $ok
        FailCount      = $fail
        SuccessRate    = [math]::Round($ok / $total, 2)
        VerifiedMachines = $machines.Count
    }
}
