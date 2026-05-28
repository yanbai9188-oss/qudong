# Patch all recent release notes to fix Chinese encoding
# Run with: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\_patch_all_releases.ps1 -Token <token>
param([string]$Token)

$headers = @{ Authorization = "token $Token"; Accept = 'application/vnd.github+json' }
$repo    = 'yanbai9188-oss/qudong'

function Patch-Release {
    param([string]$Id, [string]$Body)
    $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes(
        ([PSCustomObject]@{ body = $Body } | ConvertTo-Json -Compress)
    )
    $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/$Id" `
        -Method PATCH -Headers $headers -Body $jsonBytes -ContentType 'application/json; charset=utf-8'
    Write-Host "Patched $Id ($($r.tag_name)): OK"
}

# v2.1.2
Patch-Release -Id '330843766' -Body @"
## v2.1.2 - 多源下载架构升级

### 核心改进
- 新增多源下载引擎 (DriverDownloader.ps1)：GitHub Release / 官方直链 / Windows Update Catalog 按优先级自动回退
- 修复大包无法下载问题 (GitHub 100MB 限制)
- NVIDIA GeForce DCH 驱动现通过 Windows Update Catalog 下载 WHQL 认证 INF
- Intel Iris Xe/UHD 集显驱动新增 Catalog + Intel CDN 双源
- AMD Radeon 集显、Intel I225 网卡均切换至 Catalog 源
- Windows Update Catalog 搜索新增 Win10/Win11 过滤和架构感知排名
- 进度条乱码问题修复 (v2.1.1 延续)
"@

# v2.1.1
Patch-Release -Id '330584988' -Body @"
## v2.1.1 - 进度条乱码修复

### 问题修复
- 修复 Set-CIODIYGuiBusyState 中 StatusDot 颜色赋值异常导致进度条卡死
- 修复 Dispatcher.BeginInvoke/Invoke 委托中变量作用域问题 (GetNewClosure)
- 修复进度文字乱码：服务轮询/注册/管理员回调均改用显式变量捕获
- 修复 Write-CIODIYGuiLog 异步调用变量泄漏

### 其他
- StatusDot 工作中显示橙色，就绪显示绿色
"@

# v2.1.0
Patch-Release -Id '330514917' -Body @"
## v2.1.0 - UI 全面升级 + 过滤修复

### UI 改进
- 侧边栏导航按钮配备图标
- 设备列表卡片按钮样式区分：橙色「下载并修复」/「修复」，灰色「搜索驱动」
- 刷新统计卡片（「推荐修复」→「可一键修复」）
- 改进过滤栏，底部状态栏更精简，加入 StatusDot 忙/闲指示

### 逻辑修复
- 「推荐修复」过滤与计数统一：仅计算 ButtonText 为「下载并修复」/「修复」的项目
- CatalogSearch 项目（「搜索驱动」）不再被错误计入「推荐修复」
"@

Write-Host "All patches done."
