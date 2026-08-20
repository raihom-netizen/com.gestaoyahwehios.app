#define MyAppName "Gestão Yahweh"
#define MyAppVersion "11.2.305+2222"
#define MyAppExeName "gestao_yahweh.exe"
[Setup]
; AppId TEM de ser fixo entre versoes: e' a identidade do produto no Windows.
; Se mudar a cada build, o instalador nao atualiza — instala lado a lado e o
; utilizador acaba com varias copias. Mantido igual ao 2201.
AppId={{B8D2F0C9-1A1D-4D55-9F19-2201YAHWEH}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\Gestao Yahweh
DefaultGroupName=Gestão Yahweh
OutputDir=C:\gestao_yahweh_premium_final\windows_installer_stage_2222
OutputBaseFilename=gestao-yahweh-11.2.305+2222-windows
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
UninstallDisplayIcon={app}\{#MyAppExeName}
[Files]
Source: "C:\gestao_yahweh_premium_final\flutter_app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion
[Icons]
Name: "{group}\Gestão Yahweh"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Gestão Yahweh"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos:"
[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Executar Gestão Yahweh"; Flags: nowait postinstall skipifsilent
