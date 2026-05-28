# Driver health score — local analysis (v1.5.0)

$script:TrustedProviderPattern = 'Microsoft|Intel|Realtek|AMD|NVIDIA|Lenovo|Dell|HP|ASUS|Synaptics|Conexant|Broadcom|Qualcomm|MediaTek'

function Get-DriverHealthCachePath {
    return Join-Path (Join-Path (Get-AppDataRoot) 'Cache') 'health.json'
}

function Get-DriverHealthCache {
    $path = Get-DriverHealthCachePath
    if (-not (Test-Path $path)) { return $null }
    try {
        return Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Save-DriverHealthCache {
    param($Health)
    $path = Get-DriverHealthCachePath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    ($Health | ConvertTo-Json -Depth 6) | Set-Content $path -Encoding UTF8
}

function Get-RecentInstallFailureSummary {
    param([int]$MaxAgeDays = 30)

    $path = Get-InstallStatsPath
    $failures = New-Object System.Collections.ArrayList
    if (-not (Test-Path $path)) {
        return [PSCustomObject]@{ Count = 0; Items = @() }
    }

    $cutoff = (Get-Date).AddDays(-1 * $MaxAgeDays)
    foreach ($line in (Get-Content -Path $path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $row = $line | ConvertFrom-Json
            if ($row.success) { continue }
            if ($row.ts) {
                $ts = [DateTime]::Parse($row.ts)
                if ($ts -lt $cutoff) { continue }
            }
            [void]$failures.Add([PSCustomObject]@{
                Device  = [string]$row.device
                Package = [string]$row.pkg
                Error   = [string]$row.error
            })
        } catch { }
    }

    return [PSCustomObject]@{
        Count = $failures.Count
        Items = @($failures.ToArray())
    }
}

function Get-LocalLibraryGapMessages {
    param(
        $Manifest = $null,
        $HwProfile = $null
    )

    $msgs = New-Object System.Collections.ArrayList
    if (-not $Manifest) {
        $local = Get-LocalManifestPath
        if ($local) { $Manifest = Import-DriverManifest -Path $local }
    }
    if (-not $Manifest -or -not $Manifest.packages) { return @() }

    if (-not $HwProfile) { $HwProfile = Get-HardwareProfile }

    $driversRoot = Join-Path (Get-AppRoot) 'Drivers'
    $platform = [string]$HwProfile.Platform

    $priorityIds = @()
    if ($platform -eq 'Intel') {
        $priorityIds = @('intel_chipset', 'intel_mei', 'intel_wifi', 'intel_graphics', 'realtek_lan', 'realtek_audio')
    } elseif ($platform -eq 'AMD') {
        $priorityIds = @('amd_chipset', 'realtek_lan', 'realtek_audio')
    }

    foreach ($id in $priorityIds) {
        $found = $false
        foreach ($prop in $Manifest.packages.PSObject.Properties) {
            $pkg = $prop.Value
            $pkgId = if ($pkg.id) { [string]$pkg.id } else { $prop.Name }
            if ($pkgId -ne $id) { continue }
            $dir = Join-Path $driversRoot $id
            if (Test-Path $dir) {
                $inf = Get-ChildItem $dir -Filter '*.inf' -Recurse -EA SilentlyContinue | Select-Object -First 1
                if ($inf) { $found = $true }
            }
            if (-not $found) {
                $title = if ($pkg.title) { $pkg.title } else { $id }
                [void]$msgs.Add("本地驱动库缺失：$title")
            }
            break
        }
    }

    return @($msgs.ToArray())
}

function Get-HealthScoreColor {
    param([int]$Score)
    if ($Score -ge 90) { return '#22C55E' }
    if ($Score -ge 75) { return '#FBBF24' }
    if ($Score -ge 60) { return '#FB923C' }
    return '#F87171'
}

function Get-HealthScoreLabel {
    param([int]$Score)
    if ($Score -ge 90) { return '优秀' }
    if ($Score -ge 75) { return '良好' }
    if ($Score -ge 60) { return '一般' }
    return '需关注'
}

function Measure-DriverHealth {
    param(
        [array]$ScanResults = @(),
        [array]$FixPlan = @(),
        $Manifest = $null,
        $HwProfile = $null
    )

    if (-not $HwProfile) { $HwProfile = Get-HardwareProfile }
    if (-not $Manifest) {
        $local = Get-LocalManifestPath
        if ($local) { $Manifest = Import-DriverManifest -Path $local }
    }

    $score = 100
    $warnings = New-Object System.Collections.ArrayList
    $recommendations = New-Object System.Collections.ArrayList

    $problemDevices = @($ScanResults | Where-Object { $_.IsProblem })
    $problemCount = $problemDevices.Count
    $totalDevices = @($ScanResults).Count
    $okCount = $totalDevices - $problemCount
    $completeness = if ($totalDevices -gt 0) { [Math]::Round($okCount / $totalDevices, 3) } else { 1.0 }

    $score -= [Math]::Min(35, $problemCount * 5)
    if ($problemCount -gt 0) {
        [void]$warnings.Add(("发现 {0} 个问题设备" -f $problemCount))
        [void]$recommendations.Add('建议立即扫描并修复推荐驱动')
    }

    $outdated = @($FixPlan | Where-Object { $_.IsOutdated }).Count
    $score -= [Math]::Min(12, $outdated * 3)
    if ($outdated -gt 0) {
        [void]$warnings.Add(("检测到 {0} 个过时驱动" -f $outdated))
        foreach ($item in @($FixPlan | Where-Object { $_.IsOutdated } | Select-Object -First 3)) {
            $name = if ($item.Device.FriendlyName) { $item.Device.FriendlyName } else { '设备' }
            [void]$recommendations.Add("$name 驱动可升级")
        }
    }

    $noSource = @($FixPlan | Where-Object { $_.Action -eq 'NoSource' -and $_.Device.IsProblem })
    $score -= [Math]::Min(15, $noSource.Count * 5)
    foreach ($item in @($noSource | Select-Object -First 2)) {
        [void]$warnings.Add(("无匹配驱动包：{0}" -f $item.Device.FriendlyName))
    }

    $untrusted = @($ScanResults | Where-Object {
        $_.IsProblem -and $_.DriverProvider -and
        [string]$_.DriverProvider -notmatch $script:TrustedProviderPattern
    })
    $score -= [Math]::Min(8, $untrusted.Count * 2)
    foreach ($dev in @($untrusted | Select-Object -First 2)) {
        [void]$warnings.Add(("驱动签名/厂商需关注：{0}" -f $dev.FriendlyName))
    }

    $failStats = Get-RecentInstallFailureSummary
    $score -= [Math]::Min(10, $failStats.Count * 2)
    if ($failStats.Count -gt 0) {
        [void]$warnings.Add(("近期安装失败 {0} 次" -f $failStats.Count))
        [void]$recommendations.Add('查看日志或尝试回滚后重新修复')
    }

    $gaps = Get-LocalLibraryGapMessages -Manifest $Manifest -HwProfile $HwProfile
    $score -= [Math]::Min(8, $gaps.Count * 2)
    foreach ($g in $gaps) {
        [void]$recommendations.Add($g)
    }

    $recommendedFix = (Get-RepairSummary -FixPlan $FixPlan -ScanResults $ScanResults).Recommended
    if ($recommendedFix -gt 0 -and $problemCount -gt 0) {
        [void]$recommendations.Add(("推荐修复 {0} 项驱动" -f $recommendedFix))
    }

    if ($recommendations.Count -eq 0 -and $score -ge 90) {
        [void]$recommendations.Add('驱动状态良好，可定期扫描保持更新')
    }

    $score = [Math]::Max(0, [Math]::Min(100, [int][Math]::Round($score)))

    $summary = Get-RepairSummary -FixPlan $FixPlan -ScanResults $ScanResults

    return [PSCustomObject]@{
        HealthScore      = $score
        ScoreLabel       = (Get-HealthScoreLabel -Score $score)
        ScoreColor       = (Get-HealthScoreColor -Score $score)
        Warnings         = @($warnings.ToArray())
        Recommendations  = @($recommendations.ToArray())
        WarningCount     = $warnings.Count
        RecommendationCount = $recommendations.Count
        ProblemCount     = $problemCount
        OutdatedCount    = $outdated
        Completeness     = $completeness
        DeviceTotal      = $totalDevices
        RecommendedFix   = $summary.Recommended
        TotalDetected    = $summary.TotalDetected
        RepairSummary    = $summary
        AnalyzedAt       = (Get-Date -Format 'o')
        SummaryLine      = ("健康度 {0}% · {1}" -f $score, $summary.StatusLine)
    }
}

function Get-QuickDriverHealthEstimate {
    param($HwProfile = $null)

    if (-not $HwProfile) { $HwProfile = Get-HardwareProfile }
    $essential = Get-EssentialDeviceClasses
    $problems = 0

    foreach ($dev in (Get-PnpDevice -ErrorAction SilentlyContinue)) {
        if ($dev.Status -eq 'OK') { continue }
        if (Test-DriverRelevantDevice -Device $dev -EssentialClasses $essential) {
            $problems++
        }
    }

    $score = 100 - [Math]::Min(40, $problems * 6)
    $failStats = Get-RecentInstallFailureSummary
    $score -= [Math]::Min(10, $failStats.Count * 2)
    $score = [Math]::Max(0, [Math]::Min(100, $score))

    return [PSCustomObject]@{
        HealthScore     = $score
        ScoreLabel      = (Get-HealthScoreLabel -Score $score)
        ScoreColor      = (Get-HealthScoreColor -Score $score)
        Warnings        = @($(if ($problems -gt 0) { "约 $problems 个问题设备（快速估计）" } else { '快速检查未发现明显问题' }))
        Recommendations = @('完整扫描后将更新精确健康度')
        WarningCount    = if ($problems -gt 0) { 1 } else { 0 }
        RecommendationCount = 1
        ProblemCount    = $problems
        OutdatedCount   = 0
        Completeness    = 0
        DeviceTotal     = 0
        RecommendedFix  = 0
        AnalyzedAt      = (Get-Date -Format 'o')
        SummaryLine     = ("健康度约 {0}%（快速估计）" -f $score)
        IsQuickEstimate = $true
    }
}

function Invoke-DriverHealthAnalysis {
    param(
        [array]$ScanResults = @(),
        [array]$FixPlan = @(),
        $Manifest = $null,
        [switch]$RunScan,
        [switch]$FastMatch,
        [switch]$QuickOnly,
        [scriptblock]$OnLog
    )

    if ($QuickOnly) {
        $health = Get-QuickDriverHealthEstimate
        Save-DriverHealthCache -Health $health
        return $health
    }

    if ($RunScan -or @($ScanResults).Count -eq 0) {
        if ($OnLog) { & $OnLog '健康分析：正在扫描设备...' }
        $ScanResults = @(Invoke-DriverScanEngine -OnLog $OnLog)
        if (-not $Manifest) { $Manifest = Get-EngineManifest }
        if ($OnLog) { & $OnLog '健康分析：正在匹配驱动...' }
        $match = Invoke-DriverMatchEngine -ScanResults $ScanResults -Manifest $Manifest -OnLog $OnLog -SkipLocalIndex:$FastMatch
        $FixPlan = @($match.FixPlan)
    }

    $health = Measure-DriverHealth -ScanResults $ScanResults -FixPlan $FixPlan -Manifest $Manifest
    $health | Add-Member -NotePropertyName IsQuickEstimate -NotePropertyValue $false -Force
    $health | Add-Member -NotePropertyName ScanResults -NotePropertyValue $ScanResults -Force
    $health | Add-Member -NotePropertyName FixPlan -NotePropertyValue $FixPlan -Force

    $cacheObj = [PSCustomObject]@{
        HealthScore           = $health.HealthScore
        ScoreLabel            = $health.ScoreLabel
        ScoreColor            = $health.ScoreColor
        Warnings              = @($health.Warnings)
        Recommendations       = @($health.Recommendations)
        WarningCount          = $health.WarningCount
        RecommendationCount   = $health.RecommendationCount
        ProblemCount          = $health.ProblemCount
        OutdatedCount         = $health.OutdatedCount
        Completeness          = $health.Completeness
        DeviceTotal           = $health.DeviceTotal
        RecommendedFix        = $health.RecommendedFix
        AnalyzedAt            = $health.AnalyzedAt
        SummaryLine           = $health.SummaryLine
        IsQuickEstimate       = $false
    }
    Save-DriverHealthCache -Health $cacheObj
    if ($OnLog) {
        & $OnLog ("驱动健康度：{0}%（{1} 条警告，{2} 条建议）" -f $health.HealthScore, $health.WarningCount, $health.RecommendationCount)
    }
    return $health
}
