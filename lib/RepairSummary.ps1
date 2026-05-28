# Unified repair counts — single source of truth (v1.6.5)

function Get-VisibleFixPlanItems {
    param([Parameter(Mandatory)][array]$FixPlan)

    return @($FixPlan | Where-Object {
        if ($_.Action -eq 'NoSource') { return $false }
        if ($_.HideFromList) { return $false }
        if ($_.IsDependency -and $_.AttachedToParent) { return $false }
        if ($_.IsDependency -and $_.Device.IsSynthetic -and -not $_.Device.IsProblem) { return $false }
        return $true
    })
}

function Get-RepairSummary {
    param(
        [Parameter(Mandatory)][array]$FixPlan,
        [array]$ScanResults = @(),
        [string]$Scenario = 'all',
        [array]$GridRows = @()
    )

    $visible = @(Get-VisibleFixPlanItems -FixPlan $FixPlan)
    $strongly = 0
    $recommended = 0
    $optional = 0
    $unsafe = 0

    foreach ($item in $visible) {
        $tier = Get-RecommendTier -Item $item
        switch ($tier) {
            '强烈推荐' { $strongly++ }
            '推荐'     { $recommended++ }
            '可选'     { $optional++ }
            default    { $unsafe++ }
        }
    }

    $autoSelect = $strongly + $recommended
    $selected = if (@($GridRows).Count -gt 0) {
        @($GridRows | Where-Object { $_.IsSelected }).Count
    } else {
        $autoSelect
    }

    $problemDevices = if ($Scenario -ne 'all') {
        $visible.Count
    } else {
        @($ScanResults | Where-Object { $_.IsProblem }).Count
    }

    $total = $visible.Count
    $recTotal = $autoSelect
    $breakdown = ('发现问题：{0}  推荐修复：{1}  可选：{2}  不建议：{3}' -f $total, $recTotal, $optional, $unsafe)

    return [PSCustomObject]@{
        TotalDetected   = $total
        Strongly        = $strongly
        RecommendedTier = $recommended
        Recommended     = $recTotal
        Optional        = $optional
        Unsafe          = $unsafe
        DefaultSelected = $autoSelect
        Selected        = $selected
        ProblemDevices  = $problemDevices
        StatusLine      = $breakdown
        BreakdownLine   = $breakdown
        HealthLine      = ('推荐修复：{0}' -f $recTotal)
        ScanCompleteLine = ('扫描完成：{0}（已默认勾选 {1} 项）' -f $breakdown, $recTotal)
    }
}

function Expand-SelectedFixPlan {
    param(
        [Parameter(Mandatory)][array]$SelectedItems,
        [Parameter(Mandatory)][array]$FullFixPlan
    )

    $result = New-Object System.Collections.ArrayList
    $seen = New-Object System.Collections.Generic.HashSet[string]

    foreach ($item in $SelectedItems) {
        $sig = if ($item.MergeKey) { $item.MergeKey } else { Get-CIODIYDeviceKey -Device $item.Device }
        if (-not $seen.Contains($sig)) {
            [void]$seen.Add($sig)
            [void]$result.Add($item)
        }
        foreach ($dep in @($item.Dependencies)) {
            $dsig = if ($dep.MergeKey) { $dep.MergeKey } else { "dep:$($dep.Package.Id)" }
            if (-not $seen.Contains($dsig)) {
                [void]$seen.Add($dsig)
                [void]$result.Add($dep)
            }
        }
    }

    return @($result.ToArray())
}
