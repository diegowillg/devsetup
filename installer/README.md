# DevSetup

Instalador visual de ferramentas de desenvolvimento para Windows (via winget).

## Instalar

Baixe **[DevSetup-Setup.exe](https://github.com/diegowillg/devsetup/raw/main/installer/DevSetup-Setup.exe)** (também disponível em [Releases](https://github.com/diegowillg/devsetup/releases/latest)) e execute. O assistente cria atalhos no Menu Iniciar e o app pode ser removido em **Configurações → Aplicativos**.

> O instalador não é assinado digitalmente, então o Windows SmartScreen pode exibir um aviso. Clique em **Mais informações → Executar assim mesmo**.

## Recursos

- **Instalar** 103 ferramentas (editores, IA, linguagens, Git, containers, bancos de dados…) com escolha da **versão** (mais recente ou anteriores) e do **disco**
- **Atualizar**: detecta a versão instalada de cada ferramenta, mostra as atualizações disponíveis e atualiza tudo com um clique
- **Trocar de versão**: volte para uma versão anterior de algo já instalado
- **Desinstalar** as ferramentas selecionadas
- **Conectado à internet**: indicador online/offline, catálogo de ferramentas atualizado pelo GitHub e aviso de nova versão do DevSetup
- Interface **responsiva** (se adapta a telas pequenas) com tema claro e escuro

## Gerar o instalador

```powershell
winget install JRSoftware.InnoSetup
.\build.ps1 -Version 1.2.0
```

O arquivo é criado em `Output\`.

## Estrutura

| Caminho | Função |
| --- | --- |
| `app/` | O aplicativo: `DevSetup.ps1`, `MainWindow.xaml`, `tools.json`, logos e ícone |
| `Launcher.cs` | Código do `DevSetup.exe`, que abre o app sem janela de console |
| `DevSetup.iss` | Script do instalador (Inno Setup) |
| `build.ps1` | Compila o launcher e gera o instalador |
| `DevSetup-Setup.exe` | Instalador pronto (versão atual) |
