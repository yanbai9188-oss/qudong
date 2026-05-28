#requires -Version 5.1
$root = Split-Path $PSScriptRoot -Parent
$path = Join-Path $root 'DriverBooster.ps1'
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Host $e.ToString() }
    exit 1
}
Write-Host 'DriverBooster.ps1 PARSE OK'
exit 0
