# Install transaction: begin -> backup -> install -> verify -> commit / rollback

function Get-TransactionsRoot {
    return Join-Path (Get-AppDataRoot) 'Transactions'
}

function New-TransactionId {
    return 'tx_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
}

function Start-DriverTransaction {
    param(
        [array]$FixPlan,
        [switch]$RollbackOnError,
        [scriptblock]$OnLog
    )

    $txId = New-TransactionId
    $root = Get-TransactionsRoot
    $txDir = Join-Path $root $txId
    New-Item -ItemType Directory -Force -Path $txDir | Out-Null

    $tx = [PSCustomObject]@{
        id               = $txId
        status           = 'active'
        rollbackOnError  = [bool]$RollbackOnError
        started          = (Get-Date -Format 'o')
        finished         = $null
        steps            = @()
        planCount        = $FixPlan.Count
    }

    $txPath = Join-Path $txDir 'tx.json'
    $installedPath = Join-Path $txDir 'installed.json'
    Save-JsonFile -Path $txPath -Object $tx
    Save-JsonFile -Path $installedPath -Object @()

    Write-AppLog "Transaction begin: $txId" -OnLog $OnLog
    return [PSCustomObject]@{
        Id            = $txId
        Directory     = $txDir
        TxPath        = $txPath
        InstalledPath = $installedPath
        RollbackOnError = [bool]$RollbackOnError
    }
}

function Save-JsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        $Object
    )
    $json = $Object | ConvertTo-Json -Depth 12
    Set-Content -Path $Path -Value $json -Encoding UTF8
}

function Get-DeviceSnapshot {
    param([Parameter(Mandatory)]$Device)
    return [PSCustomObject]@{
        device     = if ($Device.HardwareIds -and $Device.HardwareIds.Count -gt 0) { $Device.HardwareIds[0] } else { $Device.InstanceId }
        instanceId = $Device.InstanceId
        friendly   = $Device.FriendlyName
        before     = $Device.DriverVersion
        status     = $Device.Status
    }
}

