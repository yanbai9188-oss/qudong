$targets = @(
    'lib\DriverDownloader.ps1',
    'lib\ServiceWorker.ps1',
    'lib\JobQueue.ps1',
    'lib\GuiWorkers.ps1',
    'lib\GuiEvents.ps1',
    'lib\GuiPages.ps1',
    'lib\GuiState.ps1',
    'lib\AppBootstrap.ps1',
    'lib\CatalogDownloader.ps1'
)
$root = Split-Path $PSScriptRoot -Parent
$bom  = [byte[]](0xEF, 0xBB, 0xBF)
foreach ($rel in $targets) {
    $path = Join-Path $root $rel
    if (-not (Test-Path $path)) { Write-Host "SKIP (not found): $rel"; continue }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Host "BOM OK: $rel"
    } else {
        $newBytes = $bom + $bytes
        [System.IO.File]::WriteAllBytes($path, $newBytes)
        Write-Host "BOM added: $rel"
    }
}
Write-Host 'Done.'
