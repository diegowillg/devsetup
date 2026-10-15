; Instalador do DevSetup (Inno Setup 6)
; Gere com: installer\build.ps1

#define AppName "DevSetup"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppExe "DevSetup.exe"
#define AppId "DevSetup.DevSetup"

[Setup]
AppId={{6B1C2E7A-5D1F-4E8B-9C3A-2F7D4B8E1A90}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=diegowillg
AppPublisherURL=https://github.com/diegowillg/devsetup
AppSupportURL=https://github.com/diegowillg/devsetup/issues
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=Output
OutputBaseFilename=DevSetup-Setup-{#AppVersion}
SetupIconFile=..\assets\devsetup.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "build\{#AppExe}";        DestDir: "{app}";           Flags: ignoreversion
Source: "..\DevSetup.ps1";        DestDir: "{app}\app";       Flags: ignoreversion
Source: "..\MainWindow.xaml";     DestDir: "{app}\app";       Flags: ignoreversion
Source: "..\tools.json";          DestDir: "{app}\app";       Flags: ignoreversion
Source: "..\assets\devsetup.ico"; DestDir: "{app}\app";       Flags: ignoreversion
Source: "..\icons\*.png";         DestDir: "{app}\app\icons"; Flags: ignoreversion

[InstallDelete]
Type: filesandordirs; Name: "{app}\app"

[Icons]
Name: "{group}\{#AppName}";       Filename: "{app}\{#AppExe}"; AppUserModelID: "{#AppId}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; AppUserModelID: "{#AppId}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
