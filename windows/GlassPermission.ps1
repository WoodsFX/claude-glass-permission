# GlassPermission pour Windows : notification pour les demandes d'autorisation de Claude Code.
#
# Lancé par le hook `PermissionRequest` de Claude Code :
#   - lit la demande (JSON) sur l'entrée standard
#   - affiche une notification sombre en bas à droite, qui glisse vers le haut
#   - renvoie la décision (allow / deny) sur la sortie standard, ou rien du tout
#     pour laisser Claude Code poser la question dans le terminal.
#
# Aucune installation nécessaire : PowerShell et WPF sont inclus dans Windows.

$ErrorActionPreference = 'Stop'

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $utf8 = New-Object System.Text.UTF8Encoding $false
    [Console]::InputEncoding = $utf8
    [Console]::OutputEncoding = $utf8

    # ---------- Lecture de la demande ----------
    $raw = [Console]::In.ReadToEnd()
    $req = $null
    try { $req = $raw | ConvertFrom-Json } catch { }

    $tool = if ($req -and $req.tool_name) { [string]$req.tool_name } else { 'Outil' }
    $inp = if ($req) { $req.tool_input } else { $null }
    $cwd = if ($req -and $req.cwd) { [string]$req.cwd } else { (Get-Location).Path }
    $project = Split-Path -Leaf $cwd

    function Get-Field([string]$name) {
        if ($inp -and $inp.PSObject.Properties[$name] -and "$($inp.$name)") { return [string]$inp.$name }
        return $null
    }
    function Get-Pretty {
        if ($inp) { return ($inp | ConvertTo-Json -Depth 6) }
        return '-'
    }

    switch -Regex ($tool) {
        '^Bash$'              { $label = 'Exécuter une commande';  $glyph = 0xE756; $detail = Get-Field 'command'; break }
        '^(Edit|MultiEdit)$'  { $label = 'Modifier un fichier';    $glyph = 0xE70F; $detail = Get-Field 'file_path'; break }
        '^Write$'             { $label = 'Créer un fichier';       $glyph = 0xE8A5; $detail = Get-Field 'file_path'; break }
        '^NotebookEdit$'      { $label = 'Modifier un notebook';   $glyph = 0xE70F; $detail = Get-Field 'notebook_path'; break }
        '^WebFetch$'          { $label = 'Ouvrir une page web';    $glyph = 0xE774; $detail = Get-Field 'url'; break }
        '^WebSearch$'         { $label = 'Rechercher sur le web';  $glyph = 0xE721; $detail = Get-Field 'query'; break }
        '^mcp__'              {
            $parts = $tool -split '__'
            $label = if ($parts.Count -ge 3) { "$($parts[1]) · $($parts[2..($parts.Count-1)] -join '__')" } else { $tool }
            $glyph = 0xEA86; $detail = $null; break
        }
        default               { $label = $tool; $glyph = 0xE90F; $detail = $null }
    }
    if (-not $detail) { $detail = Get-Pretty }

    $timeout = 90
    if ($env:GLASS_TIMEOUT -match '^\d+$') { $timeout = [int]$env:GLASS_TIMEOUT }

    # ---------- Interface ----------
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        SizeToContent="WidthAndHeight" WindowStartupLocation="Manual"
        Left="-10000" Top="-10000" ShowActivated="True" FontFamily="Segoe UI">
  <Window.Resources>
    <Style x:Key="Flat" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="10,5"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="3"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Opacity" Value="0.85"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid ClipToBounds="True">
    <Border x:Name="Card" Width="380" Margin="30,30,16,16">
      <Border.RenderTransform>
        <TranslateTransform Y="260"/>
      </Border.RenderTransform>
      <Border.Effect>
        <DropShadowEffect BlurRadius="18" ShadowDepth="4" Direction="270" Opacity="0.55" Color="Black"/>
      </Border.Effect>
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
          <GradientStop Color="#2B3542" Offset="0"/>
          <GradientStop Color="#171C24" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>

      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Height="1" Background="#14FFFFFF" VerticalAlignment="Top"/>

        <DockPanel Grid.Row="0" Margin="12">
          <Border DockPanel.Dock="Left" Width="58" Height="58" VerticalAlignment="Top"
                  Background="#8C000000" BorderBrush="#94C23D" BorderThickness="2">
            <TextBlock x:Name="Icon" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="24"
                       Foreground="#D97857" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel Margin="12,0,0,0">
            <TextBlock Text="Claude" FontSize="13" FontWeight="SemiBold" Foreground="#94C23D"/>
            <TextBlock Text="demande une autorisation" FontSize="12" Foreground="#999999"/>
            <TextBlock x:Name="Label" FontSize="13" FontWeight="Bold" Foreground="#94C23D"
                       TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="Detail" FontFamily="Consolas" FontSize="11" Foreground="#BFBFBF"
                       TextWrapping="Wrap" MaxHeight="30" TextTrimming="CharacterEllipsis" Margin="0,4,0,0"/>
          </StackPanel>
        </DockPanel>

        <DockPanel Grid.Row="1" Margin="12,0,12,10" LastChildFill="False">
          <TextBlock x:Name="Project" DockPanel.Dock="Left" FontSize="11" Foreground="#737373"
                     VerticalAlignment="Center" TextTrimming="CharacterEllipsis" MaxWidth="170"/>
          <Button x:Name="Allow" DockPanel.Dock="Right" Style="{StaticResource Flat}"
                  Background="#94C23D" Foreground="Black" Content="Autoriser  ↵"/>
          <Button x:Name="Deny" DockPanel.Dock="Right" Style="{StaticResource Flat}" Margin="0,0,8,0"
                  Background="#1AFFFFFF" Foreground="#D9D9D9" Content="Refuser  ⌫"/>
        </DockPanel>

        <Border x:Name="Bar" Grid.Row="2" Height="2" Background="#94C23D" RenderTransformOrigin="0,0.5">
          <Border.RenderTransform>
            <ScaleTransform ScaleX="1"/>
          </Border.RenderTransform>
        </Border>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

    $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $card = $window.FindName('Card')
    $slide = $card.RenderTransform
    $bar = $window.FindName('Bar').RenderTransform

    $window.FindName('Icon').Text = [string][char]$glyph
    $window.FindName('Label').Text = $label.ToUpper()
    $window.FindName('Detail').Text = $detail
    $window.FindName('Project').Text = $project

    # ---------- Comportement ----------
    $script:done = $false
    $script:result = 'terminal'
    $script:remaining = $timeout

    function Start-Slide([double]$to, [int]$ms, [scriptblock]$onDone) {
        $anim = [System.Windows.Media.Animation.DoubleAnimation]::new(
            $to, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds($ms)))
        $ease = New-Object System.Windows.Media.Animation.CubicEase
        $ease.EasingMode = if ($to -eq 0) { 'EaseOut' } else { 'EaseIn' }
        $anim.EasingFunction = $ease
        if ($onDone) { $anim.add_Completed($onDone) }
        $slide.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $anim)
    }

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(1)

    function Set-Decision([string]$kind) {
        if ($script:done) { return }
        $script:done = $true
        $script:result = $kind
        $timer.Stop()
        Start-Slide 260 250 { $window.Close() }
    }

    $timer.add_Tick({
        $script:remaining--
        $a = [System.Windows.Media.Animation.DoubleAnimation]::new(
            [double]([math]::Max($script:remaining, 0) / $timeout),
            [System.Windows.Duration]::new([TimeSpan]::FromSeconds(1)))
        $bar.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $a)
        if ($script:remaining -le 0) { Set-Decision 'terminal' }
    })

    $window.FindName('Allow').add_Click({ Set-Decision 'allow' })
    $window.FindName('Deny').add_Click({ Set-Decision 'deny' })

    # Entrée = autoriser ; Effacer / Suppr / Échap = refuser
    $window.add_PreviewKeyDown({
        param($s, $e)
        $k = $e.Key.ToString()
        if ($k -in 'Return', 'Enter') { Set-Decision 'allow'; $e.Handled = $true }
        elseif ($k -in 'Back', 'Delete', 'Escape') { Set-Decision 'deny'; $e.Handled = $true }
    })

    # En bas à droite de l'écran principal, au-dessus de la barre des tâches
    $window.add_Loaded({
        $wa = [System.Windows.SystemParameters]::WorkArea
        $window.Left = $wa.Right - $window.ActualWidth
        $window.Top = $wa.Bottom - $window.ActualHeight
        $window.Activate() | Out-Null
    })

    $window.add_ContentRendered({
        $wav = Join-Path $env:WINDIR 'Media\Windows Notify System Generic.wav'
        if (Test-Path $wav) { (New-Object System.Media.SoundPlayer $wav).Play() }
        else { [System.Media.SystemSounds]::Asterisk.Play() }
        Start-Slide 0 400 $null
        $timer.Start()
    })

    $window.ShowDialog() | Out-Null

    # ---------- Réponse au hook ----------
    if ($script:result -eq 'allow') {
        $decision = @{ behavior = 'allow' }
    } elseif ($script:result -eq 'deny') {
        $decision = @{ behavior = 'deny'; message = "L'utilisateur a refusé cette action depuis la pop-up." }
    } else {
        exit 0  # aucune sortie : Claude Code pose la question dans le terminal
    }
    $out = @{ hookSpecificOutput = @{ hookEventName = 'PermissionRequest'; decision = $decision } }
    [Console]::Out.Write(($out | ConvertTo-Json -Depth 5 -Compress))
    [Console]::Out.Flush()
    exit 0
}
catch {
    # En cas de problème, on laisse Claude Code demander normalement dans le terminal.
    [Console]::Error.WriteLine("GlassPermission : $($_.Exception.Message)")
    exit 0
}
