# GUI event bindings (v1.7.0) — calls Engine API only, never lib internals

function Start-CIODIYBackgroundHealthAnalysis {
    param([switch]$QuickFirst)

    $ctx = Get-CIODIYGuiContext
    Start-CIODIYGuiWorker -DoWork {
        if ($QuickFirst) {
            return @{ Phase = 'quick'; Health = (Invoke-DriverHealthEngine -QuickOnly) }
        }
        $health = Invoke-DriverHealthEngine -RunScan -FastMatch -OnLog $ctx.LogCallback
        return @{ Phase = 'full'; Health = $health }
    } -OnComplete {
        param($data)
        if (-not $data -or -not $data.Health) { return }
        Update-CIODIYDriverHealthPanel -Health $data.Health
        if ($data.Phase -eq 'full') {
            Write-CIODIYGuiLog -Message ("健康分析完成：{0}%" -f $data.Health.HealthScore)
            if ($data.Health.ScanResults -and $data.Health.FixPlan) {
                Update-CIODIYDriverGrid -scanResults $data.Health.ScanResults -fixPlan $data.Health.FixPlan -Scenario 'all'
            }
        } else {
            Write-CIODIYGuiLog -Message ("快速健康估计：{0}%" -f $data.Health.HealthScore)
            Start-CIODIYBackgroundHealthAnalysis
        }
    } -OnError {
        param($err)
        Write-CIODIYGuiLog -Message ("健康分析跳过：{0}" -f $err)
    }
}

function Invoke-CIODIYScenarioQuickFix {
    param([Parameter(Mandatory)][string]$Scenario)

    $ctx = Get-CIODIYGuiContext
    if ($ctx.State.IsBusy) { return }

    $ctx.State.Scenario = $Scenario
    $info = Get-DriverScenarioInfoEngine -Scenario $Scenario
    $chkOutdated = Get-CIODIYGuiControl -Name 'ChkOutdated'
    $progress = Get-CIODIYGuiControl -Name 'Progress'
    $includeOut = if ($chkOutdated) { [bool]$chkOutdated.IsChecked } else { $false }

    Set-CIODIYGuiBusyState -Busy $true -ProgressText ("正在扫描：{0}..." -f $info.Label)
    if ($progress) { $progress.Value = 10 }
    Update-CIODIYScenarioBanner -Scenario $Scenario

    Start-CIODIYGuiWorker -DoWork {
        Invoke-AppScan -PassThru -FastMatch -Scenario $Scenario -IncludeOutdated:$includeOut -OnLog $ctx.LogCallback
    } -OnComplete {
        param($result)
        Update-CIODIYDriverGrid -scanResults $result.ScanResults -fixPlan $result.FixPlan -Scenario $Scenario
        Refresh-CIODIYHealthFromScan -ScanResults $result.ScanResults -FixPlan $result.FixPlan
        if ($progress) { $progress.Value = 100 }
        $summary = Invoke-DriverRepairSummaryEngine -FixPlan $result.FixPlan -ScanResults $result.ScanResults -Scenario $Scenario
        $autoFix = @($result.FixPlan | Where-Object { $_.Action -in @('DownloadThenInstall','InstallLocal') }).Count
        $scanText = if ($summary.TotalDetected -gt 0) {
            "扫描完成 · 发现 $($summary.TotalDetected) 个问题，$autoFix 项可一键修复"
        } else {
            '扫描完成 · 所有驱动均正常'
        }
        Set-CIODIYGuiBusyState -Busy $false -ProgressText $scanText
    } -OnError {
        param($err)
        Write-CIODIYGuiLog -Message ("场景扫描失败：{0}" -f $err)
        Set-CIODIYGuiBusyState -Busy $false
    }
}

