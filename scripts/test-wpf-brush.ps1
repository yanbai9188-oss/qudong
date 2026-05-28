Add-Type -AssemblyName PresentationFramework
$tb = New-Object System.Windows.Controls.TextBlock
try {
    $tb.Foreground = '#F87171'
    Write-Host 'string assignment: OK'
} catch {
    Write-Host ("string assignment: FAIL - " + $_.Exception.Message)
}
$brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#F87171')
$tb.Foreground = $brush
Write-Host 'brush assignment: OK'
