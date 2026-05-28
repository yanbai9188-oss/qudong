[Console]::OutputEncoding = [Text.Encoding]::UTF8
$tok = $env:GITHUB_TOKEN
if (-not $tok) {
    $tokLine = ("protocol=https`nhost=github.com`n`n" | git credential fill) |
               Where-Object { $_ -like 'password=*' }
    $tok = $tokLine -replace 'password=',''
}
$hdrs = @{ Authorization = "token $tok"; Accept = 'application/vnd.github+json' }
$rel = Invoke-RestMethod 'https://api.github.com/repos/yanbai9188-oss/qudong/releases/tags/v1.1.0' -Headers $hdrs
$assets = $rel.assets
[Console]::WriteLine("Total assets: $($assets.Count)")
foreach ($a in $assets) {
    [Console]::WriteLine("$($a.name)  size=$([Math]::Round($a.size/1KB,1))KB  url=$($a.browser_download_url)")
}
