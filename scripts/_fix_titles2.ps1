# Byte-level fix for garbled Chinese in driver_packages.json
# 甯歌 (U+752F U+6B4C) in UTF-8 = E7 94 AF E6 AD 8C
# 常见 (U+5E38 U+89C1) in UTF-8 = E5 B8 B8 E8 A7 81

$path = Join-Path (Split-Path $PSScriptRoot -Parent) 'driver_packages.json'
$bytes = [IO.File]::ReadAllBytes($path)

# Bytes to find:    甯歌 UTF-8
$find    = [byte[]]@(0xE7, 0x94, 0xAF, 0xE6, 0xAD, 0x8C)
# Bytes to replace: 常见 UTF-8
$replace = [byte[]]@(0xE5, 0xB8, 0xB8, 0xE8, 0xA7, 0x81)

$found = $false
for ($i = 0; $i -le $bytes.Length - $find.Length; $i++) {
    $match = $true
    for ($j = 0; $j -lt $find.Length; $j++) {
        if ($bytes[$i + $j] -ne $find[$j]) { $match = $false; break }
    }
    if ($match) {
        for ($j = 0; $j -lt $replace.Length; $j++) {
            $bytes[$i + $j] = $replace[$j]
        }
        Write-Host "Replaced at offset $i"
        $found = $true
        # Continue to catch multiple occurrences
        $i += $find.Length - 1
    }
}

if ($found) {
    [IO.File]::WriteAllBytes($path, $bytes)
    Write-Host 'Written OK'
} else {
    Write-Host 'Pattern not found — dumping nearby bytes for diagnosis:'
    # Search for "Win10" then show next 20 bytes
    $win10 = [Text.Encoding]::UTF8.GetBytes('Win10')
    for ($i = 0; $i -le $bytes.Length - 30; $i++) {
        $m = $true
        for ($j = 0; $j -lt $win10.Length; $j++) {
            if ($bytes[$i+$j] -ne $win10[$j]) { $m = $false; break }
        }
        if ($m) {
            $near = $bytes[$i..($i+24)]
            Write-Host ('Offset {0}: {1}' -f $i, ($near | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
        }
    }
}
