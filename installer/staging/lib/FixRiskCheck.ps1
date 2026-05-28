# Pre-install risk assessment (v1.8)

function Get-FixItemInstallRisk {
    param([Parameter(Mandatory)]$Item)

    $trustRisk = Get-PackageTrustRisk -Item $Item
    $level = $trustRisk.Level

    if ($Item.IsOutdated -and $level -eq 'low') {
        $cur = [string]$Item.Device.DriverVersion
        $tgt = [string]$Item.TargetVersion
        if ($cur -and $tgt) {
            $cmp = Compare-DriverVersion -Installed $cur -Available $tgt
            if ($cmp -ge 0) {
                $level = 'medium'
                $trustRisk.Reasons += 'installed version not older than target'
            }
        }
    }

    return [PSCustomObject]@{
        Level   = $level
        Reasons = @($trustRisk.Reasons)
    }
}

function Get-FixPlanRiskAssessment {
    param([Parameter(Mandatory)][array]$FixPlan)

    $low = 0
    $medium = 0
    $high = 0
    $reboot = 0
    $blocked = New-Object System.Collections.ArrayList
    $items = New-Object System.Collections.ArrayList

    foreach ($item in @($FixPlan)) {
        $risk = Get-FixItemInstallRisk -Item $item
        [void]$items.Add([PSCustomObject]@{
            Item    = $item
            Risk    = $risk.Level
            Reasons = @($risk.Reasons)
        })

        switch ($risk.Level) {
            'high'   { $high++; [void]$blocked.Add($item) }
            'medium' { $medium++ }
            default  { $low++ }
        }

        $details = Get-DriverFixItemDetails -Item $item
        if ($details.RebootRequired) { $reboot++ }
    }

    $summary = ('Install {0} | low {1} | medium {2} | high {3} | reboot {4}' -f `
        $FixPlan.Count, $low, $medium, $high, $reboot)

    return [PSCustomObject]@{
        Total          = $FixPlan.Count
        LowRisk        = $low
        MediumRisk     = $medium
        HighRisk       = $high
        RebootCount    = $reboot
        AllowDefault   = ($high -eq 0)
        BlockedItems   = @($blocked)
        Items          = @($items)
        SummaryLine    = $summary
        ConfirmMessage = @(
            $summary,
            '',
            $(if ($high -gt 0) { "High risk: $high item(s) - review before install" } else { 'All items acceptable risk' }),
            'Driver backup and transaction protection enabled'
        ) -join [Environment]::NewLine
    }
}

function Test-FixPlanAllowedToInstall {
    param(
        [Parameter(Mandatory)][array]$FixPlan,
        [switch]$AllowMedium,
        [switch]$AllowHigh
    )

    $assessment = Get-FixPlanRiskAssessment -FixPlan $FixPlan
    if ($assessment.HighRisk -gt 0 -and -not $AllowHigh) { return $false }
    if ($assessment.MediumRisk -gt 0 -and -not $AllowMedium -and -not $AllowHigh) {
        if ($assessment.LowRisk -eq 0) { return $false }
    }
    return $true
}
