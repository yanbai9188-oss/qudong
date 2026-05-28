# User-facing text normalization (v1.6.4)

function ConvertTo-CIODIYUserText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '未知设备' }

    $t = $Text.Trim()
    if ($t -match '(?i)^\(unnamed\)$' -or $t -match '(?i)unnamed') { return '未知设备' }
    if ($t -match '(?i)CatalogSearch') { return '暂无本地匹配，建议使用 Windows 更新或手动指定驱动' }
    if ($t -match '(?i)NoPackage') { return '暂无可用驱动包' }
    if ($t -match '(?i)NoSource') { return '暂无可用驱动源' }
    if ($t -match '(?i)^Matched$') { return '已找到推荐驱动' }
    if ($t -match '(?i)LocalPackage') { return '本地驱动包' }
    if ($t -match '(?i)GitHubRelease') { return '在线驱动包' }
    return $Text
}

function Get-ActionUserLabel {
    param([string]$Action)

    switch ($Action) {
        'InstallLocal'        { return '本地驱动包' }
        'DownloadThenInstall' { return '在线驱动包' }
        'CatalogSearch'       { return '暂无本地匹配，建议使用 Windows 更新或手动指定驱动' }
        'NoSource'            { return '暂无可用驱动源' }
        'NoPackage'           { return '暂无可用驱动包' }
        default {
            $mapped = ConvertTo-CIODIYUserText -Text $Action
            if ($mapped -ne $Action) { return $mapped }
            return $Action
        }
    }
}

function Get-PackageDisplayTitle {
    param($Package)

    if (-not $Package) { return '暂无可用驱动包' }
    $title = if ($Package.Title) { [string]$Package.Title } elseif ($Package.Id) { [string]$Package.Id } else { '' }
    if ([string]::IsNullOrWhiteSpace($title)) { return '暂无可用驱动包' }
    return (ConvertTo-CIODIYUserText -Text $title)
}
