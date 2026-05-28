[Console]::OutputEncoding = [Text.Encoding]::UTF8
$utf8 = [Text.Encoding]::UTF8
$tok = $env:GITHUB_TOKEN
if (-not $tok) {
    $tokLine = ("protocol=https`nhost=github.com`n`n" | git credential fill) | Where-Object { $_ -like 'password=*' }
    $tok = $tokLine -replace 'password=',''
}
$repo = 'yanbai9188-oss/qudong'
$hdrs = @{ Authorization = "token $tok"; Accept = 'application/vnd.github+json' }
$ver  = '2.2.1'
$exe  = Join-Path (Split-Path $PSScriptRoot -Parent) "Yanbai_Driver_Setup_Online_$ver.exe"

$notes = @"
## Yanbai Driver $ver — 扫描提速 (5-10x)

### 性能优化
- **[优化] 移除 Win32_PnPSignedDriver 查询**: 在 Win11 24H2 上该 WMI 查询需 20-60 秒，
  改为对过滤后的目标设备批量调用 Get-PnpDeviceProperty，速度提升 5-10x
- **[优化] 进度条实时反馈**: 扫描从 5% 平滑更新到 80%，不再卡在 15% 假死状态
  - 5% 启动 → 20% 枚举设备 → 55% 读取驱动属性 → 80% 分析状态 → 85% 匹配包 → 100% 完成

### 包含 v2.2.0 全部修复
见 v2.2.0 发布说明（稳定性全面修复 + 驱动库扩充至 34 个包）

**安装包**: Yanbai_Driver_Setup_Online_$ver.exe
"@

$bodyBytes = $utf8.GetBytes(([PSCustomObject]@{
    tag_name = "v$ver"; target_commitish = 'main'; name = "Yanbai Driver $ver"
    body = $notes; draft = $false; prerelease = $false
} | ConvertTo-Json -Compress))

[Console]::WriteLine("Creating release v$ver ...")
$rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases" -Method POST -Headers $hdrs -Body $bodyBytes -ContentType 'application/json; charset=utf-8'
[Console]::WriteLine("Release: $($rel.html_url)")

$uploadUrl = ($rel.upload_url -replace '\{.*\}','') + "?name=$([Uri]::EscapeDataString([IO.Path]::GetFileName($exe)))"
[Console]::WriteLine("Uploading ...")
$up = Invoke-RestMethod $uploadUrl -Method POST -Headers @{ Authorization = "token $tok"; 'Content-Type' = 'application/octet-stream' } -Body ([IO.File]::ReadAllBytes($exe))
[Console]::WriteLine("Asset: $($up.browser_download_url)")
