# Reboot countdown dialog (v1.8.9)
# Replaces the harsh shutdown.exe /r /t 30 with a friendly WPF countdown.

function Show-CIODIYRebootCountdown {
    param(
        [string]$Title = '驱动安装完成',
        [string]$Subtitle = '部分驱动需要重启后才能生效',
        [string]$Detail = '',
        [int]$Seconds = 30,
        $Owner = $null
    )

    Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
    Add-Type -AssemblyName PresentationCore       -ErrorAction SilentlyContinue
    Add-Type -AssemblyName WindowsBase            -ErrorAction SilentlyContinue

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Width="480" Height="360" WindowStartupLocation="CenterOwner"
        Topmost="True" ResizeMode="NoResize" ShowInTaskbar="False">
  <Border Background="#1A1F2C" CornerRadius="14" BorderBrush="#FF6B00" BorderThickness="2" Margin="14">
    <Border.Effect>
      <DropShadowEffect BlurRadius="28" ShadowDepth="0" Color="Black" Opacity="0.6"/>
    </Border.Effect>
    <Grid Margin="28,22,28,22">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <StackPanel Grid.Row="0" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,0,0,10">
        <Border Width="44" Height="44" CornerRadius="10" VerticalAlignment="Center">
          <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
              <GradientStop Color="#22C55E" Offset="0"/>
              <GradientStop Color="#16A34A" Offset="1"/>
            </LinearGradientBrush>
          </Border.Background>
          <TextBlock Text="OK" FontSize="14" FontWeight="Bold" Foreground="White"
                     HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <TextBlock x:Name="TxtTitle" Text="驱动安装完成" FontSize="20" FontWeight="Bold"
                   Foreground="#F1F5F9" VerticalAlignment="Center" Margin="14,0,0,0"/>
      </StackPanel>

      <TextBlock x:Name="TxtSubtitle" Grid.Row="1" Text="部分驱动需要重启后才能生效"
                 FontSize="12" Foreground="#94A3B8" HorizontalAlignment="Center" Margin="0,0,0,14"/>

      <Border Grid.Row="2" Background="#0F1218" CornerRadius="8" Padding="16,12,16,12" Margin="0,0,0,10">
        <TextBlock x:Name="TxtDetail" FontSize="11" Foreground="#CBD5E1"
                   TextWrapping="Wrap" TextAlignment="Center"/>
      </Border>

      <Grid Grid.Row="3" Margin="0,16,0,16">
        <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
          <TextBlock HorizontalAlignment="Center" FontSize="11" Foreground="#94A3B8" Text="将在以下时间后自动重启"/>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,4,0,4">
            <TextBlock x:Name="TxtCountdown" Text="30" FontSize="48" FontWeight="Bold" Foreground="#FF8533"
                       VerticalAlignment="Center"/>
            <TextBlock Text="秒" FontSize="16" Foreground="#94A3B8" VerticalAlignment="Bottom" Margin="6,0,0,12"/>
          </StackPanel>
        </StackPanel>
      </Grid>

      <Border Grid.Row="4" CornerRadius="3" Background="#232936" Height="6" Margin="0,0,0,18">
        <ProgressBar x:Name="Progress" Background="Transparent" Foreground="#FF6B00" BorderThickness="0"
                     Minimum="0" Maximum="100" Value="100"/>
      </Border>

      <Grid Grid.Row="5">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="14"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Button x:Name="BtnLater" Grid.Column="0" Content="稍后重启" Height="42" FontSize="13" FontWeight="SemiBold"
                Background="#232936" Foreground="#F1F5F9" BorderThickness="0" Cursor="Hand">
          <Button.Template>
            <ControlTemplate TargetType="Button">
              <Border Background="{TemplateBinding Background}" CornerRadius="8">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
            </ControlTemplate>
          </Button.Template>
        </Button>
        <Button x:Name="BtnNow" Grid.Column="2" Content="立即重启" Height="42" FontSize="13" FontWeight="SemiBold"
                Foreground="White" BorderThickness="0" Cursor="Hand">
          <Button.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
              <GradientStop Color="#FF8533" Offset="0"/>
              <GradientStop Color="#FF6B00" Offset="1"/>
            </LinearGradientBrush>
          </Button.Background>
          <Button.Template>
            <ControlTemplate TargetType="Button">
              <Border Background="{TemplateBinding Background}" CornerRadius="8">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
            </ControlTemplate>
          </Button.Template>
        </Button>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

    [xml]$xmlDoc = $xaml
    $reader = New-Object System.Xml.XmlNodeReader $xmlDoc
    $win = [Windows.Markup.XamlReader]::Load($reader)
    if ($Owner) {
        try { $win.Owner = $Owner } catch {}
    } else {
        $win.WindowStartupLocation = 'CenterScreen'
    }

    $txtTitle = $win.FindName('TxtTitle')
    $txtSubtitle = $win.FindName('TxtSubtitle')
    $txtDetail = $win.FindName('TxtDetail')
    $txtCountdown = $win.FindName('TxtCountdown')
    $progress = $win.FindName('Progress')
    $btnNow = $win.FindName('BtnNow')
    $btnLater = $win.FindName('BtnLater')

    $txtTitle.Text = $Title
    $txtSubtitle.Text = $Subtitle
    if ($Detail) { $txtDetail.Text = $Detail }
    else { $txtDetail.Visibility = 'Collapsed' }

    # Use a hashtable for shared mutable state in closures
    $state = @{ Result = 'later'; Remaining = $Seconds; Total = $Seconds }
    $txtCountdown.Text = [string]$state.Remaining
    $progress.Value = 100

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(1)
    $timer.add_Tick({
        $state.Remaining -= 1
        if ($state.Remaining -le 0) {
            $timer.Stop()
            $state.Result = 'now'
            $win.Close()
            return
        }
        $txtCountdown.Text = [string]$state.Remaining
        $pct = ($state.Remaining / [double]$state.Total) * 100
        $anim = New-Object System.Windows.Media.Animation.DoubleAnimation $pct, ([TimeSpan]::FromMilliseconds(450))
        $progress.BeginAnimation([System.Windows.Controls.ProgressBar]::ValueProperty, $anim)
    }.GetNewClosure())

    $btnNow.add_Click({
        $timer.Stop()
        $state.Result = 'now'
        $win.Close()
    }.GetNewClosure())

    $btnLater.add_Click({
        $timer.Stop()
        $state.Result = 'later'
        $win.Close()
    }.GetNewClosure())

    $win.add_Closed({ try { $timer.Stop() } catch {} }.GetNewClosure())

    $timer.Start()
    [void]$win.ShowDialog()
    return $state.Result
}

function Invoke-CIODIYReboot {
    param([int]$DelaySeconds = 5)
    try {
        Start-Process shutdown.exe -ArgumentList '/r','/t', $DelaySeconds, '/c', 'Yanbai驱动安装完成，即将重启' -WindowStyle Hidden
    } catch {
        Start-Process shutdown.exe -ArgumentList '/r','/t', '5'
    }
}
