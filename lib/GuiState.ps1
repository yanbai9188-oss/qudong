# GUI context and shared state (v1.8.0)

$script:CIODIYGuiContext = $null

function Initialize-CIODIYGuiContext {
    param(
        [Parameter(Mandatory)]$Window,
        [Parameter(Mandatory)]$Controls,
        [string]$AppVersion = '2.2.2',
        $SessionState = $null
    )

    if (-not $SessionState) {
        $SessionState = Get-AppSessionState
    }

    $script:CIODIYGuiContext = [PSCustomObject]@{
        Window      = $Window
        Controls    = $Controls
        State       = $SessionState
        AppVersion  = $AppVersion
        LogCallback = $null
    }
    return $script:CIODIYGuiContext
}

function Get-CIODIYGuiContext {
    if (-not $script:CIODIYGuiContext) {
        throw 'GUI context not initialized'
    }
    return $script:CIODIYGuiContext
}

function Get-CIODIYGuiControl {
    param([Parameter(Mandatory)][string]$Name)
    $ctx = Get-CIODIYGuiContext
    if ($ctx.Controls.ContainsKey($Name)) { return $ctx.Controls[$Name] }
    return $null
}

function Get-OnboardingStatePath {
    return Join-Path (Get-AppDataRoot) 'Cache\onboarding.json'
}

function Test-ShouldShowOnboarding {
    $path = Get-OnboardingStatePath
    if (-not (Test-Path $path)) { return $true }
    try {
        $state = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        return -not [bool]$state.dismissed_v180
    } catch {
        return $true
    }
}

function Set-OnboardingDismissed {
    $path = Get-OnboardingStatePath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    (@{ dismissed_v180 = $true; at = (Get-Date -Format 'o') } | ConvertTo-Json) | Set-Content $path -Encoding UTF8
}

function Get-CIODIYGuiControlsFromWindow {
    param([Parameter(Mandatory)]$Window)

    $names = @(
        'BtnNavDashboard','BtnNavDrivers','BtnNavQuickFix','BtnNavDeploy','BtnNavRepo','BtnNavRollback','BtnNavLogs','BtnNavSettings',
        'PageDashboard','PageDrivers','PageQuickFix','PageDeploy','PageRepo','PageRollback','PageLogs','PageSettings',
        'BtnScan','BtnFixAll','BtnFixRecommended','BtnQuickFix','BtnSync','BtnInstallLocal',
        'BtnScenarioAudio','BtnScenarioNetwork','BtnScenarioUsb','BtnScenarioAll',
        'BtnRollbackLast','BtnRollbackSelected','BtnSelectAll','BtnSelectNone','BtnSelectRecommended',
        'TxtDriverSource','TxtSourceDetail','TxtScenario','GridDrivers','TxtLog',
        'TxtMachineTitle','TxtMachinePlatform','TxtMachineSpecs','TxtSubtitle','Progress','TxtProgress','TxtProgressPercent','StatusDot','ToastHost',
        'TxtIssueCount','TxtIssueCountOverview','TxtHealthScore','TxtHealthLabel','TxtHealthTips',
        'TxtRecommendedFix','TxtOptionalFix','TxtUnsafeFix','TxtRepoHealth','TxtDashRepoHealth','TxtRepoDetail',
        'BtnRepoRepair','CardHealth','CardIssues','CardRecommended','CardRepo','TxtManifestVer','TxtAppVersion',
        'ChkRestore','ChkBackup','ChkOutdated','ChkRollback',
        'ChkDeployAutoFix','ChkDeployReboot','ChkDeployReport','ChkDeploySilent','BtnDeployStart',
        'BorderWelcome','BtnDismissWelcome','TxtDriverDetail','TxtVersionSummary',
        'LstProblemDevices','BorderProblemEmpty','TxtProblemCount',
        'DashFilterBar','TxtDashFilterLabel','BtnClearDashFilter',
        'TxtQuickFixSummary','TxtProblemDevices','TxtRecentRepairs','LstTransactions','TxtRollbackDetail',
        'DriverDetailDrawer','DriverDetailDrawerTransform','TxtDrawerDeviceName',
        'TxtDrawerCurrentVer','TxtDrawerTargetVer','DrawerBadges','DrawerDetailList',
        'BtnDrawerClose','BtnDrawerCopyHwid'
    )

    $controls = @{}
    foreach ($n in $names) {
        $el = $Window.FindName($n)
        if ($el) { $controls[$n] = $el }
    }
    return $controls
}
