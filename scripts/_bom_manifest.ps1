$f = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\_update_manifest.ps1'
$bom = [byte[]](0xEF, 0xBB, 0xBF)
$b = [System.IO.File]::ReadAllBytes($f)
if ($b[0] -ne 0xEF) {
    [System.IO.File]::WriteAllBytes($f, ($bom + $b))
    Write-Host 'BOM added to _update_manifest.ps1'
} else {
    Write-Host '_update_manifest.ps1 already has BOM'
}
