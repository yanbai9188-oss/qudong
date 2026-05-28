# Install outcome statistics (local feedback for scoring)

function Get-InstallStatsPath {
    return Join-Path (Join-Path (Get-AppDataRoot) 'Cache') 'install_stats.jsonl'
}

function Write-InstallStat {
    param(
        [Parameter(Mandatory)]$Result,
        [string]$TransactionId = '',
        [string]$FinalStatus = ''
    )

    try {
        $os = Get-SystemOsProfile
        $entry = [PSCustomObject]@{
            ts      = (Get-Date -Format 'o')
            os      = $os.Family
            build   = $os.Build
            device  = $Result.Device
            success = [bool]$Result.Success
            action  = $Result.Action
            pkg     = if ($Result.PackageId) { $Result.PackageId } else { '' }
            verified = if ($null -ne $Result.Verified) { [bool]$Result.Verified } else { $false }
            error   = if ($Result.Error) { [string]$Result.Error } else { '' }
            tx      = $TransactionId
            status  = $FinalStatus
        }
        $line = ($entry | ConvertTo-Json -Compress)
        Add-Content -Path (Get-InstallStatsPath) -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        Write-CompatibilityRecord -Result $Result -TransactionId $TransactionId
    } catch { }
}

function Write-InstallStatBatch {
    param(
        [Parameter(Mandatory)][array]$Results,
        [string]$TransactionId = '',
        [string]$FinalStatus = ''
    )
    foreach ($r in $Results) {
        Write-InstallStat -Result $r -TransactionId $TransactionId -FinalStatus $FinalStatus
    }
}

function Get-PackageSuccessRateHint {
    param([string]$PackageId)

    $path = Get-InstallStatsPath
    if (-not $PackageId -or -not (Test-Path $path)) { return $null }

    $total = 0
    $ok = 0
    foreach ($line in (Get-Content -Path $path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $row = $line | ConvertFrom-Json
            if ($row.pkg -ne $PackageId) { continue }
            $total++
            if ($row.success) { $ok++ }
        } catch { }
    }
    if ($total -lt 3) { return $null }
    return [Math]::Round($ok / $total, 3)
}
