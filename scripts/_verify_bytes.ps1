# Verify byte sequences for garbled strings by downloading file and checking
$utf8 = [Text.Encoding]::UTF8
[Console]::OutputEncoding = $utf8

$tok = $env:GITHUB_TOKEN
if (-not $tok) {
    $tokLine = ("protocol=https`nhost=github.com`n`n" | git credential fill) |
               Where-Object { $_ -like 'password=*' }
    $tok = $tokLine -replace 'password=',''
}
$hdrs = @{ Authorization = "token $tok"; Accept = 'application/vnd.github+json' }
$meta  = Invoke-RestMethod 'https://api.github.com/repos/yanbai9188-oss/qudong/contents/driver_packages.json' -Headers $hdrs
$raw   = [byte[]][Convert]::FromBase64String(($meta.content -replace '\s',''))
$text  = $utf8.GetString($raw)

# Find each garbled title and show surrounding bytes
function Show-BytesAround([string]$needle, [byte[]]$data, [string]$enc, [int]$ctx = 3) {
    $needleBytes = [Text.Encoding]::GetEncoding($enc).GetBytes($needle)
    for ($i = 0; $i -le ($data.Length - $needleBytes.Length); $i++) {
        $ok = $true
        for ($k = 0; $k -lt $needleBytes.Length -and $ok; $k++) {
            if ($data[$i+$k] -ne $needleBytes[$k]) { $ok = $false }
        }
        if ($ok) {
            $start = [Math]::Max(0, $i-$ctx)
            $end   = [Math]::Min($data.Length-1, $i+$needleBytes.Length+$ctx-1)
            $hexStr = ($data[$start..$end] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
            [Console]::WriteLine("  Found at offset $i (context): $hexStr")
            return $needleBytes
        }
    }
    [Console]::WriteLine("  NOT FOUND")
    return $null
}

# Grab the raw bytes for the 4 garbled text fragments we want to fix
$garbledTitles = @{
    'USB_xHCI_line' = 'Intel USB 3.0 xHCI'   # search for this, then show surrounding
    'WiFi_8260_line' = 'Intel WiFi AC 8260/8265'
    'HP_line'       = 'HP LaserJet / PCL '
    'Canon_line'    = 'Canon imageCLASS / UFRII '
}

foreach ($key in $garbledTitles.Keys) {
    $q = $garbledTitles[$key]
    [Console]::WriteLine("=== $key ===")
    # Find the byte position of the ASCII part, then read subsequent bytes
    $asciiBytes = $utf8.GetBytes($q)
    for ($i = 0; $i -le ($raw.Length - $asciiBytes.Length); $i++) {
        $ok = $true
        for ($k = 0; $k -lt $asciiBytes.Length -and $ok; $k++) {
            if ($raw[$i+$k] -ne $asciiBytes[$k]) { $ok = $false }
        }
        if ($ok) {
            # Show 60 bytes from this position
            $end = [Math]::Min($raw.Length-1, $i+$asciiBytes.Length+59)
            $chunk = $raw[$i..($end)]
            $hexStr = ($chunk | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
            [Console]::WriteLine("  Hex: $hexStr")
            $chunkStr = $utf8.GetString($chunk)
            [Console]::WriteLine("  Str: $chunkStr")
            break
        }
    }
}
