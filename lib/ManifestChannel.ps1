# Manifest release channels: stable / beta / dev (v1.8)

function Get-ManifestChannelConfigPath {
    return Join-Path (Join-Path (Get-AppDataRoot) 'Cache') 'manifest_channel.json'
}

function Get-ManifestChannel {
    $path = Get-ManifestChannelConfigPath
    if (Test-Path $path) {
        try {
            $cfg = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cfg.channel -in @('stable', 'beta', 'dev')) { return [string]$cfg.channel }
        } catch { }
    }
    return 'stable'
}

function Set-ManifestChannel {
    param(
        [ValidateSet('stable', 'beta', 'dev')]
        [string]$Channel = 'stable'
    )
    $path = Get-ManifestChannelConfigPath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    (@{ channel = $Channel; updated = (Get-Date -Format 'o') } | ConvertTo-Json) | Set-Content $path -Encoding UTF8
}

function Resolve-ManifestFileForChannel {
    param([string]$Channel = 'stable')

    $root = Get-AppRoot
    $data = Get-AppDataRoot
    $channelFile = "driver_packages.$Channel.json"

    $candidates = @(
        (Join-Path $data $channelFile),
        (Join-Path $root $channelFile),
        (Join-Path $data 'driver_packages.json'),
        (Join-Path $root 'driver_packages.json')
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Get-LocalManifestPathForChannel {
    param([string]$Channel = '')
    if (-not $Channel) { $Channel = Get-ManifestChannel }

    $channelPath = Resolve-ManifestFileForChannel -Channel $Channel
    if ($channelPath) { return $channelPath }

    return Get-LocalManifestPath
}
