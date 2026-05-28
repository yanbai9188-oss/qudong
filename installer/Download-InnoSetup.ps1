#requires -Version 5.1
$url = 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_2/innosetup-6.7.2.exe'
$out = Join-Path $PSScriptRoot 'innosetup-6.7.2.exe'
Write-Host "Downloading Inno Setup 6.7.2..."
Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
$item = Get-Item $out
Write-Host ("Saved: {0} ({1:N2} MB)" -f $item.FullName, ($item.Length / 1MB))
