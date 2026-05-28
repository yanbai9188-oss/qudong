# Rich driver fix item details for UI (v1.8)

function Get-DriverPackageSourceLabel {
    param([string]$Action, $Package)

    switch ($Action) {
        'InstallLocal'        { return '本地驱动库' }
        'DownloadThenInstall' {
            if ($Package -and $Package.Url -match 'github\.com') { return 'GitHub Release 下载' }
            if ($Package -and $Package.Url) { return '在线下载' }
            return '远程镜像'
        }
        'CatalogSearch'       { return 'Windows Update Catalog (联网搜索)' }
        'NoSource'            { return '无可用来源' }
        default               { return [string]$Action }
    }
}

function Get-DriverMatchReasonText {
    param($Item)

    $parts = New-Object System.Collections.ArrayList
    if ($Item.ExactHwidMatch) { [void]$parts.Add('HWID 精确匹配') }
    else { [void]$parts.Add('HWID 模糊匹配') }

    if ($Item.Package -and (Test-PackageOsCompatible -Package $Item.Package)) {
        $os = Get-SystemOsProfile
        [void]$parts.Add(('{0} 兼容' -f $os.Label))
    } else {
        [void]$parts.Add('OS 兼容性待定')
    }

    if ($Item.ConfidencePercent -ge 85) { [void]$parts.Add('高置信度') }
    elseif ($Item.ConfidencePercent -ge 65) { [void]$parts.Add('中等置信度') }

    return ($parts -join ' · ')
}

function Get-DriverFixItemDetails {
    param(
        [Parameter(Mandatory)]$Item,
        $Manifest = $null
    )

    $dev = $Item.Device
    $pkg = $Item.Package
    $versionStatus = Get-DriverVersionStatus -Device $dev -Package $pkg `
        -IsOutdated $Item.IsOutdated -Action $Item.Action
    $trust = Get-PackageTrustMeta -Package $pkg
    $trustRisk = Get-PackageTrustRisk -Item $Item
    $tier = Get-RecommendTier -Item $Item

    $pkgSize = ''
    if ($pkg -and $pkg.LocalPath -and (Test-Path $pkg.LocalPath)) {
        try {
            $bytes = (Get-ChildItem $pkg.LocalPath -Recurse -File -EA SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            if ($bytes -gt 1MB) { $pkgSize = ('{0:N1} MB' -f ($bytes / 1MB)) }
            elseif ($bytes -gt 0) { $pkgSize = ('{0:N0} KB' -f ($bytes / 1KB)) }
        } catch { }
    }

    $reboot = $false
    if ($pkg -and $null -ne $pkg.RebootRequired) { $reboot = [bool]$pkg.RebootRequired }

    $displayName = Get-DeviceDisplayName -Device $dev -Package $pkg
    $pkgTitle = if ($pkg) { Get-PackageDisplayTitle -Package $pkg } else { '-' }
    $curVer = if ($dev.DriverVersion) { $dev.DriverVersion } else { 'not installed' }
    $tgtVer = if ($Item.TargetVersion) { $Item.TargetVersion } elseif ($pkg) { $pkg.Version } else { '-' }

    # NVIDIA GPU 特殊提示
    $nvidiaNoteLines = @()
    $isNvidiaGpu = $pkg -and ([string]$pkg.Vendor -match 'NVIDIA') -and ([string]$pkg.Category -match 'gpu')
    if ($isNvidiaGpu -and $Item.Action -eq 'CatalogSearch') {
        $nvidiaNoteLines = @(
            '',
            '[!] NVIDIA GPU 驱动建议从官网下载最新 Game Ready / Studio 驱动：',
            '    https://www.nvidia.com/Download/index.aspx',
            '    或通过 NVIDIA App / GeForce Experience 自动更新。',
            '    Windows Update Catalog 版本通常非最新 DCH 驱动。'
        )
    }

    $isAmdGpu = $pkg -and ([string]$pkg.Vendor -match 'AMD') -and ([string]$pkg.Category -match 'gpu')
    $amdNoteLines = @()
    if ($isAmdGpu -and $Item.Action -eq 'CatalogSearch') {
        $amdNoteLines = @(
            '',
            '[!] AMD GPU 驱动建议从官网下载最新版本：',
            '    https://www.amd.com/zh-cn/support/download/drivers.html'
        )
    }

    $lines = @(
        ('设备：{0}' -f $displayName),
        ('当前版本：{0}' -f $(if ($curVer -eq 'not installed') { '未安装' } else { $curVer })),
        ('推荐版本：{0}' -f $tgtVer),
        ('状态：{0}' -f (Get-DriverVersionStatusLabelUi -Status $versionStatus)),
        ('来源：{0}' -f (Get-DriverPackageSourceLabel -Action $Item.Action -Package $pkg)),
        ('可信度：{0}' -f $trust.TrustBadge),
        ('匹配原因：{0}' -f (Get-DriverMatchReasonText -Item $Item)),
        ('推荐级别：{0}' -f $tier),
        ('风险：{0}' -f $(switch ($trustRisk.Level) { 'low' { '低' } 'medium' { '中' } 'high' { '高' } default { $trustRisk.Level } })),
        $(if ($trustRisk.Reasons.Count -gt 0) { '风险原因：' + ($trustRisk.Reasons -join '；') } else { $null }),
        $(if ($pkgSize) { "包大小：$pkgSize" } else { $null }),
        $(if ($reboot) { '[*] 安装后需要重启' } else { '安装后通常无需重启' })
    ) + $nvidiaNoteLines + $amdNoteLines | Where-Object { $null -ne $_ }

    return [PSCustomObject]@{
        DeviceName         = $displayName
        PackageTitle       = $pkgTitle
        CurrentVersion     = [string]$dev.DriverVersion
        TargetVersion      = if ($Item.TargetVersion) { [string]$Item.TargetVersion } elseif ($pkg) { [string]$pkg.Version } else { '' }
        VersionStatus      = $versionStatus
        VersionStatusLabel = Get-DriverVersionStatusLabelUi -Status $versionStatus
        SourceLabel        = Get-DriverPackageSourceLabel -Action $Item.Action -Package $pkg
        TrustBadge         = $trust.TrustBadge
        TrustLevel         = $trust.TrustLevel
        MatchReason        = Get-DriverMatchReasonText -Item $Item
        RecommendTier      = $tier
        RiskLevel          = $trustRisk.Level
        RiskReasons        = @($trustRisk.Reasons)
        PackageSize        = $pkgSize
        RebootRequired     = $reboot
        Confidence         = if ($Item.ConfidencePercent) { [int]$Item.ConfidencePercent } else { 0 }
        DetailText         = ($lines -join [Environment]::NewLine)
        Whql               = $trust.Whql
    }
}

function Format-DriverFixItemDetails {
    param([Parameter(Mandatory)]$Details)
    return $Details.DetailText
}