function Invoke-CIODIYAppFix {
    param([array]$FixPlanOverride = $null)

    $ctx         = Get-CIODIYGuiContext
    $chkRestore  = Get-CIODIYGuiControl -Name 'ChkRestore'
    $chkBackup   = Get-CIODIYGuiControl -Name 'ChkBackup'
    $chkRollback = Get-CIODIYGuiControl -Name 'ChkRollback'
    $chkOutdated = Get-CIODIYGuiControl -Name 'ChkOutdated'
    $progress    = Get-CIODIYGuiControl -Name 'Progress'
    $txtProgress = Get-CIODIYGuiControl -Name 'TxtProgress'
    $window      = $ctx.Window

    $restore    = if ($chkRestore)  { [bool]$chkRestore.IsChecked  } else { $false }
    $backup     = if ($chkBackup)   { [bool]$chkBackup.IsChecked   } else { $true  }
    $rollback   = if ($chkRollback) { [bool]$chkRollback.IsChecked } else { $false }
    $includeOut = if ($chkOutdated) { [bool]$chkOutdated.IsChecked } else { $false }

    $plan = if ($FixPlanOverride) { @($FixPlanOverride) } else { @(Get-CIODIYSelectedFixPlan) }
    if ($plan.Count -eq 0) { return }

    $names = ($plan | ForEach-Object { $_.Device.FriendlyName }) -join '、'
    Write-CIODIYGuiLog -Message ("开始修复已选 {0} 项: {1}" -f $plan.Count, $names)
    Set-CIODIYGuiBusyState -Busy $true -ProgressText '正在修复驱动...'

    # Decide execution path:
    #   Admin  → call Invoke-DriverFixEngine directly (existing path, immediate)
    #   Normal → submit job to YanbaiDriverWorker (SYSTEM scheduled task), poll result
    $isAdmin = Test-IsAdmin

    # Track whether we fired an elevated registration and need to wait for the task to appear
    $needsServiceRegistration = $false

    if (-not $isAdmin) {
        if (-not (Test-CIODIYServiceWorkerAvailable)) {
            # Task not registered — offer to register it now (one UAC) or cancel
            $dlg = [System.Windows.MessageBox]::Show(
                '后台安装服务（YanbaiDriverWorker）尚未注册。' + [Environment]::NewLine + [Environment]::NewLine +
                '点击「是」：申请一次管理员权限完成注册，之后修复驱动无需再次提权。' + [Environment]::NewLine +
                '点击「否」：取消本次修复。',
                '首次使用 — 一次性初始化', 'YesNo', 'Question')

            if ($dlg -ne 'Yes') {
                Set-CIODIYGuiBusyState -Busy $false
                return
            }

            # Fire the registration process elevated (non-blocking so UI stays responsive)
            $appRt     = if ($script:AppRoot) { $script:AppRoot } else { $global:DriverBoosterAppRoot }
            $taskSc    = Join-Path $appRt 'scripts\install-task.ps1'
            $argFire   = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$taskSc`" -AppDir `"$appRt`""
            try {
                Start-Process 'powershell.exe' -ArgumentList $argFire -Verb RunAs -ErrorAction Stop
                $needsServiceRegistration = $true
                Write-CIODIYGuiLog -Message '已申请管理员权限注册服务，正在等待完成...'
                Set-CIODIYGuiBusyState -Busy $true -ProgressText '正在注册后台安装服务...'
            } catch {
                Set-CIODIYGuiBusyState -Busy $false
                Show-CIODIYToast -Message ('无法申请管理员权限: {0}' -f $_.Exception.Message) -Level Error -DurationMs 7000
                return
            }
        } else {
            Write-CIODIYGuiLog -Message '已提交修复任务给后台服务 (SYSTEM)，正在等待...'
        }
    }

    Start-CIODIYGuiWorker -DoWork {
        if ($isAdmin) {
            # ── Direct admin path ────────────────────────────────────────────
            $fixResult = Invoke-DriverFixEngine -FixPlan $plan `
                -CreateRestorePoint:$restore -BackupFirst:$backup -RollbackOnError:$rollback `
                -OnLog $ctx.LogCallback             -OnProgress {
                    param($pct, $name)
                    $cap_pct  = [double]$pct
                    $cap_name = [string]$name
                    $cap_win  = $window
                    [void]$window.Dispatcher.Invoke([System.Action]({
                        $pb  = try { $cap_win.FindName('Progress')    } catch { $null }
                        $txt = try { $cap_win.FindName('TxtProgress') } catch { $null }
                        if (-not $pb)  { $pb  = (Get-CIODIYGuiControl -Name 'Progress') }
                        if (-not $txt) { $txt = (Get-CIODIYGuiControl -Name 'TxtProgress') }
                        if ($pb)  { $pb.Value  = $cap_pct }
                        if ($txt -and $cap_name) { $txt.Text = $cap_name }
                    }.GetNewClosure()))
                }
        } else {
            # ── Service path (non-admin) ─────────────────────────────────────

            # If we just fired the elevated registration process, wait up to 60 s for the task
            if ($needsServiceRegistration) {
                $regDeadline = (Get-Date).AddSeconds(60)
                while ((Get-Date) -lt $regDeadline) {
                    if (Test-CIODIYServiceWorkerAvailable) { break }
                    [void]$ctx.LogCallback.Invoke('等待后台服务注册...')
                    $captured_win = $window
                    [void]$window.Dispatcher.Invoke([System.Action]({
                        $t = try { $captured_win.FindName('TxtProgress') } catch { $null }
                        if (-not $t) { $t = (Get-CIODIYGuiControl -Name 'TxtProgress') }
                        if ($t) { $t.Text = '正在注册后台安装服务...' }
                    }.GetNewClosure()))
                    Start-Sleep -Milliseconds 1500
                }
                if (-not (Test-CIODIYServiceWorkerAvailable)) {
                    throw '服务注册超时（60 秒），请重新安装应用'
                }
                [void]$ctx.LogCallback.Invoke('服务注册成功！正在提交修复任务...')
            }

            $jobId   = Submit-CIODIYDriverJob -FixPlan $plan -BackupFirst:$backup `
                           -RollbackOnError:$rollback -VerifyInstall:$true
            $lastMsg = ''
            $deadline = (Get-Date).AddSeconds(600)  # 10 minutes max
            $s = $null

            while ((Get-Date) -lt $deadline) {
                $s       = Get-CIODIYJobStatus -JobId $jobId
                $svcPct  = if ($s.progress) { [double]$s.progress } else { 5.0 }
                $svcMsg  = if ($s.message)  { [string]$s.message  } else { '后台服务处理中...' }

                if ($svcMsg -ne $lastMsg) {
                    $lastMsg = $svcMsg
                    [void]$ctx.LogCallback.Invoke($svcMsg)
                }
                $captured_pct = $svcPct
                $captured_msg = ([string]$svcMsg) -replace '[\x00-\x1F\x7F]', ''
                if (-not $captured_msg) { $captured_msg = '后台服务处理中...' }
                $captured_win = $window
                [void]$window.Dispatcher.Invoke([System.Action]({
                    $pb  = try { $captured_win.FindName('Progress')    } catch { $null }
                    $txt = try { $captured_win.FindName('TxtProgress') } catch { $null }
                    if (-not $pb)  { $pb  = (Get-CIODIYGuiControl -Name 'Progress') }
                    if (-not $txt) { $txt = (Get-CIODIYGuiControl -Name 'TxtProgress') }
                    if ($pb)  { $pb.Value  = $captured_pct }
                    if ($txt) { $txt.Text  = $captured_msg }
                }.GetNewClosure()))

                if ($s.status -notin @('queued', 'running')) { break }
                Start-Sleep -Milliseconds 800
            }

            # Check if we timed out without a terminal status
            if (-not $s -or $s.status -in @('queued', 'running')) {
                [void]$ctx.LogCallback.Invoke('错误：后台服务响应超时 (10分钟)，请检查服务日志')
                throw '后台驱动安装服务响应超时 (10 分钟)，任务可能仍在运行。请稍后重新扫描确认结果。'
            }

            # Normalise to the same shape Invoke-DriverFixEngine returns
            $rawResults = @()
            if ($s.results) {
                $rawResults = @($s.results | ForEach-Object {
                    [PSCustomObject]@{
                        Device    = [string]$_.device
                        Success   = [bool]$_.success
                        Action    = [string]$_.action
                        Error     = if ($_.error) { [string]$_.error } else { $null }
                        PackageId = if ($_.pkgId)  { [string]$_.pkgId  } else { '' }
                        TxId      = ''
                    }
                })
            }
            $fixResult = [PSCustomObject]@{
                Results       = $rawResults
                RebootNeeded  = if ($s.rebootNeeded) { [bool]$s.rebootNeeded } else { $false }
                FinalStatus   = [string]$s.status
                RolledBack    = if ($s.rolledBack)   { [bool]$s.rolledBack   } else { $false }
                TransactionId = if ($s.txId)         { [string]$s.txId       } else { '' }
            }
            Remove-CIODIYJobResult -JobId $jobId
        }

        $activeScenario = if ($ctx.State.Scenario) { $ctx.State.Scenario } else { 'all' }
        $scanResult = Invoke-AppScan -PassThru -FastMatch -Scenario $activeScenario -IncludeOutdated:$includeOut -OnLog $ctx.LogCallback
        return @{ Fix = $fixResult; Scan = $scanResult; Scenario = $activeScenario }
    } -OnComplete {
        param($data)
        $result = $data.Fix
        $allResults = @($result.Results)
        $ok = @($allResults | Where-Object { $_.Success }).Count
        $fail = @($allResults | Where-Object { -not $_.Success }).Count
        $rolledBack = [bool]$result.RolledBack

        # --- 构建结果摘要文本 ---
        $lines = New-Object System.Collections.ArrayList
        [void]$lines.Add('=' * 42)
        $statusIcon = if ($rolledBack) { '[!] 已回滚' } elseif ($fail -gt 0) { "[!] 部分失败" } else { '[OK]' }
        [void]$lines.Add((' {0}  成功 {1} / 共 {2} 项' -f $statusIcon, $ok, $allResults.Count))
        [void]$lines.Add('=' * 42)
        foreach ($r in $allResults) {
            $icon = if ($r.Success) { '[+]' } else { '[x]' }
            $devName = if ($r.Device) { [string]$r.Device } else { '未知设备' }
            $pkgName = if ($r.PackageId) { ' <- ' + $r.PackageId } else { '' }
            $line = ('{0} {1}{2}' -f $icon, $devName, $pkgName)
            if (-not $r.Success -and $r.Error) {
                $errStr = [string]$r.Error; if ($errStr.Length -gt 200) { $errStr = $errStr.Substring(0,200) }
                $line += [Environment]::NewLine + ('    错误: ' + $errStr)
            }
            [void]$lines.Add($line)
        }
        if ($rolledBack) {
            [void]$lines.Add('')
            [void]$lines.Add('[!] 安装过程中出错，已自动回滚至安装前状态。')
        }
        if ($result.RebootNeeded) {
            [void]$lines.Add('')
            [void]$lines.Add('[*] 部分驱动需要重启后生效。')
        }

        $summaryText = $lines -join [Environment]::NewLine
        Write-CIODIYGuiLog -Message $summaryText

        # --- 更新首页「最近修复记录」---
        $txtRecent = Get-CIODIYGuiControl -Name 'TxtRecentRepairs'
        if ($txtRecent) {
            $stamp = Get-Date -Format 'MM/dd HH:mm'
            $statusStr = if ($rolledBack) { '已回滚' } elseif ($fail -gt 0) { "部分失败($fail)" } else { '成功' }
            $driverNames = ($allResults | ForEach-Object { $_.Device }) -join '、'
            $newLine = ("{0} | {1} | {2}" -f $stamp, $statusStr, $driverNames)
            $existing = if ($txtRecent.Text -eq '暂无修复记录') { '' } else { $txtRecent.Text }
            $recentLines = @($existing -split [Environment]::NewLine | Where-Object { $_ }) + @($newLine) | Select-Object -Last 5
            $txtRecent.Text = $recentLines -join [Environment]::NewLine
        }

        # --- 更新副标题 ---
        $sub = Get-CIODIYGuiControl -Name 'TxtSubtitle'
        if ($sub) {
            $sub.Text = if ($fail -eq 0) { "修复完成：成功安装 $ok 个驱动" } else { "修复完成：成功 $ok，失败 $fail（详见日志）" }
        }

        Update-CIODIYDriverGrid -scanResults $data.Scan.ScanResults -fixPlan $data.Scan.FixPlan -Scenario $data.Scenario
        Refresh-CIODIYHealthFromScan -ScanResults $data.Scan.ScanResults -FixPlan $data.Scan.FixPlan
        if (Get-Command Update-CIODIYDashboardPanel -ErrorAction SilentlyContinue) { Update-CIODIYDashboardPanel }
        if (Get-Command Update-CIODIYQuickFixPanel -ErrorAction SilentlyContinue) { Update-CIODIYQuickFixPanel }
        Set-CIODIYGuiProgress -Value 100

        $statusBar = if ($fail -eq 0 -and -not $rolledBack) { "修复完成 · 成功 $ok 项" } else { "修复完成 · 成功 $ok / 失败 $fail" }
        Set-CIODIYGuiBusyState -Busy $false -ProgressText $statusBar

        if ($rolledBack) {
            Show-CIODIYToast -Message "安装出错已自动回滚到安装前状态" -Level Warning -DurationMs 6000
        } elseif ($fail -gt 0) {
            Show-CIODIYToast -Message ("修复完成：成功 {0} 项，失败 {1} 项" -f $ok, $fail) -Level Warning -DurationMs 5000
        } else {
            Show-CIODIYToast -Message ("修复完成：成功安装 {0} 个驱动" -f $ok) -Level Success
        }

        # 自动跳转到首页，让用户看到更新后的「最近修复记录」
        if (Get-Command Invoke-CIODIYGuiThread -ErrorAction SilentlyContinue) {
            Invoke-CIODIYGuiThread {
                $navDash = Get-CIODIYGuiControl -Name 'BtnNavDashboard'
                if ($navDash) { $navDash.RaiseEvent([System.Windows.RoutedEventArgs]([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
            }
        }

        # --- 弹出结果对话框 ---
        if ($result.RebootNeeded -and -not $rolledBack) {
            $detailLines = @(("成功安装 {0} 个驱动" -f $ok))
            if ($fail -gt 0) {
                $failNames = (@($allResults | Where-Object { -not $_.Success } | ForEach-Object { $_.Device }) -join '、')
                $detailLines += ("失败 {0} 项: {1}" -f $fail, $failNames)
            }
            $detail = $detailLines -join [Environment]::NewLine

            $rebootChoice = Show-CIODIYRebootCountdown `
                -Title '驱动安装完成' `
                -Subtitle '系统将自动重启以应用新驱动' `
                -Detail $detail `
                -Seconds 30 `
                -Owner $ctx.Window

            if ($rebootChoice -eq 'now') {
                Show-CIODIYToast -Message '5 秒后系统将重启...' -Level Warning -DurationMs 4500
                Invoke-CIODIYReboot -DelaySeconds 5
            } else {
                Show-CIODIYToast -Message '已选择稍后重启，记得手动重启以应用新驱动' -Level Info -DurationMs 6000
            }
        } elseif ($fail -gt 0 -or $rolledBack) {
            $dlgMsg = if ($rolledBack) {
                "安装过程中发生错误，已自动回滚至安装前状态。" + [Environment]::NewLine + [Environment]::NewLine + "请查看「日志」页获取详情。"
            } else {
                ("安装完成：成功 $ok 项，失败 $fail 项。" + [Environment]::NewLine + [Environment]::NewLine +
                 "失败项: " + (@($allResults | Where-Object { -not $_.Success } | ForEach-Object { $_.Device }) -join '、') +
                 [Environment]::NewLine + [Environment]::NewLine + "请查看「日志」页获取详情。")
            }
            [System.Windows.MessageBox]::Show($dlgMsg, '安装完成（有失败项）', 'OK', 'Warning') | Out-Null
        }
    } -OnError {
        param($err)
        Write-CIODIYGuiLog -Message ("修复失败：{0}" -f $err)
        $sub = Get-CIODIYGuiControl -Name 'TxtSubtitle'
        if ($sub) { $sub.Text = '修复失败 — 请查看日志' }
        Set-CIODIYGuiBusyState -Busy $false
        Show-CIODIYToast -Message ("修复失败：{0}" -f $err) -Level Error -DurationMs 7000
    }
}

