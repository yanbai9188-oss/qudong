# GUI render / panel updates (v1.7.0)

function ConvertTo-CIODIYGuiBrush {
    param([string]$Color)
    ConvertTo-CIODIYBrush -Color $Color
}

function Update-CIODIYDriverSourcePanel {
    $ctx = Get-CIODIYGuiContext
    $status = Get-DriverSourceStatusEngine -Manifest $ctx.State.Manifest
    $txtDriverSource = Get-CIODIYGuiControl -Name 'TxtDriverSource'
    $txtSourceDetail = Get-CIODIYGuiControl -Name 'TxtSourceDetail'
    if ($txtDriverSource) { $txtDriverSource.Text = $status.SourceLabel }
    if ($txtSourceDetail) { $txtSourceDetail.Text = $status.SummaryLine }
}

function Update-CIODIYHardwareProfilePanel {
    $hw = Get-HardwareProfile
    $txtMachineTitle = Get-CIODIYGuiControl -Name 'TxtMachineTitle'
    $txtMachinePlatform = Get-CIODIYGuiControl -Name 'TxtMachinePlatform'
    $txtMachineSpecs = Get-CIODIYGuiControl -Name 'TxtMachineSpecs'
    if ($txtMachineTitle) { $txtMachineTitle.Text = $hw.MachineTitle }
    if ($txtMachinePlatform) { $txtMachinePlatform.Text = $hw.PlatformLine }
    if ($txtMachineSpecs) {
        $txtMachineSpecs.Text = ('CPU: {0}  |  GPU: {1}  |  网卡: {2}' -f $hw.CPU, $hw.GPU, $hw.Network)
    }
}

function Update-CIODIYDriverHealthPanel {
    param($Health)
    if (-not $Health) { return }

    $ctx = Get-CIODIYGuiContext
    $ctx.State.Health = $Health

    $txtHealthScore = Get-CIODIYGuiControl -Name 'TxtHealthScore'
    $txtHealthLabel = Get-CIODIYGuiControl -Name 'TxtHealthLabel'
    $txtHealthTips = Get-CIODIYGuiControl -Name 'TxtHealthTips'
    $txtRecommendedFix = Get-CIODIYGuiControl -Name 'TxtRecommendedFix'
    $txtOptionalFix = Get-CIODIYGuiControl -Name 'TxtOptionalFix'
    $txtUnsafeFix = Get-CIODIYGuiControl -Name 'TxtUnsafeFix'
    $borderHealth = Get-CIODIYGuiControl -Name 'CardHealth'

    if ($txtHealthScore) {
        $txtHealthScore.Text = ('{0}%' -f $Health.HealthScore)
        if ($Health.ScoreColor -match '^#([0-9A-Fa-f]{6})$') {
            $h = $matches[1]
            $color = [System.Windows.Media.Color]::FromRgb(
                [Convert]::ToByte($h.Substring(0, 2), 16),
                [Convert]::ToByte($h.Substring(2, 2), 16),
                [Convert]::ToByte($h.Substring(4, 2), 16)
            )
            $brush = [System.Windows.Media.SolidColorBrush]::new($color)
            $txtHealthScore.Foreground = $brush
            if ($borderHealth) { $borderHealth.BorderBrush = $brush }
        }
    }
    if ($txtHealthLabel) {
        $suffix = if ($Health.IsQuickEstimate) { ' · 估计' } else { '' }
        $txtHealthLabel.Text = ('{0}{1}' -f $Health.ScoreLabel, $suffix)
    }
    if ($txtHealthTips) {
        $recommendations = @($Health.Recommendations)
        $warnings = @($Health.Warnings)
        $tips = @($recommendations | Select-Object -First 3)
        if ($Health.RepairSummary) {
            $tips = @($Health.RepairSummary.StatusLine) + $tips
        }
        if ($tips.Count -eq 0 -and $warnings.Count -gt 0) {
            $tips = @($warnings | Select-Object -First 2)
        }
        if ($tips.Count -gt 0) {
            $txtHealthTips.Text = ($tips -join ' · ')
        } else {
            $txtHealthTips.Text = [string]$Health.SummaryLine
        }
    }
    if ($txtRecommendedFix -and $Health.RepairSummary) {
        # Show all actionable items (Recommended tier + Optional tier) as the "fixable" count.
        $fixable = ([int]$Health.RepairSummary.Recommended) + ([int]$Health.RepairSummary.Optional)
        $txtRecommendedFix.Text = [string]$fixable
        if ($txtOptionalFix) { $txtOptionalFix.Text = [string]$Health.RepairSummary.Optional }
        if ($txtUnsafeFix) { $txtUnsafeFix.Text = [string]$Health.RepairSummary.Unsafe }
    } elseif ($txtRecommendedFix -and $Health.RecommendedFix) {
        $txtRecommendedFix.Text = [string]$Health.RecommendedFix
    }
}