function Add-TransactionRecord {
    param(
        [Parameter(Mandatory)]$Transaction,
        [Parameter(Mandatory)]$Record
    )

    $records = @()
    if (Test-Path $Transaction.InstalledPath) {
        $records = @(Get-Content $Transaction.InstalledPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    $records += $Record
    Save-JsonFile -Path $Transaction.InstalledPath -Object $records
    return $Record
}

function Update-TransactionStatus {
    param(
        [Parameter(Mandatory)]$Transaction,
        [Parameter(Mandatory)][string]$Status,
        [string]$StepNote = ''
    )

    $tx = Get-Content $Transaction.TxPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $tx.status = $Status
    if ($Status -in @('committed', 'rolled_back', 'failed')) {
        $tx.finished = (Get-Date -Format 'o')
    }
    if ($StepNote) {
        $steps = @($tx.steps) + @($StepNote)
        $tx | Add-Member -NotePropertyName steps -NotePropertyValue $steps -Force
    }
    Save-JsonFile -Path $Transaction.TxPath -Object $tx
}

function Invoke-SingleStepRollback {
    param(
        [Parameter(Mandatory)]$Record,
        [scriptblock]$OnLog
    )

    Write-AppLog ("Rollback: {0}" -f $Record.friendly) -OnLog $OnLog

    if ($Record.backupPath -and (Test-Path $Record.backupPath)) {
        $exportDir = Join-Path $Record.backupPath 'export'
        if (Test-Path $exportDir) {
            $infs = Get-ChildItem -Path $exportDir -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue
            foreach ($inf in $infs) {
                $out = & pnputil.exe /add-driver $inf.FullName /install 2>&1
                foreach ($line in $out) { Write-AppLog "rollback pnputil: $line" -OnLog $OnLog }
            }
        }
    }

    if ($Record.instanceId) {
        try {
            & pnputil.exe /scan-devices 2>&1 | Out-Null
        } catch { }
    }

    $Record.status = 'rollback'
    return $Record
}

function Write-TransactionRollbackScript {
    param(
        [Parameter(Mandatory)]$Transaction
    )

    $rollbackPath = Join-Path $Transaction.Directory 'rollback.ps1'
    $appRoot = Get-AppRoot
    $content = @"
# Auto-generated rollback script for $($Transaction.Id)
`$ErrorActionPreference = 'Stop'
`$AppRoot = '$appRoot'
. (Join-Path `$AppRoot 'engine\Initialize-Engine.ps1')
Invoke-DriverRollback -TxId '$($Transaction.Id)'
"@
    Set-Content -Path $rollbackPath -Value $content -Encoding UTF8
    return $rollbackPath
}

function Invoke-DriverTransactionRollback {
    param(
        [Parameter(Mandatory)]$Transaction,
        [scriptblock]$OnLog,
        [switch]$CommittedOnly
    )

    if (-not (Test-Path $Transaction.InstalledPath)) {
        Write-AppLog 'No installed.json for rollback' -OnLog $OnLog
        return @()
    }

    $records = @(Get-Content $Transaction.InstalledPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    $toRollback = @($records | Where-Object { $_.status -in @('committed', 'verified') } | Sort-Object -Property stepIndex -Descending)

    if ($CommittedOnly) {
        $toRollback = @($toRollback | Select-Object -First 1)
    }

    $results = New-Object System.Collections.ArrayList
    foreach ($rec in $toRollback) {
        $rolled = Invoke-SingleStepRollback -Record $rec -OnLog $OnLog
        [void]$results.Add($rolled)
    }

    Save-JsonFile -Path $Transaction.InstalledPath -Object $records
    Update-TransactionStatus -Transaction $Transaction -Status 'rolled_back' -StepNote 'rollback executed'
    Write-AppLog ("Rollback complete: {0} step(s)" -f $results.Count) -OnLog $OnLog
    return @($results)
}

function Get-DriverTransaction {
    param([Parameter(Mandatory)][string]$TxId)

    $txDir = Join-Path (Get-TransactionsRoot) $TxId
    if (-not (Test-Path $txDir)) { throw "Transaction not found: $TxId" }

    return [PSCustomObject]@{
        Id            = $TxId
        Directory     = $txDir
        TxPath        = Join-Path $txDir 'tx.json'
        InstalledPath = Join-Path $txDir 'installed.json'
    }
}

function Get-LatestTransaction {
    $all = @(Get-AllTransactions)
    if ($all.Count -eq 0) { return $null }
    return $all[0]
}

function Get-AllTransactions {
    param([int]$Limit = 0)

    $root = Get-TransactionsRoot
    if (-not (Test-Path $root)) { return @() }

    $dirs = @(Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending)
    if ($Limit -gt 0) { $dirs = @($dirs | Select-Object -First $Limit) }

    $list = New-Object System.Collections.ArrayList
    foreach ($d in $dirs) {
        try {
            [void]$list.Add((Get-DriverTransaction -TxId $d.Name))
        } catch { }
    }
    return @($list)
}

function Get-TransactionSummaryForGui {
    param([Parameter(Mandatory)]$Transaction)

    $result = [PSCustomObject]@{
        TxId          = $Transaction.Id
        TimeLabel     = '-'
        DriverNames   = '-'
        SuccessCount  = 0
        FailCount     = 0
        FinalStatus   = 'unknown'
        CanRollback   = $false
    }

    if (-not (Test-Path $Transaction.TxPath)) { return $result }

    $tx = Get-Content $Transaction.TxPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($tx.started) {
        try {
            $dt = [DateTime]::Parse($tx.started)
            $result.TimeLabel = $dt.ToString('yyyy-MM-dd HH:mm')
        } catch {
            $result.TimeLabel = [string]$tx.started
        }
    }
    $result.FinalStatus = [string]$tx.status

    $records = @()
    if (Test-Path $Transaction.InstalledPath) {
        try {
            $records = @(Get-Content $Transaction.InstalledPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch { }
    }

    $committed = @($records | Where-Object { $_.status -in @('committed', 'verified', 'installed') })
    $failed = @($records | Where-Object { $_.status -in @('verify_failed', 'rollback') -or $_.error })
    $result.SuccessCount = $committed.Count
    $result.FailCount = $failed.Count

    $names = @($committed | ForEach-Object { [string]$_.friendly } | Where-Object { $_ })
    if ($names.Count -eq 0) {
        $names = @($records | ForEach-Object { [string]$_.friendly } | Where-Object { $_ })
    }
    if ($names.Count -gt 0) {
        $result.DriverNames = ($names -join '、')
    }

    $result.CanRollback = ($records.Count -gt 0) -and ($tx.status -in @('committed', 'failed', 'rolled_back'))
    return $result
}

function Complete-TransactionStep {
    param(
        [Parameter(Mandatory)]$Transaction,
        [Parameter(Mandatory)]$Device,
        $Package,
        [Parameter(Mandatory)][string]$Phase,
        [string]$BackupPath = $null,
        [string]$AfterVersion = '',
        [bool]$Verified = $false,
        [int]$StepIndex = 0,
        [string]$PackageId = '',
        [string]$ErrorMessage = ''
    )

    $snap = Get-DeviceSnapshot -Device $Device
    $status = switch ($Phase) {
        'backup'   { 'backed_up' }
        'install'  { 'installed' }
        'verify'   { if ($Verified) { 'verified' } else { 'verify_failed' } }
        'commit'   { 'committed' }
        'rollback' { 'rollback' }
        default    { $Phase }
    }

    $record = [PSCustomObject]@{
        device      = $snap.device
        instanceId  = $snap.instanceId
        friendly    = $snap.friendly
        before      = $snap.before
        after       = $AfterVersion
        packageId   = $PackageId
        backupPath  = $BackupPath
        verified    = $Verified
        status      = $status
        stepIndex   = $StepIndex
        error       = $ErrorMessage
        timestamp   = (Get-Date -Format 'o')
    }

    Add-TransactionRecord -Transaction $Transaction -Record $record | Out-Null
    Update-TransactionStatus -Transaction $Transaction -Status 'active' -StepNote ("step $StepIndex : $status : $($snap.friendly)")
    return $record
}

function Close-DriverTransaction {
    param(
        [Parameter(Mandatory)]$Transaction,
        [Parameter(Mandatory)][string]$FinalStatus,
        [scriptblock]$OnLog
    )

    Update-TransactionStatus -Transaction $Transaction -Status $FinalStatus
    Write-TransactionRollbackScript -Transaction $Transaction | Out-Null
    Write-AppLog ("Transaction $FinalStatus : $($Transaction.Id)") -OnLog $OnLog
}
