# Build-Installer.ps1 — clean staging, sync source files, compile installer
# Usage: .\scripts\Build-Installer.ps1 -Version 1.9.5
#
# What this script does:
#   1. Validates version parameter
#   2. Updates version in DriverBooster.ps1 and setup.iss
#   3. Completely wipes staging (no leftover runtime state)
#   4. Copies only the files that belong in the installer
#   5. Verifies no runtime dirs leaked into staging
#   6. Runs InnoSetup to compile the installer
#   7. Prints SHA256 of the output EXE

param(
    [Parameter(Mandatory)][string]$Version,
    [switch]$SkipCompile,   # Set to just sync staging without building the EXE
    [switch]$NoHash         # Skip SHA256 output
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

function Write-Step { param([string]$msg) Write-Host "`n[BUILD] $msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Fail { param([string]$msg) Write-Host "  [!!] $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# 1. Validate version
# ---------------------------------------------------------------------------
Write-Step "Validating version '$Version'..."
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    Write-Fail "Version must be in X.Y.Z format (e.g. 1.9.5)"
}
Write-OK "Version OK"

# ---------------------------------------------------------------------------
# 2. Update version strings in source
# ---------------------------------------------------------------------------
Write-Step "Updating version strings..."

$mainScript = Join-Path $root 'DriverBooster.ps1'
$content = Get-Content $mainScript -Raw -Encoding UTF8
$content = $content -replace "\`$script:AppVersion\s*=\s*'[^']*'", "`$script:AppVersion = '$Version'"
Set-Content $mainScript -Value $content -Encoding UTF8 -NoNewline
Write-OK "DriverBooster.ps1 -> $Version"

$issFile = Join-Path $root 'installer\setup.iss'
$iss = Get-Content $issFile -Raw -Encoding UTF8
$iss = $iss -replace '#define MyAppVersion "[^"]*"', "#define MyAppVersion `"$Version`""
Set-Content $issFile -Value $iss -Encoding UTF8 -NoNewline
Write-OK "setup.iss -> $Version"

# ---------------------------------------------------------------------------
# 3. Wipe staging completely
# ---------------------------------------------------------------------------
$staging = Join-Path $root 'installer\staging'
Write-Step "Wiping staging directory..."
if (Test-Path $staging) {
    Remove-Item $staging -Recurse -Force
    Write-OK "Staging wiped"
}
New-Item -ItemType Directory -Path $staging | Out-Null
Write-OK "Staging re-created (empty)"

# ---------------------------------------------------------------------------
# 4. Copy source files into staging
# ---------------------------------------------------------------------------
Write-Step "Copying source files to staging..."

# Files/dirs that belong in the installer (never copy runtime dirs)
$include = @(
    'DriverBooster.ps1',
    'Launch.vbs',
    'driver_packages.json',
    'driver_mirror.json',
    '使用说明.txt',
    'engine',
    'lib',
    'ui',
    'deploy',
    'tools',
    'scripts'
)

# Runtime dirs that must NEVER appear in staging
$runtimeDirs = @('Cache', 'Logs', 'Transactions', 'DriverBackup', 'Drivers', 'DriverTemp')

foreach ($item in $include) {
    $src = Join-Path $root $item
    $dst = Join-Path $staging $item
    if (-not (Test-Path $src)) {
        Write-Host "  [SKIP] $item (not found)" -ForegroundColor Yellow
        continue
    }
    if ((Get-Item $src).PSIsContainer) {
        Copy-Item $src $dst -Recurse -Force
    } else {
        Copy-Item $src $dst -Force
    }
    Write-OK "Copied: $item"
}

# Keep only install-task.ps1 from the scripts directory; all other scripts
# (build helpers, upload utilities, test scripts) must not ship to end-users.
$stagingScripts = Join-Path $staging 'scripts'
if (Test-Path $stagingScripts) {
    Get-ChildItem $stagingScripts -File | Where-Object { $_.Name -ne 'install-task.ps1' } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] scripts\ trimmed — only install-task.ps1 kept" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 5. Verify no runtime dirs leaked in
# ---------------------------------------------------------------------------
Write-Step "Verifying staging is clean..."
$leaked = @()
foreach ($d in $runtimeDirs) {
    if (Test-Path (Join-Path $staging $d)) { $leaked += $d }
}
# Also check nested inside copied dirs
foreach ($d in $runtimeDirs) {
    Get-ChildItem $staging -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $d } |
        ForEach-Object { $leaked += $_.FullName.Replace($staging + '\', '') }
}
if ($leaked.Count -gt 0) {
    Write-Fail "Runtime dirs found in staging:`n  $($leaked -join "`n  ")`nAborting build."
}
Write-OK "Staging is clean — no runtime dirs"

# ---------------------------------------------------------------------------
# 6. Show staging file count
# ---------------------------------------------------------------------------
$fileCount = (Get-ChildItem $staging -Recurse -File).Count
Write-OK "Staging contains $fileCount files"

if ($SkipCompile) {
    Write-Step "SkipCompile flag set — stopping before InnoSetup"
    exit 0
}

# ---------------------------------------------------------------------------
# 7. Compile installer with InnoSetup
# ---------------------------------------------------------------------------
Write-Step "Running InnoSetup..."

$innoCmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
$innoExe = @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    $(if ($innoCmd) { $innoCmd.Source } else { $null })
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $innoExe) {
    Write-Fail "InnoSetup (ISCC.exe) not found. Install from https://jrsoftware.org/isinfo.php"
}
Write-OK "InnoSetup found: $innoExe"

$issPath = Join-Path $root 'installer\setup.iss'
$proc = Start-Process -FilePath $innoExe -ArgumentList "`"$issPath`"" -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0) {
    Write-Fail "InnoSetup exited with code $($proc.ExitCode)"
}
Write-OK "InnoSetup compile succeeded"

# ---------------------------------------------------------------------------
# 8. Print output file + SHA256
# ---------------------------------------------------------------------------
$suffix = "_Online"
$outExe = Join-Path $root "Yanbai_Driver_Setup${suffix}_${Version}.exe"
if (-not (Test-Path $outExe)) {
    # Try without suffix
    $outExe = Join-Path $root "Yanbai_Driver_Setup_${Version}.exe"
}
if (Test-Path $outExe) {
    $sizeMB = [math]::Round((Get-Item $outExe).Length / 1MB, 2)
    Write-Step "Output: $outExe ($sizeMB MB)"
    if (-not $NoHash) {
        $hash = (Get-FileHash $outExe -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-OK "SHA256: $hash"
    }
} else {
    Write-Host "  [WARN] Output EXE not found at expected path." -ForegroundColor Yellow
}

Write-Host "`n[BUILD] Done — Yanbai Driver $Version" -ForegroundColor Green
