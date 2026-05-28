# Publish-Release.ps1 — Create GitHub release with proper UTF-8 encoding
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Publish-Release.ps1 -Version "2.x.x"
#
# IMPORTANT: This file must be saved as UTF-8 (no BOM).
# All Chinese strings here will be read correctly because PowerShell -File reads UTF-8.

param(
    [Parameter(Mandatory)][string]$Version,
    [string]$ExeSuffix    = 'Online',
    [string]$Repo         = 'yanbai9188-oss/qudong',
    [string]$NotesFile    = '',    # optional path to a .md file with release notes
    [string]$NoteBody     = '',    # optional inline release notes (ASCII only)
    [switch]$Draft,
    [switch]$Prerelease
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Token ────────────────────────────────────────────────────────────────────
$inp   = "protocol=https`nhost=github.com`n`n"
$token = ($inp | git credential fill) | Where-Object { $_ -like 'password=*' }
$token = $token -replace 'password=', ''
if (-not $token) { throw '无法获取 GitHub token，请先 git credential 登录' }

$headers = @{ Authorization = "token $token"; Accept = 'application/vnd.github+json' }

# ── Find installer EXE ───────────────────────────────────────────────────────
$root   = Split-Path $PSScriptRoot -Parent
$exeName = "Yanbai_Driver_Setup_${ExeSuffix}_${Version}.exe"
$exePath = Join-Path $root $exeName
if (-not (Test-Path $exePath)) { throw "找不到安装包: $exePath" }

$sha256 = (Get-FileHash $exePath -Algorithm SHA256).Hash.ToLower()
Write-Host "[PUBLISH] $exeName  SHA256=$sha256"

# ── Build release notes ──────────────────────────────────────────────────────
if ($NotesFile -and (Test-Path $NotesFile)) {
    $body = Get-Content $NotesFile -Raw -Encoding UTF8
} elseif ($NoteBody) {
    $body = $NoteBody
} else {
    $body = "Yanbai Driver $Version`n`nSHA256: $sha256"
}

# ── Create release (UTF-8 JSON via bytes to avoid GBK encoding bug) ──────────
$releaseObj = [PSCustomObject]@{
    tag_name   = "v$Version"
    name       = "Yanbai Driver v$Version"
    body       = $body
    draft      = [bool]$Draft
    prerelease = [bool]$Prerelease
}
$jsonBytes = [System.Text.Encoding]::UTF8.GetBytes(($releaseObj | ConvertTo-Json -Compress))

Write-Host "[PUBLISH] 创建 Release v$Version..."
$rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" `
    -Method POST -Headers $headers -Body $jsonBytes -ContentType 'application/json; charset=utf-8'
Write-Host "[PUBLISH] Release 创建成功 ID=$($rel.id) tag=$($rel.tag_name)"

# ── Upload installer ──────────────────────────────────────────────────────────
Write-Host "[PUBLISH] 上传 $exeName ($([Math]::Round((Get-Item $exePath).Length/1MB,2)) MB)..."
$uploadUrl = $rel.upload_url -replace '\{\?name,label\}', "?name=$exeName"
$bytes     = [IO.File]::ReadAllBytes($exePath)
$asset     = Invoke-RestMethod -Uri $uploadUrl -Method POST `
    -Headers ($headers + @{ 'Content-Type' = 'application/octet-stream' }) -Body $bytes
Write-Host "[PUBLISH] 上传完成: $($asset.browser_download_url)"
Write-Host "[PUBLISH] Release URL: $($rel.html_url)"
