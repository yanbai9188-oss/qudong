#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$path = Join-Path (Split-Path $PSScriptRoot -Parent) 'driver_packages.json'
$m = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
$catMap = @{
    wifi     = 'network_wifi'
    lan      = 'network_lan'
    bluetooth = 'bluetooth'
    mei      = 'mei'
    chipset  = 'chipset'
    audio    = 'audio'
    media    = 'audio'
    sst      = 'audio'
    graphics = 'display'
    display  = 'display'
    serial   = 'serialio'
    storage  = 'storage'
    platform = 'platform'
    usb      = 'usb'
    touchpad = 'input'
    printer  = 'printer'
}

foreach ($prop in $m.packages.PSObject.Properties) {
    $p = $prop.Value
    $cat = if ($p.category) { [string]$p.category.ToLowerInvariant() } else { '' }
    $id = if ($p.id) { [string]$p.id.ToLowerInvariant() } else { $prop.Name.ToLowerInvariant() }
    if ($p.deviceClass) { continue }

    $cls = 'unknown'
    if ($catMap.ContainsKey($cat)) { $cls = $catMap[$cat] }
    elseif ($id -match 'wifi|7260|8260') { $cls = 'network_wifi' }
    elseif ($id -match 'bluetooth') { $cls = 'bluetooth' }
    elseif ($id -match 'mei') { $cls = 'mei' }
    elseif ($id -match 'chipset') { $cls = 'chipset' }
    elseif ($id -match 'serial') { $cls = 'serialio' }
    elseif ($id -match 'lan|8168|i219') { $cls = 'network_lan' }
    elseif ($id -match 'audio|sst') { $cls = 'audio' }
    elseif ($id -match 'graphics|nvidia|gpu') { $cls = 'display' }
    elseif ($id -match 'usb') { $cls = 'usb' }
    elseif ($id -match 'rst|storage') { $cls = 'storage' }
    elseif ($id -match 'touchpad') { $cls = 'input' }
    elseif ($id -match 'printer') { $cls = 'printer' }

    $p | Add-Member -NotePropertyName deviceClass -NotePropertyValue $cls -Force
}

($m | ConvertTo-Json -Depth 20) | Set-Content $path -Encoding UTF8
Write-Host "Patched deviceClass on manifest: $path"
