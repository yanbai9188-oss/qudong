# Driver candidate scoring — FROZEN weights (see docs/ARCHITECTURE.md)
# HWID 50 + DeviceClass 20 + OS 10 + WHQL 5 + MachineVerify 10 + InstallRate 5 = 100

$script:ScoreWeightHwidExact = 50
$script:ScoreWeightDeviceClass = 20
$script:ScoreWeightOsCompat = 10
$script:ScoreWeightWhql = 5
$script:ScoreWeightMachineVerify = 10
$script:ScoreWeightInstallRate = 5
$script:ScoreMaxTotal = 100

function Get-HwIdMatchScore {
    param(
        [string[]]$DeviceIds,
        [string[]]$PatternIds
    )
    if (-not $DeviceIds -or -not $PatternIds) { return 0 }

    $best = 0
    foreach ($pattern in $PatternIds) {
        $p = Normalize-HardwareId $pattern
        if (-not $p) { continue }
        foreach ($deviceId in $DeviceIds) {
            $d = Normalize-HardwareId $deviceId
            if (-not $d) { continue }
            if ($d -eq $p) { $best = [Math]::Max($best, $script:ScoreWeightHwidExact); continue }
            if ($d -like ($p + '*') -or $p -like ($d + '*')) {
                $best = [Math]::Max($best, 35)
            }
        }
    }
    return $best
}

function Get-DeviceClassMatchScore {
    param(
        $Candidate,
        $Device
    )

    $devClass = Get-CIODIYDeviceClass -Device $Device
    $pkgClass = if ($Candidate.DeviceClass) { [string]$Candidate.DeviceClass } else { Get-CIODIYPackageClass -Package $Candidate }
    if ($devClass -eq 'unknown' -or $pkgClass -eq 'unknown') { return 0 }
    if ($devClass -eq $pkgClass) { return $script:ScoreWeightDeviceClass }
    return 0
}

function Get-OsCompatScore {
    param(
        $Package,
        $OsProfile = $null
    )

    if (-not $OsProfile) { $OsProfile = Get-SystemOsProfile }
    if (-not (Test-PackageOsCompatible -Package $Package -OsProfile $OsProfile)) { return 0 }

    $score = 6
    if ($OsProfile.IsWin10 -and $Package.Win10Preferred) { return $script:ScoreWeightOsCompat }
    $osTags = @()
    if ($Package.Os) { $osTags = @($Package.Os) }
    if ($OsProfile.IsWin10 -and ($osTags -contains 'win10')) { $score = 8 }
    if ($OsProfile.IsWin11 -and ($osTags -contains 'win11')) { $score = 8 }
    return [Math]::Min($script:ScoreWeightOsCompat, $score)
}

function Get-MachineVerifyScore {
    param($Package)

    $pkgId = if ($Package.Id) { [string]$Package.Id } else { '' }
    $devClass = if ($Package.DeviceClass) { [string]$Package.DeviceClass } else { '' }
    if (-not $pkgId) { return 5 }

    $hint = $null
    if (Get-Command Get-PackageCompatibilityHint -ErrorAction SilentlyContinue) {
        $hint = Get-PackageCompatibilityHint -PackageId $pkgId -DeviceClass $devClass
    }
    if (-not $hint) { return 5 }

    $rate = [double]$hint.SuccessRate
    $bonus = [int]([Math]::Round($rate * $script:ScoreWeightMachineVerify))
    if ($hint.VerifiedMachines -ge 3) { $bonus = [Math]::Min($script:ScoreWeightMachineVerify, $bonus + 1) }
    return [Math]::Min($script:ScoreWeightMachineVerify, $bonus)
}

function Get-InstallRateScore {
    param($Package)

    $rate = if ($null -ne $Package.SuccessRate) { [double]$Package.SuccessRate } else { 0.85 }
    $statRate = Get-PackageSuccessRateHint -PackageId $Package.Id
    if ($null -ne $statRate) { $rate = [double]$statRate }
    return [Math]::Min($script:ScoreWeightInstallRate, [int]([Math]::Round($rate * $script:ScoreWeightInstallRate)))
}

