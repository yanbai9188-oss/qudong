# WPF DataGrid row with two-way checkbox binding (v1.6.6 trust tiers)

if (-not ('DriverGridRow' -as [type])) {
    Add-Type -ReferencedAssemblies 'PresentationFramework', 'WindowsBase' -Language CSharp @"
using System.ComponentModel;
public class DriverGridRow : INotifyPropertyChanged {
    bool _sel;
    public bool IsSelected {
        get { return _sel; }
        set { if (_sel != value) { _sel = value; OnChanged("IsSelected"); } }
    }
    public string Category { get; set; }
    public string DeviceName { get; set; }
    public string RecommendTier { get; set; }
    public string IssueDetail { get; set; }
    public string PackageTitle { get; set; }
    public string Confidence { get; set; }
    public string ActionLabel { get; set; }
    public string TrustBadge { get; set; }
    public string VersionStatus { get; set; }
    public string DeviceKey { get; set; }
    public string Status { get; set; }
    public bool HasDependencies { get; set; }
    public string ButtonText { get; set; }
    public bool CanFix { get; set; }
    public event PropertyChangedEventHandler PropertyChanged;
    void OnChanged(string n) {
        if (PropertyChanged != null) PropertyChanged(this, new PropertyChangedEventArgs(n));
    }
}
"@
}

function Get-DependencyDisplayLine {
    param($Item)

    $deps = @($Item.Dependencies)
    if ($deps.Count -eq 0) { return '' }
    $titles = @($deps | ForEach-Object {
        if ($_.Package) { Get-PackageDisplayTitle -Package $_.Package } else { '' }
    } | Where-Object { $_ })
    if ($titles.Count -eq 0) { return '' }
    $lines = @('附加组件：')
    foreach ($t in $titles) {
        $lines += ('  └ {0}' -f $t)
    }
    return ($lines -join [Environment]::NewLine)
}

function Get-PackageTitleWithDeps {
    param($Item)

    $title = Get-PackageDisplayTitle -Package $Item.Package
    $depLine = Get-DependencyDisplayLine -Item $Item
    if ($depLine) { return "$title`n$depLine" }
    return $title
}

function Get-IssueDetailLabel {
    param($Item)
    if (-not $Item) { return '-' }
    $dev = $Item.Device
    if ($Item.IsOutdated) { return '版本过旧' }
    if ($dev.IsProblem -or [string]$dev.Status -match 'Error|Problem|Unknown') {
        if ([string]::IsNullOrWhiteSpace($dev.DriverVersion)) { return '未安装' }
        if ($dev.CategoryLabel -match '无线|Wi|网络|Net' -or $dev.Class -eq 'Net') { return '无网络' }
        return '设备异常'
    }
    if ($Item.Action -in @('NoSource', 'CatalogSearch')) { return '暂无匹配包' }
    return '已有兼容驱动'
}

function New-DriverGridRowFromItem {
    param(
        [Parameter(Mandatory)]$Item,
        [switch]$SelectRecommended
    )
    $dev = $Item.Device
    $pkg = $Item.Package
    $tier = Get-RecommendTier -Item $Item
    $devKey = if ($Item.MergeKey) { $Item.MergeKey } elseif ($dev.MergeKey) { $dev.MergeKey } else { Get-CIODIYDeviceKey -Device $dev }

    $row = New-Object DriverGridRow
    $row.DeviceKey = [string]$devKey
    $row.Category = [string]$dev.CategoryLabel
    $row.DeviceName = Get-DeviceDisplayName -Device $dev -Package $pkg
    $row.RecommendTier = $tier
    $row.IssueDetail = Get-IssueDetailLabel -Item $Item
    $row.PackageTitle = Get-PackageTitleWithDeps -Item $Item
    $row.Confidence = (Format-ConfidenceLabel -Item $Item)
    $row.ActionLabel = (Get-ActionUserLabel -Action $Item.Action)
    $row.Status = (Get-StatusLabel -Device $dev -IsOutdated $Item.IsOutdated)
    $details = Get-DriverFixItemDetails -Item $Item
    $row.TrustBadge = $details.TrustBadge
    $row.VersionStatus = $details.VersionStatusLabel
    $row.HasDependencies = (@($Item.Dependencies).Count -gt 0)
    $row.IsSelected = (Test-RecommendTierAutoSelect -Tier $tier)

    # Per-row action button label and enabled state (mirrors Driver Booster per-item actions)
    switch ($Item.Action) {
        'InstallLocal'        { $row.ButtonText = '修复';      $row.CanFix = $true  }
        'DownloadThenInstall' { $row.ButtonText = '下载并修复'; $row.CanFix = $true  }
        'CatalogSearch'       { $row.ButtonText = '搜索驱动';  $row.CanFix = $true  }
        'NoSource'            { $row.ButtonText = '查看建议';  $row.CanFix = $false }
        default               { $row.ButtonText = '详情';      $row.CanFix = $false }
    }

    return $row
}
