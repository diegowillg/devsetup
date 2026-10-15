#Requires -Version 5.1
<#
    DevSetup - selecione e instale ferramentas de desenvolvimento de uma vez (via winget).
    Catálogo: tools.json  |  Interface: MainWindow.xaml
#>

param([string]$Snapshot)

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
    public string Color { get; set; }
    public string Initials { get; set; }
    public string SearchText { get; set; }
    public string Site { get; set; }
    public string IconPath { get; set; }
    string _iconBg = "#181C25"; public string IconBg { get { return _iconBg; } set { if (!string.IsNullOrEmpty(value)) _iconBg = value; } }
    public bool HasIcon { get { return !string.IsNullOrEmpty(IconPath); } }

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
    public string Color { get; set; }
    public string Icon { get; set; }
    public string Summary { get; set; }
    public string[] Ids { get; set; }
}
'@
}

function Show-Error([string]$msg) {
    [void][Windows.MessageBox]::Show($msg, 'DevSetup', 'OK', 'Error')
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
        $d.Color       = $t.color
        $d.Initials    = if ($t.initials) { $t.initials } else { $t.name.Substring(0, [Math]::Min(2, $t.name.Length)).ToUpper() }
        $d.SearchText  = ('{0} {1} {2} {3} {4}' -f $t.name, $t.desc, $t.id, $t.category, $t.keywords).ToLowerInvariant()
        $d.Site        = $t.site
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
    foreach ($n in 'Root','CategoryList','PresetList','StatusDot','StatusHalo','StatusTitle','StatusText','SearchBox','SelectAllBtn','ClearBtn',
                   'VisibleCount','ModeAll','ModeSelected','ModeMissing','SelCount','SelCountPill','StatTools','StatCats','StatInstalled',
                   'CardScroll','ToolList','EmptyState','EmptyGlyph','EmptyTitle','EmptyText','SummaryTitle','SummaryText','CopyBtn',
                   'InstallBtn','InstallBtnText','TrayIcons','TrayStack','TrayMore','TrayMoreText','TrayEmptyIcon',
                   'Toast','ToastText','Overlay','OvIcon','OvGlow','OvGlyph','OvTitle','OvSub','OvCount',
                   'OvPercent','OvBar','LogToggle','LogToggleText','OvCancel','OvClose','LogBox','QueueList','MinBtn','MaxBtn','CloseBtn') {
        $ui[$n] = $window.FindName($n)
    }

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
        New-Object Preset -Property @{ Name = $p.name; Color = $p.color; Icon = $glyph; Ids = $ids; Summary = "$($ids.Count) ferramentas" }
    }
    $ui.PresetList.ItemsSource = @($presets)
    $ui.StatTools.Text = "$($tools.Count)"
    $ui.StatCats.Text  = "$(@($data.categories).Count)"

    # ---------------------------------------------------------------- filtro
    $script:category = $null
    $script:terms    = @()
    $script:mode     = 'All'   # All | Selected | Missing

    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($tools)
    $view.GroupDescriptions.Add((New-Object Windows.Data.PropertyGroupDescription 'Category'))
    $view.Filter = [Predicate[object]] {
        param($o)
        if ($script:category -and $o.Category -ne $script:category) { return $false }
        if ($script:mode -eq 'Selected' -and -not $o.IsSelected) { return $false }
        if ($script:mode -eq 'Missing' -and $o.IsInstalled) { return $false }
        foreach ($term in $script:terms) { if (-not $o.SearchText.Contains($term)) { return $false } }
        return $true
    }
    $ui.ToolList.ItemsSource = $view

    function Update-View {
        $view.Refresh()
        $visible = @($view).Count
        $ui.EmptyState.Visibility = if ($visible -eq 0) { 'Visible' } else { 'Collapsed' }
        if ($script:mode -eq 'Selected' -and -not $script:terms) {
            $ui.EmptyGlyph.Text = [string][char]0xE7BF
            $ui.EmptyTitle.Text = 'Nada selecionado ainda'
            $ui.EmptyText.Text  = 'Escolha ferramentas na aba "Todas" ou aplique um perfil rápido.'
        } else {
            $ui.EmptyGlyph.Text = [string][char]0xE721
            $ui.EmptyTitle.Text = 'Nenhuma ferramenta encontrada'
            $ui.EmptyText.Text  = 'Tente outro termo de busca ou outra categoria.'
        }
        $ui.VisibleCount.Text = if ($visible -eq $tools.Count) { '' } else { "$visible de $($tools.Count)" }
    }

    function Update-Summary {
        $sel = @($tools | Where-Object { $_.IsSelected })
        $n = $sel.Count
        $ui.InstallBtn.IsEnabled = ($n -gt 0) -and $script:wingetOk
        $ui.CopyBtn.IsEnabled = $n -gt 0
        $ui.SelCount.Text = "$n"
        $ui.SelCountPill.Visibility = if ($n -gt 0) { 'Visible' } else { 'Collapsed' }

        $maxIcons = 6
        $ui.TrayIcons.ItemsSource = @($sel | Select-Object -First $maxIcons)
        $ui.TrayStack.Visibility = if ($n -gt 0) { 'Visible' } else { 'Collapsed' }
        $ui.TrayEmptyIcon.Visibility = if ($n -gt 0) { 'Collapsed' } else { 'Visible' }
        $ui.TrayMore.Visibility = if ($n -gt $maxIcons) { 'Visible' } else { 'Collapsed' }
        $ui.TrayMoreText.Text = "+$($n - $maxIcons)"

        if ($n -eq 0) {
            $ui.SummaryTitle.Text   = 'Nenhuma ferramenta selecionada'
            $ui.SummaryText.Text    = 'Clique nos cartões ou use um perfil rápido na barra lateral.'
            $ui.InstallBtnText.Text = 'Instalar'
        } else {
            $ui.SummaryTitle.Text   = if ($n -eq 1) { '1 ferramenta selecionada' } else { "$n ferramentas selecionadas" }
            $names = ($sel | Select-Object -First 4 | ForEach-Object Name) -join ', '
            if ($n -gt 4) { $names += " e mais $($n - 4)" }
            $ui.SummaryText.Text    = $names
            $ui.InstallBtnText.Text = if ($n -eq 1) { 'Instalar 1 ferramenta' } else { "Instalar $n ferramentas" }
        }
    }

    function Update-Stats { $ui.StatInstalled.Text = "$(@($tools | Where-Object { $_.IsInstalled }).Count)" }

    # cartões responsivos: preenche a largura disponível com colunas iguais
    $script:lastCardWidth = 0
    function Update-CardWidth {
        $avail = $ui.ToolList.ActualWidth - 8   # folga: o painel interno do grupo é alguns px mais estreito
        if ($avail -le 0) { return }
        $gap = 14; $min = 280
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
        foreach ($kf in @(@(0, 0), @(0.15, 1), @(2.0, 1), @(2.4, 0))) {
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
        if ($added -eq 0) { Show-Toast "Perfil '$($preset.Name)': nada novo para adicionar" }
        else { Show-Toast "Perfil '$($preset.Name)': +$added ferramenta(s) selecionada(s)" }
    })

    $ui.SelectAllBtn.Add_Click({
        $added = 0
        foreach ($t in @($view)) { if (-not $t.IsInstalled -and -not $t.IsSelected) { $t.IsSelected = $true; $added++ } }
        Update-Summary
        Show-Toast "+$added ferramenta(s) selecionada(s)"
    })

    $ui.ClearBtn.Add_Click({
        foreach ($t in $tools) { $t.IsSelected = $false }
        Update-Summary
        if ($script:mode -eq 'Selected') { Update-View }
    })

    $ui.CopyBtn.Add_Click({
        $cmds = $tools | Where-Object { $_.IsSelected } | ForEach-Object {
            "winget install --id $($_.Id) -e --source winget --accept-package-agreements --accept-source-agreements"
        }
        [Windows.Clipboard]::SetText(($cmds -join "`r`n"))
        Show-Toast 'Comandos copiados para a área de transferência'
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
        elseif ($e.Key -eq 'Escape' -and $ui.SearchBox.Text) { $ui.SearchBox.Clear(); $e.Handled = $true }
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

    # Instala a fila, um pacote por vez
    $installScript = {
        param($Queue, $Sync)
        $alreadyCodes = @(-1978335189, -1978335135)   # 0x8A15002B (sem atualização), 0x8A150061 (já instalado)
        $rebootCode   = -1978334967                    # 0x8A150109 (reinicialização necessária)
        $units = @{ 'B' = 1; 'KB' = 1KB; 'MB' = 1MB; 'GB' = 1GB }

        foreach ($t in $Queue) {
            if ($Sync.Cancel) { $t.State = 'Skipped'; $t.Status = 'Cancelado'; $Sync.Completed++; continue }

            $t.State = 'Running'; $t.Status = 'Preparando…'; $t.IsIndeterminate = $true; $t.Progress = 0
            $Sync.Log.Enqueue("")
            $Sync.Log.Enqueue("▶ $($t.Name)  [$($t.Id)]")
            try {
                $psi = New-Object Diagnostics.ProcessStartInfo 'winget'
                $psi.Arguments = "install --id `"$($t.Id)`" --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity"
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
                            $t.Status = "Baixando $pct%  ·  $($m.Groups[3].Value) $($m.Groups[4].Value)"
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
                    if ($sawDownload) { $t.Status = 'Instalando…'; $t.IsIndeterminate = $true }
                    $Sync.Log.Enqueue("   $line")
                }
                $proc.WaitForExit()
                $code = $proc.ExitCode

                if ($code -eq 0) {
                    $t.State = 'Done'; $t.Status = 'Instalado'; $t.IsInstalled = $true; $Sync.Ok++
                } elseif ($alreadyCodes -contains $code) {
                    $t.State = 'Done'; $t.Status = 'Já instalado'; $t.IsInstalled = $true; $Sync.Already++
                } elseif ($code -eq $rebootCode) {
                    $t.State = 'Done'; $t.Status = 'Instalado · reinicie o PC'; $t.IsInstalled = $true; $Sync.Ok++; $Sync.NeedReboot = $true
                } else {
                    $reason = switch ($code) {
                        -1978335212 { 'Pacote não encontrado' }          # 0x8A150014
                        -1978335216 { 'Sem instalador compatível' }      # 0x8A150010
                        -1978334975 { 'Instalador em uso, tente de novo' } # 0x8A150101
                        -1978334974 { 'Reinicie o PC e tente de novo' }  # 0x8A150102
                        -1978334970 { 'Bloqueado por política' }         # 0x8A150106
                        -1978334967 { 'Reinicie o PC' }
                        -1978334972 { 'Espaço em disco insuficiente' }   # 0x8A150104
                        -1978335230 { 'Sem conexão / fonte indisponível' } # 0x8A150002
                        1602        { 'Cancelado pelo usuário' }
                        1603        { 'Erro fatal do instalador' }
                        default     { 'Falhou' }
                    }
                    $t.State = 'Failed'; $t.Status = ('{0} (0x{1:X8})' -f $reason, $code); $Sync.Failed++
                }
                $Sync.Log.Enqueue(("   → código de saída {0} (0x{0:X8})" -f $code))
            } catch {
                $t.State = 'Failed'; $t.Status = 'Erro ao executar winget'; $Sync.Failed++
                $Sync.Log.Enqueue("   ERRO: $($_.Exception.Message)")
            }
            $t.IsIndeterminate = $false; $t.Progress = 100
            $Sync.Completed++
        }
        $Sync.Finished = $true
    }

    # ---------------------------------------------------------------- instalação (UI)
    $script:installing = $false
    $script:queue = @()

    $ui.InstallBtn.Add_Click({
        $script:queue = @($tools | Where-Object { $_.IsSelected })
        if ($script:queue.Count -eq 0) { return }

        foreach ($t in $script:queue) { $t.State = 'Queued'; $t.Status = 'Na fila'; $t.Progress = 0; $t.IsIndeterminate = $false }
        $sync.Completed = 0; $sync.Finished = $false; $sync.Cancel = $false
        $sync.Ok = 0; $sync.Already = 0; $sync.Failed = 0; $sync.NeedReboot = $false
        $ui.LogBox.Clear()

        $ui.QueueList.ItemsSource = $script:queue
        $ui.OvTitle.Text = 'Instalando ferramentas'
        $ui.OvSub.Text = 'Não feche esta janela. Alguns instaladores podem pedir permissão de administrador.'
        $ui.OvIcon.Background = $window.FindResource('AccentGrad'); $ui.OvGlow.Background = $ui.OvIcon.Background
        $ui.OvGlyph.Text = [string][char]0xE896
        $ui.OvBar.Value = 0
        $ui.OvCancel.Visibility = 'Visible'; $ui.OvCancel.IsEnabled = $true
        $ui.OvClose.Visibility = 'Collapsed'
        $ui.Overlay.Visibility = 'Visible'

        $script:installing = $true
        Start-Worker $installScript @{ Queue = $script:queue; Sync = $sync }
    })

    $ui.OvCancel.Add_Click({
        $sync.Cancel = $true
        $ui.OvCancel.IsEnabled = $false
        $ui.OvSub.Text = 'Cancelando: a instalação atual será concluída e as restantes serão ignoradas.'
    })

    $ui.LogToggle.Add_Click({
        if ($ui.LogBox.Visibility -eq 'Visible') { $ui.LogBox.Visibility = 'Collapsed'; $ui.LogToggleText.Text = 'Mostrar log detalhado' }
        else { $ui.LogBox.Visibility = 'Visible'; $ui.LogToggleText.Text = 'Ocultar log'; $ui.LogBox.ScrollToEnd() }
    })

    $ui.OvClose.Add_Click({
        foreach ($t in $script:queue) {
            if ($t.State -eq 'Done') { $t.IsSelected = $false }
            $t.State = 'Idle'; $t.Status = ''
        }
        $ui.Overlay.Visibility = 'Collapsed'
        Update-Stats
        Update-View
        Update-Summary
    })

    function Complete-Install {
        $script:installing = $false
        $ok = $sync.Ok; $already = $sync.Already; $failed = $sync.Failed
        $parts = @()
        if ($ok)      { $parts += "$ok instalada(s)" }
        if ($already) { $parts += "$already já existia(m)" }
        if ($failed)  { $parts += "$failed falharam" }
        $skipped = @($script:queue | Where-Object { $_.State -eq 'Skipped' }).Count
        if ($skipped) { $parts += "$skipped cancelada(s)" }
        $sub = $parts -join '  ·  '
        if ($sync.NeedReboot) { $sub += '. Reinicie o computador para concluir.' }

        if ($failed) {
            $ui.OvTitle.Text = 'Concluído com avisos'
            $ui.OvIcon.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#D9921C'); $ui.OvGlow.Background = $ui.OvIcon.Background
            $ui.OvGlyph.Text = [string][char]0xE7BA
            $sub += '  —  veja o log para detalhes.'
        } else {
            $ui.OvTitle.Text = 'Tudo pronto!'
            $ui.OvIcon.Background = [Windows.Media.BrushConverter]::new().ConvertFrom('#22A06B'); $ui.OvGlow.Background = $ui.OvIcon.Background
            $ui.OvGlyph.Text = [string][char]0xE73E
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
                $ui.StatusTitle.Text = 'winget pronto'
                $ui.StatusText.Text = 'Não foi possível detectar o que já está instalado.'
            } else {
                $ui.StatusDot.Fill = [Windows.Media.BrushConverter]::new().ConvertFrom('#3DD68C'); $ui.StatusHalo.Fill = $ui.StatusDot.Fill
                $ui.StatusTitle.Text = 'winget pronto'
                $ui.StatusText.Text = "$($sync.InstalledCount) ferramenta(s) do catálogo já instalada(s)."
            }
            Update-Stats
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
            $ui.OvCount.Text = "$done de $total concluída(s)" + $(if ($running) { "  ·  instalando $($running.Name)" } else { '' })

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
        $ui.StatusDot.Fill = [Windows.Media.BrushConverter]::new().ConvertFrom('#FF5C6C'); $ui.StatusHalo.Fill = $ui.StatusDot.Fill
        $ui.StatusTitle.Text = 'winget não encontrado'
        $ui.StatusText.Text = 'Instale o "Instalador de Aplicativo" na Microsoft Store.'
        $window.Add_ContentRendered({
            $r = [Windows.MessageBox]::Show("O winget (Gerenciador de Pacotes do Windows) não foi encontrado.`n`nDeseja abrir a Microsoft Store para instalar o 'Instalador de Aplicativo'?", 'DevSetup', 'YesNo', 'Warning')
            if ($r -eq 'Yes') { Start-Process 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1' }
        })
    }

    Update-View
    Update-Summary

    if ($Snapshot) {
        # modo de diagnóstico: salva um PNG da janela e fecha
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
