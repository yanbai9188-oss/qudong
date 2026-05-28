# Fix garbled Chinese titles in driver_packages.json
# Saved as UTF-8 - replacement strings are read correctly

$path    = Join-Path (Split-Path $PSScriptRoot -Parent) 'driver_packages.json'
$content = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)

# 甯歌 (U+752F U+6B4C) are UTF-8 bytes of 常见 misread as GBK
$garbled1 = [char]0x752F + [char]0x6B4C   # 甯歌
$fixed    = $content.Replace($garbled1, '常见')

$changed = ($fixed -ne $content)
if ($changed) {
    [IO.File]::WriteAllText($path, $fixed, [Text.Encoding]::UTF8)
    Write-Host 'Fixed: 甯歌 → 常见'
    $content = $fixed
}

# Show all title lines so we can verify
$lines = $content -split [Environment]::NewLine
$lines | Where-Object { $_ -match '"title"' } | ForEach-Object { Write-Host $_.Trim() }

if (-not $changed) { Write-Host '(no changes needed)' }
