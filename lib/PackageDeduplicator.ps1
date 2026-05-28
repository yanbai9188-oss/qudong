# Merge fix-plan rows that share the same driver package (v1.6.6)

function Merge-PackageDuplicateRows {
    param([Parameter(Mandatory)][array]$FixPlan)

    if ($FixPlan.Count -le 1) { return @($FixPlan) }

    $visible = New-Object System.Collections.ArrayList
    $hidden = New-Object System.Collections.ArrayList
    foreach ($item in $FixPlan) {
        if ($item.HideFromList) { [void]$hidden.Add($item) }
        else { [void]$visible.Add($item) }
    }

    if ($visible.Count -le 1) {
        return @($FixPlan)
    }

    $groups = @{}
    $order = New-Object System.Collections.ArrayList
    foreach ($item in @($visible)) {
        $pkgId = if ($item.Package -and $item.Package.Id) { [string]$item.Package.Id } else { "none:$($item.MergeKey)" }
        if (-not $groups.ContainsKey($pkgId)) {
            $groups[$pkgId] = New-Object System.Collections.ArrayList
            [void]$order.Add($pkgId)
        }
        [void]$groups[$pkgId].Add($item)
    }

    $merged = New-Object System.Collections.ArrayList
    foreach ($pkgId in $order) {
        $items = @($groups[$pkgId])
        if ($items.Count -eq 1 -or $pkgId -like 'none:*') {
            [void]$merged.Add($items[0])
            continue
        }

        $best = @($items | Sort-Object @{
            Expression = { if ($null -ne $_.Score) { [int]$_.Score } else { 0 } }
            Descending = $true
        })[0]

        $labels = New-Object System.Collections.ArrayList
        foreach ($it in $items) {
            $lbl = Resolve-CIODIYDeviceName -Device $it.Device -Package $it.Package
            $lbl = Format-CIODIYDeviceDisplayName -Name $lbl -Device $it.Device -Package $it.Package
            if ($labels -notcontains $lbl) { [void]$labels.Add($lbl) }
        }

        $groupName = if ($pkgId -match 'chipset|mei|serial') {
            'Intel 芯片组设备'
        } else {
            ($labels | Select-Object -First 1)
        }

        $best.Device | Add-Member -NotePropertyName MergedCount -NotePropertyValue $items.Count -Force
        $best.Device | Add-Member -NotePropertyName PackageGroupLabels -NotePropertyValue @($labels.ToArray()) -Force
        $best.Device | Add-Member -NotePropertyName FriendlyName -NotePropertyValue $groupName -Force
        $best | Add-Member -NotePropertyName PackageGroupCount -NotePropertyValue $items.Count -Force
        if ($items.Count -gt 1) {
            $best | Add-Member -NotePropertyName MergeKey -NotePropertyValue ("pkggroup:$pkgId") -Force
        }
        [void]$merged.Add($best)
    }

    return @($merged.ToArray()) + @($hidden.ToArray())
}