function Update-CIODIYRepoHealthPanel {
    param($RepoHealth = $null)
    if (-not $RepoHealth) {
        $result = Get-DriverRepositoryHealthEngine
        if (-not $result.Success) { return }
        $RepoHealth = $result.Data
    }
    $ctx = Get-CIODIYGuiContext
    $ctx.State.RepoHealth = $RepoHealth
    $txtRepoHealth = Get-CIODIYGuiControl -Name 'TxtRepoHealth'
    if ($txtRepoHealth) { $txtRepoHealth.Text = $RepoHealth.ShortLine }
}

function Update-CIODIYFixButtonLabel {
    $ctx = Get-CIODIYGuiContext
    $btnFixAll = Get-CIODIYGuiControl -Name 'BtnFixAll'
    $txtIssueCount = Get-CIODIYGuiControl -Name 'TxtIssueCount'
    $txtIssueCountOverview = Get-CIODIYGuiControl -Name 'TxtIssueCountOverview'
    $txtRecommendedFix = Get-CIODIYGuiControl -Name 'TxtRecommendedFix'
    $txtOptionalFix = Get-CIODIYGuiControl -Name 'TxtOptionalFix'
    $txtUnsafeFix = Get-CIODIYGuiControl -Name 'TxtUnsafeFix'
    $txtScenario = Get-CIODIYGuiControl -Name 'TxtScenario'

    $sel = @($ctx.State.GridRows | Where-Object { $_.IsSelected }).Count
    if ($btnFixAll) { $btnFixAll.Content = "修复已选 ($sel)" }

    if ($ctx.State.RepairSummary) {
        $total = [string]$ctx.State.RepairSummary.TotalDetected
        if ($txtIssueCount) { $txtIssueCount.Text = $total }
        if ($txtIssueCountOverview) { $txtIssueCountOverview.Text = $total }

        # Count only items the app can AUTO-fix (DownloadThenInstall / InstallLocal).
        # Must stay in sync with the 'recommended' filter in Update-CIODIYDashboardPanel (GuiPages.ps1).
        $autoFixTexts = @('下载并修复', '修复')
        $fixableCount = @($ctx.State.GridRows | Where-Object { $_.ButtonText -in $autoFixTexts }).Count
        if ($txtRecommendedFix) { $txtRecommendedFix.Text = [string]$fixableCount }
        if ($txtOptionalFix) { $txtOptionalFix.Text = [string]$ctx.State.RepairSummary.Optional }
        if ($txtUnsafeFix) { $txtUnsafeFix.Text = [string]$ctx.State.RepairSummary.Unsafe }
    }
    if ($ctx.State.Scenario -ne 'all') {
        $info = Get-DriverScenarioInfoEngine -Scenario $ctx.State.Scenario
        if ($txtScenario) { $txtScenario.Text = ('当前场景: {0}' -f $info.Label) }
    }
}

function Update-CIODIYScenarioBanner {
    param([string]$Scenario = 'all')
    $txtScenario = Get-CIODIYGuiControl -Name 'TxtScenario'
    if (-not $txtScenario) { return }
    if ($Scenario -eq 'all') {
        $txtScenario.Text = ''
        return
    }
    $info = Get-DriverScenarioInfoEngine -Scenario $Scenario
    $txtScenario.Text = ('当前场景: {0}' -f $info.Label)
}

