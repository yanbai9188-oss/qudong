#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$fail = 0

function Assert($name, [scriptblock]$Test) {
    try {
        if (-not (& $Test)) { Write-Host "FAIL: $name"; $script:fail++ }
        else { Write-Host "OK: $name" }
    } catch {
        Write-Host "FAIL: $name - $($_.Exception.Message)"
        $script:fail++
    }
}

$global:DriverBoosterAppRoot = $root
$script:AppRoot = $root
. (Join-Path $root 'lib\Utils.ps1')
. (Join-Path $root 'lib\AppStartup.ps1')
Assert 'AppStartup loads' { $true }
Assert 'STA thread' { [Threading.Thread]::CurrentThread.ApartmentState -eq 'STA' }

try {
    Initialize-CIODIYEngine -AppRoot $root
    . (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root
    Write-Host 'OK: Engine init'
} catch {
    Write-Host "FAIL: Engine init - $($_.Exception.Message)"
    $fail++
}

Assert 'Single instance first' { Test-CIODIYSingleInstance -AppRoot $root }
Remove-CIODIYInstanceLock
Assert 'Single instance after unlock' { Test-CIODIYSingleInstance -AppRoot $root }
Remove-CIODIYInstanceLock

$userData = Join-Path $env:LOCALAPPDATA 'CIODIY_DriverBooster'
Assert 'Data root resolves' { (Get-AppDataRoot).Length -gt 0 }
Assert 'Startup log writable' {
    Write-CIODIYStartupLog -Message 'test-stability write check' -AppRoot $root
    Test-Path (Join-Path (Get-AppDataRoot) 'Logs\startup.log')
}

powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\test-gui-startup.ps1')
if ($LASTEXITCODE -ne 0) { $fail++ } else { Write-Host 'OK: GUI startup test' }

if ($fail -gt 0) { exit 1 }
Write-Host 'test-stability.ps1 OK'
exit 0
