#requires -Version 5.1
param([string]$AppDir = 'C:\Program Files\Yanbai_Driver')

$ErrorActionPreference = 'Stop'
$icon = Join-Path $AppDir 'ui\yanbai.ico'
if (-not (Test-Path $icon)) { throw "Icon not found: $icon" }

$shell = New-Object -ComObject WScript.Shell
$iconLoc = "$icon,0"
$fixed = 0

$roots = @(
    [Environment]::GetFolderPath('CommonDesktopDirectory'),
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('CommonPrograms'),
    [Environment]::GetFolderPath('Programs')
)

foreach ($root in ($roots | Select-Object -Unique)) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem $root -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $sc = $shell.CreateShortcut($_.FullName)
            if ($sc.TargetPath -notlike '*wscript.exe*') { return }
            if ($sc.Arguments -notlike '*Launch.vbs*') { return }
            $sc.IconLocation = $iconLoc
            $sc.Save()
            $script:fixed++
            Write-Host "Fixed: $($_.FullName)"
        } catch {
            Write-Warning "Skip $($_.FullName): $($_.Exception.Message)"
        }
    }
}

if (Test-Path (Join-Path $AppDir 'DriverBooster.ps1')) {
    $src = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'DriverBooster.ps1'
    if (-not (Test-Path $src)) {
        $src = Join-Path (Split-Path $PSScriptRoot -Parent) 'DriverBooster.ps1'
    }
    if ((Test-Path $src) -and ($src -ne (Join-Path $AppDir 'DriverBooster.ps1'))) {
        Copy-Item $src (Join-Path $AppDir 'DriverBooster.ps1') -Force -ErrorAction SilentlyContinue
    }
}

$iconSrc = Join-Path (Split-Path $PSScriptRoot -Parent) 'ui\yanbai.ico'
if (-not (Test-Path $iconSrc)) { $iconSrc = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'ui\yanbai.ico' }
if (Test-Path $iconSrc) {
    Copy-Item $iconSrc $icon -Force
    Write-Host "Updated icon: $icon"
}

Write-Host "Done. Fixed $fixed shortcut(s)."
