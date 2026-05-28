# CIODIY canonical object shapes (v1.7.0)

function New-CIODIYOperationResult {
    param(
        [bool]$Success = $true,
        [string]$Code = 'OK',
        [string]$Message = '',
        [string]$Detail = '',
        $Data = $null
    )
    return [PSCustomObject]@{
        Success = $Success
        Code    = $Code
        Message = $Message
        Detail  = $Detail
        Data    = $Data
    }
}

function New-CIODIYFixPlanItem {
    param(
        [string]$DeviceId = '',
        [string]$DeviceKey = '',
        [string]$DisplayName = '',
        [string]$DeviceClass = '',
        [string]$PackageId = '',
        [string]$PackageName = '',
        [string]$RecommendTier = '',
        [int]$Confidence = 0,
        [bool]$DefaultSelected = $false,
        [bool]$IsDependency = $false,
        [string]$ParentPackageId = '',
        [string]$Source = '',
        [string]$StatusText = '',
        [array]$Children = @(),
        $Raw = $null
    )
    return [PSCustomObject]@{
        DeviceId        = $DeviceId
        DeviceKey       = $DeviceKey
        DisplayName     = $DisplayName
        DeviceClass     = $DeviceClass
        PackageId       = $PackageId
        PackageName     = $PackageName
        RecommendTier   = $RecommendTier
        Confidence      = $Confidence
        DefaultSelected = $DefaultSelected
        IsDependency    = $IsDependency
        ParentPackageId = $ParentPackageId
        Source          = $Source
        StatusText      = $StatusText
        Children        = @($Children)
        Raw             = $Raw
    }
}

function New-CIODIYRepairSummary {
    param(
        [string]$TotalDetected = '0',
        [string]$Recommended = '0',
        [string]$Optional = '0',
        [string]$Unsafe = '0',
        [string]$StatusLine = '',
        [string]$ScanCompleteLine = ''
    )
    return [PSCustomObject]@{
        TotalDetected    = $TotalDetected
        Recommended      = $Recommended
        Optional         = $Optional
        Unsafe           = $Unsafe
        StatusLine       = $StatusLine
        ScanCompleteLine = $ScanCompleteLine
    }
}

function New-CIODIYRepoHealth {
    param(
        [int]$HealthPercent = 0,
        [string]$ShortLine = '',
        [string]$SummaryLine = ''
    )
    return [PSCustomObject]@{
        HealthPercent = $HealthPercent
        ShortLine     = $ShortLine
        SummaryLine   = $SummaryLine
    }
}

function ConvertTo-CIODIYFixPlanItem {
    param(
        [Parameter(Mandatory)]$InternalItem
    )

    if ($InternalItem -is [hashtable] -and $InternalItem.ContainsKey('DeviceId')) {
        return [PSCustomObject]$InternalItem
    }

    $dev = $InternalItem.Device
    $pkg = $InternalItem.Package
    $tier = if (Get-Command Get-RecommendTier -ErrorAction SilentlyContinue) {
        Get-RecommendTier -Item $InternalItem
    } else { '' }

    $deviceKey = if ($InternalItem.MergeKey) { [string]$InternalItem.MergeKey }
        elseif ($dev -and $dev.MergeKey) { [string]$dev.MergeKey }
        elseif ($dev -and (Get-Command Get-CIODIYDeviceKey -ErrorAction SilentlyContinue)) { Get-CIODIYDeviceKey -Device $dev }
        else { '' }

    $displayName = if ($dev -and (Get-Command Get-DeviceDisplayName -ErrorAction SilentlyContinue)) {
        Get-DeviceDisplayName -Device $dev -Package $pkg
    } elseif ($dev) { [string]$dev.FriendlyName } else { '' }

    $pkgName = if ($pkg -and (Get-Command Get-PackageDisplayTitle -ErrorAction SilentlyContinue)) {
        Get-PackageDisplayTitle -Package $pkg
    } elseif ($pkg) { [string]$pkg.Title } else { '' }

    $confidence = 0
    if ($InternalItem.ConfidencePercent) { $confidence = [int]$InternalItem.ConfidencePercent }
    elseif ($InternalItem.Confidence) { $confidence = [int]$InternalItem.Confidence }

    $source = switch ([string]$InternalItem.Action) {
        'InstallLocal'        { 'local' }
        'DownloadThenInstall' { 'remote' }
        'CatalogSearch'       { 'catalog' }
        default               { [string]$InternalItem.Action }
    }

    $statusText = if ($InternalItem.IsOutdated) { 'outdated' }
        elseif ($dev -and $dev.IsProblem) { 'problem' }
        else { 'pending' }

    return New-CIODIYFixPlanItem `
        -DeviceId $(if ($dev) { [string]$dev.InstanceId } else { '' }) `
        -DeviceKey $deviceKey `
        -DisplayName $displayName `
        -DeviceClass $(if ($dev) { [string]$dev.DeviceClass } else { '' }) `
        -PackageId $(if ($pkg) { [string]$pkg.Id } else { '' }) `
        -PackageName $pkgName `
        -RecommendTier $tier `
        -Confidence $confidence `
        -DefaultSelected (Test-RecommendTierAutoSelect -Tier $tier) `
        -IsDependency ([bool]$InternalItem.HideFromList) `
        -ParentPackageId $(if ($InternalItem.ParentPackageId) { [string]$InternalItem.ParentPackageId } else { '' }) `
        -Source $source `
        -StatusText $statusText `
        -Children @($InternalItem.Dependencies) `
        -Raw $InternalItem
}

function ConvertTo-CIODIYFixPlanView {
    param([Parameter(Mandatory)][array]$FixPlan)
    return @($FixPlan | ForEach-Object { ConvertTo-CIODIYFixPlanItem -InternalItem $_ })
}
