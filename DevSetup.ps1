#Requires -Version 5.1
<#
    DevSetup - selecione e instale ferramentas de desenvolvimento de uma vez (via winget).
    Catálogo: tools.json  |  Interface: MainWindow.xaml
#>

param(
    [string]$Snapshot,                  # diagnóstico: salva um PNG da janela e fecha
    [ValidateSet('', 'light', 'dark')]
    [string]$Theme = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`""
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

if (-not ('DevTool' -as [type])) {
    Add-Type -TypeDefinition @'
using System.ComponentModel;

public class DevTool : INotifyPropertyChanged {
    public event PropertyChangedEventHandler PropertyChanged;
    void Notify(string p) { var h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs(p)); }

    public string Id { get; set; }
    public string Name { get; set; }
    public string Description { get; set; }
    public string Category { get; set; }
    public string Initials { get; set; }
    public string SearchText { get; set; }
    public string Site { get; set; }
    string _source = "winget"; public string Source { get { return _source; } set { if (!string.IsNullOrEmpty(value)) _source = value; } }
    public string IconPath { get; set; }
    public string IconBg { get; set; }
    public bool HasIcon { get { return !string.IsNullOrEmpty(IconPath); } }
    public bool HasIconBg { get { return !string.IsNullOrEmpty(IconBg); } }

    bool _sel;   public bool   IsSelected      { get { return _sel; }   set { if (_sel != value)   { _sel = value;   Notify("IsSelected"); } } }
    bool _inst;  public bool   IsInstalled     { get { return _inst; }  set { if (_inst != value)  { _inst = value;  Notify("IsInstalled"); } } }
    string _st = "";     public string Status  { get { return _st; }    set { if (_st != value)    { _st = value;    Notify("Status"); } } }
    string _state = "Idle"; public string State { get { return _state; } set { if (_state != value) { _state = value; Notify("State"); } } }
    double _prog;  public double Progress      { get { return _prog; }  set { if (_prog != value)  { _prog = value;  Notify("Progress"); } } }
    bool _ind;   public bool   IsIndeterminate { get { return _ind; }   set { if (_ind != value)   { _ind = value;   Notify("IsIndeterminate"); } } }
}

public class NavCategory {
    public string Name { get; set; }
    public string Icon { get; set; }
    public int Count { get; set; }
}

public class Preset {
    public string Name { get; set; }
    public string Icon { get; set; }
    public string Summary { get; set; }
    public string[] Ids { get; set; }
}

public class DriveItem {
    public string Root { get; set; }
    public string Title { get; set; }
    public string FreeText { get; set; }
    public double UsedPercent { get; set; }
    public bool IsSystem { get; set; }
}
'@
}

function Show-Error([string]$msg) {
    [void][Windows.MessageBox]::Show($msg, 'DevSetup', 'OK', 'Error')
}

# ------------------------------------------------------------------ preferências
$settingsPath = Join-Path $env:APPDATA 'DevSetup\settings.json'
function Get-Settings {
    try { if (Test-Path $settingsPath) { return Get-Content $settingsPath -Raw | ConvertFrom-Json } } catch {}
    return [pscustomobject]@{}
}
function Save-Setting([string]$key, $value) {
    try {
        $s = Get-Settings
        $s | Add-Member -NotePropertyName $key -NotePropertyValue $value -Force
        New-Item -ItemType Directory -Force (Split-Path $settingsPath) | Out-Null
        $s | ConvertTo-Json | Set-Content $settingsPath -Encoding UTF8
    } catch {}
}

# ------------------------------------------------------------------ temas
$palettes = @{
    light = @{
        Bg = '#FFFFFF'; Sidebar = '#FAFAFA'; Surface = '#FFFFFF'; NavSelected = '#EFEFEF'; Subtle = '#F4F4F5'
        Border = '#EAEAEA'; BorderStrong = '#D4D4D4'; Text = '#111111'; TextMuted = '#6B6B6B'; TextFaint = '#A3A3A3'
        Accent = '#111111'; AccentHover = '#2E2E2E'; AccentFg = '#FFFFFF'
        Success = '#15803D'; SuccessBg = '#ECFDF3'; Danger = '#DC2626'; Warning = '#B45309'
        Scrim = '#59000000'; ScrollThumb = '#D4D4D4'; ScrollThumbHover = '#A3A3A3'; Track = '#EDEDED'
        LogoBg = '#F7F7F7'; Selection = '#BFDBFE'
    }
    dark = @{
        Bg = '#0B0B0C'; Sidebar = '#0F0F10'; Surface = '#131314'; NavSelected = '#1F1F21'; Subtle = '#1A1A1C'
        Border = '#242426'; BorderStrong = '#36363A'; Text = '#EDEDED'; TextMuted = '#9A9AA0'; TextFaint = '#5F5F66'
        Accent = '#EDEDED'; AccentHover = '#FFFFFF'; AccentFg = '#0B0B0C'
        Success = '#4ADE80'; SuccessBg = '#132A1C'; Danger = '#F87171'; Warning = '#FBBF24'
        Scrim = '#B3000000'; ScrollThumb = '#36363A'; ScrollThumbHover = '#4A4A50'; Track = '#242426'
        LogoBg = '#1A1A1C'; Selection = '#264F78'
    }
}

function Get-SystemTheme {
    try {
        $v = Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop
        if ($v -eq 0) { return 'dark' }
    } catch {}
    return 'light'
}

try {
    # ---------------------------------------------------------------- dados
    $data  = Get-Content (Join-Path $root 'tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $tools = New-Object 'System.Collections.ObjectModel.ObservableCollection[DevTool]'
    $byId  = @{}

    foreach ($t in $data.tools) {
        $d = New-Object DevTool
        $d.Id          = $t.id
        $d.Name        = $t.name
        $d.Description = $t.desc
        $d.Category    = $t.category
        $d.Initials    = if ($t.initials) { $t.initials } else { $t.name.Substring(0, [Math]::Min(2, $t.name.Length)).ToUpper() }
        $d.SearchText  = ('{0} {1} {2} {3} {4}' -f $t.name, $t.desc, $t.id, $t.category, $t.keywords).ToLowerInvariant()
        $d.Site        = $t.site
        $d.Source      = $t.source
        $d.IconBg      = $t.iconBg
        $icon = Join-Path $root "icons\$($t.id).png"
        if (Test-Path -LiteralPath $icon) { $d.IconPath = $icon }
        $tools.Add($d)
        $byId[$t.id] = $d
    }

    # ---------------------------------------------------------------- janela
    $xaml   = Get-Content (Join-Path $root 'MainWindow.xaml') -Raw -Encoding UTF8
    $window = [Windows.Markup.XamlReader]::Parse($xaml)
    $ui = @{}
    foreach ($n in 'Root','CategoryList','PresetList','StatusDot','StatusText','ThemeBtn','ThemeGlyph','SearchBox','SelectAllBtn','ClearBtn',
                   'ModeAll','ModeSelected','ModeMissing','ModeInstalled','CountAll','SelCount','CountMissing','CountInstalled',
                   'CardScroll','ToolList','EmptyState','EmptyGlyph','EmptyTitle','EmptyText','SummaryTitle','SummaryText','CopyBtn',
                   'InstallBtn','InstallBtnText','Toast','ToastText',
                   'DrivePicker','DriveSub','DriveList','DrivePath','DriveCancel','DriveOk',
                   'Overlay','OvGlyph','OvTitle','OvSub','OvCount','OvPercent','OvBar','LogToggle','LogToggleText',
                   'OvCancel','OvClose','LogBox','QueueList','MinBtn','MaxBtn','CloseBtn') {
        $ui[$n] = $window.FindName($n)
    }

    $brushConv = New-Object Windows.Media.BrushConverter
    function Set-Theme([string]$name) {
        $script:theme = $name
        foreach ($k in $palettes[$name].Keys) {
            $b = $brushConv.ConvertFrom($palettes[$name][$k]); $b.Freeze()
            $window.Resources[$k] = $b
        }
        # ícone mostra o tema para o qual o botão alterna
        $ui.ThemeGlyph.Text = if ($name -eq 'dark') { [string][char]0xE706 } else { [string][char]0xE708 }
    }

    $settings = Get-Settings
    $initialTheme = if ($Theme) { $Theme } elseif ($settings.theme) { $settings.theme } else { Get-SystemTheme }
    Set-Theme $initialTheme
    $ui.ThemeBtn.Add_Click({
        $next = if ($script:theme -eq 'dark') { 'light' } else { 'dark' }
        Set-Theme $next
        Save-Setting 'theme' $next
    })

    # ---------------------------------------------------------------- categorias / perfis
    $cats = New-Object System.Collections.ArrayList
    [void]$cats.Add((New-Object NavCategory -Property @{ Name = 'Todas'; Icon = [string][char]0xE71D; Count = $tools.Count }))
    foreach ($c in $data.categories) {
        $count = @($tools | Where-Object { $_.Category -eq $c.name }).Count
        [void]$cats.Add((New-Object NavCategory -Property @{ Name = $c.name; Icon = [string][char][Convert]::ToInt32($c.icon, 16); Count = $count }))
    }
    $ui.CategoryList.ItemsSource = $cats
    $ui.CategoryList.SelectedIndex = 0

    $presets = foreach ($p in $data.presets) {
        $ids = @($p.ids | Where-Object { $byId.ContainsKey($_) })
        $glyph = if ($p.icon) { [string][char][Convert]::ToInt32($p.icon, 16) } else { [string][char]0xE734 }
        New-Object Preset -Property @{ Name = $p.name; Icon = $glyph; Ids = $ids; Summary = "$($ids.Count)" }
    }
    $ui.PresetList.ItemsSource = @($presets)

    # ---------------------------------------------------------------- filtro
    $script:category = $null
    $script:terms    = @()
    $script:mode     = 'All'   # All | Selected | Missing | Installed

    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($tools)
    $view.GroupDescriptions.Add((New-Object Windows.Data.PropertyGroupDescription 'Category'))
    $view.Filter = [Predicate[object]] {
        param($o)
        if ($script:category -and $o.Category -ne $script:category) { return $false }
        switch ($script:mode) {
            'Selected'  { if (-not $o.IsSelected) { return $false } }
            'Missing'   { if ($o.IsInstalled) { return $false } }
            'Installed' { if (-not $o.IsInstalled) { return $false } }
        }
        foreach ($term in $script:terms) { if (-not $o.SearchText.Contains($term)) { return $false } }
        return $true
    }
    $ui.ToolList.ItemsSource = $view

    function Update-View {
        $view.Refresh()
        $visible = @($view).Count
        $ui.EmptyState.Visibility = if ($visible -eq 0) { 'Visible' } else { 'Collapsed' }
        if ($script:mode -eq 'Selected' -and -not $script:terms) {
            $ui.EmptyGlyph.Text = [string][char]0xE73A
            $ui.EmptyTitle.Text = 'Nada selecionado'
            $ui.EmptyText.Text  = 'Escolha ferramentas na aba Todas ou use um perfil.'
        } else {
            $ui.EmptyGlyph.Text = [string][char]0xE721
            $ui.EmptyTitle.Text = 'Nenhuma ferramenta encontrada'
            $ui.EmptyText.Text  = 'Tente outro termo de busca ou outra categoria.'
        }
    }

    function Update-Counts {
        $inst = @($tools | Where-Object { $_.IsInstalled }).Count
        $ui.CountAll.Text       = "$($tools.Count)"
        $ui.CountInstalled.Text = "$inst"
        $ui.CountMissing.Text   = "$($tools.Count - $inst)"
    }

    function Update-Summary {
        $sel = @($tools | Where-Object { $_.IsSelected })
        $n = $sel.Count
        $ui.InstallBtn.IsEnabled = ($n -gt 0) -and $script:wingetOk
        $ui.CopyBtn.IsEnabled = $n -gt 0
        $ui.SelCount.Text = "$n"
        if ($n -eq 0) {
            $ui.SummaryTitle.Text   = 'Nenhuma ferramenta selecionada'
            $ui.SummaryText.Text    = 'Clique nos cartões ou escolha um perfil.'
            $ui.InstallBtnText.Text = 'Instalar'
        } else {
            $ui.SummaryTitle.Text   = if ($n -eq 1) { '1 ferramenta selecionada' } else { "$n ferramentas selecionadas" }
            $names = ($sel | Select-Object -First 5 | ForEach-Object Name) -join ', '
            if ($n -gt 5) { $names += " e mais $($n - 5)" }
            $ui.SummaryText.Text    = $names
            $ui.InstallBtnText.Text = "Instalar ($n)"
        }
    }

    # cartões responsivos: preenche a largura disponível com colunas iguais
    $script:lastCardWidth = 0
    function Update-CardWidth {
        $avail = $ui.ToolList.ActualWidth - 8   # folga: o painel interno do grupo é alguns px mais estreito
        if ($avail -le 0) { return }
        $gap = 12; $min = 280
        $cols = [Math]::Max(1, [Math]::Floor(($avail + 0.5) / ($min + $gap)))
        $w = [Math]::Floor($avail / $cols) - $gap
        if ($w -ne $script:lastCardWidth) {
            $script:lastCardWidth = $w
            $window.Resources['CardWidth'] = [double]$w
        }
    }
    $ui.ToolList.Add_SizeChanged({ Update-CardWidth })

    function Set-Mode([string]$m) {
        $script:mode = $m
        Update-View
        $ui.CardScroll.ScrollToTop()
    }

    function Show-Toast([string]$text) {
        $ui.ToastText.Text = $text
        $anim = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        foreach ($kf in @(@(0, 0), @(0.12, 1), @(1.8, 1), @(2.1, 0))) {
            [void]$anim.KeyFrames.Add((New-Object Windows.Media.Animation.LinearDoubleKeyFrame($kf[1], [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($kf[0])))))
        }
        $ui.Toast.BeginAnimation([Windows.UIElement]::OpacityProperty, $anim)
    }

    # ---------------------------------------------------------------- eventos da interface
    $ui.CategoryList.Add_SelectionChanged({
        $c = $ui.CategoryList.SelectedItem
        $script:category = if ($c -and $c.Name -ne 'Todas') { $c.Name } else { $null }
        Update-View
        $ui.CardScroll.ScrollToTop()
    })

    $ui.SearchBox.Add_TextChanged({
        $script:terms = @($ui.SearchBox.Text.ToLowerInvariant().Split(' ', [StringSplitOptions]::RemoveEmptyEntries))
        Update-View
    })

    $ui.ModeAll.Add_Checked({ Set-Mode 'All' })
    $ui.ModeSelected.Add_Checked({ Set-Mode 'Selected' })
    $ui.ModeMissing.Add_Checked({ Set-Mode 'Missing' })
    $ui.ModeInstalled.Add_Checked({ Set-Mode 'Installed' })

    $ui.ToolList.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler] {
        param($s, $e)
        $src = $e.OriginalSource
        if ($src -is [Windows.Controls.Button] -and $src.Tag -eq 'site') {
            $site = $src.DataContext.Site
            if ($site -match '^https://') { Start-Process $site }
            $e.Handled = $true
            return
        }
        Update-Summary
        if ($script:mode -eq 'Selected') { Update-View }
    })

    $ui.PresetList.AddHandler([Windows.Controls.Primitives.ButtonBase]::ClickEvent, [Windows.RoutedEventHandler] {
        param($s, $e)
        $preset = $e.OriginalSource.DataContext
        if (-not $preset) { return }
        $added = 0
        foreach ($id in $preset.Ids) {
            $t = $byId[$id]
            if (-not $t.IsInstalled -and -not $t.IsSelected) { $t.IsSelected = $true; $added++ }
        }
        Update-Summary
        if ($added -eq 0) { Show-Toast "$($preset.Name): nada novo para adicionar" }
        else { Show-Toast "$($preset.Name): $added adicionada(s)" }
    })

    $ui.SelectAllBtn.Add_Click({
        $added = 0
        foreach ($t in @($view)) { if (-not $t.IsInstalled -and -not $t.IsSelected) { $t.IsSelected = $true; $added++ } }
        Update-Summary
        Show-Toast "$added adicionada(s)"
    })

    $ui.ClearBtn.Add_Click({
        foreach ($t in $tools) { $t.IsSelected = $false }
        Update-Summary
        if ($script:mode -eq 'Selected') { Update-View }
    })

    $ui.CopyBtn.Add_Click({
        $cmds = $tools | Where-Object { $_.IsSelected } | ForEach-Object {
            "winget install --id $($_.Id) -e --source $($_.Source) --accept-package-agreements --accept-source-agreements"
        }
        [Windows.Clipboard]::SetText(($cmds -join "`r`n"))
        Show-Toast 'Comandos copiados'
    })

    # janela sem moldura
    $ui.MinBtn.Add_Click({ $window.WindowState = 'Minimized' })
    $ui.MaxBtn.Add_Click({ $window.WindowState = if ($window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' } })
    $ui.CloseBtn.Add_Click({ $window.Close() })
    $window.Add_StateChanged({
        if ($window.WindowState -eq 'Maximized') { $ui.Root.Margin = '7'; $ui.MaxBtn.Content = [string][char]0xE923 }
        else { $ui.Root.Margin = '0'; $ui.MaxBtn.Content = [string][char]0xE922 }
    })

    $window.Add_PreviewKeyDown({
        param($s, $e)
        $ctrl = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -ne 0
        if ($ctrl -and $e.Key -eq 'F') { $ui.SearchBox.Focus(); $ui.SearchBox.SelectAll(); $e.Handled = $true }
        elseif ($e.Key -eq 'Escape') {
            if ($ui.DrivePicker.Visibility -eq 'Visible') { $ui.DrivePicker.Visibility = 'Collapsed'; $e.Handled = $true }
            elseif ($ui.SearchBox.Text) { $ui.SearchBox.Clear(); $e.Handled = $true }
        }
    })

    # ---------------------------------------------------------------- trabalho em segundo plano
    $sync = [hashtable]::Synchronized(@{
        Log = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
        DetectDone = $false; DetectError = $null; InstalledCount = 0
        Completed = 0; Finished = $false; Cancel = $false
        Ok = 0; Already = 0; Failed = 0; NeedReboot = $false
    })

    function Start-Worker([scriptblock]$Script, [hashtable]$Params) {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($Script)
        foreach ($k in $Params.Keys) { [void]$ps.AddParameter($k, $Params[$k]) }
        [void]$ps.BeginInvoke()
    }

    # Detecta o que já está instalado (winget export lista os pacotes reconhecidos)
    $detectScript = {
        param($Tools, $Sync)
        try {
            $tmp = Join-Path $env:TEMP ('devsetup-' + [guid]::NewGuid().ToString('N') + '.json')
            $p = Start-Process winget -ArgumentList @('export', '-o', "`"$tmp`"", '--accept-source-agreements') -WindowStyle Hidden -Wait -PassThru
            $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            if (Test-Path $tmp) {
                $json = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($src in $json.Sources) { foreach ($pkg in $src.Packages) { [void]$set.Add($pkg.PackageIdentifier) } }
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
            $n = 0
            foreach ($t in $Tools) { if ($set.Contains($t.Id)) { $t.IsInstalled = $true; $n++ } }
            $Sync.InstalledCount = $n
        } catch {
            $Sync.DetectError = $_.Exception.Message
        }
        $Sync.DetectDone = $true
    }

    # Instala a fila, um pacote por vez. $InstallRoot vazio = local padrão de cada instalador.
    $installScript = {
        param($Queue, $Sync, $InstallRoot)
        $alreadyCodes = @(-1978335189, -1978335135)   # 0x8A15002B (sem atualização), 0x8A150061 (já instalado)
        $rebootCode   = -1978334967                    # 0x8A150109 (reinicialização necessária)
        $units = @{ 'B' = 1; 'KB' = 1KB; 'MB' = 1MB; 'GB' = 1GB }

        foreach ($t in $Queue) {
            if ($Sync.Cancel) { $t.State = 'Skipped'; $t.Status = 'Cancelado'; $Sync.Completed++; continue }

            $t.State = 'Running'; $t.Status = 'Preparando'; $t.IsIndeterminate = $true; $t.Progress = 0
            $Sync.Log.Enqueue("")
            $Sync.Log.Enqueue("> $($t.Name)  [$($t.Id)]")
            try {
                $wingetArgs = "install --id `"$($t.Id)`" --exact --source $($t.Source) --silent --accept-package-agreements --accept-source-agreements --disable-interactivity"
                if ($InstallRoot -and $t.Source -eq 'winget') {
                    $folder = Join-Path $InstallRoot ($t.Name -replace '[\\/:*?"<>|]', '')
                    $wingetArgs += " --location `"$folder`""
                    $Sync.Log.Enqueue("   destino: $folder")
                }
                $psi = New-Object Diagnostics.ProcessStartInfo 'winget'
                $psi.Arguments = $wingetArgs
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $psi.RedirectStandardOutput = $true
                $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
                $proc = [Diagnostics.Process]::Start($psi)

                $sawDownload = $false
                while ($null -ne ($line = $proc.StandardOutput.ReadLine())) {
                    $line = ($line -replace '\x1b\[[0-9;?]*[A-Za-z]', '').Trim()
                    if (-not $line -or $line -match '^[-\\|/]$') { continue }
                    $m = [regex]::Match($line, '([\d\.,]+)\s*(B|KB|MB|GB)\s*/\s*([\d\.,]+)\s*(B|KB|MB|GB)')
                    if ($m.Success) {
                        $cur = [double]::Parse($m.Groups[1].Value.Replace(',', '.'), [Globalization.CultureInfo]::InvariantCulture) * $units[$m.Groups[2].Value]
                        $tot = [double]::Parse($m.Groups[3].Value.Replace(',', '.'), [Globalization.CultureInfo]::InvariantCulture) * $units[$m.Groups[4].Value]
                        if ($tot -gt 0) {
                            $pct = [Math]::Min(100, [Math]::Round($cur / $tot * 100))
                            $t.IsIndeterminate = $false; $t.Progress = $pct
                            $t.Status = "Baixando $pct%"
                            $sawDownload = $true
                        }
                        continue
                    }
                    $m = [regex]::Match($line, '(\d{1,3})\s*%')
                    if ($m.Success -and $line -match '[█▒]') {
                        $t.IsIndeterminate = $false; $t.Progress = [int]$m.Groups[1].Value
                        continue
                    }
                    if ($line -match '[█▒]') { continue }
                    if ($sawDownload) { $t.Status = 'Instalando'; $t.IsIndeterminate = $true }
                    $Sync.Log.Enqueue("   $line")
                }
                $proc.WaitForExit()
                $code = $proc.ExitCode

                if ($code -eq 0) {
                    $t.State = 'Done'; $t.Status = 'Instalado'; $t.IsInstalled = $true; $Sync.Ok++
                } elseif ($alreadyCodes -contains $code) {
                    $t.State = 'Done'; $t.Status = 'Já instalado'; $t.IsInstalled = $true; $Sync.Already++
                } elseif ($code -eq $rebootCode) {
                    $t.State = 'Done'; $t.Status = 'Instalado, reinicie o PC'; $t.IsInstalled = $true; $Sync.Ok++; $Sync.NeedReboot = $true
                } else {
                    $reason = switch ($code) {
                        -1978335212 { 'Pacote não encontrado' }            # 0x8A150014
                        -1978335216 { 'Sem instalador compatível' }        # 0x8A150010
                        -1978334975 { 'Instalador em uso' }                # 0x8A150101
                        -1978334974 { 'Reinicie o PC e tente de novo' }    # 0x8A150102
                        -1978334970 { 'Bloqueado por política' }           # 0x8A150106
                        -1978334972 { 'Espaço em disco insuficiente' }     # 0x8A150104
                        -1978335230 { 'Sem conexão' }                      # 0x8A150002
                        1602        { 'Cancelado pelo usuário' }
                        1603        { 'Erro do instalador' }
                        default     { 'Falhou' }
                    }
                    $t.State = 'Failed'; $t.Status = $reason; $Sync.Failed++
                }
                $Sync.Log.Enqueue(("   código de saída {0} (0x{0:X8})" -f $code))
            } catch {
                $t.State = 'Failed'; $t.Status = 'Erro ao executar winget'; $Sync.Failed++
                $Sync.Log.Enqueue("   ERRO: $($_.Exception.Message)")
            }
            $t.IsIndeterminate = $false; $t.Progress = 100
            $Sync.Completed++
        }
        $Sync.Finished = $true
    }

    # ---------------------------------------------------------------- escolha do disco
    function Format-Size([double]$bytes) {
        if ($bytes -ge 1TB) { return '{0:N1} TB' -f ($bytes / 1TB) }
        return '{0:N0} GB' -f ($bytes / 1GB)
    }

    $sysDrive = [IO.Path]::GetPathRoot($env:SystemRoot)
    function Show-DrivePicker {
        $drives = foreach ($d in [IO.DriveInfo]::GetDrives()) {
            if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady) { continue }
            $label = if ($d.VolumeLabel) { $d.VolumeLabel } else { 'Disco local' }
            New-Object DriveItem -Property @{
                Root        = $d.RootDirectory.FullName
                Title       = "$label ($($d.Name.TrimEnd('\')))"
                FreeText    = "$(Format-Size $d.AvailableFreeSpace) livres de $(Format-Size $d.TotalSize)" + $(if ($d.AvailableFreeSpace -lt 15GB) { '  ·  pouco espaço' } else { '' })
                UsedPercent = [Math]::Round((1 - $d.AvailableFreeSpace / $d.TotalSize) * 100)
                IsSystem    = ($d.RootDirectory.FullName -eq $sysDrive)
            }
        }
        $drives = @($drives)
        $ui.DriveList.ItemsSource = $drives
        $last = (Get-Settings).drive
        $pick = $drives | Where-Object { $_.Root -eq $last } | Select-Object -First 1
        if (-not $pick) { $pick = $drives | Where-Object IsSystem | Select-Object -First 1 }
        $ui.DriveList.SelectedItem = $pick
        $n = @($tools | Where-Object { $_.IsSelected }).Count
        $ui.DriveSub.Text = "Escolha o disco onde $(if ($n -eq 1) { 'a ferramenta será instalada' } else { "as $n ferramentas serão instaladas" })."
        $ui.DrivePicker.Visibility = 'Visible'
    }

    function Get-InstallRoot($drive) {
        if (-not $drive -or $drive.IsSystem) { return $null }
        return (Join-Path $drive.Root 'DevTools')
    }

    $ui.DriveList.Add_SelectionChanged({
        $d = $ui.DriveList.SelectedItem
        $ui.DriveOk.IsEnabled = [bool]$d
        if (-not $d) { $ui.DrivePath.Text = ''; return }
        $r = Get-InstallRoot $d
        $ui.DrivePath.Text = if ($r) { "Destino: $r\<ferramenta>" } else { 'Destino: local padrão de cada instalador (Program Files)' }
    })

    $ui.DriveCancel.Add_Click({ $ui.DrivePicker.Visibility = 'Collapsed' })

    # ---------------------------------------------------------------- instalação (UI)
    $script:installing = $false
    $script:queue = @()

    $ui.InstallBtn.Add_Click({ Show-DrivePicker })

    $ui.DriveOk.Add_Click({
        $drive = $ui.DriveList.SelectedItem
        if (-not $drive) { return }
        Save-Setting 'drive' $drive.Root
        $installRoot = Get-InstallRoot $drive
        $ui.DrivePicker.Visibility = 'Collapsed'

        $script:queue = @($tools | Where-Object { $_.IsSelected })
        if ($script:queue.Count -eq 0) { return }

        foreach ($t in $script:queue) { $t.State = 'Queued'; $t.Status = 'Na fila'; $t.Progress = 0; $t.IsIndeterminate = $false }
        $sync.Completed = 0; $sync.Finished = $false; $sync.Cancel = $false
        $sync.Ok = 0; $sync.Already = 0; $sync.Failed = 0; $sync.NeedReboot = $false
        $ui.LogBox.Clear()

        $ui.QueueList.ItemsSource = $script:queue
        $ui.OvTitle.Text = 'Instalando'
        $ui.OvGlyph.Visibility = 'Collapsed'
        $dest = if ($installRoot) { "em $installRoot" } else { "no disco do sistema" }
        $ui.OvSub.Text = "Instalando $dest. Alguns instaladores podem pedir permissão de administrador."
        $ui.OvBar.Value = 0
        $ui.OvCancel.Visibility = 'Visible'; $ui.OvCancel.IsEnabled = $true
        $ui.OvClose.Visibility = 'Collapsed'
        $ui.Overlay.Visibility = 'Visible'

        if ($installRoot) { New-Item -ItemType Directory -Force $installRoot -ErrorAction SilentlyContinue | Out-Null }
        $script:installing = $true
        Start-Worker $installScript @{ Queue = $script:queue; Sync = $sync; InstallRoot = $installRoot }
    })

    $ui.OvCancel.Add_Click({
        $sync.Cancel = $true
        $ui.OvCancel.IsEnabled = $false
        $ui.OvSub.Text = 'Cancelando: a instalação atual será concluída e as restantes serão ignoradas.'
    })

    $ui.LogToggle.Add_Click({
        if ($ui.LogBox.Visibility -eq 'Visible') { $ui.LogBox.Visibility = 'Collapsed'; $ui.LogToggleText.Text = 'Mostrar log' }
        else { $ui.LogBox.Visibility = 'Visible'; $ui.LogToggleText.Text = 'Ocultar log'; $ui.LogBox.ScrollToEnd() }
    })

    $ui.OvClose.Add_Click({
        foreach ($t in $script:queue) {
            if ($t.State -eq 'Done') { $t.IsSelected = $false }
            $t.State = 'Idle'; $t.Status = ''
        }
        $ui.Overlay.Visibility = 'Collapsed'
        Update-Counts
        Update-View
        Update-Summary
    })

    function Complete-Install {
        $script:installing = $false
        $parts = @()
        if ($sync.Ok)      { $parts += "$($sync.Ok) instalada(s)" }
        if ($sync.Already) { $parts += "$($sync.Already) já existia(m)" }
        if ($sync.Failed)  { $parts += "$($sync.Failed) com falha" }
        $skipped = @($script:queue | Where-Object { $_.State -eq 'Skipped' }).Count
        if ($skipped) { $parts += "$skipped cancelada(s)" }
        $sub = $parts -join ', '
        if ($sync.NeedReboot) { $sub += '. Reinicie o computador para concluir.' }

        $ui.OvGlyph.Visibility = 'Visible'
        if ($sync.Failed) {
            $ui.OvTitle.Text = 'Concluído com falhas'
            $ui.OvGlyph.Text = [string][char]0xE7BA
            $ui.OvGlyph.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Warning')
            $sub += '. Veja o log para detalhes.'
        } else {
            $ui.OvTitle.Text = 'Concluído'
            $ui.OvGlyph.Text = [string][char]0xE73E
            $ui.OvGlyph.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Success')
        }
        $ui.OvSub.Text = $sub
        $ui.OvCancel.Visibility = 'Collapsed'
        $ui.OvClose.Visibility = 'Visible'
        $ui.OvBar.Value = 100
        $ui.OvPercent.Text = '100%'
        [void][Media.SystemSounds]::Asterisk.Play()
    }

    # ---------------------------------------------------------------- timer de atualização da UI
    $script:detectHandled = $false
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({
        if ($sync.DetectDone -and -not $script:detectHandled) {
            $script:detectHandled = $true
            if ($sync.DetectError) {
                $ui.StatusText.Text = 'winget pronto'
            } else {
                $ui.StatusDot.SetResourceReference([Windows.Shapes.Shape]::FillProperty, 'Success')
                $ui.StatusText.Text = "winget pronto · $($sync.InstalledCount) instaladas"
            }
            Update-Counts
            Update-View
        }

        if ($script:installing) {
            $line = $null
            $sb = New-Object Text.StringBuilder
            while ($sync.Log.TryDequeue([ref]$line)) { [void]$sb.AppendLine($line) }
            if ($sb.Length -gt 0) { $ui.LogBox.AppendText($sb.ToString()); $ui.LogBox.ScrollToEnd() }

            $total = $script:queue.Count
            $done = $sync.Completed
            $running = $script:queue | Where-Object { $_.State -eq 'Running' } | Select-Object -First 1
            $partial = if ($running -and -not $running.IsIndeterminate) { $running.Progress / 100 } elseif ($running) { 0.5 } else { 0 }
            $pct = [Math]::Min(100, [Math]::Round((($done + $partial) / $total) * 100))
            $ui.OvBar.Value = $pct
            $ui.OvPercent.Text = "$pct%"
            $ui.OvCount.Text = "$done de $total"

            if ($sync.Finished) { Complete-Install }
        }
    })
    $timer.Start()

    $window.Add_Closing({
        param($s, $e)
        if ($script:installing) {
            $r = [Windows.MessageBox]::Show('Uma instalação está em andamento. Deseja realmente sair? A instalação atual continuará em segundo plano, mas as restantes serão canceladas.', 'DevSetup', 'YesNo', 'Warning')
            if ($r -ne 'Yes') { $e.Cancel = $true; return }
            $sync.Cancel = $true
        }
        $timer.Stop()
    })

    # ---------------------------------------------------------------- inicialização
    $script:wingetOk = [bool](Get-Command winget -ErrorAction SilentlyContinue)
    if ($script:wingetOk) {
        Start-Worker $detectScript @{ Tools = $tools; Sync = $sync }
    } else {
        $ui.StatusDot.SetResourceReference([Windows.Shapes.Shape]::FillProperty, 'Danger')
        $ui.StatusText.Text = 'winget não encontrado'
        $window.Add_ContentRendered({
            $r = [Windows.MessageBox]::Show("O winget (Gerenciador de Pacotes do Windows) não foi encontrado.`n`nDeseja abrir a Microsoft Store para instalar o 'Instalador de Aplicativo'?", 'DevSetup', 'YesNo', 'Warning')
            if ($r -eq 'Yes') { Start-Process 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1' }
        })
    }

    Update-Counts
    Update-View
    Update-Summary

    if ($Snapshot) {
        $window.Add_ContentRendered({
            $t2 = New-Object Windows.Threading.DispatcherTimer
            $t2.Interval = [TimeSpan]::FromSeconds(7)
            $t2.Add_Tick({
                $t2.Stop()
                $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.ActualWidth, [int]$window.ActualHeight, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
                $bmp.Render($window)
                $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
                $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
                $fs = [IO.File]::Create($Snapshot); $enc.Save($fs); $fs.Close()
                $window.Close()
            }.GetNewClosure())
            $t2.Start()
        })
    }

    [void]$window.ShowDialog()
}
catch {
    Show-Error ("Erro ao iniciar o DevSetup:`n`n" + $_.Exception.Message + "`n`n" + $_.InvocationInfo.PositionMessage)
}
