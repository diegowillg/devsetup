# DevSetup

Instalador visual de ferramentas de desenvolvimento para Windows (via winget).

**Download:** [Releases](https://github.com/diegowillg/devsetup/releases/latest)

## Gerar o instalador

```powershell
winget install JRSoftware.InnoSetup
.\build.ps1 -Version 1.0.0
```

O arquivo é criado em `Output\`.

## Estrutura

| Caminho | Função |
| --- | --- |
| `app/` | O aplicativo: `DevSetup.ps1`, `MainWindow.xaml`, `tools.json`, logos e ícone |
| `Launcher.cs` | Código do `DevSetup.exe`, que abre o app sem janela de console |
| `DevSetup.iss` | Script do instalador (Inno Setup) |
| `build.ps1` | Compila o launcher e gera o instalador |
