#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

Write-Host '=== test_install (dry) ==='

# Transaction API surface
$fakePlan = @()
$tx = Start-DriverTransaction -FixPlan $fakePlan -RollbackOnError
if (-not (Test-Path $tx.TxPath)) { throw 'tx.json not created' }
if (-not (Test-Path $tx.InstalledPath)) { throw 'installed.json not created' }

Close-DriverTransaction -Transaction $tx -FinalStatus 'committed'
$rb = Join-Path $tx.Directory 'rollback.ps1'
if (-not (Test-Path $rb)) { throw 'rollback.ps1 not generated' }

Write-Host ("PASS transaction id={0}" -f $tx.Id)
exit 0
