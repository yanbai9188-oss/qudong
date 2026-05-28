# Package trust metadata (v1.8) — quality over quantity

function Get-PackageTrustMeta {
    param(
        $Package,
        $PackageRaw = $null
    )

    $raw = if ($PackageRaw) { $PackageRaw } else { $Package }
    if (-not $raw) {
        return [PSCustomObject]@{
            TrustLevel         = 'unknown'
            SourceVendor       = ''
            Whql               = $false
            VerifiedOn         = ''
            VerifiedMachines   = 0
            InstallSuccessRate = $null
            TrustBadge         = 'Unverified'
        }
    }

    $vendor = if ($raw.vendor) { [string]$raw.vendor } elseif ($Package -and $Package.Vendor) { [string]$Package.Vendor } else { '' }
    $whql = $false
    if ($null -ne $raw.whql) { $whql = [bool]$raw.whql }
    elseif ($Package -and $null -ne $Package.Whql) { $whql = [bool]$Package.Whql }

    $signed = $false
    if ($null -ne $raw.signed) { $signed = [bool]$raw.signed }

    $trustLevel = if ($raw.trustLevel) { [string]$raw.trustLevel }
        elseif ($vendor -and $whql -and $signed) { 'official' }
        elseif ($vendor) { 'vendor' }
        elseif ($raw.url -match 'github\.com') { 'community' }
        else { 'unknown' }

    $verifiedOn = if ($raw.verifiedOn) { [string]$raw.verifiedOn } else { '' }
    $verifiedMachines = if ($raw.verifiedMachines) { [int]$raw.verifiedMachines } else { 0 }
    $successRate = if ($null -ne $raw.installSuccessRate) { [double]$raw.installSuccessRate } else { $null }

    if (-not $successRate -and $Package -and $Package.Id) {
        $hint = Get-PackageSuccessRateHint -PackageId $Package.Id
        if ($null -ne $hint) { $successRate = $hint }
    }

    $compat = $null
    if ($Package -and $Package.Id) {
        $compat = Get-PackageCompatibilityHint -PackageId $Package.Id
        if ($compat -and $compat.VerifiedMachines -gt $verifiedMachines) {
            $verifiedMachines = $compat.VerifiedMachines
        }
        if ($compat -and $null -eq $successRate) { $successRate = $compat.SuccessRate }
    }

    $badgeParts = New-Object System.Collections.ArrayList
    switch ($trustLevel) {
        'official'  { [void]$badgeParts.Add('Official') }
        'vendor'    { [void]$badgeParts.Add('Vendor') }
        'community' { [void]$badgeParts.Add('Community') }
        default     { [void]$badgeParts.Add('Unverified') }
    }
    if ($whql) { [void]$badgeParts.Add('WHQL') }
    if ($verifiedMachines -gt 0) { [void]$badgeParts.Add("Verified x$verifiedMachines") }
    elseif ($successRate -and $successRate -ge 0.9) { [void]$badgeParts.Add('High success rate') }

    return [PSCustomObject]@{
        TrustLevel         = $trustLevel
        SourceVendor       = $vendor
        Whql               = $whql
        VerifiedOn         = $verifiedOn
        VerifiedMachines   = $verifiedMachines
        InstallSuccessRate = $successRate
        TrustBadge         = ($badgeParts -join ' | ')
    }
}

function Get-PackageTrustRisk {
    param($Item)

    $meta = Get-PackageTrustMeta -Package $Item.Package
    $risk = 'low'
    $reasons = New-Object System.Collections.ArrayList

    if ($meta.TrustLevel -eq 'unknown') {
        $risk = 'high'
        [void]$reasons.Add('unverified source')
    } elseif ($meta.TrustLevel -eq 'community') {
        $risk = 'medium'
        [void]$reasons.Add('community package')
    }

    if (-not $meta.Whql) {
        if ($risk -eq 'low') { $risk = 'medium' }
        [void]$reasons.Add('not WHQL')
    }

    if ($Item.Action -in @('CatalogSearch', 'NoSource')) {
        $risk = 'high'
        [void]$reasons.Add('no confirmed package')
    }

    $pct = if ($Item.ConfidencePercent) { [int]$Item.ConfidencePercent } else { 0 }
    if ($pct -lt 50) {
        $risk = 'high'
        [void]$reasons.Add('low confidence match')
    } elseif ($pct -lt 70 -and $risk -eq 'low') {
        $risk = 'medium'
        [void]$reasons.Add('moderate confidence')
    }

    if ($Item.ExactHwidMatch -eq $false) {
        if ($risk -eq 'low') { $risk = 'medium' }
        [void]$reasons.Add('fuzzy HWID match')
    }

    if ($Item.Package -and -not (Test-PackageOsCompatible -Package $Item.Package)) {
        $risk = 'high'
        [void]$reasons.Add('OS compatibility uncertain')
    }

    return [PSCustomObject]@{
        Level   = $risk
        Reasons = @($reasons)
    }
}
