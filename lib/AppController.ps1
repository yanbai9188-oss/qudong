# Application session state (CLI + GUI share the same scan/fix state)

function New-AppSessionState {
    return @{
        Manifest      = $null
        ScanResults   = @()
        FixPlan       = @()
        FullFixPlan   = @()
        Scenario      = 'all'
        IsBusy        = $false
        GridRows      = @()
        RepairSummary = $null
        RepoHealth    = $null
        FixPlanByKey  = @{}
        Health        = $null
    }
}

function Get-AppSessionState {
    if (-not $script:AppSessionState) {
        $script:AppSessionState = New-AppSessionState
    }
    return $script:AppSessionState
}

function Import-AppManifest {
    $state = Get-AppSessionState
    try {
        $state.Manifest = Get-EngineManifest
    } catch {
        Write-CIODIYStartupLog -Message ("Manifest load failed: $($_.Exception.Message)") -AppRoot $script:AppRoot
        $state.Manifest = $null
    }
}

function Invoke-AppScan {
    param(
        [scriptblock]$OnLog,
        [scriptblock]$OnDone,
        [scriptblock]$OnProgress,  # { param($pct,$msg) }  forwarded to UI progress bar
        [switch]$IncludeOutdated,
        [string]$Scenario = 'all',
        [switch]$PassThru,
        [switch]$FastMatch
    )

    $state = Get-AppSessionState
    $state.Scenario = if ($Scenario) { $Scenario } else { 'all' }

    $result = Invoke-DriverAppScanEngine -Scenario $state.Scenario `
        -IncludeOutdated:$IncludeOutdated -FastMatch:$FastMatch -OnLog $OnLog -OnProgress $OnProgress -Manifest $state.Manifest

    if (-not $result.Success) {
        throw $result.Message
    }

    $state.ScanResults = @($result.Data.ScanResults)
    $state.FullFixPlan = @($result.Data.FullFixPlan)
    $state.FixPlan = @($result.Data.FixPlan)
    if ($result.Data.Manifest) { $state.Manifest = $result.Data.Manifest }
    if ($result.Data.RepairSummary) { $state.RepairSummary = $result.Data.RepairSummary }

    if ($PassThru) {
        return @{
            ScanResults = @($state.ScanResults)
            FixPlan     = @($state.FixPlan)
        }
    }
    if ($OnDone) { & $OnDone $state.ScanResults $state.FixPlan }
}

function Format-ConfidenceLabel {
    param($Item)
    if (-not $Item) { return '-' }
    $raw = if ($Item.Raw) { $Item.Raw } else { $Item }
    if (-not $raw.Package) { return '-' }
    $pct = if ($raw.ConfidencePercent) { $raw.ConfidencePercent } else { 0 }
    if ($pct -le 0) { return '-' }
    return ('{0}%' -f $pct)
}

function Get-ActionLabel {
    param([string]$Action)
    return Get-ActionUserLabel -Action $Action
}

function Get-StatusLabel {
    param($Device, [bool]$IsOutdated)
    if ($IsOutdated) { return '过时' }
    switch ([string]$Device.Status) {
        'OK'       { return '正常' }
        'Error'    { return '错误' }
        'Unknown'  { return '未知' }
        'Degraded' { return '降级' }
        'Problem'  { return '异常' }
        'Warning'  { return '警告' }
        default    {
            $s = [string]$Device.Status
            if ($s -match 'error|fail|problem|degrad' -or $Device.IsProblem) { return '错误' }
            if ($s) { return $s }
            return '未知'
        }
    }
}