function Invoke-CIODIYDeployFromGui {
    $ctx = Get-CIODIYGuiContext
    if ($ctx.State.IsBusy) { return }
    if (-not (Test-IsAdmin)) {
        [System.Windows.MessageBox]::Show('装机模式需要管理员权限。请右键以管理员身份运行。', '需要管理员权限', 'OK', 'Warning') | Out-Null
        return
    }

    $chkDeployAutoFix = Get-CIODIYGuiControl -Name 'ChkDeployAutoFix'
    $chkDeployReboot = Get-CIODIYGuiControl -Name 'ChkDeployReboot'
    $chkDeployReport = Get-CIODIYGuiControl -Name 'ChkDeployReport'
    $chkDeploySilent = Get-CIODIYGuiControl -Name 'ChkDeploySilent'
    $chkRestore = Get-CIODIYGuiControl -Name 'ChkRestore'
    $chkBackup = Get-CIODIYGuiControl -Name 'ChkBackup'
    $chkRollback = Get-CIODIYGuiControl -Name 'ChkRollback'
    $chkOutdated = Get-CIODIYGuiControl -Name 'ChkOutdated'
    $progress = Get-CIODIYGuiControl -Name 'Progress'
    $txtProgress = Get-CIODIYGuiControl -Name 'TxtProgress'
    $window = $ctx.Window

    $autoFix = if ($chkDeployAutoFix) { [bool]$chkDeployAutoFix.IsChecked } else { $true }
    $reboot = if ($chkDeployReboot) { [bool]$chkDeployReboot.IsChecked } else { $false }
    $report = if ($chkDeployReport) { [bool]$chkDeployReport.IsChecked } else { $true }
    $silent = if ($chkDeploySilent) { [bool]$chkDeploySilent.IsChecked } else { $false }
    $restore = if ($chkRestore) { [bool]$chkRestore.IsChecked } else { $false }
    $backup = if ($chkBackup) { [bool]$chkBackup.IsChecked } else { $true }
    $rollback = if ($chkRollback) { [bool]$chkRollback.IsChecked } else { $false }
    $includeOut = if ($chkOutdated) { [bool]$chkOutdated.IsChecked } else { $false }

    if (-not $silent) {
        $msg = @(
            '装机模式将自动：', '1. 扫描全部设备',
            $(if ($autoFix) { '2. 安装所有「推荐」驱动' } else { '2. 仅扫描（不安装）' }),
            $(if ($report) { '3. 导出 HTML 报告' } else { '' }),
            $(if ($reboot) { '4. 完成后自动重启' } else { '' })
        ) -join [Environment]::NewLine
        if ([System.Windows.MessageBox]::Show($msg, '确认装机模式', 'YesNo', 'Question') -ne 'Yes') { return }
    }

    Set-CIODIYGuiBusyState -Busy $true -ProgressText '装机模式：正在扫描...'
    if ($progress) { $progress.Value = 8 }

    Start-CIODIYGuiWorker -DoWork {
        Invoke-DeployModeEngine -AutoFix:$autoFix -RebootIfNeeded:$reboot -ExportReport:$report `
            -Silent:$silent -FastMatch -Scenario 'all' -IncludeOutdated:$includeOut `
            -CreateRestorePoint:$restore -BackupFirst:$backup -RollbackOnError:$rollback `
            -AppVersion $ctx.AppVersion -OnLog $ctx.LogCallback             -OnProgress {
                param($pct, $name)
                $cap_pct  = [double]$pct
                $cap_name = [string]$name
                $cap_win  = $window
                [void]$window.Dispatcher.BeginInvoke([System.Action]({
                    $pb  = try { $cap_win.FindName('Progress')    } catch { $null }
                    $txt = try { $cap_win.FindName('TxtProgress') } catch { $null }
                    if (-not $pb)  { $pb  = (Get-CIODIYGuiControl -Name 'Progress') }
                    if (-not $txt) { $txt = (Get-CIODIYGuiControl -Name 'TxtProgress') }
                    if ($pb)  { $pb.Value  = $cap_pct }
                    if ($txt -and $cap_name) { $txt.Text = $cap_name }
                }.GetNewClosure()))
            }
    } -OnComplete {
        param($result)
        Import-AppManifest
        Update-CIODIYDriverGrid -scanResults $result.ScanResults -fixPlan $result.FixPlanAll -Scenario 'all'
        Refresh-CIODIYHealthFromScan -ScanResults $result.ScanResults -FixPlan $result.FixPlanAll
        if ($progress) { $progress.Value = 100 }
        $statusLabel = Get-DeployStatusLabel -Status $result.Status
        Set-CIODIYGuiBusyState -Busy $false -ProgressText ("装机完成：{0}" -f $statusLabel)
        Write-CIODIYGuiLog -Message ("装机模式完成 · {0} · 推荐安装 {1} 项" -f $statusLabel, @($result.FixPlanSelected).Count)
        if ($result.ReportPath) { Write-CIODIYGuiLog -Message ("报告: {0}" -f $result.ReportPath) }
        if (-not $silent) {
            $body = "状态: $statusLabel`n推荐安装: $($result.FixPlanSelected.Count) 项"
            if ($result.ReportPath) { $body += "`n报告: $($result.ReportPath)" }
            [System.Windows.MessageBox]::Show($body, '装机模式完成', 'OK', 'Information') | Out-Null
        }
        if ($reboot -and $result.RebootNeeded) {
            if ([System.Windows.MessageBox]::Show('驱动安装完成，是否现在重启？', '需要重启', 'YesNo', 'Question') -eq 'Yes') {
                Invoke-DeployReboot -DelaySec 30 -Force:$false
            }
        }
    } -OnError {
        param($err)
        Write-CIODIYGuiLog -Message ("装机模式失败：{0}" -f $err)
        Set-CIODIYGuiBusyState -Busy $false
    }
}

