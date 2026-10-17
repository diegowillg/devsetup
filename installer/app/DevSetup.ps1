#Requires -Version 5.1
<#
    DevSetup - instale, atualize e remova ferramentas de desenvolvimento (via winget).
    Catálogo: tools.json (atualizado pela internet)  |  Interface: MainWindow.xaml
#>

param(
    [string]$Snapshot,                  # diagnóstico: salva um PNG da janela e fecha
    [ValidateSet('', 'light', 'dark')]
    [string]$Theme = '',
    [string]$Size = ''                  # diagnóstico: força o tamanho da janela, ex. 1024x700
)

$AppVersion = '1.2.1'
$RepoApi    = 'https://api.github.com/repos/diegowillg/devsetup/releases/latest'
$CatalogUrl = 'https://raw.githubusercontent.com/diegowillg/devsetup/main/installer/app/tools.json'

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`""
    return
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

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

    bool _sel;   public bool IsSelected  { get { return _sel; }  set { if (_sel != value)  { _sel = value;  Notify("IsSelected"); } } }
    bool _inst;  public bool IsInstalled { get { return _inst; } set { if (_inst != value) { _inst = value; Notify("IsInstalled"); } } }

    string _iv = ""; public string InstalledVersion {
        get { return _iv; }
        set { var v = value ?? ""; if (_iv != v) { _iv = v; Notify("InstalledVersion"); Notify("InstalledLabel"); } } }
    public string InstalledLabel { get {
        if (string.IsNullOrEmpty(_iv) || _iv == "Unknown") return "Instalado";
        return "Instalado · " + (_iv.Length > 14 ? _iv.Substring(0, 14) + "…" : _iv); } }

    string _latest = ""; public string LatestVersion {
        get { return _latest; }
        set { var v = value ?? ""; if (_latest != v) { _latest = v; Notify("LatestVersion"); Notify("UpdateLabel"); } } }
    bool _upd; public bool HasUpdate { get { return _upd; } set { if (_upd != value) { _upd = value; Notify("HasUpdate"); } } }
    public string UpdateLabel { get { return "↑ " + (_latest.Length > 14 ? _latest.Substring(0, 14) + "…" : _latest); } }

    string _st = "";        public string Status { get { return _st; }    set { if (_st != value)    { _st = value;    Notify("Status"); } } }
    string _state = "Idle"; public string State  { get { return _state; } set { if (_state != value) { _state = value; Notify("State"); } } }
    double _prog; public double Progress      { get { return _prog; } set { if (_prog != value) { _prog = value; Notify("Progress"); } } }
    bool _ind;    public bool IsIndeterminate { get { return _ind; }  set { if (_ind != value)  { _ind = value;  Notify("IsIndeterminate"); } } }

    // versões disponíveis ("" = mais recente)
    public bool VersionsLoaded { get; set; }
    public string[] AllVersions { get; set; }
    VersionOption[] _versions; public VersionOption[] Versions { get { return _versions; } set { _versions = value; Notify("Versions"); Notify("SelectedVersion"); } }
    string _selVer = ""; public string SelectedVersion { get { return _selVer; } set { if (value == null) return; if (_selVer != value) { _selVer = value; Notify("SelectedVersion"); } } }
    bool _verReady; public bool VersionsReady { get { return _verReady; } set { if (_verReady != value) { _verReady = value; Notify("VersionsReady"); } } }
    bool _showPicker = true; public bool ShowVersionPicker { get { return _showPicker; } set { if (_showPicker != value) { _showPicker = value; Notify("ShowVersionPicker"); } } }
    string _rt = ""; public string ReviewText { get { return _rt; } set { if (_rt != value) { _rt = value; Notify("ReviewText"); } } }

    // operação planejada: install | upgrade | uninstall | reinstall
    public string Action { get; set; }
    public string TargetVersion { get; set; }
}

public class VersionOption {
    public string Label { get; set; }
    public string Value { get; set; }
    public override string ToString() { return Label; }
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
$dataDir      = Join-Path $env:APPDATA 'DevSetup'
$settingsPath = Join-Path $dataDir 'settings.json'
$catalogCache = Join-Path $dataDir 'catalog.json'
function Get-Settings {
    try { if (Test-Path $settingsPath) { return Get-Content $settingsPath -Raw | ConvertFrom-Json } } catch {}
    return [pscustomobject]@{}
}
function Save-Setting([string]$key, $value) {
    try {
        $s = Get-Settings
        $s | Add-Member -NotePropertyName $key -NotePropertyValue $value -Force
        New-Item -ItemType Directory -Force $dataDir | Out-Null
        $s | ConvertTo-Json | Set-Content $settingsPath -Encoding UTF8
    } catch {}
}

# ------------------------------------------------------------------ comparação de versões
function Compare-Version([string]$a, [string]$b) {
    $pa = @($a -split '[\.\-\+_ ]' | Where-Object { $_ -ne '' })
    $pb = @($b -split '[\.\-\+_ ]' | Where-Object { $_ -ne '' })
    $n = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $x = if ($i -lt $pa.Count) { $pa[$i] } else { '0' }
        $y = if ($i -lt $pb.Count) { $pb[$i] } else { '0' }
        $nx = 0L; $ny = 0L
        if ([long]::TryParse($x, [ref]$nx) -and [long]::TryParse($y, [ref]$ny)) {
            if ($nx -ne $ny) { return [Math]::Sign($nx - $ny) }
        } else {
            $c = [string]::Compare($x, $y, $true)
            if ($c -ne 0) { return [Math]::Sign($c) }
        }
    }
    return 0
}

# ------------------------------------------------------------------ temas
$palettes = @{
    light = @{
        Bg = '#FFFFFF'; Sidebar = '#FAFAFA'; Surface = '#FFFFFF'; NavSelected = '#EFEFEF'; Subtle = '#F4F4F5'
        Border = '#EAEAEA'; BorderStrong = '#D4D4D4'; Text = '#111111'; TextMuted = '#6B6B6B'; TextFaint = '#A3A3A3'
        Accent = '#111111'; AccentHover = '#2E2E2E'; AccentFg = '#FFFFFF'
        Success = '#15803D'; SuccessBg = '#ECFDF3'; Info = '#1D4ED8'; InfoBg = '#EFF4FF'
        Danger = '#DC2626'; DangerBg = '#FEF2F2'; Warning = '#B45309'
        Scrim = '#59000000'; ScrollThumb = '#D4D4D4'; ScrollThumbHover = '#A3A3A3'; Track = '#EDEDED'
        LogoBg = '#F7F7F7'; Selection = '#BFDBFE'
    }
    dark = @{
        Bg = '#0B0B0C'; Sidebar = '#0F0F10'; Surface = '#131314'; NavSelected = '#1F1F21'; Subtle = '#1A1A1C'
        Border = '#242426'; BorderStrong = '#36363A'; Text = '#EDEDED'; TextMuted = '#9A9AA0'; TextFaint = '#5F5F66'
        Accent = '#EDEDED'; AccentHover = '#FFFFFF'; AccentFg = '#0B0B0C'
        Success = '#4ADE80'; SuccessBg = '#132A1C'; Info = '#7AA2FF'; InfoBg = '#16213A'
        Danger = '#F87171'; DangerBg = '#2A1414'; Warning = '#FBBF24'
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
    # ---------------------------------------------------------------- catálogo (embutido ou o mais novo baixado da internet)
    $data = Get-Content (Join-Path $root 'tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    try {
        if (Test-Path $catalogCache) {
            $cached = Get-Content $catalogCache -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([int]$cached.catalogVersion -gt [int]$data.catalogVersion -and @($cached.tools).Count -gt 0) { $data = $cached }
        }
    } catch {}
    $catalogVersion = [int]$data.catalogVersion

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
    if (-not ('AppId' -as [type])) {
        Add-Type -Name AppId -Namespace '' -MemberDefinition '[DllImport("shell32.dll")] public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string id);'
    }
    [void][AppId]::SetCurrentProcessExplicitAppUserModelID('DevSetup.DevSetup')

    $xaml   = Get-Content (Join-Path $root 'MainWindow.xaml') -Raw -Encoding UTF8
    $window = [Windows.Markup.XamlReader]::Parse($xaml)
    $iconFile = @((Join-Path $root 'devsetup.ico'), (Join-Path $root 'assets\devsetup.ico')) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($iconFile) { $window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$iconFile) }

    $ui = @{}
    foreach ($n in 'Root','SidebarCol','Brand','CompactDivider','SidebarScroll','CategoryList','PresetList','StatusDot','StatusText','StatusDetail','ThemeBtn','ThemeGlyph',
                   'OfflineBanner','AppUpdateBanner','AppUpdateText','AppUpdateBtn',
                   'HeaderGrid','HeaderSub','SearchBox','TabsGrid','TabActions','UpdateAllBtn','UpdateAllText','SelectAllBtn','ClearBtn',
                   'ModeAll','ModeSelected','ModeInstalled','ModeUpdates','ModeMissing',
                   'CountAll','SelCount','CountInstalled','CountUpdates','UpdatesPill','CountMissing',
                   'CardScroll','ToolList','EmptyState','EmptyGlyph','EmptyTitle','EmptyText',
                   'ActionBar','SummaryTitle','SummaryText','CopyBtn','UninstallBtn','UninstallBtnText','UpdateBtn','UpdateBtnText','InstallBtn','InstallBtnText',
                   'Toast','ToastText',
                   'ReviewPanel','ReviewCard','ReviewTitle','ReviewSub','ReviewCancel','ReviewOk','ReviewOkText','DiskSection','DriveList','DrivePath',
                   'ReviewListTitle','VersionsStatus','ReviewScroll','ReviewList',
                   'Overlay','OvGlyph','OvTitle','OvSub','OvCount','OvPercent','OvBar','LogToggle','LogToggleText',
                   'OvCancel','OvClose','LogBox','QueueList','MinBtn','MaxBtn','CloseBtn') {
        $ui[$n] = $window.FindName($n)
    }

    # tamanho inicial proporcional à tela (nunca maior que a área útil)
    $wa = [Windows.SystemParameters]::WorkArea
    $window.MinWidth  = [Math]::Min(760, $wa.Width)
    $window.MinHeight = [Math]::Min(520, $wa.Height)
    if ($Size -match '^(\d+)x(\d+)$') {
        $window.Width = [double]$Matches[1]; $window.Height = [double]$Matches[2]
        $window.MinWidth = 0; $window.MinHeight = 0
    } else {
        $window.Width  = [Math]::Min(1280, [Math]::Floor($wa.Width * 0.92))
        $window.Height = [Math]::Min(840,  [Math]::Floor($wa.Height * 0.92))
    }

    $brushConv = New-Object Windows.Media.BrushConverter
    function Set-Theme([string]$name) {
        $script:theme = $name
        foreach ($k in $palettes[$name].Keys) {
            $b = $brushConv.ConvertFrom($palettes[$name][$k]); $b.Freeze()
            $window.Resources[$k] = $b
        }
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
    $script:mode     = 'All'   # All | Selected | Installed | Updates | Missing

    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($tools)
    $view.GroupDescriptions.Add((New-Object Windows.Data.PropertyGroupDescription 'Category'))
    $view.Filter = [Predicate[object]] {
        param($o)
        if ($script:category -and $o.Category -ne $script:category) { return $false }
        switch ($script:mode) {
            'Selected'  { if (-not $o.IsSelected) { return $false } }
            'Installed' { if (-not $o.IsInstalled) { return $false } }
            'Updates'   { if (-not $o.HasUpdate) { return $false } }
            'Missing'   { if ($o.IsInstalled) { return $false } }
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
            $ui.EmptyGlyph.Text = [string][char]0xE73A; $ui.EmptyTitle.Text = 'Nada selecionado'
            $ui.EmptyText.Text  = 'Escolha ferramentas na aba Todas ou use um perfil.'
        } elseif ($script:mode -eq 'Updates' -and -not $script:terms) {
            $ui.EmptyGlyph.Text = [string][char]0xE73E; $ui.EmptyTitle.Text = 'Tudo atualizado'
            $ui.EmptyText.Text  = if ($script:pendingUpdateChecks -gt 0) { 'Ainda verificando atualizações…' } else { 'Nenhuma atualização disponível para as ferramentas instaladas.' }
        } else {
            $ui.EmptyGlyph.Text = [string][char]0xE721; $ui.EmptyTitle.Text = 'Nenhuma ferramenta encontrada'
            $ui.EmptyText.Text  = 'Tente outro termo de busca ou outra categoria.'
        }
    }

    function Update-Counts {
        $inst = @($tools | Where-Object { $_.IsInstalled }).Count
        $upd  = @($tools | Where-Object { $_.HasUpdate }).Count
        $ui.CountAll.Text       = "$($tools.Count)"
        $ui.CountInstalled.Text = "$inst"
        $ui.CountMissing.Text   = "$($tools.Count - $inst)"
        $ui.CountUpdates.Text   = "$upd"
        $ui.UpdatesPill.Visibility = if ($upd -gt 0) { 'Visible' } else { 'Collapsed' }
        $ui.UpdateAllBtn.Visibility = if ($upd -gt 0 -and $script:online -and -not $script:compactActions) { 'Visible' } else { 'Collapsed' }
        $ui.UpdateAllText.Text = "Atualizar tudo ($upd)"
    }

    function Update-Summary {
        $sel = @($tools | Where-Object { $_.IsSelected })
        $toInstall = @($sel | Where-Object { -not $_.IsInstalled }).Count
        $installed = @($sel | Where-Object { $_.IsInstalled }).Count
        $ui.SelCount.Text = "$($sel.Count)"
        $ready = $script:wingetOk -and $script:online

        $ui.InstallBtn.IsEnabled = $ready -and $toInstall -gt 0
        $ui.InstallBtnText.Text  = if ($toInstall) { "Instalar ($toInstall)" } else { 'Instalar' }
        $ui.UpdateBtn.Visibility    = if ($installed) { 'Visible' } else { 'Collapsed' }
        $ui.UpdateBtn.IsEnabled     = $ready
        $ui.UpdateBtnText.Text      = "Atualizar ($installed)"
        $ui.UninstallBtn.Visibility = if ($installed) { 'Visible' } else { 'Collapsed' }
        $ui.UninstallBtn.IsEnabled  = [bool]$script:wingetOk
        $ui.UninstallBtnText.Text   = "Desinstalar ($installed)"
        $ui.CopyBtn.IsEnabled = $sel.Count -gt 0

        if ($sel.Count -eq 0) {
            $ui.SummaryTitle.Text = 'Nenhuma ferramenta selecionada'
            $ui.SummaryText.Text  = 'Clique nos cartões ou escolha um perfil.'
        } else {
            $ui.SummaryTitle.Text = if ($sel.Count -eq 1) { '1 ferramenta selecionada' } else { "$($sel.Count) ferramentas selecionadas" }
            $parts = @()
            if ($toInstall) { $parts += "$toInstall para instalar" }
            if ($installed) { $parts += "$installed já instalada(s)" }
            $ui.SummaryText.Text = ($parts -join ' · ') + ' — ' + (($sel | Select-Object -First 4 | ForEach-Object Name) -join ', ') + $(if ($sel.Count -gt 4) { '…' } else { '' })
        }
        if (-not $script:online) { $ui.InstallBtn.ToolTip = 'Sem conexão com a internet' } else { $ui.InstallBtn.ToolTip = $null }
    }

    # ---------------------------------------------------------------- layout responsivo
    $script:cardMin = 280
    $script:lastCardWidth = 0
    function Update-CardWidth {
        $avail = $ui.ToolList.ActualWidth - 8   # folga: o painel interno do grupo é alguns px mais estreito
        if ($avail -le 0) { return }
        $gap = 12
        $cols = [Math]::Max(1, [Math]::Floor(($avail + 0.5) / ($script:cardMin + $gap)))
        $w = [Math]::Floor($avail / $cols) - $gap
        if ($w -ne $script:lastCardWidth) {
            $script:lastCardWidth = $w
            $window.Resources['CardWidth'] = [double]$w
        }
    }
    $ui.ToolList.Add_SizeChanged({ Update-CardWidth })

    function Apply-Layout {
        $w = $window.ActualWidth; $h = $window.ActualHeight
        if ($w -le 0) { $w = $window.Width; $h = $window.Height }

        $compact = $w -lt 1000
        $ui.SidebarCol.Width = New-Object Windows.GridLength ($(if ($compact) { 60 } else { 248 }))
        $window.Resources['NavTextVisibility'] = if ($compact) { [Windows.Visibility]::Collapsed } else { [Windows.Visibility]::Visible }
        $ui.CompactDivider.Visibility = if ($compact) { 'Visible' } else { 'Collapsed' }
        $ui.SidebarScroll.VerticalScrollBarVisibility = if ($compact) { 'Hidden' } else { 'Auto' }
        $ui.Brand.Margin = if ($compact) { '19,14,0,22' } else { '19,14,12,22' }

        $pad = if ($w -lt 1150) { 24 } else { 40 }
        $ui.HeaderGrid.Margin  = "$pad,6,$pad,0"
        $ui.TabsGrid.Margin    = "$pad,18,$pad,0"
        $ui.CardScroll.Padding = "$pad,0,$([Math]::Max(12, $pad - 12)),0"
        $ui.ActionBar.Padding  = "$pad,12"
        $ui.SearchBox.Width    = if ($w -lt 860) { 170 } elseif ($w -lt 1150) { 230 } else { 300 }
        $ui.HeaderSub.Visibility = if ($w -lt 900) { 'Collapsed' } else { 'Visible' }

        $script:compactActions = $w -lt 1080
        $ui.SelectAllBtn.Visibility = if ($script:compactActions) { 'Collapsed' } else { 'Visible' }
        $ui.ClearBtn.Visibility     = if ($w -lt 900) { 'Collapsed' } else { 'Visible' }
        $ui.CopyBtn.Visibility      = if ($w -lt 1080) { 'Collapsed' } else { 'Visible' }
        $script:cardMin = if ($w -lt 1150) { 250 } else { 280 }
        $script:lastCardWidth = 0
        Update-CardWidth
        Update-Counts

        # diálogos acompanham a altura da janela
        $ui.ReviewScroll.MaxHeight = [Math]::Max(110, $h - $(if ($ui.DiskSection.Visibility -eq 'Visible') { 480 } else { 300 }))
        $ui.ReviewCard.Margin = if ($h -lt 640) { '16,16' } else { '24,40' }
    }
    $window.Add_SizeChanged({ Apply-Layout })

    function Set-Mode([string]$m) {
        $script:mode = $m
        Update-View
        $ui.CardScroll.ScrollToTop()
    }

    function Show-Toast([string]$text, [double]$seconds = 1.8) {
        $ui.ToastText.Text = $text
        $anim = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
        foreach ($kf in @(@(0, 0), @(0.12, 1), @($seconds, 1), @(($seconds + 0.3), 0))) {
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
    $ui.ModeInstalled.Add_Checked({ Set-Mode 'Installed' })
    $ui.ModeUpdates.Add_Checked({ Set-Mode 'Updates' })
    $ui.ModeMissing.Add_Checked({ Set-Mode 'Missing' })

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
        $onlyMissing = $script:mode -notin @('Installed', 'Updates')
        foreach ($t in @($view)) {
            if ($onlyMissing -and $t.IsInstalled) { continue }
            if (-not $t.IsSelected) { $t.IsSelected = $true; $added++ }
        }
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
            $verb = if ($_.IsInstalled) { 'upgrade' } else { 'install' }
            "winget $verb --id $($_.Id) -e --source $($_.Source)" + $(if ($_.SelectedVersion) { " --version $($_.SelectedVersion)" } else { '' }) + " --accept-package-agreements --accept-source-agreements"
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
            if ($ui.ReviewPanel.Visibility -eq 'Visible') { $ui.ReviewPanel.Visibility = 'Collapsed'; $e.Handled = $true }
            elseif ($ui.SearchBox.Text) { $ui.SearchBox.Clear(); $e.Handled = $true }
        }
    })

    # ---------------------------------------------------------------- trabalho em segundo plano
    $sync = [hashtable]::Synchronized(@{
        Log = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
        DetectDone = $false; DetectError = $null; Installed = $null
        Completed = 0; Finished = $false; Cancel = $false
        Ok = 0; Already = 0; Failed = 0; NeedReboot = $false
        Online = $null; Stop = $false
        AppUpdate = $null; CatalogNew = $null
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

    # Ferramentas instaladas e suas versões (winget export --include-versions)
    $detectScript = {
        param($Sync, $W)
        try {
            $tmp = Join-Path $env:TEMP ('devsetup-' + [guid]::NewGuid().ToString('N') + '.json')
            $exportArgs = @('export', '-o', "`"$tmp`"", '--include-versions', '--accept-source-agreements') + @($W.Flag | Where-Object { $_ })
            Start-Process $W.Path -ArgumentList $exportArgs -WindowStyle Hidden -Wait
            $map = @{}
            if (Test-Path $tmp) {
                $json = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($src in $json.Sources) { foreach ($pkg in $src.Packages) { $map[$pkg.PackageIdentifier.ToLowerInvariant()] = [string]$pkg.Version } }
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
            $Sync.Installed = $map
        } catch {
            $Sync.DetectError = $_.Exception.Message
        }
        $Sync.DetectDone = $true
    }

    # Conexão com a internet (verificada a cada 15 s)
    $onlineScript = {
        param($Sync)
        while (-not $Sync.Stop) {
            $ok = $false
            if ([Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) {
                foreach ($url in 'http://www.msftconnecttest.com/connecttest.txt', 'https://www.github.com') {
                    try {
                        $req = [Net.WebRequest]::Create($url); $req.Timeout = 5000; $req.Method = 'GET'
                        $resp = $req.GetResponse(); $resp.Close(); $ok = $true; break
                    } catch {}
                }
            }
            $Sync.Online = $ok
            for ($i = 0; $i -lt 30 -and -not $Sync.Stop; $i++) { Start-Sleep -Milliseconds 500 }
        }
    }

    # Nova versão do DevSetup e catálogo atualizado (GitHub)
    $onlineChecksScript = {
        param($Sync, $AppVersion, $RepoApi, $CatalogUrl, $CatalogVersion, $CatalogCache, $KnownIds)
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        try {
            $rel = Invoke-RestMethod $RepoApi -Headers @{ 'User-Agent' = 'DevSetup' } -TimeoutSec 15
            $tag = ($rel.tag_name -replace '^v', '')
            if ([version]$tag -gt [version]$AppVersion) {
                $asset = @($rel.assets | Where-Object { $_.name -like '*.exe' }) | Select-Object -First 1
                $Sync.AppUpdate = @{ Version = $tag; Url = $asset.browser_download_url; Page = $rel.html_url; Name = $asset.name }
            }
        } catch {}
        try {
            $raw = Invoke-WebRequest $CatalogUrl -UseBasicParsing -Headers @{ 'User-Agent' = 'DevSetup' } -TimeoutSec 15
            $remote = $raw.Content | ConvertFrom-Json
            if ([int]$remote.catalogVersion -gt $CatalogVersion -and @($remote.tools).Count -gt 0) {
                New-Item -ItemType Directory -Force (Split-Path $CatalogCache) | Out-Null
                [IO.File]::WriteAllText($CatalogCache, $raw.Content, (New-Object Text.UTF8Encoding $false))
                $new = @($remote.tools | Where-Object { $KnownIds -notcontains $_.id }).Count
                $Sync.CatalogNew = $new
            }
        } catch {}
    }

    # ---------------------------------------------------------------- versões disponíveis (winget show --versions)
    $versionResults = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string,object]'
    $script:versionPending = @{}
    $script:pendingUpdateChecks = 0
    $versionPool = [runspacefactory]::CreateRunspacePool(1, 4)
    $versionPool.Open()

    $versionScript = {
        param($Id, $Results, $W)
        try {
            $psi = New-Object Diagnostics.ProcessStartInfo $W.Path
            $psi.Arguments = "show --id `"$Id`" --exact --source winget --versions --accept-source-agreements $($W.Flag)"
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true; $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
            $proc = [Diagnostics.Process]::Start($psi)
            $out = $proc.StandardOutput.ReadToEnd(); $proc.WaitForExit()
            $versions = New-Object Collections.Generic.List[string]
            $started = $false
            foreach ($l in ($out -split "`r?`n")) {
                $l = $l.Trim()
                if (-not $started) { if ($l -match '^-{3,}$') { $started = $true }; continue }
                if ($l -match '^[0-9A-Za-z][\w\.\-\+]*$' -and $l -ne 'Unknown') { $versions.Add($l) }
            }
            $Results[$Id] = @{ Ok = ($proc.ExitCode -eq 0); Versions = $versions.ToArray() }
        } catch {
            $Results[$Id] = @{ Ok = $false; Versions = @() }
        }
    }

    function Update-ToolState($t) {
        $t.HasUpdate = $t.IsInstalled -and $t.LatestVersion -and $t.InstalledVersion -and $t.InstalledVersion -ne 'Unknown' -and
                       ((Compare-Version $t.LatestVersion $t.InstalledVersion) -gt 0)
    }

    function Build-VersionOptions($t) {
        $opts = New-Object Collections.Generic.List[object]
        $latestLabel = if ($t.LatestVersion) { "Mais recente ($($t.LatestVersion))" } else { 'Mais recente' }
        $opts.Add((New-Object VersionOption -Property @{ Label = $latestLabel; Value = '' }))
        foreach ($v in @($t.AllVersions)) {
            if (-not $v) { continue }
            $lbl = if ($t.IsInstalled -and $t.InstalledVersion -and (Compare-Version $v $t.InstalledVersion) -eq 0) { "$v (instalada)" } else { $v }
            $opts.Add((New-Object VersionOption -Property @{ Label = $lbl; Value = $v }))
        }
        $t.Versions = [VersionOption[]]$opts.ToArray()
        $t.VersionsReady = @($t.AllVersions).Count -gt 1 -or ($t.IsInstalled -and @($t.AllVersions).Count -ge 1)
    }

    function Request-Versions($t) {
        if ($t.VersionsLoaded -or $script:versionPending.ContainsKey($t.Id)) { return }
        if ($t.Source -ne 'winget') { $t.VersionsLoaded = $true; return }
        $ps = [powershell]::Create()
        $ps.RunspacePool = $versionPool
        [void]$ps.AddScript($versionScript).AddArgument($t.Id).AddArgument($versionResults).AddArgument($wingetInfo)
        $script:versionPending[$t.Id] = @{ PS = $ps; Handle = $ps.BeginInvoke() }
    }

    function Apply-VersionResults {
        $changed = $false
        foreach ($id in @($script:versionPending.Keys)) {
            $r = $null
            if (-not $versionResults.TryGetValue($id, [ref]$r)) { continue }
            $job = $script:versionPending[$id]; $script:versionPending.Remove($id)
            try { $job.PS.EndInvoke($job.Handle) | Out-Null; $job.PS.Dispose() } catch {}
            $t = $byId[$id]
            $t.VersionsLoaded = $true
            $t.AllVersions = [string[]]@($r.Versions)
            if (@($r.Versions).Count -gt 0) { $t.LatestVersion = $r.Versions[0] }
            Update-ToolState $t
            if ($ui.ReviewPanel.Visibility -eq 'Visible' -and @($ui.ReviewList.ItemsSource) -contains $t) {
                Build-VersionOptions $t
                Set-ReviewText $t
            }
            $changed = $true
        }
        return $changed
    }

    # ---------------------------------------------------------------- revisão (instalar / atualizar / desinstalar)
    function Format-Size([double]$bytes) {
        if ($bytes -ge 1TB) { return '{0:N1} TB' -f ($bytes / 1TB) }
        return '{0:N0} GB' -f ($bytes / 1GB)
    }
    $sysDrive = [IO.Path]::GetPathRoot($env:SystemRoot)

    function Set-ReviewText($t) {
        $loading = $script:versionPending.ContainsKey($t.Id)
        switch ($script:reviewMode) {
            'install' {
                $t.ReviewText = if ($t.Source -ne 'winget') { 'Microsoft Store · sempre a mais recente' }
                                elseif ($loading) { 'Buscando versões…' }
                                elseif (-not $t.LatestVersion) { 'Não foi possível listar as versões' }
                                elseif (@($t.AllVersions).Count -le 1) { "Mais recente: $($t.LatestVersion)" }
                                else { "Mais recente: $($t.LatestVersion) · $(@($t.AllVersions).Count - 1) anteriores" }
            }
            'update' {
                $iv = if ($t.InstalledVersion -and $t.InstalledVersion -ne 'Unknown') { $t.InstalledVersion } else { 'versão desconhecida' }
                $t.ReviewText = if ($t.Source -ne 'winget') { "Instalada: $iv · Microsoft Store" }
                                elseif ($loading) { "Instalada: $iv · buscando versões…" }
                                elseif ($t.HasUpdate) { "Instalada: $iv → disponível: $($t.LatestVersion)" }
                                elseif ($t.LatestVersion) { "Instalada: $iv · já é a mais recente" }
                                else { "Instalada: $iv" }
            }
            'uninstall' {
                $iv = if ($t.InstalledVersion -and $t.InstalledVersion -ne 'Unknown') { $t.InstalledVersion } else { 'versão desconhecida' }
                $t.ReviewText = "Instalada: $iv"
            }
        }
    }

    function Update-VersionsStatus {
        if ($script:reviewMode -eq 'uninstall') { $ui.VersionsStatus.Text = ''; return }
        $sel = @($ui.ReviewList.ItemsSource)
        $pending = @($sel | Where-Object { $script:versionPending.ContainsKey($_.Id) }).Count
        $ui.VersionsStatus.Text = if ($pending) { "Buscando versões ($($sel.Count - $pending)/$($sel.Count))…" } else { 'Consultado no winget agora' }
    }

    function Show-Review([string]$mode, $items) {
        $items = [DevTool[]]@($items)   # tipado: o WPF precisa do objeto real para ouvir as mudanças
        if ($items.Count -eq 0) { return }
        $script:reviewMode = $mode
        $n = $items.Count
        $plural = if ($n -eq 1) { '1 ferramenta' } else { "$n ferramentas" }

        switch ($mode) {
            'install' {
                $ui.ReviewTitle.Text = 'Revisar instalação'
                $ui.ReviewSub.Text = "$plural. Por padrão é instalada a versão mais recente; escolha uma anterior se precisar."
                $ui.ReviewListTitle.Text = 'Versões'
                $ui.ReviewOkText.Text = 'Instalar'
                $ui.DiskSection.Visibility = 'Visible'
            }
            'update' {
                $ui.ReviewTitle.Text = 'Atualizar ou trocar versão'
                $ui.ReviewSub.Text = "$plural. Mantenha ""Mais recente"" para atualizar, ou escolha outra versão para trocar (versões antigas são reinstaladas)."
                $ui.ReviewListTitle.Text = 'Versão desejada'
                $ui.ReviewOkText.Text = 'Aplicar'
                $ui.DiskSection.Visibility = 'Collapsed'
            }
            'uninstall' {
                $ui.ReviewTitle.Text = 'Desinstalar ferramentas'
                $ui.ReviewSub.Text = "$plural serão removidas do computador. Alguns desinstaladores podem pedir confirmação."
                $ui.ReviewListTitle.Text = 'Serão removidas'
                $ui.ReviewOkText.Text = 'Desinstalar'
                $ui.DiskSection.Visibility = 'Collapsed'
            }
        }

        foreach ($t in $items) {
            $t.SelectedVersion = ''
            $t.ShowVersionPicker = ($mode -ne 'uninstall')
            if ($mode -ne 'uninstall') { Request-Versions $t; Build-VersionOptions $t }
            Set-ReviewText $t
        }
        $ui.ReviewList.ItemsSource = $items

        if ($mode -eq 'install') {
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
        }
        Update-VersionsStatus
        $ui.ReviewPanel.Visibility = 'Visible'
        Apply-Layout
    }

    function Get-InstallRoot($drive) {
        if (-not $drive -or $drive.IsSystem) { return $null }
        return (Join-Path $drive.Root 'DevTools')
    }

    $ui.DriveList.Add_SelectionChanged({
        $d = $ui.DriveList.SelectedItem
        if (-not $d) { $ui.DrivePath.Text = ''; return }
        $r = Get-InstallRoot $d
        $ui.DrivePath.Text = if ($r) { "Destino: $r\<ferramenta>" } else { 'Destino: local padrão de cada instalador (Program Files)' }
    })

    $ui.ReviewCancel.Add_Click({ $ui.ReviewPanel.Visibility = 'Collapsed' })

    $ui.InstallBtn.Add_Click({ Show-Review 'install' ($tools | Where-Object { $_.IsSelected -and -not $_.IsInstalled }) })
    $ui.UpdateBtn.Add_Click({ Show-Review 'update' ($tools | Where-Object { $_.IsSelected -and $_.IsInstalled }) })
    $ui.UninstallBtn.Add_Click({ Show-Review 'uninstall' ($tools | Where-Object { $_.IsSelected -and $_.IsInstalled }) })
    $ui.UpdateAllBtn.Add_Click({ Show-Review 'update' ($tools | Where-Object { $_.HasUpdate }) })

    # ---------------------------------------------------------------- execução (instalar / atualizar / desinstalar)
    $operationScript = {
        param($Queue, $Sync, $InstallRoot, $W)
        $alreadyCodes = @(-1978335189, -1978335135)   # 0x8A15002B (sem atualização), 0x8A150061 (já instalado)
        $rebootCode   = -1978334967                    # 0x8A150109 (reinicialização necessária)
        $units = @{ 'B' = 1; 'KB' = 1KB; 'MB' = 1MB; 'GB' = 1GB }

        function Invoke-Winget($t, [string]$arguments, [string]$busyText) {
            $psi = New-Object Diagnostics.ProcessStartInfo $W.Path
            $psi.Arguments = $arguments
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true; $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
            $Sync.Log.Enqueue("   winget $arguments")
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
                if ($m.Success -and $line -match '[█▒]') { $t.IsIndeterminate = $false; $t.Progress = [int]$m.Groups[1].Value; continue }
                if ($line -match '[█▒]') { continue }
                if ($sawDownload) { $t.Status = $busyText; $t.IsIndeterminate = $true }
                $Sync.Log.Enqueue("   $line")
            }
            $proc.WaitForExit()
            $Sync.Log.Enqueue(("   código de saída {0} (0x{0:X8})" -f $proc.ExitCode))
            return $proc.ExitCode
        }

        function Get-Reason([int]$code) {
            switch ($code) {
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
        }
        function Get-Fail([int]$code) { '{0} (código 0x{1:X8})' -f (Get-Reason $code), $code }

        $common = "--accept-source-agreements $($W.Flag)".Trim()
        $Sync.Log.Enqueue("winget: $($W.Path) (versão $($W.Version))")
        if (@($Queue | Where-Object { $_.Action -ne 'uninstall' }).Count -gt 0) {
            $Sync.Log.Enqueue('Atualizando catálogo do winget...')
            try { Start-Process $W.Path -ArgumentList ("source update --name winget $($W.Flag)".Trim()) -WindowStyle Hidden -Wait } catch {}
        }

        foreach ($t in $Queue) {
            if ($Sync.Cancel) { $t.State = 'Skipped'; $t.Status = 'Cancelado'; $Sync.Completed++; continue }
            $t.State = 'Running'; $t.IsIndeterminate = $true; $t.Progress = 0
            $Sync.Log.Enqueue('')
            $Sync.Log.Enqueue("> $($t.Name)  [$($t.Id)]  ação: $($t.Action)")
            $v = $t.TargetVersion
            $verArg = if ($t.SelectedVersion) { " --version `"$($t.SelectedVersion)`"" } else { '' }
            try {
                switch ($t.Action) {
                    'install' {
                        $t.Status = 'Preparando'
                        $a = "install --id `"$($t.Id)`" --exact --source $($t.Source) --silent --accept-package-agreements $common$verArg"
                        $withLocation = $InstallRoot -and $t.Source -eq 'winget'
                        $loc = if ($withLocation) { " --location `"$(Join-Path $InstallRoot ($t.Name -replace '[\\/:*?"<>|]', ''))`"" } else { '' }
                        $code = Invoke-Winget $t ($a + $loc) 'Instalando'
                        $fallback = $false
                        if ($withLocation -and $code -ne 0 -and $code -ne $rebootCode -and $alreadyCodes -notcontains $code) {
                            # alguns instaladores não aceitam outro local: tenta no local padrão
                            $Sync.Log.Enqueue('   o instalador recusou o local escolhido; tentando no local padrão')
                            $t.Status = 'Tentando no local padrão'; $t.IsIndeterminate = $true
                            $code = Invoke-Winget $t $a 'Instalando'
                            $fallback = $true
                        }
                        if ($code -eq 0 -or $code -eq $rebootCode) {
                            $t.State = 'Done'; $t.Status = $(if ($v) { "Instalado · $v" } else { 'Instalado' })
                            if ($fallback) { $t.Status += ' · no disco do sistema' }
                            $t.IsInstalled = $true; if ($v) { $t.InstalledVersion = $v }; $Sync.Ok++
                            if ($code -eq $rebootCode) { $Sync.NeedReboot = $true; $t.Status += ' · reinicie o PC' }
                        } elseif ($alreadyCodes -contains $code) {
                            $t.State = 'Done'; $t.Status = 'Já instalado'; $t.IsInstalled = $true; $Sync.Already++
                        } else { $t.State = 'Failed'; $t.Status = Get-Fail $code; $Sync.Failed++ }
                    }
                    'upgrade' {
                        $t.Status = 'Preparando'
                        $a = "upgrade --id `"$($t.Id)`" --exact --source $($t.Source) --silent --accept-package-agreements $common$verArg"
                        $code = Invoke-Winget $t $a 'Atualizando'
                        if ($code -eq 0 -or $code -eq $rebootCode) {
                            $t.State = 'Done'; $t.Status = $(if ($v) { "Atualizado · $v" } else { 'Atualizado' })
                            if ($v) { $t.InstalledVersion = $v }; $t.HasUpdate = $false; $Sync.Ok++
                            if ($code -eq $rebootCode) { $Sync.NeedReboot = $true; $t.Status += ' · reinicie o PC' }
                        } elseif ($alreadyCodes -contains $code) {
                            $t.State = 'Done'; $t.Status = 'Já está atualizado'; $t.HasUpdate = $false; $Sync.Already++
                        } else { $t.State = 'Failed'; $t.Status = Get-Fail $code; $Sync.Failed++ }
                    }
                    'uninstall' {
                        $t.Status = 'Removendo'
                        $code = Invoke-Winget $t "uninstall --id `"$($t.Id)`" --exact --silent $common" 'Removendo'
                        if ($code -eq 0 -or $code -eq $rebootCode) {
                            $t.State = 'Done'; $t.Status = 'Desinstalado'
                            $t.IsInstalled = $false; $t.InstalledVersion = ''; $t.HasUpdate = $false; $Sync.Ok++
                        } else { $t.State = 'Failed'; $t.Status = Get-Fail $code; $Sync.Failed++ }
                    }
                    'reinstall' {
                        $t.Status = 'Removendo versão atual'
                        $code = Invoke-Winget $t "uninstall --id `"$($t.Id)`" --exact --silent $common" 'Removendo versão atual'
                        if ($code -ne 0) { $t.State = 'Failed'; $t.Status = 'Falha ao remover a versão atual'; $Sync.Failed++; break }
                        $t.IsInstalled = $false
                        $t.Status = "Instalando $v"; $t.IsIndeterminate = $true
                        $code = Invoke-Winget $t "install --id `"$($t.Id)`" --exact --source $($t.Source) --silent --accept-package-agreements $common --version `"$v`"" "Instalando $v"
                        if ($code -eq 0 -or $code -eq $rebootCode) {
                            $t.State = 'Done'; $t.Status = "Versão $v instalada"; $t.IsInstalled = $true; $t.InstalledVersion = $v; $Sync.Ok++
                        } else { $t.State = 'Failed'; $t.Status = (Get-Fail $code) + ' · a versão anterior foi removida'; $Sync.Failed++ }
                    }
                }
            } catch {
                $msg = $_.Exception.Message -replace '\s+', ' '
                $t.State = 'Failed'; $t.Status = 'Erro: ' + $(if ($msg.Length -gt 70) { $msg.Substring(0, 70) + '…' } else { $msg }); $Sync.Failed++
                $Sync.Log.Enqueue("   ERRO: $($_.Exception.Message)")
            }
            $t.IsIndeterminate = $false; $t.Progress = 100
            $Sync.Completed++
        }
        $Sync.Finished = $true
    }

    $script:busy = $false
    $script:queue = @()

    $ui.ReviewOk.Add_Click({
        $mode = $script:reviewMode
        $items = @($ui.ReviewList.ItemsSource)
        $installRoot = $null
        if ($mode -eq 'install') {
            $drive = $ui.DriveList.SelectedItem
            if ($drive) { Save-Setting 'drive' $drive.Root; $installRoot = Get-InstallRoot $drive }
        }

        $queue = New-Object Collections.Generic.List[DevTool]
        foreach ($t in $items) {
            $t.Action = $null
            $target = if ($t.SelectedVersion) { $t.SelectedVersion } else { $t.LatestVersion }
            $t.TargetVersion = $target
            switch ($mode) {
                'install'   { $t.Action = 'install' }
                'uninstall' { $t.Action = 'uninstall' }
                'update' {
                    $known = $t.InstalledVersion -and $t.InstalledVersion -ne 'Unknown'
                    if (-not $target) { $t.Action = 'upgrade' }
                    elseif ($known -and (Compare-Version $target $t.InstalledVersion) -eq 0) { $t.Action = $null }
                    elseif ($known -and $t.SelectedVersion -and (Compare-Version $target $t.InstalledVersion) -lt 0) { $t.Action = 'reinstall' }
                    else { $t.Action = 'upgrade' }
                }
            }
            if ($t.Action) { $queue.Add($t) }
        }
        $ui.ReviewPanel.Visibility = 'Collapsed'
        if ($queue.Count -eq 0) { Show-Toast 'Nada a fazer: as ferramentas já estão nas versões escolhidas' 2.6; return }

        $script:queue = [DevTool[]]$queue.ToArray()
        foreach ($t in $script:queue) {
            $t.State = 'Queued'; $t.Progress = 0; $t.IsIndeterminate = $false
            $t.Status = switch ($t.Action) {
                'install'   { "Na fila · instalar $(if ($t.TargetVersion) { $t.TargetVersion } else { 'mais recente' })" }
                'upgrade'   { "Na fila · atualizar para $(if ($t.TargetVersion) { $t.TargetVersion } else { 'a mais recente' })" }
                'reinstall' { "Na fila · trocar para $($t.TargetVersion)" }
                'uninstall' { 'Na fila · desinstalar' }
            }
        }
        $sync.Completed = 0; $sync.Finished = $false; $sync.Cancel = $false
        $sync.Ok = 0; $sync.Already = 0; $sync.Failed = 0; $sync.NeedReboot = $false
        $ui.LogBox.Clear()

        $ui.QueueList.ItemsSource = $script:queue
        $ui.OvTitle.Text = switch ($mode) { 'install' { 'Instalando' } 'update' { 'Atualizando' } 'uninstall' { 'Desinstalando' } }
        $ui.OvGlyph.Visibility = 'Collapsed'
        $ui.OvSub.Text = if ($mode -eq 'install' -and $installRoot) { "Instalando em $installRoot. Alguns instaladores podem pedir permissão de administrador." }
                         else { 'Alguns instaladores podem pedir permissão de administrador.' }
        $ui.OvBar.Value = 0
        $ui.OvCancel.Visibility = 'Visible'; $ui.OvCancel.IsEnabled = $true
        $ui.OvClose.Visibility = 'Collapsed'
        $ui.Overlay.Visibility = 'Visible'

        if ($installRoot) { New-Item -ItemType Directory -Force $installRoot -ErrorAction SilentlyContinue | Out-Null }
        $script:busy = $true
        Start-Worker $operationScript @{ Queue = $script:queue; Sync = $sync; InstallRoot = $installRoot; W = $wingetInfo }
    })

    $ui.OvCancel.Add_Click({
        $sync.Cancel = $true
        $ui.OvCancel.IsEnabled = $false
        $ui.OvSub.Text = 'Cancelando: a operação atual será concluída e as restantes serão ignoradas.'
    })

    $ui.LogToggle.Add_Click({
        if ($ui.LogBox.Visibility -eq 'Visible') { $ui.LogBox.Visibility = 'Collapsed'; $ui.LogToggleText.Text = 'Mostrar log' }
        else { $ui.LogBox.Visibility = 'Visible'; $ui.LogToggleText.Text = 'Ocultar log'; $ui.LogBox.ScrollToEnd() }
    })

    function Start-Detection {
        $sync.DetectDone = $false; $sync.DetectError = $null
        $script:detectHandled = $false
        Start-Worker $detectScript @{ Sync = $sync; W = $wingetInfo }
    }

    $ui.OvClose.Add_Click({
        foreach ($t in $script:queue) {
            if ($t.State -eq 'Done') { $t.IsSelected = $false }
            $t.State = 'Idle'; $t.Status = ''
            Update-ToolState $t
        }
        $ui.Overlay.Visibility = 'Collapsed'
        Update-Counts; Update-View; Update-Summary
        Start-Detection    # confirma o estado real no winget
    })

    function Complete-Operation {
        $script:busy = $false
        $parts = @()
        if ($sync.Ok)      { $parts += "$($sync.Ok) concluída(s)" }
        if ($sync.Already) { $parts += "$($sync.Already) sem alteração" }
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

    # ---------------------------------------------------------------- atualização do próprio DevSetup
    $ui.AppUpdateBtn.Add_Click({
        $u = $sync.AppUpdate
        if (-not $u) { return }
        if (-not $u.Url) { Start-Process $u.Page; return }
        try {
            $window.Cursor = [Windows.Input.Cursors]::Wait
            $dest = Join-Path $env:TEMP $(if ($u.Name) { $u.Name } else { "DevSetup-Setup-$($u.Version).exe" })
            $wc = New-Object Net.WebClient
            $wc.Headers.Add('User-Agent', 'DevSetup')
            $wc.DownloadFile($u.Url, $dest)
            Start-Process $dest
            $window.Close()
        } catch {
            $window.Cursor = $null
            Show-Toast 'Não foi possível baixar a atualização; abrindo a página do GitHub' 2.5
            Start-Process $u.Page
        }
    })

    # ---------------------------------------------------------------- status
    $script:online = $true          # otimista até a primeira verificação
    $script:onlineKnown = $false
    function Update-Status {
        if (-not $script:wingetOk) {
            $ui.StatusDot.SetResourceReference([Windows.Shapes.Shape]::FillProperty, 'Danger')
            $ui.StatusText.Text = 'winget não encontrado'; $ui.StatusDetail.Text = 'Instale o Instalador de Aplicativo'
            return
        }
        if (-not $script:onlineKnown) {
            $ui.StatusDot.SetResourceReference([Windows.Shapes.Shape]::FillProperty, 'TextFaint')
            $ui.StatusText.Text = 'Verificando conexão…'
        } elseif ($script:online) {
            $ui.StatusDot.SetResourceReference([Windows.Shapes.Shape]::FillProperty, 'Success')
            $ui.StatusText.Text = 'Online'
        } else {
            $ui.StatusDot.SetResourceReference([Windows.Shapes.Shape]::FillProperty, 'Danger')
            $ui.StatusText.Text = 'Sem internet'
        }
        $inst = @($tools | Where-Object { $_.IsInstalled }).Count
        $upd  = @($tools | Where-Object { $_.HasUpdate }).Count
        $ui.StatusDetail.Text = if (-not $script:detectHandled) { 'Lendo ferramentas instaladas…' }
                                elseif ($script:pendingUpdateChecks -gt 0) { "Buscando atualizações ($script:pendingUpdateChecks restantes)…" }
                                elseif ($upd) { "$inst instaladas · $upd atualizações" }
                                else { "$inst instaladas · tudo atualizado" }
        $ui.OfflineBanner.Visibility = if ($script:onlineKnown -and -not $script:online) { 'Visible' } else { 'Collapsed' }
    }

    # ---------------------------------------------------------------- timer de atualização da UI
    $script:detectHandled = $false
    $script:onlineChecksStarted = $false
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({
        # conexão
        if ($null -ne $sync.Online -and ($sync.Online -ne $script:online -or -not $script:onlineKnown)) {
            $script:online = [bool]$sync.Online; $script:onlineKnown = $true
            Update-Status; Update-Summary; Update-Counts
            if ($script:online -and -not $script:onlineChecksStarted) {
                $script:onlineChecksStarted = $true
                Start-Worker $onlineChecksScript @{ Sync = $sync; AppVersion = $AppVersion; RepoApi = $RepoApi; CatalogUrl = $CatalogUrl
                                                    CatalogVersion = $catalogVersion; CatalogCache = $catalogCache; KnownIds = [string[]]@($byId.Keys) }
            }
        }
        if ($sync.AppUpdate -and $ui.AppUpdateBanner.Visibility -ne 'Visible') {
            $ui.AppUpdateText.Text = "DevSetup $($sync.AppUpdate.Version) disponível"
            $ui.AppUpdateBanner.Visibility = 'Visible'
        }
        if ($null -ne $sync.CatalogNew) {
            $n = $sync.CatalogNew; $sync.CatalogNew = $null
            Show-Toast $(if ($n -gt 0) { "Catálogo atualizado: $n nova(s) ferramenta(s). Reabra o DevSetup para ver." } else { 'Catálogo atualizado. Reabra o DevSetup para ver as novidades.' }) 4
        }

        # instaladas + versões
        if ($sync.DetectDone -and -not $script:detectHandled) {
            $script:detectHandled = $true
            $map = $sync.Installed
            if ($map) {
                foreach ($t in $tools) {
                    $key = $t.Id.ToLowerInvariant()
                    $t.IsInstalled = $map.ContainsKey($key)
                    $t.InstalledVersion = if ($t.IsInstalled) { $map[$key] } else { '' }
                    Update-ToolState $t
                    if ($t.IsInstalled) { Request-Versions $t }
                }
            }
            Update-Counts; Update-View; Update-Summary; Update-Status
        }

        if ($script:versionPending.Count -gt 0) {
            if (Apply-VersionResults) {
                $script:pendingUpdateChecks = @($tools | Where-Object { $_.IsInstalled -and $script:versionPending.ContainsKey($_.Id) }).Count
                Update-Counts; Update-Status
                if ($script:mode -eq 'Updates') { Update-View }
            }
            if ($ui.ReviewPanel.Visibility -eq 'Visible') { Update-VersionsStatus }
        } elseif ($script:pendingUpdateChecks -ne 0) {
            $script:pendingUpdateChecks = 0; Update-Status
            if ($script:mode -eq 'Updates') { Update-View }
        }

        # operação em andamento
        if ($script:busy) {
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
            if ($sync.Finished) { Complete-Operation }
        }
    })
    $timer.Start()

    $window.Add_Closing({
        param($s, $e)
        if ($script:busy) {
            $r = [Windows.MessageBox]::Show('Uma operação está em andamento. Deseja realmente sair? A ferramenta atual continuará em segundo plano, mas as restantes serão canceladas.', 'DevSetup', 'YesNo', 'Warning')
            if ($r -ne 'Yes') { $e.Cancel = $true; return }
            $sync.Cancel = $true
        }
        $sync.Stop = $true
        $timer.Stop()
    })

    # ---------------------------------------------------------------- inicialização
    # localiza o winget e descobre a versão (opções novas só são usadas quando suportadas)
    $wingetPath = $null
    $cmd = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $wingetPath = $cmd.Source }
    elseif (Test-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe") { $wingetPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" }
    $wingetVersion = [version]'0.0'
    if ($wingetPath) {
        try {
            $vout = (& $wingetPath --version 2>$null | Out-String).Trim()
            $m = [regex]::Match($vout, '(\d+)\.(\d+)(\.(\d+))?')
            if ($m.Success) { $wingetVersion = [version]('{0}.{1}.{2}' -f $m.Groups[1].Value, $m.Groups[2].Value, $(if ($m.Groups[4].Success) { $m.Groups[4].Value } else { 0 })) }
        } catch {}
    }
    $wingetInfo = @{
        Path    = $wingetPath
        Version = $wingetVersion.ToString()
        Flag    = $(if ($wingetVersion -ge [version]'1.4') { '--disable-interactivity' } else { '' })
    }
    $script:wingetOk = [bool]$wingetPath
    if ($script:wingetOk -and $wingetVersion -lt [version]'1.4') {
        $window.Add_ContentRendered({
            Show-Toast "Seu winget ($($wingetInfo.Version)) é antigo. Se algo falhar, atualize o Instalador de Aplicativo na Microsoft Store." 6
        })
    }
    Start-Worker $onlineScript @{ Sync = $sync }
    if ($script:wingetOk) {
        Start-Detection
    } else {
        $window.Add_ContentRendered({
            $r = [Windows.MessageBox]::Show("O winget (Gerenciador de Pacotes do Windows) não foi encontrado.`n`nDeseja abrir a Microsoft Store para instalar o 'Instalador de Aplicativo'?", 'DevSetup', 'YesNo', 'Warning')
            if ($r -eq 'Yes') { Start-Process 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1' }
        })
    }

    Update-Counts
    Update-View
    Update-Summary
    Update-Status
    $window.Add_ContentRendered({ Apply-Layout })

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
