# This file is saved as UTF-8 — do NOT convert encoding
param([string]$Token, [string]$ReleaseId, [string]$Repo)

$headers = @{
    Authorization = "token $Token"
    Accept        = 'application/vnd.github+json'
}

$body213 = @"
## v2.1.3 - Windows Update Catalog 下载引擎升级

### 核心改进
- 接入 **MSCatalogLTS** (PowerShell Gallery 开源模块，5.3万次下载，持续维护)
- Catalog 下载路径：MSCatalogLTS → HTTP 刮屏 双重保障
- MSCatalogLTS 在应用**启动时后台静默预安装**，用户点修复时已就绪
- 搜索结果智能排序：优先 Win10/Win11、DCH 驱动、Drivers 分类
- 安装状态缓存（24h 冷却避免重复请求 PSGallery）
- 继承 v2.1.2 多源下载架构（GitHub / 直链 / Catalog）
"@

$jsonBytes = [System.Text.Encoding]::UTF8.GetBytes(
    ([PSCustomObject]@{ body = $body213 } | ConvertTo-Json -Compress)
)

$resp = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/$ReleaseId" `
    -Method PATCH -Headers $headers -Body $jsonBytes `
    -ContentType 'application/json; charset=utf-8'

Write-Host "OK: $($resp.name)"
Write-Host ($resp.body.Substring(0, [Math]::Min(100, $resp.body.Length)))
