; Instalador único do Gestão YAHWEH (Windows) — Inno Setup 6.
;
; Gera UM .exe autocontido a partir de build\windows\x64\runner\Release.
; Instala por USUÁRIO (sem UAC): é o que mantém a instalação leve e sem
; travar em máquinas onde o usuário não é administrador.
;
; Compilar:
;   ISCC.exe /DMyAppVersion=11.2.305 /DMyBuildNumber=2211 installer\gestao_yahweh.iss

#ifndef MyAppVersion
  #define MyAppVersion "11.2.305"
#endif
#ifndef MyBuildNumber
  #define MyBuildNumber "0"
#endif

#define MyAppName "Gestao YAHWEH"
#define MyAppPublisher "Gestao YAHWEH"
#define MyAppURL "https://gestaoyahweh.com.br"
#define MyAppExeName "gestao_yahweh.exe"
#define SrcDir "..\flutter_app\build\windows\x64\runner\Release"

[Setup]
; AppId FIXO: é o que faz a próxima versão ATUALIZAR em vez de instalar
; um segundo app lado a lado. Nunca trocar entre releases.
AppId={{7C4E9A61-2B8F-4E0D-9A3C-5F1D6B8E27A4}
AppName={#MyAppName}
AppVersion={#MyAppVersion}.{#MyBuildNumber}
AppVerName={#MyAppName} {#MyAppVersion}
VersionInfoVersion={#MyAppVersion}.{#MyBuildNumber}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; Sem UAC: instala em %LOCALAPPDATA%\Programs\Gestao YAHWEH.
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableDirPage=no
AllowNoIcons=yes

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

OutputDir=..\dist\windows
OutputBaseFilename=GestaoYahweh-Setup-{#MyAppVersion}-{#MyBuildNumber}
SetupIconFile=..\flutter_app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

; LZMA2/max + sólido: menor .exe possível num download único.
Compression=lzma2/max
SolidCompression=yes
InternalCompressLevel=max
WizardStyle=modern

; Fecha o app aberto antes de sobrescrever — sem isto a atualização falha
; com "arquivo em uso" e o instalador parece travado.
CloseApplications=yes
CloseApplicationsFilter=*.exe,*.dll
RestartApplications=no

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na area de trabalho"; GroupDescription: "Atalhos:"

[Files]
Source: "{#SrcDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SrcDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir o {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\data"
