# Push local driver_packages.json as manifest.json to GitHub repo
param([string]$Token)

$repo    = 'yanbai9188-oss/qudong'
$branch  = 'main'
$headers = @{ Authorization = "token $Token"; Accept = 'application/vnd.github+json' }

$localPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'driver_packages.json'
$content   = [IO.File]::ReadAllText($localPath, [Text.Encoding]::UTF8)

# Get current file SHA (required for update)
$current = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/manifest.json" `
    -Headers $headers -ErrorAction SilentlyContinue
$sha = if ($current) { $current.sha } else { $null }

# Base64-encode the UTF-8 content
$bytes      = [Text.Encoding]::UTF8.GetBytes($content)
$base64     = [Convert]::ToBase64String($bytes)

$bodyObj = [PSCustomObject]@{
    message = 'manifest: update to v1.6.0 (fix garbled Chinese, add NVIDIA/Intel GPU catalog sources)'
    content = $base64
    branch  = $branch
}
if ($sha) { $bodyObj | Add-Member -NotePropertyName 'sha' -NotePropertyValue $sha }

$jsonBytes = [Text.Encoding]::UTF8.GetBytes(($bodyObj | ConvertTo-Json -Compress))

$result = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/manifest.json" `
    -Method PUT -Headers $headers -Body $jsonBytes -ContentType 'application/json; charset=utf-8'

Write-Host "Pushed manifest.json — commit: $($result.commit.sha.Substring(0,8))"
Write-Host "URL: $($result.content.html_url)"
