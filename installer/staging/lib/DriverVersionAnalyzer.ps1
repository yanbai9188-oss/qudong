# Device driver version / status analysis (v1.8)

function Test-GenericMicrosoftDriver {
    param($Device)
    $provider = [string]$Device.DriverProvider
    $name = [string]$Device.FriendlyName
    if ($provider -match 'Microsoft|Windows') { return $true }
    if ($name -match 'Microsoft|基本|Generic|标准') { return $true }
    return $false
}

function Get-DriverVersionStatus {
    param(
        [Parameter(Mandatory)]$Device,
        $Package = $null,
        [bool]$IsOutdated = $false,
        [string]$Action = ''
    )

    if ($Device.IsProblem -or [string]$Device.Status -match 'Error|Problem|Degraded') {
        if ([string]::IsNullOrWhiteSpace($Device.DriverVersion)) {
            return 'Missing'
        }
        return 'DeviceError'
    }

    if ($Action -in @('NoSource', 'CatalogSearch', 'NoPackage')) {
        if ([string]::IsNullOrWhiteSpace($Device.DriverVersion)) { return 'Missing' }
        if (Test-GenericMicrosoftDriver -Device $Device) { return 'GenericMicrosoft' }
        return 'DeviceError'
    }

    if ($IsOutdated) { return 'Outdated' }

    if ([string]::IsNullOrWhiteSpace($Device.DriverVersion)) {
        return 'Missing'
    }

    if (Test-GenericMicrosoftDriver -Device $Device) {
        return 'GenericMicrosoft'
    }

    if ($Package -and $Device.DriverVersion -and $Package.Version) {
        $cmp = Compare-DriverVersion -Installed $Device.DriverVersion -Available $Package.Version
        if ($cmp -lt 0) { return 'Outdated' }
        if ($cmp -ge 0) { return 'UpToDate' }
    }

    if (-not $Device.IsProblem) { return 'UpToDate' }
    return 'DeviceError'
}

function Get-DriverVersionStatusLabel {
    param([string]$Status)
    switch ($Status) {
        'Missing'          { return 'missing' }
        'Outdated'         { return 'outdated' }
        'GenericMicrosoft' { return 'generic' }
        'DeviceError'      { return 'error' }
        'UpToDate'         { return 'uptodate' }
        default            { return $Status }
    }
}

function Get-DriverVersionStatusLabelUi {
    param([string]$Status)
    switch ($Status) {
        'Missing'          { return ([string][char]0x7F3A) + ([string][char]0x5931) + ([string][char]0x9A71) + ([string][char]0x9A71) }
        'Outdated'         { return ([string][char]0x53EF) + ([string][char]0x66F4) + ([string][char]0x65B0) }
        'GenericMicrosoft' { return ([string][char]0x901A) + ([string][char]0x7528) + ([string][char]0x9A71) + ([string][char]0x52A8) }
        'DeviceError'      { return ([string][char]0x5F02) + ([string][char]0x5E38) + ([string][char]0x9A71) + ([string][char]0x52A8) }
        'UpToDate'         { return ([string][char]0x5DF2) + ([string][char]0x662F) + ([string][char]0x6700) + ([string][char]0x65B0) }
        default            { return Get-DriverVersionStatusLabel -Status $Status }
    }
}

function Get-DriverVersionStatusSummary {
    param([Parameter(Mandatory)][array]$FixPlan)

    $counts = @{
        Missing          = 0
        Outdated         = 0
        GenericMicrosoft = 0
        DeviceError      = 0
        UpToDate         = 0
    }

    foreach ($item in $FixPlan) {
        $st = Get-DriverVersionStatus -Device $item.Device -Package $item.Package `
            -IsOutdated $item.IsOutdated -Action $item.Action
        if ($counts.ContainsKey($st)) { $counts[$st]++ }
    }

    return [PSCustomObject]@{
        Missing          = $counts.Missing
        Outdated         = $counts.Outdated
        GenericMicrosoft = $counts.GenericMicrosoft
        DeviceError      = $counts.DeviceError
        UpToDate         = $counts.UpToDate
        SummaryLine      = ('missing {0} | outdated {1} | error {2} | generic {3}' -f `
            $counts.Missing, $counts.Outdated, $counts.DeviceError, $counts.GenericMicrosoft)
    }
}
