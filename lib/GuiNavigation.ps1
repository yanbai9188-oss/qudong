# GUI page navigation (v1.8.0) — 8-page shell, structure frozen for v2.0

$script:CIODIYCurrentPage = 'Dashboard'

$script:CIODIYPageNames = @(
    'Dashboard', 'Drivers', 'QuickFix', 'Deploy', 'Repo', 'Rollback', 'Logs', 'Settings'
)

function Get-CIODIYPageControlName {
    param([Parameter(Mandatory)][string]$Page)
    return 'Page' + $Page
}

function Get-CIODIYNavButtonName {
    param([Parameter(Mandatory)][string]$Page)
    return 'BtnNav' + $Page
}

function Switch-CIODIYGuiPage {
    param([Parameter(Mandatory)][string]$Page)

    if ($Page -notin $script:CIODIYPageNames) { return }

    $ctx = Get-CIODIYGuiContext
    $script:CIODIYCurrentPage = $Page

    foreach ($p in $script:CIODIYPageNames) {
        $panel = Get-CIODIYGuiControl -Name (Get-CIODIYPageControlName -Page $p)
        if ($panel) {
            $panel.Visibility = if ($p -eq $Page) { 'Visible' } else { 'Collapsed' }
        }
        $navBtn = Get-CIODIYGuiControl -Name (Get-CIODIYNavButtonName -Page $p)
        if ($navBtn) {
            $navBtn.Tag = if ($p -eq $Page) { 'Active' } else { 'Inactive' }
        }
    }

    switch ($Page) {
        'Dashboard' { Update-CIODIYDashboardPanel }
        'QuickFix'  { Update-CIODIYQuickFixPanel }
        'Rollback'  { Update-CIODIYRollbackPanel }
        'Repo'      { Update-CIODIYRepoPagePanel }
        default     { }
    }
}

function Register-CIODIYGuiNavigation {
    foreach ($p in $script:CIODIYPageNames) {
        $btnName = Get-CIODIYNavButtonName -Page $p
        $btn = Get-CIODIYGuiControl -Name $btnName
        if (-not $btn) { continue }
        $pageCopy = $p
        $btn.Add_Click({
            Switch-CIODIYGuiPage -Page $pageCopy
        }.GetNewClosure())
    }
    Switch-CIODIYGuiPage -Page 'Dashboard'
}

function Get-CIODIYCurrentPage {
    return $script:CIODIYCurrentPage
}
