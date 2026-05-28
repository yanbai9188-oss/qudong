#requires -Version 5.1
# CIODIY 发布前体检 — 版本一致性 / 驱动包 / SHA256 / 下载链接

param(
    [string]$AppRoot = '',
    [switch]$Strict
)

$ErrorActionPreference = 'Continue'
$root = if ($AppRoot) { $AppRoot } else { Split-Path $PSScriptRoot -Parent }
. (Join-Path $root 'engine\Initialize-Engine.ps1') -AppRoot $root

$pass = 0
$warn = 0
$fail = 0
$lines = New-Object System.Collections.Generic.List[string]

function Add-HealthResult {
    param([string]$Level, [string]$Message)
    switch ($Level) {
        'pass' { $script:pass++; $script:lines.Add("[通过] $Message") }
        'warn' { $script:warn++; $script:lines.Add("[警告] $Message") }
        'fail' { $script:fail++; $script:lines.Add("[失败] $Message") }
        default { $script:lines.Add("[$Level] $Message") }
    }
}

function Get-ExpectedAppVersion {
    $path = Join-Path $root 'DriverBooster.ps1'
    if (-not (Test-Path $path)) { return $null }
    $m = [regex]::Match((Get-Content $path -Raw -Encoding UTF8), "\`$script:AppVersion\s*=\s*'([^']+)'")
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

Write-Host ''
Write-Host 'CIODIY 发布体检报告' -ForegroundColor Cyan
Write-Host ('根目录: {0}' -f $root)
Write-Host ('时间: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-Host ''

$appVer = Get-ExpectedAppVersion
if ($appVer) {
    Add-HealthResult -Level 'pass' -Message ("应用版本：v{0}" -f $appVer)
} else {
    Add-HealthResult -Level 'fail' -Message '无法读取 DriverBooster.ps1 版本'
}

$issPath = Join-Path $root 'installer\setup.iss'
if (Test-Path $issPath) {
    $issVer = [regex]::Match((Get-Content $issPath -Raw -Encoding UTF8), '#define MyAppVersion "([^"]+)"').Groups[1].Value
    if ($issVer -eq $appVer) {
        Add-HealthResult -Level 'pass' -Message ("Setup 版本：{0}" -f $issVer)
    } else {
        Add-HealthResult -Level 'fail' -Message ("Setup 版本 {0} 与应用 {1} 不一致" -f $issVer, $appVer)
    }
} else {
    Add-HealthResult -Level 'warn' -Message '未找到 installer\setup.iss'
}

$readmePath = Join-Path $root '使用说明.txt'
if (Test-Path $readmePath) {
    $readme = Get-Content $readmePath -Raw -Encoding UTF8
    if ($readme -match "v$appVer") {
        Add-HealthResult -Level 'pass' -Message ("使用说明已包含 v{0}" -f $appVer)
    } else {
        Add-HealthResult -Level 'fail' -Message ("使用说明未更新到 v{0}" -f $appVer)
    }
}

$manifestPath = Join-Path $root 'driver_packages.json'
$manifest = $null
if (Test-Path $manifestPath) {
    try {
        $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Add-HealthResult -Level 'pass' -Message ("manifest 版本：v{0}（{1} 个包）" -f $manifest.version, @($manifest.packages.PSObject.Properties).Count)
    } catch {
        Add-HealthResult -Level 'fail' -Message ("manifest 解析失败：{0}" -f $_.Exception.Message)
    }
} else {
    Add-HealthResult -Level 'fail' -Message '缺少 driver_packages.json'
}

$cacheDir = Join-Path $root 'Cache'
$zipCache = Join-Path $cacheDir 'packages'
$driversRoot = Join-Path $root 'Drivers'

if ($manifest -and $manifest.packages) {
    foreach ($prop in $manifest.packages.PSObject.Properties) {
        $key = $prop.Name
        $pkg = $prop.Value
        $id = if ($pkg.id) { $pkg.id } else { ($key -replace '^Seed_', '').ToLower() }
        $localDir = Join-Path $driversRoot $id
        $zipName = [IO.Path]::GetFileName($pkg.url)
        $zipPath = Join-Path $cacheDir $zipName

        $localInfs = 0
        if (Test-Path $localDir) {
            $localInfs = @(Get-ChildItem $localDir -Filter '*.inf' -Recurse -EA SilentlyContinue).Count
            if ($localInfs -eq 0) {
                Add-HealthResult -Level 'warn' -Message ("{0} 本地包为空" -f $id)
            } else {
                Add-HealthResult -Level 'pass' -Message ("{0} 本地 {1} 个 INF" -f $id, $localInfs)
            }
        }

        if ($pkg.url -and $pkg.url -match '^https?://') {
            if ($Strict) {
                try {
                    Invoke-WebRequest -Uri $pkg.url -Method Head -UseBasicParsing -TimeoutSec 15 | Out-Null
                    Add-HealthResult -Level 'pass' -Message ("URL 可访问：{0}" -f $zipName)
                } catch {
                    Add-HealthResult -Level 'fail' -Message ("URL 不可访问：{0}" -f $zipName)
                }
            }
        }

        if ($pkg.sha256 -and (Test-Path $zipPath)) {
            $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
            if ($hash -eq $pkg.sha256.ToLower()) {
                Add-HealthResult -Level 'pass' -Message ("SHA256 匹配：{0}" -f $id)
            } else {
                Add-HealthResult -Level 'fail' -Message ("SHA256 不匹配：{0}" -f $id)
            }
        } elseif ($pkg.sha256 -and -not (Test-Path $zipPath)) {
            Add-HealthResult -Level 'warn' -Message ("未缓存 ZIP：{0}" -f $zipName)
        }

        if ((Test-Path $zipPath) -and -not $localInfs) {
            try {
                $tmp = Join-Path $env:TEMP ("ciodiy_test_" + $id)
                if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
                Expand-Archive -Path $zipPath -DestinationPath $tmp -Force
                $infCount = @(Get-ChildItem $tmp -Filter '*.inf' -Recurse).Count
                if ($infCount -gt 0) {
                    Add-HealthResult -Level 'pass' -Message ("{0} ZIP 含 {1} 个 INF" -f $id, $infCount)
                } else {
                    Add-HealthResult -Level 'fail' -Message ("{0} ZIP 无 INF" -f $id)
                }
                Remove-Item $tmp -Recurse -Force -EA SilentlyContinue
            } catch {
                Add-HealthResult -Level 'fail' -Message ("{0} ZIP 解压失败" -f $id)
            }
        }
    }
}

foreach ($line in $lines) {
    $color = 'Gray'
    if ($line -like '[通过]*') { $color = 'Green' }
    elseif ($line -like '[警告]*') { $color = 'Yellow' }
    elseif ($line -like '[失败]*') { $color = 'Red' }
    Write-Host $line -ForegroundColor $color
}

Write-Host ''
Write-Host ("汇总：通过 {0} | 警告 {1} | 失败 {2}" -f $pass, $warn, $fail) -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 }
exit 0
