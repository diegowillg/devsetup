# Gera installer\Output\DevSetup-Setup-<versão>.exe
# Requer: Inno Setup 6 (winget install JRSoftware.InnoSetup)
param([string]$Version = '1.0.0')

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSCommandPath

# 1. Launcher (DevSetup.exe) com o compilador C# que já vem no Windows
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$buildDir = Join-Path $here 'build'
New-Item -ItemType Directory -Force $buildDir | Out-Null
$src = (Get-Content (Join-Path $here 'Launcher.cs') -Raw) -replace '1\.0\.0\.0', "$Version.0"
$tmpSrc = Join-Path $buildDir 'Launcher.cs'
Set-Content $tmpSrc $src -Encoding UTF8
& $csc /nologo /target:winexe /optimize+ /codepage:65001 `
    "/win32icon:$(Join-Path $here 'app\devsetup.ico')" `
    "/out:$(Join-Path $buildDir 'DevSetup.exe')" `
    /reference:System.Windows.Forms.dll /reference:System.Core.dll $tmpSrc
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o launcher.' }

# 2. Instalador
$iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 não encontrado. Instale com: winget install JRSoftware.InnoSetup' }

& $iscc /Q "/DAppVersion=$Version" (Join-Path $here 'DevSetup.iss')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao gerar o instalador.' }

Get-Item (Join-Path $here "Output\DevSetup-Setup-$Version.exe")
