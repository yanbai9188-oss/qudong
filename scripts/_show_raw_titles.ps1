# Show all title lines from remote driver_packages.json as-is (no fixes)
$utf8 = [Text.Encoding]::UTF8
[Console]::OutputEncoding = $utf8

$tok = $env:GITHUB_TOKEN
if (-not $tok) {
    $tokLine = ("protocol=https`nhost=github.com`n`n" | git credential fill) |
               Where-Object { $_ -like 'password=*' }
    $tok = $tokLine -replace 'password=',''
}
$hdrs = @{ Authorization = "token $tok"; Accept = 'application/vnd.github+json' }
$meta = Invoke-RestMethod 'https://api.github.com/repos/yanbai9188-oss/qudong/contents/driver_packages.json' -Headers $hdrs
$content = $utf8.GetString([Convert]::FromBase64String(($meta.content -replace '\s','')))

[Console]::WriteLine("=== Raw titles from remote driver_packages.json ===")
($content -split "`n") | Where-Object { $_ -match '"title"' } | ForEach-Object {
    [Console]::WriteLine($_.Trim())
}