function Set-CIODIYGridRowStyle {
    param($Row, $Item)
    if (-not $Row -or -not $Item) { return }
    $bg = switch ([string]$Item.Status) {
        '错误' { '#3F1D1D' }
        '异常' { '#3F1D1D' }
        '过时' { '#3F3319' }
        '降级' { '#3F3319' }
        '警告' { '#3F3319' }
        '正常' { '#1A2E1A' }
        default { $null }
    }
    if ($bg) { $Row.Background = ConvertTo-CIODIYGuiBrush -Color $bg }
    if ($Item.HasDependencies) {
        $Row.Foreground = ConvertTo-CIODIYGuiBrush -Color '#CBD5E1'
    }
}

function Register-CIODIYGridRowHandlers {
    $ctx = Get-CIODIYGuiContext
    # Clear any previously registered handlers before re-registering.
    # Without this, repeated scans accumulate duplicate PropertyChanged subscriptions
    # causing performance degradation and erratic button label updates.
    if ($ctx.State['GridRowHandlers']) {
        $old = $ctx.State['GridRowHandlers']
        foreach ($entry in $old) {
            try { $entry.Row.remove_PropertyChanged($entry.Handler) } catch {}
        }
    }
    $handlers = New-Object System.Collections.Generic.List[object]
    foreach ($row in $ctx.State.GridRows) {
        $handler = [System.ComponentModel.PropertyChangedEventHandler]{
            param($sender, $e)
            if ($e.PropertyName -eq 'IsSelected') {
                Invoke-CIODIYGuiThread { Update-CIODIYFixButtonLabel }
            }
        }
        $row.add_PropertyChanged($handler)
        [void]$handlers.Add([PSCustomObject]@{ Row = $row; Handler = $handler })
    }
    $ctx.State['GridRowHandlers'] = $handlers.ToArray()
}

function Set-CIODIYAllGridSelection {
    param([bool]$Selected, [string]$Filter = 'all')
    $ctx = Get-CIODIYGuiContext
    foreach ($row in $ctx.State.GridRows) {
        if ($Filter -eq 'recommended') {
            $row.IsSelected = (Test-RecommendTierAutoSelect -Tier $row.RecommendTier)
        } else {
            $row.IsSelected = $Selected
        }
    }
    Update-CIODIYFixButtonLabel
}

