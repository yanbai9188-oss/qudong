# Per-page render helpers (v1.8.0)

function Get-CIODIYRecommendedFixPlan {
    $ctx = Get-CIODIYGuiContext
    $plan = @($ctx.State.FixPlan)
    if ($plan.Count -eq 0) { return @() }

    # Include all items that have a concrete repair action (the GridRow would show CanFix=true).
    # Previously only '推荐'/'强烈推荐' tier items were included, so '可选' items like
    # DownloadThenInstall WiFi drivers were silently excluded and "修复推荐项" appeared to
    # do nothing.  Now we include everything actionable except explicit NoSource items.
    $visible = @($plan | Where-Object {
        $_.Action -notin @('NoSource', $null) -and
        -not $_.HideFromList -and
        -not ($_.IsDependency -and $_.AttachedToParent)
    })
    if ($visible.Count -gt 0) { return @($visible) }

    # Fallback: original tier-based filter
    return @($plan | Where-Object {
        $tier = Get-RecommendTier -Item $_
        Test-RecommendTierAutoSelect -Tier $tier
    })
}

function Set-CIODIYDashFilter {
    param([string]$Mode = 'all')
    # Store in the shared GUI state (accessible from any scope — GUI thread, event handlers, etc.)
    $ctx = Get-CIODIYGuiContext
    $ctx.State['DashFilterMode'] = $Mode
    Update-CIODIYDashboardPanel
    # Scroll problem list into view after filter change
    $lst = Get-CIODIYGuiControl -Name 'LstProblemDevices'
    if ($lst) { $lst.BringIntoView() }
}