function Get-WhqlScore {
    param($Package)
    if ($Package.Whql) { return $script:ScoreWeightWhql }
    if ($Package.Signed) { return 2 }
    return 0
}

function ConvertTo-PackageCandidate {
    param(
        [Parameter(Mandatory)][string]$PackageKey,
        $PackageRaw,
        $Device
    )

    $id = if ($PackageRaw.id) { [string]$PackageRaw.id } else { $PackageKey -replace '^Seed_', '' }
    return [PSCustomObject]@{
        PackageId      = $PackageKey
        Id             = $id
        Title          = if ($PackageRaw.title) { $PackageRaw.title } else { $PackageKey }
        Version        = if ($PackageRaw.version) { [string]$PackageRaw.version } else { '' }
        Category       = if ($PackageRaw.category) { [string]$PackageRaw.category } else { '' }
        Vendor         = if ($PackageRaw.vendor) { [string]$PackageRaw.vendor } else { '' }
        Url            = if ($PackageRaw.url) { [string]$PackageRaw.url } else { '' }
        Sha256         = if ($PackageRaw.sha256) { [string]$PackageRaw.sha256 } else { '' }
        Risk           = if ($PackageRaw.risk) { [string]$PackageRaw.risk } else { 'medium' }
        Whql           = [bool]$PackageRaw.whql
        Signed         = if ($null -eq $PackageRaw.signed) { $true } else { [bool]$PackageRaw.signed }
        RebootRequired = [bool]$PackageRaw.reboot_required
        InstallType    = if ($PackageRaw.install_type) { [string]$PackageRaw.install_type } else { 'inf' }
        LocalOnly      = [bool]$PackageRaw.local_only
        LocalPath      = $null
        Depends        = @($PackageRaw.depends)
        Conflicts      = @($PackageRaw.conflicts)
        Blacklist      = @($PackageRaw.blacklist)
        InstallOrder   = if ($null -ne $PackageRaw.installOrder) { [int]$PackageRaw.installOrder } else { 50 }
        Verify         = if ($PackageRaw.verify) { [string]$PackageRaw.verify } else { '' }
        Rollback       = if ($null -eq $PackageRaw.rollback) { $true } else { [bool]$PackageRaw.rollback }
        SuccessRate    = if ($null -ne $PackageRaw.success_rate) { [double]$PackageRaw.success_rate } else { 0.85 }
        Confidence     = if ($PackageRaw.confidence) { [string]$PackageRaw.confidence } else { 'medium' }
        ScoreHint      = if ($null -ne $PackageRaw.score) { [int]$PackageRaw.score } else { 0 }
        Os             = if ($PackageRaw.os) { @($PackageRaw.os) } else { @() }
        OsMinBuild     = if ($null -ne $PackageRaw.os_min_build) { [int]$PackageRaw.os_min_build } else { 0 }
        OsMaxBuild     = if ($null -ne $PackageRaw.os_max_build) { [int]$PackageRaw.os_max_build } else { 0 }
        Win10Preferred = [bool]$PackageRaw.win10_preferred
        OemBrands      = if ($PackageRaw.oem_brands) { @($PackageRaw.oem_brands) } else { @() }
        DeviceClass    = Get-CIODIYPackageClass -PackageRaw $PackageRaw
        Device         = $Device
        # Multi-source download array — preserved so JobQueue and ServiceWorker can use it
        Sources        = if ($PackageRaw.sources) { @($PackageRaw.sources) } else { @() }
    }
}

