# Preview mojibake fix for remote driver_packages.json (dry run, no push)
$utf8 = [Text.Encoding]::UTF8
$gbk  = [Text.Encoding]::GetEncoding(936)
[Console]::OutputEncoding = $utf8

# Read GitHub token via git credential
$tok = $env:GITHUB_TOKEN
if (-not $tok) {
    $tokLine = ("protocol=https`nhost=github.com`n`n" | git credential fill) |
               Where-Object { $_ -like 'password=*' }
    $tok = $tokLine -replace 'password=',''
}
if (-not $tok) { Write-Error 'No GitHub token found'; exit 1 }

$hdrs = @{ Authorization = "token $tok"; Accept = 'application/vnd.github+json' }
$meta = Invoke-RestMethod 'https://api.github.com/repos/yanbai9188-oss/qudong/contents/driver_packages.json' -Headers $hdrs
$rawBytes = [Convert]::FromBase64String(($meta.content -replace '\s',''))
[Console]::WriteLine("Downloaded $($rawBytes.Length) bytes, sha=$($meta.sha)")

# ─ Strategy B: hardcoded byte patch: 甯歌 (E7 94 AF E6 AD 8C) -> 常见 (E5 B8 B8 E8 A7 81) ─
$src = [byte[]](0xE7,0x94,0xAF,0xE6,0xAD,0x8C)
$dst = [byte[]](0xE5,0xB8,0xB8,0xE8,0xA7,0x81)
$list = [Collections.Generic.List[byte]]$rawBytes
$i = 0; $cnt = 0
while ($i -le ($list.Count - $src.Length)) {
    $ok = $true
    for ($k=0; $k -lt $src.Length -and $ok; $k++) {
        if ($list[$i+$k] -ne $src[$k]) { $ok = $false }
    }
    if ($ok) {
        $list.RemoveRange($i, $src.Length)
        $list.InsertRange($i, $dst)
        $i += $dst.Length
        $cnt++
    } else { $i++ }
}
[Console]::WriteLine("Hard-patch [E7 94 AF E6 AD 8C] => [E5 B8 B8 E8 A7 81]: $cnt occurrences")
$patchedBytes = $list.ToArray()

# ─ Strategy A: for each CJK run, get GBK bytes -> decode as UTF-8 ─
$content = $utf8.GetString($patchedBytes)

$fixCount = 0
$fixed = [Text.RegularExpressions.Regex]::Replace(
    $content,
    '(?<=:\s*")[^"]*[^\x00-\x7F][^"]*(?=")',
    [Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $val = $m.Value
        $result = [Text.RegularExpressions.Regex]::Replace(
            $val,
            '[\x80-\uFFFF]+',
            [Text.RegularExpressions.MatchEvaluator]{
                param($run)
                $r = $run.Value
                try {
                    $b = $gbk.GetBytes($r)
                    # skip if GBK encoding inserted replacement '?' bytes
                    if ($b -contains 0x3F) { return $r }
                    $d = $utf8.GetString($b)
                    if ($d -ne $r -and $d.Length -ge 1) { return $d }
                } catch {}
                return $r
            }
        )
        if ($result -ne $val) {
            $script:fixCount++
            [Console]::WriteLine("  FIX: " + $val)
            [Console]::WriteLine("    => " + $result)
        }
        return $result
    }
)

[Console]::WriteLine("Strategy A fixes: $fixCount")
[Console]::WriteLine("")
[Console]::WriteLine("=== All title lines after fix ===")
($fixed -split "`n") | Where-Object { $_ -match '"title"' } | ForEach-Object {
    [Console]::WriteLine($_.Trim())
}
