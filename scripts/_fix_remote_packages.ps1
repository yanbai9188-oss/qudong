# Fix ONLY the known mojibake garbled Chinese in remote driver_packages.json
# All byte sequences are taken directly from the actual file content.

$utf8 = [Text.Encoding]::UTF8
[Console]::OutputEncoding = $utf8

$tok = $env:GITHUB_TOKEN
if (-not $tok) {
    $tokLine = ("protocol=https`nhost=github.com`n`n" | git credential fill) |
               Where-Object { $_ -like 'password=*' }
    $tok = $tokLine -replace 'password=',''
}
if (-not $tok) { Write-Error 'No GitHub token'; exit 1 }

$repo = 'yanbai9188-oss/qudong'
$hdrs = @{ Authorization = "token $tok"; Accept = 'application/vnd.github+json' }

[Console]::WriteLine('Downloading driver_packages.json...')
$meta    = Invoke-RestMethod "https://api.github.com/repos/$repo/contents/driver_packages.json" -Headers $hdrs
$fileSha = $meta.sha
$raw     = [byte[]][Convert]::FromBase64String(($meta.content -replace '\s',''))
[Console]::WriteLine("  $($raw.Length) bytes  sha=$fileSha")

# ── Patch table: (SrcHex, DstHex, Description) ───────────────────────────────
# IMPORTANT: apply longer/more-specific patches first to avoid partial matches.
$patches = @(
    # 1. HP: 閫氱敤鎵撳嵃椹卞姩 (27 bytes) → 通用打印驱动 (18 bytes)
    @{
        Src = '  E9 96 AB  E6 B0 B1  E6 95 A4  E9 8E B5  E6 92 B3  E5 B5 83  E6 A4 B9  E5 8D 9E  E5 A7 A9'
        Dst = '  E9 80 9A  E7 94 A8  E6 89 93  E5 8D B0  E9 A9 B1  E5 8A A8'
        Desc= '閫氱敤鎵撳嵃椹卞姩 -> 通用打印驱动'
    }
    # 2. WiFi: 甯歌+PUA (E7 94 AF E6 AD 8C EE 9D 86, 9 bytes) → 常见 (6 bytes)
    @{
        Src = '  E7 94 AF  E6 AD 8C  EE 9D 86'
        Dst = '  E5 B8 B8  E8 A7 81'
        Desc= '甯歌[PUA] -> 常见'
    }
    # 3. USB xHCI chipset: 鑺[PUA]墖缁? (12 bytes) → 芯片组 (10 bytes, with trailing space)
    #    File bytes: E9 91 BA  EE 88 9C  E5 A2 96  E7 BC 81  3F  (12 bytes, ends before USB)
    @{
        Src = '  E9 91 BA  EE 88 9C  E5 A2 96  E7 BC 81  3F'
        Dst = '  E8 8A AF  E7 89 87  E7 BB 84  20'
        Desc= '鑺[PUA]墖缁? -> 芯片组 '
    }
    # 4. USB batch / Canon: 鎵归噺 (9 bytes, E9 8E B5 E5 BD 92 E5 99 BA) → 批量
    #    Only the "Win10 批量" part of the USB title; different continuation than Canon
    @{
        Src = '  E9 8E B5  E5 BD 92  E5 99 BA'
        Dst = '  E6 89 B9  E9 87 8F'
        Desc= '鎵归噺 -> 批量'
    }
    # 5. Canon: 鎵撳嵃椹卞姩 (18 bytes) → 打印驱动 (12 bytes)
    @{
        Src = '  E9 8E B5  E6 92 B3  E5 B5 83  E6 A4 B9  E5 8D 9E  E5 A7 A9'
        Dst = '  E6 89 93  E5 8D B0  E9 A9 B1  E5 8A A8'
        Desc= '鎵撳嵃椹卞姩 -> 打印驱动'
    }
)

function Convert-HexString([string]$hexStr) {
    ($hexStr.Trim() -split '\s+') | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) }
}

$list = [Collections.Generic.List[byte]]$raw

foreach ($p in $patches) {
    $src = [byte[]](Convert-HexString $p.Src)
    $dst = [byte[]](Convert-HexString $p.Dst)
    $i = 0; $cnt = 0
    while ($i -le ($list.Count - $src.Length)) {
        $ok = $true
        for ($k = 0; $k -lt $src.Length -and $ok; $k++) {
            if ($list[$i+$k] -ne $src[$k]) { $ok = $false }
        }
        if ($ok) {
            $list.RemoveRange($i, $src.Length)
            $list.InsertRange($i, $dst)
            $i += $dst.Length; $cnt++
        } else { $i++ }
    }
    [Console]::WriteLine("  [$cnt] $($p.Desc)")
}

$patched = $utf8.GetString($list.ToArray())

# ── Show all titles ───────────────────────────────────────────────────────────
[Console]::WriteLine('')
[Console]::WriteLine('=== All titles after fix ===')
($patched -split "`n") | Where-Object { $_ -match '"title"' } | ForEach-Object {
    [Console]::WriteLine($_.Trim())
}

# ── Push ──────────────────────────────────────────────────────────────────────
[Console]::WriteLine('')
[Console]::WriteLine('Pushing to GitHub...')
$newBase64 = [Convert]::ToBase64String($utf8.GetBytes($patched))
$bodyBytes  = $utf8.GetBytes(([PSCustomObject]@{
    message = 'driver_packages: fix all mojibake garbled Chinese in title fields'
    content = $newBase64
    sha     = $fileSha
    branch  = 'main'
} | ConvertTo-Json -Compress))

$r = Invoke-RestMethod "https://api.github.com/repos/$repo/contents/driver_packages.json" `
    -Method PUT -Headers $hdrs -Body $bodyBytes -ContentType 'application/json; charset=utf-8'
[Console]::WriteLine("Done! Commit: $($r.commit.sha.Substring(0,8))")
[Console]::WriteLine("URL: $($r.content.html_url)")
