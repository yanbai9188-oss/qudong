$f = 'c:\Users\admin\Desktop\YanbaiDriverSetup\scripts\_update_manifest.ps1'
$f2 = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\_update_manifest.ps1'
$target = if (Test-Path $f2) { $f2 } else { $f }
$bom = [byte[]](0xEF,0xBB,0xBF)
$b = [IO.File]::ReadAllBytes($target)
if ($b[0] -ne 0xEF) { [IO.File]::WriteAllBytes($target, ($bom + $b)); Write-Host 'BOM added' }
else { Write-Host 'Already has BOM' }