function Update-CIODIYDashboardPanel {
    $ctx = Get-CIODIYGuiContext
    $allRows = @($ctx.State.GridRows)

    # Apply filter — read from shared state, default 'all'
    $filterMode = if ($ctx.State.DashFilterMode) { $ctx.State.DashFilterMode } else { 'all' }
    # 'recommended' = only items the app can AUTO-fix (DownloadThenInstall / InstallLocal).
    # CatalogSearch items show "搜索驱动" but require manual action, so they are excluded here.
    # This must match the count formula in Update-CIODIYFixButtonLabel (GuiRender.ps1).
    $autoFixTexts = @('下载并修复', '修复')
    $rows = switch ($filterMode) {
        'recommended' { @($allRows | Where-Object { $_.ButtonText -in $autoFixTexts }) }
        'optional'    { @($allRows | Where-Object { $_.ButtonText -notin $autoFixTexts }) }
        default       { $allRows }
    }

    # --- Filter status bar ---
    $filterBar   = Get-CIODIYGuiControl -Name 'DashFilterBar'
    $filterLabel = Get-CIODIYGuiControl -Name 'TxtDashFilterLabel'
    if ($filterBar) {
        if ($filterMode -eq 'all') {
            $filterBar.Visibility = 'Collapsed'
        } else {
            $filterBar.Visibility = 'Visible'
            if ($filterLabel) {
                $label = switch ($filterMode) {
                    'recommended' { "已过滤：仅显示 $($rows.Count) 个推荐修复项" }
                    'optional'    { "已过滤：仅显示 $($rows.Count) 个其他问题设备" }
                    default       { "已过滤：$($rows.Count) 项" }
                }
                $filterLabel.Text = $label
            }
        }
    }
    # Keep the stat-card for 推荐修复 highlighted when filter is active
    $cardRec = Get-CIODIYGuiControl -Name 'CardRecommended'
    if ($cardRec) {
        $cardRec.BorderBrush = if ($filterMode -eq 'recommended') {
            [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#FF6B00'))
        } else {
            [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#2A3140'))
        }
        $cardRec.BorderThickness = if ($filterMode -eq 'recommended') {
            [System.Windows.Thickness]::new(2)
        } else {
            [System.Windows.Thickness]::new(1)
        }
    }

    # --- Problem device card list ---
    $lstProblems   = Get-CIODIYGuiControl -Name 'LstProblemDevices'
    $borderEmpty   = Get-CIODIYGuiControl -Name 'BorderProblemEmpty'
    $txtCount      = Get-CIODIYGuiControl -Name 'TxtProblemCount'

    if ($lstProblems) {
        $lstProblems.Items.Clear()
        if ($rows.Count -eq 0) {
            $lstProblems.Visibility = 'Collapsed'
            if ($borderEmpty) {
                $borderEmpty.Visibility = 'Visible'
                $emptyMsg = if ($filterMode -ne 'all') {
                    "当前过滤（$filterMode）下无匹配项。"
                } elseif (@($ctx.State.ScanResults).Count -gt 0) {
                    '本次扫描未发现需要处理的问题设备。'
                } else {
                    '尚未扫描。点击「立即扫描」后会在这里显示问题设备和操作按钮。'
                }
                $tb = $borderEmpty.Child
                if ($tb -is [System.Windows.Controls.TextBlock]) { $tb.Text = $emptyMsg }
            }
            if ($txtCount) { $txtCount.Text = '' }
        } else {
            if ($borderEmpty) { $borderEmpty.Visibility = 'Collapsed' }
            $lstProblems.Visibility = 'Visible'
            $displayRows = @($rows | Select-Object -First 10)
            foreach ($row in $displayRows) {
                $lstProblems.Items.Add($row) | Out-Null
            }
            if ($txtCount) {
                $total = $allRows.Count
                $suffix = if ($rows.Count -lt $total -and $filterMode -eq 'all') {
                    "，还有 $($total - $rows.Count) 项请到「驱动中心」查看"
                } elseif ($rows.Count -gt 10) {
                    "，还有 $($rows.Count - 10) 项请到「驱动中心」查看"
                } else { '' }
                $txtCount.Text = "（共 $($rows.Count) 项$suffix）"
            }
        }
    }

    $txtRecent = Get-CIODIYGuiControl -Name 'TxtRecentRepairs'
    if (-not $txtRecent) { return }

    $lines = New-Object System.Collections.ArrayList
    $txList = @()
    if (Get-Command Get-DriverTransactionsEngine -ErrorAction SilentlyContinue) {
        $txList = @(Get-DriverTransactionsEngine -Limit 5)
    } elseif (Get-Command Get-AllTransactions -ErrorAction SilentlyContinue) {
        $txList = @(Get-AllTransactions -Limit 5)
    }

    foreach ($tx in $txList) {
        $summary = $null
        if (Get-Command Get-DriverTransactionSummaryEngine -ErrorAction SilentlyContinue) {
            $summary = Get-DriverTransactionSummaryEngine -Transaction $tx
        } elseif (Get-Command Get-TransactionSummaryForGui -ErrorAction SilentlyContinue) {
            $summary = Get-TransactionSummaryForGui -Transaction $tx
        }
        if (-not $summary) { continue }
        [void]$lines.Add(('{0} | {1} | ok={2} fail={3}' -f $summary.TimeLabel, $summary.DriverNames, $summary.SuccessCount, $summary.FailCount))
    }

    if ($lines.Count -eq 0) {
        $txtRecent.Text = '暂无修复记录。扫描后点击「一键修复」即可。'
    } else {
        $txtRecent.Text = ($lines -join [Environment]::NewLine)
    }

    $txtDashRepo = Get-CIODIYGuiControl -Name 'TxtDashRepoHealth'
    if ($txtDashRepo -and $ctx.State.RepoHealth) {
        $rh = $ctx.State.RepoHealth
        if ($rh.IsLazyCache) {
            $txtDashRepo.Text = ('在线模式 · {0} 包' -f $rh.TotalPackages)
        } else {
            $txtDashRepo.Text = ('已缓存 {0}/{1}' -f ($rh.CachedCount), $rh.TotalPackages)
        }
    }
}

function Update-CIODIYQuickFixPanel {
    $plan = @(Get-CIODIYRecommendedFixPlan)
    $txt = Get-CIODIYGuiControl -Name 'TxtQuickFixSummary'
    if (-not $txt) { return }

    if ($plan.Count -eq 0) {
        $txt.Text = '请先点击「立即扫描」，推荐修复项将显示在此处。'
        return
    }

    $assessment = Get-FixPlanRiskAssessment -FixPlan $plan
    $rebootCount = @($plan | Where-Object { $_.Package -and $_.Package.RebootRequired }).Count
    $chkBackup = Get-CIODIYGuiControl -Name 'ChkBackup'
    $chkRestore = Get-CIODIYGuiControl -Name 'ChkRestore'
    $backupOn = if ($chkBackup) { [bool]$chkBackup.IsChecked } else { $true }
    $restoreOn = if ($chkRestore) { [bool]$chkRestore.IsChecked } else { $true }

    $lines = @(
        ('推荐修复：{0} 项' -f $plan.Count),
        ('低风险：{0} · 中等：{1} · 高风险：{2}（将跳过）' -f $assessment.LowRisk, $assessment.MediumRisk, $assessment.HighRisk),
        ('需重启：{0} 项' -f $rebootCount),
        ('驱动备份：{0}' -f $(if ($backupOn) { '已启用' } else { '未启用' })),
        ('系统还原点：{0}' -f $(if ($restoreOn) { '将创建' } else { '跳过' }))
    )
    $txt.Text = ($lines -join [Environment]::NewLine)
}

function Update-CIODIYRollbackPanel {
    $lst = Get-CIODIYGuiControl -Name 'LstTransactions'
    $txtDetail = Get-CIODIYGuiControl -Name 'TxtRollbackDetail'
    if (-not $lst) { return }

    $lst.Items.Clear()
    $txList = @()
    if (Get-Command Get-DriverTransactionsEngine -ErrorAction SilentlyContinue) {
        $txList = @(Get-DriverTransactionsEngine -Limit 20)
    } elseif (Get-Command Get-AllTransactions -ErrorAction SilentlyContinue) {
        $txList = @(Get-AllTransactions -Limit 20)
    }

    foreach ($tx in $txList) {
        $summary = $null
        try {
            if (Get-Command Get-DriverTransactionSummaryEngine -ErrorAction SilentlyContinue) {
                $summary = Get-DriverTransactionSummaryEngine -Transaction $tx
            } else {
                $summary = Get-TransactionSummaryForGui -Transaction $tx
            }
        } catch { $summary = $null }

        if (-not $summary) {
            $summary = [PSCustomObject]@{ TimeLabel = '?'; DriverNames = '?'; SuccessCount = 0; FailCount = 0; FinalStatus = 'unknown' }
        }
        $label = ('{0} | {1} | ok={2}' -f $summary.TimeLabel, $summary.DriverNames, $summary.SuccessCount)
        $lst.Items.Add([PSCustomObject]@{ Label = $label; Transaction = $tx; Summary = $summary }) | Out-Null
    }

    if ($txtDetail -and $lst.Items.Count -eq 0) {
        $txtDetail.Text = '暂无修复事务记录。'
    }
}

function Update-CIODIYRollbackDetail {
    param($Item)
    $txtDetail = Get-CIODIYGuiControl -Name 'TxtRollbackDetail'
    if (-not $txtDetail -or -not $Item) { return }
    $s = $Item.Summary
    $txtDetail.Text = @(
        ('时间：{0}' -f $s.TimeLabel),
        ('驱动：{0}' -f $s.DriverNames),
        ('成功：{0} · 失败：{1}' -f $s.SuccessCount, $s.FailCount),
        ('状态：{0}' -f $s.FinalStatus)
    ) -join [Environment]::NewLine
}

function Update-CIODIYRepoPagePanel {
    Update-CIODIYRepoHealthPanel
    $ctx = Get-CIODIYGuiContext
    $txtRepoDetail = Get-CIODIYGuiControl -Name 'TxtRepoDetail'
    if (-not $txtRepoDetail -or -not $ctx.State.RepoHealth) { return }
    $rh = $ctx.State.RepoHealth
    if ($rh.IsLazyCache) {
        $txtRepoDetail.Text = @(
            ('运行模式：在线下载（节省安装包体积）'),
            ('注册驱动包：{0} 个' -f $rh.TotalPackages),
            ('本地缓存：0 个 · 修复时按需下载并校验 SHA256'),
            [string]$rh.SummaryLine
        ) -join [Environment]::NewLine
    } else {
        $txtRepoDetail.Text = @(
            ('健康度：{0}%' -f $rh.HealthPercent),
            ('总包数：{0} · 已缓存：{1} · 警告：{2} · 失败：{3}' -f $rh.TotalPackages, $rh.CachedCount, $rh.Warning, $rh.Failed),
            [string]$rh.SummaryLine
        ) -join [Environment]::NewLine
    }
}

function Invoke-CIODIYFixRecommended {
    $ctx = Get-CIODIYGuiContext
    if ($ctx.State.IsBusy) { return }

    $plan = @(Get-CIODIYRecommendedFixPlan)
    if ($plan.Count -eq 0) {
        [System.Windows.MessageBox]::Show('请先扫描。未发现推荐修复项。', '一键修复', 'OK', 'Information') | Out-Null
        return
    }

    $assessment = Get-FixPlanRiskAssessment -FixPlan $plan
    $msg = $assessment.ConfirmMessage
    if ($assessment.HighRisk -gt 0) {
        $msg += [Environment]::NewLine + [Environment]::NewLine + '高风险项将被跳过，是否继续安装其余项？'
        if ([System.Windows.MessageBox]::Show($msg, '安装前风险检查', 'YesNo', 'Warning') -ne 'Yes') { return }
        $plan = @($plan | Where-Object { (Get-FixItemInstallRisk -Item $_).Level -ne 'high' })
        if ($plan.Count -eq 0) { return }
    } else {
        $msg += [Environment]::NewLine + [Environment]::NewLine + '确定继续？'
        if ([System.Windows.MessageBox]::Show($msg, '安装前风险检查', 'YesNo', 'Question') -ne 'Yes') { return }
    }

    Invoke-CIODIYAppFix -FixPlanOverride $plan
}
