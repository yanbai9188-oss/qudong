#requires -Version 5.1
# Verify all lib/*.ps1 parse under PowerShell 5.1 (encoding safety)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fail = 0

Get-ChildItem (Join-Path $root 'lib') -Filter '*.ps1' | ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        Write-Host "[FAIL] $($_.Name): $($errors[0].Message)" -ForegroundColor Red
        $fail++
    } else {
        Write-Host "[PASS] $($_.Name)" -ForegroundColor Green
    }
}

if ($fail -gt 0) { exit 1 }
Write-Host "All lib scripts parse OK"
exit 0
