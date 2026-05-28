# Windows OS profile for driver package matching (Win10-first CIODIY)

function Get-SystemOsProfile {
    if ($script:CachedOsProfile) { return $script:CachedOsProfile }

    $build = 0
    $caption = ''
    $arch = 'x64'
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $build = [int]$os.BuildNumber
        $caption = [string]$os.Caption
        $arch = if ($os.OSArchitecture -match '64') { 'x64' } else { 'x86' }
    } catch { }

    $family = if ($build -ge 22000) { 'win11' } elseif ($build -ge 10240) { 'win10' } else { 'legacy' }
    $label = switch ($family) {
        'win11' { 'Windows 11' }
        'win10' { 'Windows 10' }
        default { 'Windows (legacy)' }
    }

    $script:CachedOsProfile = [PSCustomObject]@{
        Caption    = $caption
        Build      = $build
        Family     = $family
        Label      = $label
        Arch       = $arch
        IsWin10    = ($family -eq 'win10')
        IsWin11    = ($family -eq 'win11')
        IsSupported = ($family -in @('win10', 'win11'))
    }
    return $script:CachedOsProfile
}

function Test-PackageOsCompatible {
    param(
        $Package,
        $OsProfile = $null
    )

    if (-not $OsProfile) { $OsProfile = Get-SystemOsProfile }
    if (-not $OsProfile.IsSupported) { return $false }

    $osTags = @()
    if ($Package.Os) { $osTags = @($Package.Os) }
    elseif ($Package._RawOs) { $osTags = @($Package._RawOs) }

    if ($osTags.Count -gt 0) {
        if ($OsProfile.Family -notin $osTags) { return $false }
    }

    if ($null -ne $Package.OsMinBuild -and $Package.OsMinBuild -gt 0) {
        if ($OsProfile.Build -lt [int]$Package.OsMinBuild) { return $false }
    }
    if ($null -ne $Package.OsMaxBuild -and $Package.OsMaxBuild -gt 0) {
        if ($OsProfile.Build -gt [int]$Package.OsMaxBuild) { return $false }
    }

    return $true
}

function Get-OsMatchScore {
    param(
        $Package,
        $OsProfile = $null
    )

    if (-not $OsProfile) { $OsProfile = Get-SystemOsProfile }
    if (-not (Test-PackageOsCompatible -Package $Package -OsProfile $OsProfile)) { return 0 }

    $score = 3
    $osTags = @()
    if ($Package.Os) { $osTags = @($Package.Os) }

    if ($OsProfile.IsWin10 -and ($osTags -contains 'win10') -and ($osTags -notcontains 'win11')) {
        $score += 4
    }
    if ($Package.Win10Preferred) { $score += 3 }
    return $score
}