function Update-CIODIYDriverGrid {
    param($scanResults, $fixPlan, [string]$Scenario = 'all')

    $ctx = Get-CIODIYGuiContext
    $gridDrivers = Get-CIODIYGuiControl -Name 'GridDrivers'

    # Reset dashboard filter on every new scan so stale filters don't confuse the user
    $ctx.State['DashFilterMode'] = 'all'
    $fb = Get-CIODIYGuiControl -Name 'DashFilterBar'
    if ($fb) { $fb.Visibility = 'Collapsed' }

    # Use explicit hashtable indexer here: in WPF/STA context, PowerShell's property
    # adapter for Hashtable can fail on @(List[object]) assignment. Direct indexer is safe.
    $ctx.State['ScanResults'] = [object[]]@($scanResults)
    $ctx.State['FixPlan'] = [object[]]@($fixPlan)
    $ctx.State['Scenario'] = $Scenario
    $ctx.State['FixPlanByKey'] = @{}

    $rows = New-Object System.Collections.Generic.List[object]
    $visible = @(Get-DriverVisibleFixPlanEngine -FixPlan $fixPlan)

    foreach ($item in $visible) {
        $view = ConvertTo-CIODIYFixPlanItem -InternalItem $item
        $key = $view.DeviceKey
        $ctx.State.FixPlanByKey[$key] = $item
        $rows.Add((New-DriverGridRowFromItem -Item $item))
    }

    # Must use ToArray() + explicit indexer - @($rows) fails in WPF/STA (参数类型不匹配)
    $ctx.State['GridRows'] = [object[]]$rows.ToArray()

    $ctx.State['RepairSummary'] = Invoke-DriverRepairSummaryEngine `
        -FixPlan $fixPlan -ScanResults $scanResults -Scenario $Scenario -GridRows $ctx.State.GridRows

    Register-CIODIYGridRowHandlers
    if ($gridDrivers) {
        $gridDrivers.ItemsSource = $null
        $gridDrivers.ItemsSource = $ctx.State.GridRows
    }

    $txtVersionSummary = Get-CIODIYGuiControl -Name 'TxtVersionSummary'
    if ($txtVersionSummary) {
        $vs = Get-DriverVersionStatusSummary -FixPlan $fixPlan
        $txtVersionSummary.Text = $vs.SummaryLine
    }

    Update-CIODIYFixButtonLabel
    if (Get-Command Update-CIODIYDashboardPanel -ErrorAction SilentlyContinue) { Update-CIODIYDashboardPanel }
    if (Get-Command Update-CIODIYQuickFixPanel -ErrorAction SilentlyContinue) { Update-CIODIYQuickFixPanel }
}

function Update-CIODIYDriverDetailPanel {
    param($GridRow = $null)

    $txt = Get-CIODIYGuiControl -Name 'TxtDriverDetail'
    if (-not $txt) { return }

    if (-not $GridRow) {
        $txt.Text = '选中一行查看驱动详情（当前版本、来源、WHQL、匹配原因、风险）'
        return
    }

    $ctx = Get-CIODIYGuiContext
    $key = [string]$GridRow.DeviceKey
    if (-not $ctx.State.FixPlanByKey.ContainsKey($key)) {
        $txt.Text = '无法加载详情'
        return
    }

    $item = $ctx.State.FixPlanByKey[$key]
    $details = Get-DriverFixItemDetails -Item $item
    $txt.Text = $details.DetailText
}

function Register-CIODIYGridSelectionHandler {
    $grid = Get-CIODIYGuiControl -Name 'GridDrivers'
    if (-not $grid) { return }
    $grid.Add_SelectionChanged({
        param($sender, $e)
        $row = $sender.SelectedItem
        Update-CIODIYDriverDetailPanel -GridRow $row
        if ($row -and (Get-Command Show-CIODIYDriverDetailDrawer -ErrorAction SilentlyContinue)) {
            Show-CIODIYDriverDetailDrawer -GridRow $row
        }
    })

    if (Get-Command Register-CIODIYDriverDetailDrawer -ErrorAction SilentlyContinue) {
        Register-CIODIYDriverDetailDrawer
    }
}

function Get-CIODIYSelectedFixPlan {
    $ctx = Get-CIODIYGuiContext
    $keys = @($ctx.State.GridRows | Where-Object { $_.IsSelected } | ForEach-Object { $_.DeviceKey })
    if ($keys.Count -eq 0) { return @() }

    $selected = @($ctx.State.FixPlan | Where-Object {
        $view = ConvertTo-CIODIYFixPlanItem -InternalItem $_
        $keys -contains $view.DeviceKey
    })
    return @(Expand-DriverFixPlanSelectionEngine -SelectedItems $selected -FullFixPlan $ctx.State.FixPlan)
}

function Refresh-CIODIYHealthFromScan {
    param([array]$ScanResults, [array]$FixPlan)
    $ctx = Get-CIODIYGuiContext
    $health = Invoke-DriverHealthEngine -ScanResults $ScanResults -FixPlan $FixPlan -Manifest $ctx.State.Manifest
    Update-CIODIYDriverHealthPanel -Health $health
}

function Register-CIODIYProblemListHandler {
    $lst = Get-CIODIYGuiControl -Name 'LstProblemDevices'
    if (-not $lst) { return }

    $lst.Add_PreviewMouseLeftButtonDown({
        param($sender, $e)
        # Walk up the visual tree from the clicked element to find the containing Button
        $btn = $e.OriginalSource
        while ($btn -and $btn -isnot [System.Windows.Controls.Button]) {
            $btn = [System.Windows.Media.VisualTreeHelper]::GetParent($btn)
        }
        if (-not $btn -or $btn.Name -notin @('BtnCardAction', 'BtnCardDetail')) { return }

        $row = $btn.DataContext
        if (-not $row -or [string]::IsNullOrEmpty([string]$row.DeviceKey)) { return }

        $ctx = Get-CIODIYGuiContext

        if ($btn.Name -eq 'BtnCardDetail') {
            Update-CIODIYDriverDetailPanel -GridRow $row
            $drawer = Get-CIODIYGuiControl -Name 'DriverDetailDrawer'
            if ($drawer) { $drawer.Visibility = 'Visible' }
            $e.Handled = $true
            return
        }

        if ($btn.Name -eq 'BtnCardAction' -and $btn.IsEnabled) {
            if ($ctx.State.IsBusy) { return }
            $item = $ctx.State.FixPlanByKey[$row.DeviceKey]
            if (-not $item) { return }
            $e.Handled = $true
            Invoke-CIODIYAppFix -FixPlanOverride @($item)
        }
    })
}

function Register-CIODIYGridLoadingRowHandler {
    $gridDrivers = Get-CIODIYGuiControl -Name 'GridDrivers'
    if (-not $gridDrivers) { return }
    $gridDrivers.Add_LoadingRow({
        param($sender, $e)
        if ($e.Row -and $e.Row.Item) {
            Set-CIODIYGridRowStyle -Row $e.Row -Item $e.Row.Item
        }
    })

    # Catch per-row action button clicks that bubble up from DataTemplate buttons.
    # Using PreviewMouseLeftButtonDown so we intercept before the DataGrid row-selection fires.
    $gridDrivers.Add_PreviewMouseLeftButtonDown({
        param($sender, $e)
        $src = $e.OriginalSource
        # Walk up the visual tree to find the containing Button
        $btn = $src
        while ($btn -and $btn -isnot [System.Windows.Controls.Button]) {
            $btn = [System.Windows.Media.VisualTreeHelper]::GetParent($btn)
        }
        if (-not $btn -or $btn.Name -ne 'BtnRowAction' -or -not $btn.IsEnabled) { return }

        $row = $btn.DataContext
        if (-not $row -or [string]::IsNullOrEmpty($row.DeviceKey)) { return }

        $ctx = Get-CIODIYGuiContext
        if ($ctx.State.IsBusy) { return }

        $item = $ctx.State.FixPlanByKey[$row.DeviceKey]
        if (-not $item) { return }

        $e.Handled = $true
        Invoke-CIODIYAppFix -FixPlanOverride @($item)
    })
}

function Initialize-CIODIYGuiChrome {
    $ctx = Get-CIODIYGuiContext
    $txtAppVersion = Get-CIODIYGuiControl -Name 'TxtAppVersion'
    $txtSubtitle = Get-CIODIYGuiControl -Name 'TxtSubtitle'
    $borderWelcome = Get-CIODIYGuiControl -Name 'BorderWelcome'

    Update-CIODIYHardwareProfilePanel
    Write-CIODIYGuiLog -Message ('硬件识别: {0}' -f (Get-HardwareProfile).MachineTitle)

    $cachedHealth = Get-DriverHealthCache
    if ($cachedHealth) { Update-CIODIYDriverHealthPanel -Health $cachedHealth }

    if (-not (Test-IsAdmin)) {
        if ($txtSubtitle) {
            $txtSubtitle.Text = '未以管理员运行 - 扫描可用，安装驱动需提升权限'
            $txtSubtitle.Foreground = ConvertTo-CIODIYGuiBrush -Color '#F87171'
        }
    }
    if ($txtAppVersion) { $txtAppVersion.Text = 'v' + $ctx.AppVersion }

    if ($borderWelcome) {
        $borderWelcome.Visibility = if (Test-ShouldShowOnboarding) { 'Visible' } else { 'Collapsed' }
    }
}