function Score-DriverCandidate {
    param(
        [Parameter(Mandatory)]$Candidate,
        [Parameter(Mandatory)]$Device,
        [string[]]$InstalledPackageIds = @()
    )

    if ($Candidate.Conflicts -and $InstalledPackageIds.Count -gt 0) {
        foreach ($conflict in @($Candidate.Conflicts)) {
            foreach ($installed in $InstalledPackageIds) {
                if ($installed -eq $conflict -or $Candidate.Id -eq $conflict) {
                    return [PSCustomObject]@{
                        Candidate         = $Candidate
                        Score             = 0
                        ConfidencePercent = 0
                        ConfidenceLabel   = 'blocked'
                        Disqualified      = $true
                        Reason            = "conflict:$conflict"
                    }
                }
            }
        }
    }

    if ($Candidate.Blacklist -and $Device.DriverVersion) {
        foreach ($bad in @($Candidate.Blacklist)) {
            if ($Device.DriverVersion -like "*$bad*") {
                return [PSCustomObject]@{
                    Candidate         = $Candidate
                    Score             = 0
                    ConfidencePercent = 0
                    ConfidenceLabel   = 'blocked'
                    Disqualified      = $true
                    Reason            = "blacklist:$bad"
                }
            }
        }
    }

    $osProfile = Get-SystemOsProfile
    if (-not (Test-PackageOsCompatible -Package $Candidate -OsProfile $osProfile)) {
        return [PSCustomObject]@{
            Candidate         = $Candidate
            Score             = 0
            ConfidencePercent = 0
            ConfidenceLabel   = 'blocked'
            Disqualified      = $true
            Reason            = "os:$($osProfile.Family)"
        }
    }

    $hwScore = Get-HwIdMatchScore -DeviceIds $Device.HardwareIds -PatternIds @(
        if ($Candidate._MatchHwids) { @($Candidate._MatchHwids) } else { @() }
    )
    $classScore = Get-DeviceClassMatchScore -Candidate $Candidate -Device $Device
    $osScore = Get-OsCompatScore -Package $Candidate -OsProfile $osProfile
    $whqlScore = Get-WhqlScore -Package $Candidate
    $machineScore = Get-MachineVerifyScore -Package $Candidate
    $installScore = Get-InstallRateScore -Package $Candidate

    $total = $hwScore + $classScore + $osScore + $whqlScore + $machineScore + $installScore
    $pct = [Math]::Min(99, [int]([Math]::Round($total / $script:ScoreMaxTotal * 100)))

    $label = if ($pct -ge 95) { 'high' } elseif ($pct -ge 80) { 'medium' } else { 'low' }

    return [PSCustomObject]@{
        Candidate         = $Candidate
        Score             = $total
        ConfidencePercent = $pct
        ConfidenceLabel   = $label
        Disqualified      = $false
        Reason            = ''
        Breakdown         = @{
            hwid          = $hwScore
            deviceClass   = $classScore
            os            = $osScore
            whql          = $whqlScore
            machineVerify = $machineScore
            installRate   = $installScore
        }
    }
}

function Select-BestScoredCandidate {
    param(
        [Parameter(Mandatory)][array]$Candidates,
        [Parameter(Mandatory)]$Device,
        [string[]]$InstalledPackageIds = @()
    )

    $ranked = New-Object System.Collections.ArrayList
    foreach ($c in $Candidates) {
        $scored = Score-DriverCandidate -Candidate $c -Device $Device -InstalledPackageIds $InstalledPackageIds
        if (-not $scored.Disqualified) { [void]$ranked.Add($scored) }
    }

    if ($ranked.Count -eq 0) { return $null }

    $best = @($ranked | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{ Expression = { $_.Candidate.InstallOrder }; Descending = $false })[0]
    $pkg = $best.Candidate
    $pkg | Add-Member -NotePropertyName Score -NotePropertyValue $best.Score -Force
    $pkg | Add-Member -NotePropertyName ConfidencePercent -NotePropertyValue $best.ConfidencePercent -Force
    $pkg | Add-Member -NotePropertyName ConfidenceLabel -NotePropertyValue $best.ConfidenceLabel -Force
    $pkg | Add-Member -NotePropertyName ScoreBreakdown -NotePropertyValue $best.Breakdown -Force
    return $pkg
}
