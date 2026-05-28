#requires -Version 5.1
# Unified test runner (v1.7.0)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$pass = 0
$fail = 0
$warn = 0

$tests = @(
    @{ Path = 'tests\test_ps1_parse.ps1'; Label = 'ps1_parse' }
    @{ Path = 'tests\test_scorer_frozen.ps1'; Label = 'scorer_frozen' }
    @{ Path = 'tests\test_types.ps1'; Label = 'types' }
    @{ Path = 'tests\test_driver_details.ps1'; Label = 'driver_details' }
    @{ Path = 'tests\test_class_guard.ps1'; Label = 'class_guard' }
    @{ Path = 'tests\test_match.ps1'; Label = 'match' }
    @{ Path = 'tests\test_os.ps1'; Label = 'os' }
    @{ Path = 'tests\test_scan.ps1'; Label = 'scan' }
    @{ Path = 'scripts\test-scenario.ps1'; Label = 'scenario' }
    @{ Path = 'tests\test_health.ps1'; Label = 'health' }
    @{ Path = 'tests\test_deploy.ps1'; Label = 'deploy' }
    @{ Path = 'tests\test_hardware.ps1'; Label = 'hardware' }
    @{ Path = 'tests\test_repo_builder.ps1'; Label = 'repo_builder' }
    @{ Path = 'scripts\test-stability.ps1'; Label = 'stability' }
    @{ Path = 'scripts\pre-install-check.ps1'; Label = 'pre_install' }
)

Write-Host ''
Write-Host '=== CIODIY run_all.ps1 ===' -ForegroundColor Cyan
Write-Host ("Root: {0}" -f $root)
Write-Host ''

foreach ($t in $tests) {
    $p = Join-Path $root $t.Path
    if (-not (Test-Path $p)) {
        Write-Host "[WARN] skip missing: $($t.Label)" -ForegroundColor Yellow
        $warn++
        continue
    }
    Write-Host "--- $($t.Label) ---" -ForegroundColor DarkCyan
    powershell -NoProfile -Sta -ExecutionPolicy Bypass -File $p
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[PASS] $($t.Label)" -ForegroundColor Green
        $pass++
    } else {
        Write-Host "[FAIL] $($t.Label)" -ForegroundColor Red
        $fail++
    }
    Write-Host ''
}

Write-Host ("Summary: PASS={0} FAIL={1} WARN={2}" -f $pass, $fail, $warn) -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 }
exit 0
