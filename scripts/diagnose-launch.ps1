#requires -Version 5.1
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
$report = Join-Path $root 'Logs\diagnose.log'
New-Item -ItemType Directory -Force -Path (Join-Path $root 'Logs') | Out-Null

function R($m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Add-Content $report $line -Encoding UTF8
    Write-Host $line
}

R "=== DIAGNOSE START ==="
R "Root: $root"
R "PSVersion: $($PSVersionTable.PSVersion)"
R "STA: $([Threading.Thread]::CurrentThread.ApartmentState)"
R "Is64: $([Environment]::Is64BitProcess)"

# lock file
$lock = Join-Path $root 'Cache\app.lock'
if (Test-Path $lock) {
    R "LOCK EXISTS: $(Get-Content $lock -Raw)"
} else {
    R "No app.lock"
}

# parse DriverBooster
R "Parse DriverBooster..."
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'DriverBooster.ps1'), [ref]$null, [ref]$errs)
if ($errs) { foreach ($e in $errs) { R "PARSE ERR: $e" } } else { R "Parse OK" }

# load startup + engine
try {
    . (Join-Path $root 'lib\AppStartup.ps1')
    Initialize-CIODIYEngine -AppRoot $root
    . (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root
    R "Engine OK, Test-IsAdmin=$(Get-Command Test-IsAdmin -EA SilentlyContinue)"
} catch {
    R "ENGINE FAIL: $($_.Exception.Message)"
    exit 1
}

# single instance
$ok = Test-CIODIYSingleInstance -AppRoot $root
R "SingleInstance: $ok"
if (-not $ok) { R "BLOCKED by duplicate instance" }

# try GUI init without ShowDialog
try {
    Add-Type -AssemblyName PresentationFramework
    [xml]$xaml = Get-Content (Join-Path $root 'ui\MainWindow.xaml') -Raw -Encoding UTF8
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    R "XAML OK"
    . (Join-Path $root 'lib\GuiDriverRow.ps1')
    R "GuiDriverRow OK"
    Remove-CIODIYInstanceLock
} catch {
    R "GUI INIT FAIL: $($_.Exception.Message)"
    R $_.ScriptStackTrace
    Remove-CIODIYInstanceLock
    exit 1
}

# full launch 8 sec timeout via job
R "Launching DriverBooster (8s)..."
$job = Start-Job -ScriptBlock {
    param($p)
    & powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File $p
} -ArgumentList (Join-Path $root 'DriverBooster.ps1')
Wait-Job $job -Timeout 8 | Out-Null
if ($job.State -eq 'Running') {
    R "DriverBooster still running after 8s (GOOD - GUI likely open)"
    Stop-Job $job -EA SilentlyContinue
    Remove-Job $job -Force -EA SilentlyContinue
} else {
    $out = Receive-Job $job 2>&1
    R "DriverBooster exited early:"
    foreach ($line in @($out)) { R "  $line" }
    Remove-Job $job -Force -EA SilentlyContinue
}

R "=== DIAGNOSE END ==="
