# Registers (or updates) the YanbaiDriverWorker scheduled task.
# Must run as administrator — called automatically by the Inno Setup installer.
#
# The task runs as SYSTEM (highest privilege) but only when explicitly triggered by
# the GUI via Start-ScheduledTask.  It exits automatically after being idle for 60 s,
# so it is NOT a persistent background service eating memory at all times.

param([string]$AppDir = 'C:\Program Files\Yanbai_Driver')

$ErrorActionPreference = 'Stop'

$ps     = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
# Quote the script path so it works when AppDir contains spaces (e.g. C:\Program Files\…)
$scriptQ = '"' + "$AppDir\lib\ServiceWorker.ps1" + '"'
$argStr  = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $scriptQ -IdleTimeoutSeconds 60"

$action    = New-ScheduledTaskAction -Execute $ps -Argument $argStr -WorkingDirectory $AppDir
$settings  = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 8) `
    -MultipleInstances  IgnoreNew `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable:$false `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

# Register (or overwrite) the task silently
Register-ScheduledTask `
    -TaskName   'YanbaiDriverWorker' `
    -TaskPath   '\' `
    -Action     $action `
    -Settings   $settings `
    -Principal  $principal `
    -Description 'Yanbai Driver — background install worker (SYSTEM). Started on demand by the GUI; exits after 60 s idle.' `
    -Force | Out-Null

Write-Host 'YanbaiDriverWorker task registered OK'

# Write a marker file so the GUI can detect registration without needing Get-ScheduledTask
$svcDir  = "$env:ProgramData\Yanbai_Driver"
$flagDir = $svcDir
if (-not (Test-Path $flagDir)) { New-Item -ItemType Directory -Force -Path $flagDir | Out-Null }
[System.IO.File]::WriteAllText("$flagDir\service_registered.flag", (Get-Date -Format 'o'))
Write-Host 'Marker file written'
