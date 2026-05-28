# Deploy mode HTML report (v1.4.0)

function Escape-HtmlText {
    param([string]$Text)
    if (-not $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function Format-DeployDuration {
    param([TimeSpan]$Span)
    if ($Span.TotalHours -ge 1) {
        return ('{0}小时{1}分{2}秒' -f [int]$Span.TotalHours, $Span.Minutes, $Span.Seconds)
    }
    if ($Span.TotalMinutes -ge 1) {
        return ('{0}分{1}秒' -f [int]$Span.TotalMinutes, $Span.Seconds)
    }
    return ('{0}秒' -f [Math]::Max(1, [int]$Span.TotalSeconds))
}

function Get-DeployStatusLabel {
    param([string]$Status)
    switch ([string]$Status) {
        'success'     { return '成功' }
        'partial'     { return '部分成功' }
        'failed'      { return '失败' }
        'rolled_back' { return '已回滚' }
        'no_action'   { return '无需安装' }
        'scan_only'   { return '仅扫描' }
        default       { return $Status }
    }
}

function New-DeployReportPath {
    param([string]$LogsDir = '')
    if (-not $LogsDir) { $LogsDir = Join-Path (Get-AppDataRoot) 'Logs' }
    if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    return (Join-Path $LogsDir "Deploy_$stamp.html")
}

function Export-DeployHtmlReport {
    param(
        [Parameter(Mandatory)]$Report,
        [string]$Path = ''
    )

    if (-not $Path) { $Path = New-DeployReportPath }
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    $hw = $Report.HardwareProfile
    $statusLabel = Get-DeployStatusLabel -Status $Report.Status
    $duration = Format-DeployDuration -Span $Report.Duration
    $rebootText = if ($Report.RebootNeeded) { '需重启' } else { '无需重启' }
    $appVer = if ($Report.AppVersion) { $Report.AppVersion } else { '1.4.0' }

    $scanRows = New-Object System.Text.StringBuilder
    foreach ($item in @($Report.MissingDrivers)) {
        $name = Escape-HtmlText $item.Device
        $pkg = Escape-HtmlText $item.Package
        $issue = Escape-HtmlText $item.Issue
        [void]$scanRows.AppendLine("<tr><td>$name</td><td>$issue</td><td>$pkg</td></tr>")
    }
    if ($scanRows.Length -eq 0) {
        [void]$scanRows.AppendLine('<tr><td colspan="3">未发现需修复的推荐驱动</td></tr>')
    }

    $installRows = New-Object System.Text.StringBuilder
    foreach ($line in @($Report.InstallLines)) {
        $name = Escape-HtmlText $line.Device
        $pkg = Escape-HtmlText $line.Package
        $result = if ($line.Success) {
            '<span class="ok">成功</span>'
        } else {
            '<span class="fail">失败</span> ' + (Escape-HtmlText $line.Error)
        }
        [void]$installRows.AppendLine("<tr><td>$name</td><td>$pkg</td><td>$result</td></tr>")
    }
    if ($installRows.Length -eq 0) {
        [void]$installRows.AppendLine('<tr><td colspan="3">未执行安装</td></tr>')
    }

    $html = @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<title>CIODIY 装机报告 $($Report.StartedAt.ToString('yyyy-MM-dd HH:mm'))</title>
<style>
body{font-family:"Segoe UI",Microsoft YaHei,sans-serif;background:#0f1218;color:#e2e8f0;margin:0;padding:24px}
.wrap{max-width:880px;margin:0 auto}
h1{color:#ff6b00;font-size:22px;margin:0 0 8px}
.meta{color:#94a3b8;font-size:13px;margin-bottom:20px}
.card{background:#1e2430;border:1px solid #2a3140;border-radius:10px;padding:16px 18px;margin-bottom:16px}
.card h2{font-size:15px;margin:0 0 12px;color:#f1f5f9}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:8px 16px;font-size:13px}
.label{color:#64748b}
.val{color:#f1f5f9}
.status{font-size:18px;font-weight:700;color:#22c55e}
.status.warn{color:#fbbf24}
.status.bad{color:#f87171}
table{width:100%;border-collapse:collapse;font-size:12px}
th,td{border-bottom:1px solid #2a3140;padding:8px 6px;text-align:left}
th{color:#94a3b8;font-weight:600}
.ok{color:#22c55e}.fail{color:#f87171}
.footer{color:#64748b;font-size:11px;margin-top:20px}
</style>
</head>
<body>
<div class="wrap">
<h1>CIODIY 装机模式报告</h1>
<div class="meta">应用 v$appVer · 生成于 $(Escape-HtmlText ($Report.FinishedAt.ToString('yyyy-MM-dd HH:mm:ss')))</div>

<div class="card">
<h2>设备</h2>
<div class="grid">
<div><span class="label">机型</span><div class="val">$(Escape-HtmlText $hw.MachineTitle)</div></div>
<div><span class="label">系统</span><div class="val">$(Escape-HtmlText $hw.SystemFull)</div></div>
<div><span class="label">平台</span><div class="val">$(Escape-HtmlText $hw.PlatformLine)</div></div>
<div><span class="label">CPU</span><div class="val">$(Escape-HtmlText $hw.CPU)</div></div>
<div><span class="label">GPU</span><div class="val">$(Escape-HtmlText $hw.GPU)</div></div>
<div><span class="label">网卡</span><div class="val">$(Escape-HtmlText $hw.Network)</div></div>
</div>
</div>

<div class="card">
<h2>扫描 · 缺失/推荐驱动 ($($Report.MissingDrivers.Count))</h2>
<table>
<thead><tr><th>设备</th><th>问题</th><th>推荐包</th></tr></thead>
<tbody>
$scanRows
</tbody>
</table>
</div>

<div class="card">
<h2>安装结果 ($($Report.InstallLines.Count))</h2>
<table>
<thead><tr><th>设备</th><th>驱动包</th><th>结果</th></tr></thead>
<tbody>
$installRows
</tbody>
</table>
</div>

<div class="card">
<h2>摘要</h2>
<div class="grid">
<div><span class="label">状态</span><div class="status $(if ($Report.Status -in @('failed','rolled_back')) { 'bad' } elseif ($Report.Status -eq 'partial') { 'warn' } else { '' })">$statusLabel</div></div>
<div><span class="label">耗时</span><div class="val">$duration</div></div>
<div><span class="label">事务</span><div class="val">$(Escape-HtmlText $Report.TransactionId)</div></div>
<div><span class="label">重启</span><div class="val">$rebootText</div></div>
</div>
</div>

<div class="footer">CIODIY Driver Booster · 装机模式自动报告</div>
</div>
</body>
</html>
"@

    [System.IO.File]::WriteAllText($Path, $html, [System.Text.UTF8Encoding]::new($false))
    return $Path
}
