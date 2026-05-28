Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
$root = Split-Path $PSScriptRoot -Parent
[xml]$xaml = Get-Content (Join-Path $root 'ui\MainWindow.xaml') -Raw -Encoding UTF8
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$appCurrent = [System.Windows.Application]::Current
Write-Host ("Application.Current is null: " + ($null -eq $appCurrent))
try {
    if ($appCurrent) {
        [void]$appCurrent.add_DispatcherUnhandledException({ param($s,$e) })
        Write-Host 'App.Current handler: OK'
    } else {
        Write-Host 'App.Current handler: SKIPPED (null)'
    }
} catch {
    Write-Host ("App.Current handler: FAIL - " + $_.Exception.Message)
}
try {
    $handler = [System.Windows.Threading.DispatcherUnhandledExceptionEventHandler]{
        param($sender, $e)
        $e.Handled = $true
    }
    $window.Dispatcher.add_UnhandledException($handler)
    Write-Host 'Window.Dispatcher handler: OK'
} catch {
    Write-Host ("Window.Dispatcher handler: FAIL - " + $_.Exception.Message)
}
