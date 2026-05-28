#requires -Version 5.1
# Pre-install validation: paths, versions, startup chain, core tests
param(
    [string]$AppRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'
$fail = 0
$warn = 0
$pass = 0

function Report {
    param([string]$Level, [string]$Message)
    switch ($Level) {
        'PASS' { $script:pass++; Write-Host "[PASS] $Message" -ForegroundColor Green }
        'WARN' { $script:warn++; Write-Host "[WARN] $Message" -ForegroundColor Yellow }
        'FAIL' { $script:fail++; Write-Host "[FAIL] $Message" -ForegroundColor Red }
        default { Write-Host "[$Level] $Message" }
    }
}

Write-Host ''
Write-Host '=== CIODIY Pre-Install Check ===' -ForegroundColor Cyan
Write-Host ("Root: {0}" -f $AppRoot)
Write-Host ("Time: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-Host ''

$db = Get-Content (Join-Path $AppRoot 'DriverBooster.ps1') -Raw -Encoding UTF8
$appVer = [regex]::Match($db, "\`$script:AppVersion\s*=\s*'([^']+)'").Groups[1].Value
$issVer = [regex]::Match((Get-Content (Join-Path $AppRoot 'installer\setup.iss') -Raw -Encoding UTF8), '#define MyAppVersion "([^"]+)"').Groups[1].Value
$bootVer = [regex]::Match((Get-Content (Join-Path $AppRoot 'lib\AppBootstrap.ps1') -Raw -Encoding UTF8), "app_version\s*=\s*'([^']+)'").Groups[1].Value

if ($appVer -and $appVer -eq $issVer -and $appVer -eq $bootVer) {
    Report PASS "Version aligned: v$appVer"
} else {
    Report FAIL "Version mismatch App=$appVer ISS=$issVer Bootstrap=$bootVer"
}

$readmePath = Join-Path $AppRoot '使用说明.txt'
if ((Test-Path -LiteralPath $readmePath) -and ((Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8) -match "v$appVer")) {
    Report PASS "Readme mentions v$appVer"
} else {
    Report WARN "Readme may not mention v$appVer"
}

$required = @(
    'DriverBooster.ps1', 'Launch.vbs', 'lib\Utils.ps1', 'lib\AppStartup.ps1',
    'engine\DriverEngine.ps1', 'ui\MainWindow.xaml', 'lib\GuiDriverRow.ps1', 'driver_packages.json'
)
foreach ($f in $required) {
    $full = Join-Path $AppRoot $f
    if (Test-Path -LiteralPath $full) { Report PASS "Found: $f" }
    else { Report FAIL "Missing: $f" }
}

$launcher = Get-ChildItem -LiteralPath $AppRoot -Filter '*.bat' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'Launch|启动' } | Select-Object -First 1
if ($launcher) { Report PASS ("Launcher: {0}" -f $launcher.Name) }
else { Report FAIL 'No launcher .bat found' }

. (Join-Path $AppRoot 'lib\AppStartup.ps1')

$readOnlyRoot = Join-Path $env:TEMP ("ciodiy_pf_test_$PID")
if (Test-Path $readOnlyRoot) { Remove-Item $readOnlyRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $readOnlyRoot | Out-Null
try {
    $acl = Get-Acl $readOnlyRoot
    $deny = New-Object System.Security.AccessControl.FileSystemAccessRule(
        [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
        'Write,CreateFiles,AppendData,Delete',
        'ContainerInherit,ObjectInherit',
        'None',
        'Deny'
    )
    $acl.AddAccessRule($deny)
    Set-Acl $readOnlyRoot $acl

    $resolved = Resolve-CIODIYDataRoot -AppRoot $readOnlyRoot
    if ($resolved -ne $readOnlyRoot -and $resolved -like '*CIODIY_DriverBooster*') {
        Report PASS "Read-only install redirects to: $resolved"
    } else {
        Report FAIL "Read-only redirect failed (got=$resolved)"
    }

    Write-CIODIYStartupLog -Message 'pre-install-check readonly test' -AppRoot $readOnlyRoot
    $logPath = Join-Path $resolved 'Logs\startup.log'
    if (Test-Path $logPath) { Report PASS 'startup.log writable after redirect' }
    else { Report FAIL "startup.log missing: $logPath" }

    $lockPath = Get-CIODIYInstanceLockPath -AppRoot $readOnlyRoot
    if ($lockPath -like "*$env:LOCALAPPDATA*") { Report PASS "Lock in user profile" }
    else { Report FAIL "Lock still under install dir: $lockPath" }
} catch {
    Report FAIL "Read-only simulation error: $($_.Exception.Message)"
} finally {
    if (Test-Path $readOnlyRoot) { Remove-Item $readOnlyRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

. (Join-Path $AppRoot 'lib\Utils.ps1')
$global:DriverBoosterAppRoot = $AppRoot
$script:AppRoot = $AppRoot
$script:CachedDataRoot = $null

try {
    . (Join-Path $AppRoot 'engine\DriverEngine.ps1') -AppRoot $AppRoot
    if (Get-Command Test-IsAdmin -ErrorAction SilentlyContinue) {
        Report PASS 'Engine loaded at script scope (Test-IsAdmin visible)'
    } else {
        Report FAIL 'Engine scope bug: Test-IsAdmin missing'
    }
    $data = Get-AppDataRoot
    if (Test-Path (Join-Path $data 'Cache')) { Report PASS "AppDataRoot: $data" }
    else { Report FAIL 'AppDataRoot Cache missing' }
} catch {
    Report FAIL "Engine load failed: $($_.Exception.Message)"
}

try {
    if (Test-CIODIYSingleInstance -AppRoot $AppRoot) {
        Report PASS 'Single instance lock acquired'
        Remove-CIODIYInstanceLock
    } else {
        Report WARN 'Single instance blocked (orphan process?)'
        Remove-CIODIYInstanceLock -ErrorAction SilentlyContinue
    }
} catch {
    Report FAIL "Instance lock error: $($_.Exception.Message)"
}

if ([Threading.Thread]::CurrentThread.ApartmentState -eq 'STA') {
    Report PASS 'STA thread OK for WPF'
} else {
    Report WARN 'Not STA - use launcher .bat with -Sta'
}

$vbs = Get-Content (Join-Path $AppRoot 'Launch.vbs') -Raw -Encoding UTF8
if ($vbs -match 'WindowStyle|Hidden|-WindowStyle\s+Hidden') {
    Report FAIL 'Launch.vbs still uses hidden window'
} else {
    Report PASS 'Launch.vbs uses visible window'
}

$subTests = @(
    'scripts\test-stability.ps1',
    'scripts\test-scenario.ps1',
    'tests\test_class_guard.ps1',
    'tests\test_match.ps1'
)
foreach ($t in $subTests) {
    $p = Join-Path $AppRoot $t
    if (-not (Test-Path $p)) { Report WARN "Skip missing test: $t"; continue }
    powershell -NoProfile -Sta -ExecutionPolicy Bypass -File $p | Out-Null
    if ($LASTEXITCODE -eq 0) { Report PASS "Subtest OK: $t" }
    else { Report FAIL "Subtest FAIL: $t" }
}

Write-Host ''
Write-Host ("Summary: PASS={0} WARN={1} FAIL={2}" -f $pass, $warn, $fail) -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 }
exit 0
