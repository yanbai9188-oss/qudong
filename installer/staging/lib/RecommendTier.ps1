# Recommendation tier labels (v1.6.4 trust fix)

function Get-RecommendTier {
    param($Item)

    if (-not $Item) { return '不建议自动安装' }
    if ($Item.Action -in @('CatalogSearch', 'NoSource', 'NoPackage')) { return '不建议自动安装' }
    if (-not $Item.Package) { return '不建议自动安装' }

    $devClass = Get-CIODIYDeviceClass -Device $Item.Device
    $pkgClass = Get-CIODIYPackageClass -Package $Item.Package
    if ($devClass -ne 'unknown' -and $pkgClass -ne 'unknown' -and $devClass -ne $pkgClass) {
        return '不建议自动安装'
    }

    $pct = if ($null -ne $Item.ConfidencePercent) { [int]$Item.ConfidencePercent } else { 0 }
    if ($pct -lt 60) { return '不建议自动安装' }

    $exact = $false
    if ($null -ne $Item.ExactHwidMatch) { $exact = [bool]$Item.ExactHwidMatch }
    elseif ($Item.Package._MatchHwids) {
        $exact = Test-ExactHwidMatch -Device $Item.Device -PatternIds @($Item.Package._MatchHwids)
    }

    $osOk = Test-PackageOsCompatible -Package $Item.Package

    if ($pct -ge 95 -and $exact -and $osOk) { return '强烈推荐' }
    if ($pct -ge 80 -and $exact -and $osOk) { return '推荐' }
    if ($pct -ge 60 -and $devClass -ne 'unknown' -and $pkgClass -eq $devClass) { return '可选' }
    return '不建议自动安装'
}

function Test-RecommendTierAutoSelect {
    param([string]$Tier)
    return ($Tier -in @('强烈推荐', '推荐'))
}
