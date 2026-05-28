$bom = [byte[]](0xEF, 0xBB, 0xBF)
$files = @(
    'lib\DriverScanner.ps1',
    'engine\DriverEngine.ps1',
    'lib\AppController.ps1'
)
$root = Split-Path $PSScriptRoot -Parent
foreach ($rel in $files) {
    $f = Join-Path $root $rel
    if (-not (Test-Path $f)) { Write-Host "NOT FOUND: $rel"; continue }
    $bytes = [IO.File]::ReadAllBytes($f)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Host "Already BOM: $rel"
    } else {
        [IO.File]::WriteAllBytes($f, ($bom + $bytes))
        Write-Host "BOM added:   $rel"
    }
}
