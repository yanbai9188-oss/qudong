#requires -Version 5.1
<#
.SYNOPSIS
  CIODIY 驱动仓库一键构建：扫描 Drivers → 校验 INF → 打 ZIP → 更新 manifest → 可选上传 Release

.EXAMPLE
  .\scripts\Publish-DriverRepo.ps1 -DryRun
  .\scripts\Publish-DriverRepo.ps1 -ManifestVersion 1.4.0 -ReleaseTag v1.2.0
  .\scripts\Publish-DriverRepo.ps1 -UploadRelease -ReleaseTag v1.2.0 -PushManifest
#>
param(
    [string]$ReleaseTag = 'v1.1.0',
    [string]$Repo = 'yanbai9188-oss/qudong',
    [string]$ManifestVersion = '',
    [string]$OutputDir = '',
    [switch]$DryRun,
    [switch]$AddNewPackages,
    [switch]$UploadRelease,
    [switch]$PushManifest,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

function Write-Step {
    param([string]$Message, [string]$Level = 'info')
    $color = switch ($Level) {
        'warn' { 'Yellow' }
        'ok'   { 'Green' }
        'err'  { 'Red' }
        default { 'Cyan' }
    }
    Write-Host $Message -ForegroundColor $color
}

Write-Step '=== CIODIY Driver Repo Builder v1.6 ==='

if (-not $SkipBuild) {
    $result = Invoke-BuildDriverRepository `
        -ReleaseTag $ReleaseTag `
        -Repo $Repo `
        -ManifestVersion $ManifestVersion `
        -OutputDir $OutputDir `
        -DryRun:$DryRun `
        -AddNewPackages:$AddNewPackages `
        -OnLog { param($m, $lvl) Write-Step $m $lvl }

    $reportPath = Write-DriverRepoBuildReport -Result $result
    Write-Step ("报告: {0}" -f $reportPath) 'ok'
    Write-Step ("打包完成: {0} 个 ZIP，跳过 {1}" -f $result.Built.Count, $result.Skipped.Count) 'ok'
} else {
    $result = [PSCustomObject]@{
        Built   = @()
        Skipped = @()
        OutputDir = if ($OutputDir) { $OutputDir } else { Join-Path $root 'qudong-repo\packages' }
        ReleaseTag = $ReleaseTag
    }
}

if ($DryRun) {
    Write-Step 'DryRun 模式，未写入 manifest / 未上传。' 'warn'
    exit 0
}

if ($UploadRelease) {
    $publishScript = Join-Path $root 'qudong-repo\Publish-Release.ps1'
    if (-not (Test-Path $publishScript)) { throw "缺少 $publishScript" }

    Write-Step '=== 上传到 GitHub Release ==='
    $pubParams = @{
        Tag       = $ReleaseTag
        Repo      = $Repo
        SkipBuild = $true
    }
    if (-not $PushManifest) { $pubParams.SkipPush = $true }
    & $publishScript @pubParams
} elseif ($PushManifest) {
    $repoDir = Join-Path $root 'qudong-repo'
    if (Test-Path (Join-Path $repoDir '.git')) {
        Push-Location $repoDir
        git add manifest.json driver_packages.json 2>$null
        $st = git status --porcelain
        if ($st) {
            git commit -m "Update driver manifest via Publish-DriverRepo ($ReleaseTag)"
            git push origin main
            Write-Step 'manifest 已 push 到 qudong-repo。' 'ok'
        } else {
            Write-Step 'manifest 无变更，跳过 push。' 'warn'
        }
        Pop-Location
    } else {
        Write-Step 'qudong-repo 非 git 仓库，跳过 PushManifest。' 'warn'
    }
}

Write-Step '完成。' 'ok'
