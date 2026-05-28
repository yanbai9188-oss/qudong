#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

$result = Invoke-BuildDriverRepository -DryRun -OnLog { param($m) Write-Host $m }
if ($result.Built.Count -lt 1) { throw 'Expected at least one buildable driver folder' }
Write-Host ("DryRun OK: built={0} skipped={1}" -f $result.Built.Count, $result.Skipped.Count)
