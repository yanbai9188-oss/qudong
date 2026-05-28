[Console]::OutputEncoding = [Text.Encoding]::UTF8
$utf8 = [Text.Encoding]::UTF8

$tok = $env:GITHUB_TOKEN
if (-not $tok) {
    $tokLine = ("protocol=https`nhost=github.com`n`n" | git credential fill) |
               Where-Object { $_ -like 'password=*' }
    $tok = $tokLine -replace 'password=',''
}
if (-not $tok) { Write-Error 'No GitHub token'; exit 1 }

$repo  = 'yanbai9188-oss/qudong'
$hdrs  = @{ Authorization = "token $tok"; Accept = 'application/vnd.github+json' }
$ver   = '2.2.0'
$tag   = "v$ver"
$exe   = Join-Path (Split-Path $PSScriptRoot -Parent) "Yanbai_Driver_Setup_Online_$ver.exe"

if (-not (Test-Path $exe)) { Write-Error "Installer not found: $exe"; exit 1 }

# Build release notes bytes directly (avoid GBK encoding on Chinese Windows)
$notesCN = @"
## Yanbai Driver $ver — 稳定性全面修复 + 驱动库扩充

### 关键修复
- **[修复] CatalogDownloader.ps1**: 消除 PS5.1 不兼容的 `??` 空合并运算符（导致引擎加载失败）
- **[修复] ServiceWorker.ps1**: 动态路径（不再硬编码 C:\Program Files\Yanbai_Driver），解决非标准安装路径失败问题
- **[修复] 全部含中文字符串的 .ps1**: 统一添加 UTF-8 BOM，兼容 Windows PowerShell 5.1 + GBK 系统

### 架构修复
- **[修复] JobQueue.ps1**: Start-ScheduledTask 失败不再静默吞掉，写入 queue.log 并抛出 Warning
- **[修复] ServiceWorker.ps1**: 任务文件先移入 processing/ 目录再处理，完成后删除——消除崩溃时 job 丢失问题
- **[修复] ServiceWorker.ps1**: 默认空闲超时从 60s 延长至 3600s，安装期间不再提前退出
- **[修复] JobQueue.ps1 + ServiceWorker.ps1**: sources 数组完整序列化/反序列化，多源下载架构全流程打通
- **[修复] install-task.ps1**: 任务执行时限从 30 分钟改为 8 小时，大驱动包安装不再超时

### GUI 稳定性
- **[修复] GuiWorkers.ps1**: 新增 IsBusy 并发互斥锁，防止双击触发第二个 Worker 破坏共享 Runspace
- **[修复] GuiWorkers.ps1**: 引擎 Bootstrap 出错后写入 startup.log 而非静默失败
- **[修复] GuiRender.ps1**: PropertyChanged 注册前先注销旧 Handler，消除多次扫描后的重复事件堆积
- **[修复] GuiEvents.ps1**: 后台服务轮询超时（10 分钟）正确抛出错误而非返回空假成功结果
- **[修复] GuiEvents.ps1**: 修复日志里 -replace scriptblock 语法（PS5.1 不支持）

### 多源清单打通
- **[修复] DriverScorer.ps1**: ConvertTo-PackageCandidate 保留 sources 数组字段
- **[修复] DriverMatcher.ps1**: action 逻辑优先检查 sources 字段，Catalog/direct 包不再被判成 CatalogSearch

### 驱动库扩充（18 → 34 个包）
新增 16 个驱动包（全部来自 GitHub Release v1.1.0）：
- Intel Chipset INF、Intel MEI、Intel Serial IO、Intel RST、Intel DTT
- Intel Platform、Intel USB3 xHCI、Intel Bluetooth（新/老）、Intel Display Audio
- AMD Ryzen Chipset
- Realtek 读卡器、Synaptics 触摸板、ELAN 触摸板
- HP PCL 打印驱动、Canon UFRII 打印驱动
- manifest.json / driver_packages.json 统一升级至 v1.7.0

### 部署
**安装包**: Yanbai_Driver_Setup_Online_$ver.exe  
**目标系统**: Windows 10 / Windows 11 (x64)
"@

$bodyObj = [PSCustomObject]@{
    tag_name         = $tag
    target_commitish = 'main'
    name             = "Yanbai Driver $ver"
    body             = $notesCN
    draft            = $false
    prerelease       = $false
}
$bodyBytes = $utf8.GetBytes(($bodyObj | ConvertTo-Json -Compress))

[Console]::WriteLine("Creating release $tag ...")
$rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases" `
    -Method POST -Headers $hdrs -Body $bodyBytes -ContentType 'application/json; charset=utf-8'
[Console]::WriteLine("Release created: $($rel.html_url)")

# Upload asset
$uploadUrl = $rel.upload_url -replace '\{.*\}',''
$uploadUrl += "?name=$([Uri]::EscapeDataString([IO.Path]::GetFileName($exe)))"
[Console]::WriteLine("Uploading $([IO.Path]::GetFileName($exe)) ...")
$binHdr = @{ Authorization = "token $tok"; 'Content-Type' = 'application/octet-stream' }
$exeBytes = [IO.File]::ReadAllBytes($exe)
$up = Invoke-RestMethod $uploadUrl -Method POST -Headers $binHdr -Body $exeBytes
[Console]::WriteLine("Asset: $($up.browser_download_url)")
[Console]::WriteLine('Done.')