function Register-CIODIYGuiEvents {
    $ctx = Get-CIODIYGuiContext
    $window = $ctx.Window

    Register-CIODIYGuiNavigationEvents

    # ── Stat-card click handlers ──────────────────────────────────────────────

    # Helper: check if a scan has been completed (GridRows populated)
    # $ctx.State.ScanCompleted is never set; use GridRows.Count instead.
    $hasScanData = { @($ctx.State.GridRows).Count -gt 0 }

    # 驱动健康 → 展示所有问题（清除过滤），滚动到问题列表
    $cardHealth = Get-CIODIYGuiControl -Name 'CardHealth'
    if ($cardHealth) {
        $cardHealth.Add_Click({
            $c = Get-CIODIYGuiContext
            if (@($c.State.GridRows).Count -eq 0) {
                Show-CIODIYToast -Message '请先扫描以查看驱动健康详情' -Level Warning -DurationMs 3000
                return
            }
            Switch-CIODIYGuiPage -Page 'Dashboard'
            Set-CIODIYDashFilter -Mode 'all'
        })
    }

    # 问题设备 → 在首页显示全部问题设备（清除过滤）
    $cardIssues = Get-CIODIYGuiControl -Name 'CardIssues'
    if ($cardIssues) {
        $cardIssues.Add_Click({
            $c = Get-CIODIYGuiContext
            if (@($c.State.GridRows).Count -eq 0) {
                # 未扫描时点击 → 触发扫描
                $btnScan2 = Get-CIODIYGuiControl -Name 'BtnScan'
                if ($btnScan2 -and -not $c.State.IsBusy) {
                    $btnScan2.RaiseEvent([System.Windows.RoutedEventArgs]([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                }
                return
            }
            Switch-CIODIYGuiPage -Page 'Dashboard'
            Set-CIODIYDashFilter -Mode 'all'
        })
    }

    # 推荐修复 → 在首页过滤只显示可修复项
    $cardRecommended = Get-CIODIYGuiControl -Name 'CardRecommended'
    if ($cardRecommended) {
        $cardRecommended.Add_Click({
            $c = Get-CIODIYGuiContext
            if (@($c.State.GridRows).Count -eq 0) {
                Show-CIODIYToast -Message '请先扫描以获取推荐修复项' -Level Warning -DurationMs 3000
                return
            }
            Switch-CIODIYGuiPage -Page 'Dashboard'
            Set-CIODIYDashFilter -Mode 'recommended'
        })
    }

    # 驱动库 → 驱动合库 page
    $cardRepo = Get-CIODIYGuiControl -Name 'CardRepo'
    if ($cardRepo) {
        $cardRepo.Add_Click({
            Switch-CIODIYGuiPage -Page 'Repo'
        })
    }

    # 清除过滤按钮
    $btnClearFilter = Get-CIODIYGuiControl -Name 'BtnClearDashFilter'
    if ($btnClearFilter) {
        $btnClearFilter.Add_Click({
            Set-CIODIYDashFilter -Mode 'all'
        })
    }

    $btnDismissWelcome = Get-CIODIYGuiControl -Name 'BtnDismissWelcome'
    if ($btnDismissWelcome) {
        $btnDismissWelcome.Add_Click({
            Set-OnboardingDismissed
            # Fetch control inside handler — outer local vars are not in scope for WPF event scriptblocks
            $bw = Get-CIODIYGuiControl -Name 'BorderWelcome'
            if ($bw) { $bw.Visibility = 'Collapsed' }
        })
    }

    $btnRepoRepair = Get-CIODIYGuiControl -Name 'BtnRepoRepair'
    if ($btnRepoRepair) {
        $btnRepoRepair.Add_Click({
            if ($ctx.State.IsBusy) { return }
            Set-CIODIYGuiBusyState -Busy $true -ProgressText '正在修复驱动库...'
            Start-CIODIYGuiWorker -DoWork {
                Invoke-DriverRepositoryRepairEngine -OnLog $ctx.LogCallback
            } -OnComplete {
                param($result)
                if ($result.Success) {
                    Update-CIODIYRepoHealthPanel -RepoHealth $result.Data
                    Write-CIODIYGuiLog -Message $result.Message
                    Set-CIODIYGuiBusyState -Busy $false -ProgressText ('驱动库修复完成：{0}%' -f $result.Data.HealthPercent)
                } else {
                    Write-CIODIYGuiLog -Message ("驱动库修复失败：{0}" -f $result.Message)
                    Set-CIODIYGuiBusyState -Busy $false
                }
            } -OnError {
                param($err)
                Write-CIODIYGuiLog -Message ("驱动库修复失败：{0}" -f $err)
                Set-CIODIYGuiBusyState -Busy $false
            }
        })
    }

    $window.Add_Loaded({
        Write-CIODIYGuiLog -Message 'Yanbai驱动已就绪，点击「立即扫描」开始。'
        $txtProgress = Get-CIODIYGuiControl -Name 'TxtProgress'
        $txtManifestVer = Get-CIODIYGuiControl -Name 'TxtManifestVer'
        $txtSubtitle = Get-CIODIYGuiControl -Name 'TxtSubtitle'
        if ($txtProgress) { $txtProgress.Text = '就绪' }
        if ($txtSubtitle) { $txtSubtitle.Text = 'Win10/Win11 智能驱动检测 · 扫描后一键修复' }

        $deferBootstrap = {
            Start-CIODIYGuiWorker -DoWork {
                Invoke-AppBootstrapEngine -OnLog $ctx.LogCallback -Background
            } -OnComplete {
                param($manifest)
                if ($manifest) {
                    $ctx.State.Manifest = $manifest
                    if ($txtManifestVer) { $txtManifestVer.Text = 'v' + $manifest.version }
                    Write-CIODIYGuiLog -Message ("驱动库已更新 v{0}" -f $manifest.version)
                }
                Update-CIODIYDriverSourcePanel
                if ($txtProgress) { $txtProgress.Text = '就绪' }
            } -OnError {
                param($err)
                Write-CIODIYGuiLog -Message ("驱动库同步跳过: {0}" -f $err)
            }
        }

        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(8)
        $timer.Add_Tick(({
            param($sender, $e)
            $sender.Stop()
            & $deferBootstrap
        }).GetNewClosure())
        $timer.Start()
    })

    $btnScan = Get-CIODIYGuiControl -Name 'BtnScan'
    if ($btnScan) {
        $btnScan.Add_Click({
            if ($ctx.State.IsBusy) { return }
            Update-CIODIYScenarioBanner -Scenario 'all'
            $ctx.State.Scenario = 'all'
            $chkOutdated = Get-CIODIYGuiControl -Name 'ChkOutdated'
            $txtSubtitle = Get-CIODIYGuiControl -Name 'TxtSubtitle'
            $includeOut = if ($chkOutdated) { [bool]$chkOutdated.IsChecked } else { $false }
            Set-CIODIYGuiBusyState -Busy $true -ProgressText '正在扫描设备...'
            Set-CIODIYGuiProgress -Value 5
            if ($txtSubtitle) { $txtSubtitle.Text = '正在枚举硬件设备...' }
            Show-CIODIYToast -Message '正在扫描硬件，请稍候...' -Level Info
            $scanWindow = $ctx.Window
            Start-CIODIYGuiWorker -DoWork {
                # Build a scan-progress callback that posts UI updates via the Dispatcher.
                # This runs in the worker runspace, so we capture $scanWindow explicitly.
                $captured_scanWin = $scanWindow
                $scanProgressCb = {
                    param($pct, $msg)
                    $cp = $pct; $cm = [string]$msg
                    $cm = ($cm -replace '[\x00-\x1F\x7F]', '').Trim()
                    if (-not $cm) { $cm = '正在扫描...' }
                    try {
                        [void]$captured_scanWin.Dispatcher.BeginInvoke([System.Action]({
                            $pb  = try { $captured_scanWin.FindName('Progress')    } catch { $null }
                            $txt = try { $captured_scanWin.FindName('TxtProgress') } catch { $null }
                            if ($pb)  { $pb.IsIndeterminate = $false; $pb.Value = $cp }
                            if ($txt) { $txt.Text = $cm }
                        }.GetNewClosure()))
                    } catch {}
                }.GetNewClosure()
                Invoke-AppScan -PassThru -FastMatch -Scenario 'all' -IncludeOutdated:$includeOut -OnLog $ctx.LogCallback -OnProgress $scanProgressCb
            } -OnComplete {
                param($result)
                $guiCtx = Get-CIODIYGuiContext
                $scanResults = @($result.ScanResults)
                $fixPlan     = @($result.FixPlan)
                Update-CIODIYDriverGrid -scanResults $scanResults -fixPlan $fixPlan -Scenario 'all'
                Refresh-CIODIYHealthFromScan -ScanResults $scanResults -FixPlan $fixPlan
                Set-CIODIYGuiProgress -Value 100
                $scanSummary = $guiCtx.State.RepairSummary.ScanCompleteLine
                $devCount = $scanResults.Count
                $fixCount = $fixPlan.Count
                Set-CIODIYGuiBusyState -Busy $false -ProgressText $scanSummary
                $sub = Get-CIODIYGuiControl -Name 'TxtSubtitle'
                if ($sub) { $sub.Text = if ($scanSummary) { $scanSummary } else { 'Win10/Win11 智能驱动检测 · 扫描后一键修复' } }
                if ($fixCount -gt 0) {
                    Show-CIODIYToast -Message ("扫描完成：{0} 个设备，{1} 项可修复" -f $devCount, $fixCount) -Level Success
                } else {
                    Show-CIODIYToast -Message ("扫描完成：{0} 个设备，所有驱动都已是最新" -f $devCount) -Level Success
                }
            } -OnError {
                param($err)
                Write-CIODIYGuiLog -Message ("扫描失败：{0}" -f $err)
                Set-CIODIYGuiBusyState -Busy $false
                $sub = Get-CIODIYGuiControl -Name 'TxtSubtitle'
                if ($sub) { $sub.Text = 'Win10/Win11 智能驱动检测 · 扫描后一键修复' }
                Show-CIODIYToast -Message ("扫描失败：{0}" -f $err) -Level Error -DurationMs 6000
            }
        })
    }

    $btnScenarioAll = Get-CIODIYGuiControl -Name 'BtnScenarioAll'
    if ($btnScenarioAll) {
        $btnScenarioAll.Add_Click({
            if ($ctx.State.IsBusy) { return }
            $ctx.State.Scenario = 'all'
            Update-CIODIYScenarioBanner -Scenario 'all'
            $chkOutdated = Get-CIODIYGuiControl -Name 'ChkOutdated'
            $progress = Get-CIODIYGuiControl -Name 'Progress'
            $includeOut = if ($chkOutdated) { [bool]$chkOutdated.IsChecked } else { $false }
            Set-CIODIYGuiBusyState -Busy $true -ProgressText '正在扫描全部设备...'
            if ($progress) { $progress.Value = 5 }
            $scanWin2 = $ctx.Window
            Start-CIODIYGuiWorker -DoWork {
                $captured_scanWin2 = $scanWin2
                $scanProgressCb2 = {
                    param($pct, $msg)
                    $cp = $pct; $cm = ([string]$msg -replace '[\x00-\x1F\x7F]', '').Trim()
                    if (-not $cm) { $cm = '正在扫描...' }
                    try {
                        [void]$captured_scanWin2.Dispatcher.BeginInvoke([System.Action]({
                            $pb  = try { $captured_scanWin2.FindName('Progress')    } catch { $null }
                            $txt = try { $captured_scanWin2.FindName('TxtProgress') } catch { $null }
                            if ($pb)  { $pb.IsIndeterminate = $false; $pb.Value = $cp }
                            if ($txt) { $txt.Text = $cm }
                        }.GetNewClosure()))
                    } catch {}
                }.GetNewClosure()
                Invoke-AppScan -PassThru -FastMatch -Scenario 'all' -IncludeOutdated:$includeOut -OnLog $ctx.LogCallback -OnProgress $scanProgressCb2
            } -OnComplete {
                param($result)
                if (-not $result) { Set-CIODIYGuiBusyState -Busy $false; return }
                Update-CIODIYDriverGrid -scanResults $result.ScanResults -fixPlan $result.FixPlan -Scenario 'all'
                Refresh-CIODIYHealthFromScan -ScanResults $result.ScanResults -FixPlan $result.FixPlan
                if ($progress) { $progress.Value = 100 }
                Set-CIODIYGuiBusyState -Busy $false -ProgressText ("全部设备：发现 {0} 项待修复" -f @($result.FixPlan).Count)
            } -OnError {
                param($err)
                Write-CIODIYGuiLog -Message ("扫描失败：{0}" -f $err)
                Set-CIODIYGuiBusyState -Busy $false
            }
        })
    }

    $btnScenarioAudio = Get-CIODIYGuiControl -Name 'BtnScenarioAudio'
    if ($btnScenarioAudio) { $btnScenarioAudio.Add_Click({ Invoke-CIODIYScenarioQuickFix -Scenario 'audio' }) }
    $btnScenarioNetwork = Get-CIODIYGuiControl -Name 'BtnScenarioNetwork'
    if ($btnScenarioNetwork) { $btnScenarioNetwork.Add_Click({ Invoke-CIODIYScenarioQuickFix -Scenario 'network' }) }
    $btnScenarioUsb = Get-CIODIYGuiControl -Name 'BtnScenarioUsb'
    if ($btnScenarioUsb) { $btnScenarioUsb.Add_Click({ Invoke-CIODIYScenarioQuickFix -Scenario 'usb' }) }

    $btnFixAll = Get-CIODIYGuiControl -Name 'BtnFixAll'
    if ($btnFixAll) {
        $btnFixAll.Add_Click({
            if ($ctx.State.IsBusy) { return }
            $plan = @(Get-CIODIYSelectedFixPlan)
            if ($plan.Count -eq 0) {
                [System.Windows.MessageBox]::Show('请先扫描并勾选要修复的驱动。', '提示', 'OK', 'Information') | Out-Null
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
        })
    }

    $btnSelectAll = Get-CIODIYGuiControl -Name 'BtnSelectAll'
    if ($btnSelectAll) { $btnSelectAll.Add_Click({ Set-CIODIYAllGridSelection -Selected $true }) }
    $btnSelectNone = Get-CIODIYGuiControl -Name 'BtnSelectNone'
    if ($btnSelectNone) { $btnSelectNone.Add_Click({ Set-CIODIYAllGridSelection -Selected $false }) }
    $btnSelectRecommended = Get-CIODIYGuiControl -Name 'BtnSelectRecommended'
    if ($btnSelectRecommended) { $btnSelectRecommended.Add_Click({ Set-CIODIYAllGridSelection -Selected $false -Filter 'recommended' }) }

    $btnRollbackLast = Get-CIODIYGuiControl -Name 'BtnRollbackLast'
    if ($btnRollbackLast) {
        $btnRollbackLast.Add_Click({
            if ($ctx.State.IsBusy) { return }
            if (-not (Test-IsAdmin)) {
                [System.Windows.MessageBox]::Show('请以管理员身份运行后再回滚。', '需要管理员权限', 'OK', 'Warning') | Out-Null
                return
            }
            $tx = Get-DriverLatestTransactionEngine
            if (-not $tx) {
                [System.Windows.MessageBox]::Show('没有可回滚的修复记录。', '回滚', 'OK', 'Information') | Out-Null
                return
            }
            $summary = Get-DriverTransactionSummaryEngine -Transaction $tx
            $msg = "上次修复时间：$($summary.TimeLabel)`n安装驱动：$($summary.DriverNames)`n结果：成功 $($summary.SuccessCount) 项，失败 $($summary.FailCount) 项`n`n确定回滚上次修复？"
            if ([System.Windows.MessageBox]::Show($msg, '回滚上次修复', 'YesNo', 'Question') -ne 'Yes') { return }
            Set-CIODIYGuiBusyState -Busy $true -ProgressText '正在回滚...'
            Start-CIODIYGuiWorker -DoWork {
                Invoke-DriverRollbackEngine -Last -OnLog $ctx.LogCallback
            } -OnComplete {
                param($results)
                Write-CIODIYGuiLog -Message ("回滚完成，已还原 {0} 项" -f @($results).Count)
                Set-CIODIYGuiBusyState -Busy $false -ProgressText '回滚完成'
            } -OnError {
                param($err)
                Write-CIODIYGuiLog -Message ("回滚失败：{0}" -f $err)
                Set-CIODIYGuiBusyState -Busy $false
            }
        })
    }

    $btnSync = Get-CIODIYGuiControl -Name 'BtnSync'
    if ($btnSync) {
        $btnSync.Add_Click({
            if ($ctx.State.IsBusy) { return }
            Set-CIODIYGuiBusyState -Busy $true -ProgressText '正在同步驱动镜像...'
            Start-CIODIYGuiWorker -DoWork {
                Invoke-DriverSyncEngine -OnLog $ctx.LogCallback
            } -OnComplete {
                param($manifest)
                $ctx.State.Manifest = $manifest
                $txtManifestVer = Get-CIODIYGuiControl -Name 'TxtManifestVer'
                if ($txtManifestVer) { $txtManifestVer.Text = 'v' + $manifest.version }
                Write-CIODIYGuiLog -Message ("镜像已同步 v{0}" -f $manifest.version)
                Set-CIODIYGuiBusyState -Busy $false -ProgressText '同步完成'
            } -OnError {
                param($err)
                Write-CIODIYGuiLog -Message ("同步失败：{0}" -f $err)
                Set-CIODIYGuiBusyState -Busy $false
            }
        })
    }

    $btnDeployStart = Get-CIODIYGuiControl -Name 'BtnDeployStart'
    if ($btnDeployStart) { $btnDeployStart.Add_Click({ Invoke-CIODIYDeployFromGui }) }

    $btnInstallLocal = Get-CIODIYGuiControl -Name 'BtnInstallLocal'
    if ($btnInstallLocal) {
        $btnInstallLocal.Add_Click({
            if ($ctx.State.IsBusy) { return }
            if (-not (Test-IsAdmin)) {
                [System.Windows.MessageBox]::Show('请以管理员身份运行。', '提示', 'OK', 'Warning') | Out-Null
                return
            }
            $chkRollback = Get-CIODIYGuiControl -Name 'ChkRollback'
            $rollback = if ($chkRollback) { [bool]$chkRollback.IsChecked } else { $false }
            Set-CIODIYGuiBusyState -Busy $true -ProgressText '正在安装本地驱动库...'
            Start-CIODIYGuiWorker -DoWork {
                Invoke-DriverInstallEngine -LocalLibraryOnly -RollbackOnError:$rollback -OnLog $ctx.LogCallback | Out-Null
            } -OnComplete {
                Write-CIODIYGuiLog -Message '本地驱动库安装完成。'
                Set-CIODIYGuiBusyState -Busy $false -ProgressText '完成'
            } -OnError {
                param($err)
                Write-CIODIYGuiLog -Message ("安装失败：{0}" -f $err)
                Set-CIODIYGuiBusyState -Busy $false
            }
        })
    }
}

function Register-CIODIYGuiNavigationEvents {
    $ctx = Get-CIODIYGuiContext

    $btnFixRec = Get-CIODIYGuiControl -Name 'BtnFixRecommended'
    if ($btnFixRec) { $btnFixRec.Add_Click({ Invoke-CIODIYFixRecommended }) }

    $btnQuickFix = Get-CIODIYGuiControl -Name 'BtnQuickFix'
    if ($btnQuickFix) { $btnQuickFix.Add_Click({ Invoke-CIODIYFixRecommended }) }

    $lstTx = Get-CIODIYGuiControl -Name 'LstTransactions'
    if ($lstTx) {
        $lstTx.Add_SelectionChanged({
            param($sender, $e)
            Update-CIODIYRollbackDetail -Item $sender.SelectedItem
        })
    }

    $btnRollbackSel = Get-CIODIYGuiControl -Name 'BtnRollbackSelected'
    if ($btnRollbackSel) {
        $btnRollbackSel.Add_Click({
            if ($ctx.State.IsBusy) { return }
            if (-not (Test-IsAdmin)) {
                [System.Windows.MessageBox]::Show('请以管理员身份运行后再回滚。', '需要管理员权限', 'OK', 'Warning') | Out-Null
                return
            }
            $lst = Get-CIODIYGuiControl -Name 'LstTransactions'
            if (-not $lst -or -not $lst.SelectedItem) {
                [System.Windows.MessageBox]::Show('请先选择一条事务记录。', '回滚', 'OK', 'Information') | Out-Null
                return
            }
            $tx = $lst.SelectedItem.Transaction
            $summary = $lst.SelectedItem.Summary
            $msg = "时间：$($summary.TimeLabel)`n驱动：$($summary.DriverNames)`n`n确定回滚此事务？"
            if ([System.Windows.MessageBox]::Show($msg, '回滚事务', 'YesNo', 'Question') -ne 'Yes') { return }
            Set-CIODIYGuiBusyState -Busy $true -ProgressText '正在回滚...'
            Start-CIODIYGuiWorker -DoWork {
                Invoke-DriverRollbackEngine -TxId $tx.Id -OnLog $ctx.LogCallback
            } -OnComplete {
                param($results)
                Write-CIODIYGuiLog -Message ("回滚完成，已还原 {0} 项" -f @($results).Count)
                Update-CIODIYRollbackPanel
                Set-CIODIYGuiBusyState -Busy $false -ProgressText '回滚完成'
            } -OnError {
                param($err)
                Write-CIODIYGuiLog -Message ("回滚失败：{0}" -f $err)
                Set-CIODIYGuiBusyState -Busy $false
            }
        })
    }
}

function Initialize-CIODIYGuiAfterLoad {
    Import-AppManifest
    $ctx = Get-CIODIYGuiContext
    $txtManifestVer = Get-CIODIYGuiControl -Name 'TxtManifestVer'

    Update-CIODIYDriverSourcePanel
    if ($ctx.State.Manifest -and $txtManifestVer) {
        $txtManifestVer.Text = 'v' + $ctx.State.Manifest.version
    } elseif ($txtManifestVer) {
        $txtManifestVer.Text = '本地'
    }
}
