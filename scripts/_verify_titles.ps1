[Console]::OutputEncoding = [Text.Encoding]::UTF8
$content = [IO.File]::ReadAllText(
    (Join-Path (Split-Path $PSScriptRoot -Parent) 'driver_packages.json'),
    [Text.Encoding]::UTF8
)
$lines = $content -split "`n"
$lines | Where-Object { $_ -match '"title"' } | ForEach-Object {
    [Console]::WriteLine($_.Trim())
}
