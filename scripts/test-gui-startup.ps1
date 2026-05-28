#requires -Version 5.1

$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent

$log = Join-Path $root 'Logs\gui_startup_test.log'

New-Item -ItemType Directory -Force -Path (Split-Path $log -Parent) | Out-Null



function Log($m) {

    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $m

    Add-Content -Path $log -Value $line -Encoding UTF8

    Write-Host $line

}



try {

    Log 'Load engine'

    . (Join-Path $root 'lib\AppStartup.ps1')

    Initialize-CIODIYEngine -AppRoot $root

    . (Join-Path $root 'engine\DriverEngine.ps1') -AppRoot $root

    Log 'Engine OK'



    Log 'Load WPF'

    Add-Type -AssemblyName PresentationFramework

    Add-Type -AssemblyName PresentationCore

    Add-Type -AssemblyName WindowsBase



    Log 'Load XAML'

    $xamlPath = Join-Path $root 'ui\MainWindow.xaml'

    [xml]$xaml = Get-Content -Path $xamlPath -Raw -Encoding UTF8

    $reader = New-Object System.Xml.XmlNodeReader $xaml

    $window = [Windows.Markup.XamlReader]::Load($reader)

    Log 'XAML OK'



    . (Join-Path $root 'lib\GuiState.ps1')

    $controls = Get-CIODIYGuiControlsFromWindow -Window $window

    $required = @(

        'BtnScan','BtnFixAll','BtnFixRecommended','GridDrivers','TxtLog','Progress','TxtProgress',

        'PageDashboard','PageDrivers','BtnNavDashboard','BtnNavDrivers','LstTransactions'

    )

    foreach ($n in $required) {

        if (-not $controls.ContainsKey($n)) { Log "MISSING: $n" }

    }

    Log 'FindName done'



    Log 'Load GuiDriverRow'

    . (Join-Path $root 'lib\GuiDriverRow.ps1')

    Log 'GuiDriverRow OK'



    Log 'Test DriverGridRow'

    $row = New-Object DriverGridRow

    $row.HasDependencies = $true

    Log 'DriverGridRow type OK'



    Log 'ALL OK'

    exit 0

} catch {

    Log ("FAIL: $($_.Exception.GetType().FullName): $($_.Exception.Message)")

    Log $_.ScriptStackTrace

    exit 1

}

