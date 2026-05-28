$bom = [byte[]](0xEF,0xBB,0xBF)
$files = @(
    'lib\ServiceWorker.ps1',
    'lib\DriverDownloader.ps1',
    'lib\CatalogDownloader.ps1',
    'lib\JobQueue.ps1',
    'lib\GuiEvents.ps1',
    'lib\GuiWorkers.ps1',
    'lib\GuiRender.ps1',
    'lib\DriverScorer.ps1',
    'lib\DriverMatcher.ps1',
    'scripts\install-task.ps1'
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
